package states;

import backend.WeekData;
import backend.Highscore;
import backend.Song;
import backend.SongMetadata;
import backend.Conductor;

import objects.HealthIcon;
import objects.MusicPlayer;

import options.GameplayChangersSubstate;
import substates.ResetScoreSubState;

import flixel.math.FlxMath;
import flixel.util.FlxDestroyUtil;
import flixel.graphics.FlxGraphic;

import openfl.utils.Assets;

import haxe.Json;
#if FEATURE_FILESYSTEM
import sys.FileSystem;
import sys.io.File;
import backend.Mods;
#end

class FreeplayState extends MusicBeatState
{
	var songs:Array<SongMetadata> = [];

	var selector:FlxText;
	private static var curSelected:Int = 0;
	var lerpSelected:Float = 0;
	var curDifficulty:Int = -1;
	private static var lastDifficultyName:String = Difficulty.getDefault();

	var scoreBG:FlxSprite;
	var scoreText:FlxText;
	var diffText:FlxText;
	var lerpScore:Int = 0;
	var lerpRating:Float = 0;
	var intendedScore:Int = 0;
	var intendedRating:Float = 0;

	private var grpSongs:FlxTypedGroup<Alphabet>;
	private var curPlaying:Bool = false;

	private var iconArray:Array<HealthIcon> = [];
	
	var bg:FlxSprite;
	var intendedColor:Int;
	private var bgScaleLerp:Float = 0; // Lerp插值进度 (0-1)
	private var bgBeatDuration:Float = 0; // 节拍动画总时长
	private var bgBeatElapsed:Float = 0; // 节拍动画已过去时间

	var missingTextBG:FlxSprite;
	var missingText:FlxText;

	var bottomString:String;
	var bottomText:FlxText;
	var bottomBG:FlxSprite;

	var player:MusicPlayer;
	
	// BPM变化提示相关
	private var bpmText:FlxText;
	private var bpmTextBG:FlxSprite;
	private var lastBPM:Float = -1;
	private var bpmDisplayTime:Float = 0;

	override function create()
	{
		//Paths.clearStoredMemory();
		//Paths.clearUnusedMemory();
		
		persistentUpdate = true;
		PlayState.isStoryMode = false;
		WeekData.reloadWeekFiles(false);

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence
		DiscordClient.changePresence("In the Menus", null);
		#end

		final accept:String = (controls.mobileC) ? "A" : "ACCEPT";
		final reject:String = (controls.mobileC) ? "B" : "BACK";

		if(WeekData.weeksList.length < 1)
		{
			FlxTransitionableState.skipNextTransIn = true;
			persistentUpdate = false;
			MusicBeatState.switchState(new states.ErrorState("NO WEEKS ADDED FOR FREEPLAY\n\nPress " + accept + " to go to the Week Editor Menu.\nPress " + reject + " to return to Main Menu.",
				function() MusicBeatState.switchState(new states.editors.WeekEditorState()),
				function() MusicBeatState.switchState(new states.MainMenuState())));
			return;
		}

		for (i in 0...WeekData.weeksList.length)
		{
			if(weekIsLocked(WeekData.weeksList[i])) continue;

			var leWeek:WeekData = WeekData.weeksLoaded.get(WeekData.weeksList[i]);
			var leSongs:Array<String> = [];
			var leChars:Array<String> = [];

			for (j in 0...leWeek.songs.length)
			{
				leSongs.push(leWeek.songs[j][0]);
				leChars.push(leWeek.songs[j][1]);
			}

			WeekData.setDirectoryFromWeek(leWeek);
			for (song in leWeek.songs)
			{
				var colors:Array<Int> = song[2];
				if(colors == null || colors.length < 3)
				{
					colors = [146, 113, 253];
				}
				addSong(song[0], i, song[1], FlxColor.fromRGB(colors[0], colors[1], colors[2]));
			}
		}
		Mods.loadTopMod();

		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		add(bg);
		bg.screenCenter();
		bg.scale.set(1.0, 1.0); // 确保初始scale为1

		grpSongs = new FlxTypedGroup<Alphabet>();
		add(grpSongs);

		for (i in 0...songs.length)
		{
			var songText:Alphabet = new Alphabet(90, 320, songs[i].songName, true);
			songText.targetY = i;
			grpSongs.add(songText);

			songText.scaleX = Math.min(1, 980 / songText.width);
			songText.snapToPosition();

			Mods.currentModDirectory = songs[i].folder;
			var icon:HealthIcon = new HealthIcon(songs[i].songCharacter);
			icon.sprTracker = songText;

			
			// too laggy with a lot of songs, so i had to recode the logic for it
			songText.visible = songText.active = songText.isMenuItem = false;
			icon.visible = icon.active = false;

			// using a FlxGroup is too much fuss!
			iconArray.push(icon);
			add(icon);

			// songText.x += 40;
			// DONT PUT X IN THE FIRST PARAMETER OF new ALPHABET() !!
			// songText.screenCenter(X);
		}
		WeekData.setDirectoryFromWeek();

		scoreText = new FlxText(FlxG.width * 0.7, 5, 0, "", 32);
		scoreText.setFormat(Paths.font(Language.get('game_font')), 32, FlxColor.WHITE, RIGHT);

		scoreBG = new FlxSprite(scoreText.x - 6, 0).makeGraphic(1, 66, 0xFF000000);
		scoreBG.alpha = 0.6;
		add(scoreBG);

		diffText = new FlxText(scoreText.x, scoreText.y + 36, 0, "", 24);
		diffText.font = scoreText.font;
		add(diffText);

		add(scoreText);


		missingTextBG = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		missingTextBG.alpha = 0.6;
		missingTextBG.visible = false;
		add(missingTextBG);
		
		missingText = new FlxText(50, 0, FlxG.width - 100, '', 24);
		missingText.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		missingText.scrollFactor.set();
		missingText.visible = false;
		add(missingText);

		if(curSelected >= songs.length) curSelected = 0;
		bg.color = songs[curSelected].color;
		intendedColor = bg.color;
		lerpSelected = curSelected;

		curDifficulty = Math.round(Math.max(0, Difficulty.defaultList.indexOf(lastDifficultyName)));

		bottomBG = new FlxSprite(0, FlxG.height - 26).makeGraphic(FlxG.width, 26, 0xFF000000);
		bottomBG.alpha = 0.6;
		add(bottomBG);

		final space:String = (controls.mobileC) ? "X" : "SPACE";
		final control:String = (controls.mobileC) ? "C" : "CTRL";
		final reset:String = (controls.mobileC) ? "Y" : "RESET";
		
		var leText:String = LanguageBasic.getPhrase("freeplay_tip", "Press {1} to listen to the Song / Press {2} to open the Gameplay Changers Menu / Press {3} to Reset your Score and Accuracy.", [space, control, reset]);
		bottomString = leText;
		var size:Int = 16;
		bottomText = new FlxText(bottomBG.x, bottomBG.y + 4, FlxG.width, leText, size);
		bottomText.setFormat(Paths.font("vcr.ttf"), size, FlxColor.WHITE, CENTER);
		bottomText.scrollFactor.set();
		add(bottomText);
		
		player = new MusicPlayer(this);
		add(player);
		
		// 创建BPM变化提示背景（先创建，渲染在底层）
		bpmTextBG = new FlxSprite(0, 0); // 初始位置为0,0
		bpmTextBG.alpha = 0;
		bpmTextBG.scrollFactor.set(); // 固定位置
		add(bpmTextBG);
		
		// 创建BPM变化提示文本（后创建，渲染在顶层）
		bpmText = new FlxText(0, 20, 0, "", 32);
		bpmText.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, RIGHT);
		bpmText.alpha = 0;
		bpmText.scrollFactor.set(); // 固定位置
		add(bpmText);
		
		changeSelection();
		updateTexts();

		// Update replay status display text
		updateReplayBottomText();

		addTouchPad('LEFT_FULL', 'A_B_C_X_Y_Z');
		super.create();

	}

	override function closeSubState()
	{
		changeSelection(0, false);
		persistentUpdate = true;
		super.closeSubState();
		removeTouchPad();
		addTouchPad('LEFT_FULL', 'A_B_C_X_Y_Z');
	}

	public function addSong(songName:String, weekNum:Int, songCharacter:String, color:Int)
	{
		songs.push(new SongMetadata(songName, weekNum, songCharacter, color));
	}

	function weekIsLocked(name:String):Bool
	{
		var leWeek:WeekData = WeekData.weeksLoaded.get(name);
		return (!leWeek.startUnlocked && leWeek.weekBefore.length > 0 && (!StoryMenuState.weekCompleted.exists(leWeek.weekBefore) || !StoryMenuState.weekCompleted.get(leWeek.weekBefore)));
	}

	var instPlaying:Int = -1;
	public static var vocals:FlxSound = null;
	public static var opponentVocals:FlxSound = null;
	var holdTime:Float = 0;

	var stopMusicPlay:Bool = false;
	override function update(elapsed:Float)
	{
		if(WeekData.weeksList.length < 1)
			return;

		if (FlxG.sound.music.volume < 0.7)
			FlxG.sound.music.volume += 0.5 * elapsed;
		
		// 更新Conductor.songPosition以触发beatHit
		if (player.playingMusic && FlxG.sound.music != null)
		{
			Conductor.songPosition = FlxG.sound.music.time;
			
			// 检测BPM变化并显示提示 - 使用getBPMFromSeconds获取当前时间点的实际BPM
			var currentBPM = Conductor.getBPMFromSeconds(Conductor.songPosition).bpm;
			if (currentBPM != lastBPM)
			{
				bpmText.text = 'BPM: ${Math.round(currentBPM)}';
				bpmText.x = FlxG.width - bpmText.width - 10;
				bpmText.y = (FlxG.height - bpmText.height) / 2; // 垂直居中
				
				// 重新创建背景图形以确保正确的大小和位置
				bpmTextBG.loadGraphic(FlxGraphic.fromRectangle(Std.int(bpmText.width + 20), Std.int(bpmText.height + 10), 0xFF000000));
				bpmTextBG.x = bpmText.x - 10;
				bpmTextBG.y = bpmText.y - 5;
				
				bpmDisplayTime = 0;
			}
			lastBPM = currentBPM;
		}
		
		// 更新BPM提示显示/隐藏
		if (bpmDisplayTime >= 0)
		{
			bpmDisplayTime += elapsed;
			if (bpmDisplayTime < 1.0) // 显示1秒
			{
				bpmText.alpha = 1;
				bpmTextBG.alpha = 0.6;
			}
			else if (bpmDisplayTime < 1.5) // 0.5秒淡出
			{
				var fade = (bpmDisplayTime - 1.0) / 0.5;
				bpmText.alpha = 1 - fade;
				bpmTextBG.alpha = 0.6 * (1 - fade);
			}
			else
			{
				bpmText.alpha = 0;
				bpmTextBG.alpha = 0;
			}
		}

		// 背景缩放Lerp动画（从1.05过渡回1）
		if (bg != null && bg.scale.x > 1.0)
		{
			bgBeatElapsed += elapsed;
			
			// 计算插值进度 (0-1)
			bgScaleLerp = Math.min(bgBeatElapsed / bgBeatDuration, 1.0);
			
			// 使用立方缓出函数使过渡更自然
			var easedProgress = 1 - Math.pow(1 - bgScaleLerp, 3);
			var scale = FlxMath.lerp(1.05, 1.0, easedProgress);
			bg.scale.set(scale, scale);
		}

		lerpScore = Math.floor(FlxMath.lerp(intendedScore, lerpScore, Math.exp(-elapsed * 24)));
		lerpRating = FlxMath.lerp(intendedRating, lerpRating, Math.exp(-elapsed * 12));

		if (Math.abs(lerpScore - intendedScore) <= 10)
			lerpScore = intendedScore;
		if (Math.abs(lerpRating - intendedRating) <= 0.01)
			lerpRating = intendedRating;

		var ratingSplit:Array<String> = Std.string(CoolUtil.floorDecimal(lerpRating * 100, 2)).split('.');
		if(ratingSplit.length < 2) //No decimals, add an empty space
			ratingSplit.push('');
		
		while(ratingSplit[1].length < 2) //Less than 2 decimals in it, add decimals then
			ratingSplit[1] += '0';

		var shiftMult:Int = 1;
		if((FlxG.keys.pressed.SHIFT || touchPad.buttonZ.pressed) && !player.playingMusic) shiftMult = 3;

		if (!player.playingMusic)
		{
			//scoreText.text = LanguageBasic.getPhrase('personal_best', 'PERSONAL BEST: {1} ({2}%)', [lerpScore, ratingSplit.join('.')]);
			scoreText.text = '${Language.get('score_best_desc')} ${lerpScore} (${ratingSplit.join('.')}%)';
			positionHighscore();
			
			if(songs.length > 1)
			{
				if(FlxG.keys.justPressed.HOME)
				{
					curSelected = 0;
					changeSelection();
					holdTime = 0;	
				}
				else if(FlxG.keys.justPressed.END)
				{
					curSelected = songs.length - 1;
					changeSelection();
					holdTime = 0;	
				}
				if (controls.UI_UP_P)
				{
					changeSelection(-shiftMult);
					holdTime = 0;
				}
				if (controls.UI_DOWN_P)
				{
					changeSelection(shiftMult);
					holdTime = 0;
				}

				if(controls.UI_DOWN || controls.UI_UP)
				{
					var checkLastHold:Int = Math.floor((holdTime - 0.5) * 10);
					holdTime += elapsed;
					var checkNewHold:Int = Math.floor((holdTime - 0.5) * 10);

					if(holdTime > 0.5 && checkNewHold - checkLastHold > 0)
						changeSelection((checkNewHold - checkLastHold) * (controls.UI_UP ? -shiftMult : shiftMult));
				}

				if(FlxG.mouse.wheel != 0)
				{
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.2);
					changeSelection(-shiftMult * FlxG.mouse.wheel, false);
				}
			}

			if (controls.UI_LEFT_P)
			{
				changeDiff(-1);
				_updateSongLastDifficulty();
			}
			else if (controls.UI_RIGHT_P)
			{
				changeDiff(1);
				_updateSongLastDifficulty();
			}
		}

		if (controls.BACK)
		{
			if (player.playingMusic)
			{
				FlxG.sound.music.stop();
				destroyFreeplayVocals();
				FlxG.sound.music.volume = 0;
				instPlaying = -1;

			player.playingMusic = false;
			player.switchPlayMusic();

			// 重置Conductor状态
			Conductor.songPosition = 0;
			lastBeatHit = -1;
			
			// 隐藏BPM提示
			bpmText.alpha = 0;
			bpmTextBG.alpha = 0;
			bpmDisplayTime = -1;
			lastBPM = -1;
			
			FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);
			FlxTween.tween(FlxG.sound.music, {volume: 1}, 1);
			}
			else 
			{
				persistentUpdate = false;
				FlxG.sound.play(Paths.sound('cancelMenu'));
				MusicBeatState.switchState(new MainMenuState());
			}
		}

		if((FlxG.keys.justPressed.CONTROL || touchPad.buttonC.justPressed) && !player.playingMusic)
		{
			persistentUpdate = false;
			openSubState(new GameplayChangersSubstate());
			removeTouchPad();
		}
		else if(FlxG.keys.justPressed.SPACE || touchPad.buttonX.justPressed)
		{
			if(instPlaying != curSelected && !player.playingMusic)
			{
				destroyFreeplayVocals();
				FlxG.sound.music.volume = 0;

				Mods.currentModDirectory = songs[curSelected].folder;
				var poop:String = Highscore.formatSong(songs[curSelected].songName.toLowerCase(), curDifficulty);
				Song.loadFromJson(poop, songs[curSelected].songName.toLowerCase());
				
				// 设置Conductor的BPM信息以支持beat检测
				Conductor.bpm = PlayState.SONG.bpm;
				Conductor.mapBPMChanges(PlayState.SONG);
				
				// 显示初始BPM
				bpmText.text = 'BPM: ${Math.round(Conductor.bpm)}';
				bpmText.x = FlxG.width - bpmText.width - 10;
				bpmText.y = (FlxG.height - bpmText.height) / 2; // 垂直居中
				
				// 创建背景图形
				bpmTextBG.loadGraphic(FlxGraphic.fromRectangle(Std.int(bpmText.width + 20), Std.int(bpmText.height + 10), 0xFF000000));
				bpmTextBG.x = bpmText.x - 10;
				bpmTextBG.y = bpmText.y - 5;
				
				bpmDisplayTime = 0;
				
				if (PlayState.SONG.needsVoices)
				{
					vocals = new FlxSound();
					try
					{
						var playerVocals:String = getVocalFromCharacter(PlayState.SONG.player1);
						var loadedVocals = Paths.voices(PlayState.SONG.song, (playerVocals != null && playerVocals.length > 0) ? playerVocals : 'Player', PlayState.SONG.specialVocal);
						if(loadedVocals == null) loadedVocals = Paths.voices(PlayState.SONG.song, null, PlayState.SONG.specialVocal);
						
						if(loadedVocals != null && loadedVocals.length > 0)
						{
							vocals.loadEmbedded(loadedVocals);
							FlxG.sound.list.add(vocals);
							vocals.persist = vocals.looped = true;
							vocals.volume = 0.8;
							vocals.play();
							vocals.pause();
						}
						else vocals = FlxDestroyUtil.destroy(vocals);
					}
					catch(e:Dynamic)
					{
						vocals = FlxDestroyUtil.destroy(vocals);
					}
					
					opponentVocals = new FlxSound();
					try
					{
						//trace('please work...');
						var oppVocals:String = getVocalFromCharacter(PlayState.SONG.player2);
						var loadedVocals = Paths.voices(PlayState.SONG.song, (oppVocals != null && oppVocals.length > 0) ? oppVocals : 'Opponent', PlayState.SONG.specialVocal);
						
						if(loadedVocals != null && loadedVocals.length > 0)
						{
							opponentVocals.loadEmbedded(loadedVocals);
							FlxG.sound.list.add(opponentVocals);
							opponentVocals.persist = opponentVocals.looped = true;
							opponentVocals.volume = 0.8;
							opponentVocals.play();
							opponentVocals.pause();
							//trace('yaaay!!');
						}
						else opponentVocals = FlxDestroyUtil.destroy(opponentVocals);
					}
					catch(e:Dynamic)
					{
						//trace('FUUUCK');
						opponentVocals = FlxDestroyUtil.destroy(opponentVocals);
					}
				}

FlxG.sound.playMusic(Paths.inst(PlayState.SONG.song, PlayState.SONG.specialInst), 0.8);
			FlxG.sound.music.pause();
			instPlaying = curSelected;

			player.playingMusic = true;
			player.curTime = 0;
			player.switchPlayMusic();
			player.pauseOrResume(true);
			
			// 重置BPM检测，并显示初始BPM
			lastBPM = -1;
			bpmDisplayTime = -1;
			}
			else if (instPlaying == curSelected && player.playingMusic)
			{
				player.pauseOrResume(!player.playing);
			}
		}
		else if (controls.ACCEPT && !player.playingMusic)
		{
			persistentUpdate = false;
			var songLowercase:String = Paths.formatToSongPath(songs[curSelected].songName);
			var poop:String = Highscore.formatSong(songLowercase, curDifficulty);

			try
			{
				Song.loadFromJson(poop, songLowercase);
				PlayState.isStoryMode = false;
				PlayState.storyDifficulty = curDifficulty;

trace('CURRENT WEEK: ' + WeekData.getWeekFileName());
		}
		catch(e:haxe.Exception)
		{
			// Error handling

				var errorStr:String = e.message;
				if(errorStr.contains('There is no TEXT asset with an ID of')) errorStr = 'Missing file: ' + errorStr.substring(errorStr.indexOf(songLowercase), errorStr.length-1); //Missing chart
				else errorStr += '\n\n' + e.stack;

				missingText.text = 'ERROR WHILE LOADING CHART:\n$errorStr';
				missingText.screenCenter(Y);
				missingText.visible = true;
				missingTextBG.visible = true;
				FlxG.sound.play(Paths.sound('cancelMenu'));

				updateTexts(elapsed);
				super.update(elapsed);
				return;
			}

@:privateAccess
		if(PlayState._lastLoadedModDirectory != Mods.currentModDirectory)
		{
			Paths.freeGraphicsFromMemory();
		}
			LoadingState.prepareToSong();
			LoadingState.loadAndSwitchState(new PlayState());
			#if !SHOW_LOADING_SCREEN FlxG.sound.music.stop(); #end
			stopMusicPlay = true;

			destroyFreeplayVocals();
			#if (MODS_ALLOWED && DISCORD_ALLOWED)
			DiscordClient.loadModRPC();
			#end
		}
		else if((controls.RESET || touchPad.buttonY.justPressed) && !player.playingMusic)
		{
			persistentUpdate = false;
			openSubState(new ResetScoreSubState(songs[curSelected].songName, curDifficulty, songs[curSelected].songCharacter));
			removeTouchPad();
			FlxG.sound.play(Paths.sound('scrollMenu'));
		}

		// Replay loading entry point: F7 loads latest saved replay (if exists)
		#if FEATURE_FILESYSTEM
		var moddirLoad:String = (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0) ? Mods.currentModDirectory : 'global';
		var replayFolderLoad:String = Paths.mods(moddirLoad + '/replay');
		if (FileSystem.exists(replayFolderLoad))
		{
			var filesLoad:Array<String> = FileSystem.readDirectory(replayFolderLoad);
			if (filesLoad != null && filesLoad.length > 0)
			{
				// Get currently selected song name (formatted)
				var currentSongName:String = Paths.formatToSongPath(songs[curSelected].songName);

				// Get currently selected difficulty name
				var currentDifficultyName:String = Difficulty.getString(curDifficulty, false);

				// Find latest replay file matching current song and difficulty
				var latest:String = null;
				var latestM:Float = -1;
				var savedSongName:String = null;
				for (f in filesLoad)
				{
					if (!f.endsWith('.replay.json')) continue;
					
					var p = replayFolderLoad + '/' + f;
					try
					{
						var content:String = File.getContent(p);
						var obj:Dynamic = Json.parse(content);
						var meta:Dynamic = Reflect.field(obj, 'meta');
						if (meta != null && Reflect.hasField(meta, 'song'))
						{
							var replaySongName:String = Reflect.field(meta, 'song');
							var chartPath:Dynamic = (meta != null && Reflect.hasField(meta, 'chartPath')) ? Reflect.field(meta, 'chartPath') : null;
							var replayDifficulty:String = getDifficultyFromChartPath(chartPath, meta);
							
							// Check if replay matches current song and difficulty
							if (Paths.formatToSongPath(replaySongName) == currentSongName && replayDifficulty == currentDifficultyName)
							{
								var s = FileSystem.stat(p);
								var m:Float = 0;
								if (s != null && Reflect.hasField(s, 'mtime'))
								{
									var mt = Reflect.field(s, 'mtime');
									if (Std.isOfType(mt, Date)) m = mt.getTime(); else m = Std.parseFloat(Std.string(mt));
								}
								if (m > latestM) { latestM = m; latest = p; savedSongName = replaySongName; }
							}
						}
					}
					catch(e:Dynamic)
					{
						trace('Failed to read replay file ${f}: ' + e);
					}
				}
				
				if (FlxG.keys.justPressed.F7 && !player.playingMusic)
				{
					if (latest != null)
					{
						// Load and play the replay
						try
						{
							var content:String = File.getContent(latest);
							var obj:Dynamic = Json.parse(content);
							var replayArr = Reflect.field(obj, 'replay');
							var meta:Dynamic = Reflect.field(obj, 'meta');
							var chartPath:Dynamic = (meta != null && Reflect.hasField(meta, 'chartPath')) ? Reflect.field(meta, 'chartPath') : null;
							var savedM:Dynamic = (meta != null && Reflect.hasField(meta, 'chartMTime')) ? Reflect.field(meta, 'chartMTime') : null;
							var warn:Bool = false;
							if (chartPath != null && FileSystem.exists(chartPath))
							{
								var s2 = FileSystem.stat(chartPath);
								var curM = (s2 != null && Reflect.hasField(s2, 'mtime')) ? Reflect.field(s2, 'mtime') : null;
								if (savedM != null && curM != null && Std.string(savedM) != Std.string(curM)) warn = true;
							}
							else warn = true;
							if (warn)
							{
								missingText.text = 'Warning: chart file changed since save. Playback may desync.';
								missingText.screenCenter(Y);
								missingText.visible = true;
								missingTextBG.visible = true;
							}
						// Set pending replay data and load song
						PlayState.pendingReplayData = replayArr;
							PlayState.shouldStartReplay = true;
							// 提取并保存判定设置
							if (meta != null && Reflect.hasField(meta, 'judgmentSettings')) {
								PlayState.replayJudgmentSettings = Reflect.field(meta, 'judgmentSettings');
							} else {
								PlayState.replayJudgmentSettings = null;
							}
							// 提取并保存游戏设置
							if (meta != null && Reflect.hasField(meta, 'gameplaySettings')) {
								PlayState.replayGameplaySettings = Reflect.field(meta, 'gameplaySettings');
							} else {
								PlayState.replayGameplaySettings = null;
							}
							var songLowercase:String = Paths.formatToSongPath(songs[curSelected].songName);
							var poop:String = Highscore.formatSong(songLowercase, curDifficulty);
							Song.loadFromJson(poop, songLowercase);
							PlayState.isStoryMode = false;
							PlayState.storyDifficulty = curDifficulty;
							LoadingState.prepareToSong();
							LoadingState.loadAndSwitchState(new PlayState());
						}
						catch(e:Dynamic)
						{
							trace('Failed to load replay: ' + e);
						}
					}
					else
					{
						// Show prompt: current song and difficulty have no replay
						missingText.text = 'No replay found for "${songs[curSelected].songName}" (${currentDifficultyName}).';
						missingText.screenCenter(Y);
						missingText.visible = true;
						missingTextBG.visible = true;
					}
				}
			}
		}
		#end

		updateTexts(elapsed);
		super.update(elapsed);
	}
	
	function getVocalFromCharacter(char:String)
	{
		try
		{
			var path:String = Paths.getPath('characters/$char.json', TEXT);
			#if MODS_ALLOWED
			var character:Dynamic = Json.parse(File.getContent(path));
			#else
			var character:Dynamic = Json.parse(Assets.getText(path));
			#end
			return character.vocals_file;
		}
		catch (e:Dynamic) {}
		return null;
	}

	public static function destroyFreeplayVocals() {
		if(vocals != null) vocals.stop();
		vocals = FlxDestroyUtil.destroy(vocals);

		if(opponentVocals != null) opponentVocals.stop();
		opponentVocals = FlxDestroyUtil.destroy(opponentVocals);
	}

	function changeDiff(change:Int = 0)
	{
		if (player.playingMusic)
			return;

		curDifficulty = FlxMath.wrap(curDifficulty + change, 0, Difficulty.list.length-1);
		#if !switch
		intendedScore = Highscore.getScore(songs[curSelected].songName, curDifficulty);
		intendedRating = Highscore.getRating(songs[curSelected].songName, curDifficulty);
		#end

		lastDifficultyName = Difficulty.getString(curDifficulty, false);
		var displayDiff:String = Difficulty.getString(curDifficulty);
		if (Difficulty.list.length > 1)
			diffText.text = '< ' + displayDiff.toUpperCase() + ' >';
		else
			diffText.text = displayDiff.toUpperCase();

		positionHighscore();
		missingText.visible = false;
		missingTextBG.visible = false;
	}

	function changeSelection(change:Int = 0, playSound:Bool = true)
	{
		if (player.playingMusic)
			return;

		curSelected = FlxMath.wrap(curSelected + change, 0, songs.length-1);
		_updateSongLastDifficulty();
		if(playSound) FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		var newColor:Int = songs[curSelected].color;
		if(newColor != intendedColor)
		{
			intendedColor = newColor;
			FlxTween.cancelTweensOf(bg);
			FlxTween.color(bg, 1, bg.color, intendedColor);
		}

for (num => item in grpSongs.members)
	{
		var icon:HealthIcon = iconArray[num];
		item.alpha = 0.6;
		icon.alpha = 0.6;
		if (item.targetY == curSelected)
		{
			item.alpha = 1;
			icon.alpha = 1;
		}
	}
		
		Mods.currentModDirectory = songs[curSelected].folder;
		PlayState.storyWeek = songs[curSelected].week;
		Difficulty.loadFromWeek();
		
		var savedDiff:String = songs[curSelected].lastDifficulty;
		var lastDiff:Int = Difficulty.list.indexOf(lastDifficultyName);
		if(savedDiff != null && !Difficulty.list.contains(savedDiff) && Difficulty.list.contains(savedDiff))
			curDifficulty = Math.round(Math.max(0, Difficulty.list.indexOf(savedDiff)));
		else if(lastDiff > -1)
			curDifficulty = lastDiff;
		else if(Difficulty.list.contains(Difficulty.getDefault()))
			curDifficulty = Math.round(Math.max(0, Difficulty.defaultList.indexOf(Difficulty.getDefault())));
		else
			curDifficulty = 0;

		changeDiff();
		_updateSongLastDifficulty();
		updateReplayBottomText();
	}

	inline private function _updateSongLastDifficulty()
		songs[curSelected].lastDifficulty = Difficulty.getString(curDifficulty, false);

	/**
	 * Get difficulty name from chart file path or meta data
	 * @param chartPath Chart file path, e.g. ".../song-hard.json"
	 * @param meta Replay meta data containing difficulty information
	 * @return Difficulty name (e.g. Easy/Normal/Hard) or default difficulty
	 */
	private function getDifficultyFromChartPath(chartPath:String, ?meta:Dynamic):Null<String>
	{
		if (meta != null && Reflect.hasField(meta, 'difficulty'))
			return Reflect.field(meta, 'difficulty');
		if (chartPath == null) return Difficulty.getDefault();
		// Find the last path separator
		var lastSep = chartPath.lastIndexOf('/');
		if (lastSep == -1) lastSep = chartPath.lastIndexOf('\\');
		var fileName:String = (lastSep >= 0) ? chartPath.substr(lastSep + 1) : chartPath;
		// Remove .json extension
		if (fileName.endsWith('.json'))
			fileName = fileName.substr(0, fileName.length - 5);
		// Find the last dash separator like "song-hard.json"
		var lastDash = fileName.lastIndexOf('-');
		if (lastDash == -1)
		{
			// No dash found, file might be "song.json" without difficulty
			return Difficulty.getDefault();
		}
		var potentialDiff:String = fileName.substr(lastDash + 1);
		// Check if the extracted part matches any difficulty name
		for (diff in Difficulty.list)
		{
			if (Paths.formatToSongPath(diff) == Paths.formatToSongPath(potentialDiff))
				return diff;
		}
		// No matching difficulty found, return default
		return Difficulty.getDefault();
	}



	private function updateReplayBottomText():Void
	{
		#if FEATURE_FILESYSTEM
		var moddirCheck:String = (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0) ? Mods.currentModDirectory : 'global';
		var replayFolderCheck:String = Paths.mods(moddirCheck + '/replay');
		if (FileSystem.exists(replayFolderCheck))
		{
			var files:Array<String> = FileSystem.readDirectory(replayFolderCheck);
			if (files != null && files.length > 0)
			{
				// Get currently selected song name (formatted) and difficulty name
				var currentSongName:String = Paths.formatToSongPath(songs[curSelected].songName);
				var currentDifficultyName:String = Difficulty.getString(curDifficulty, false);
				var matchedReplayCount:Int = 0;
				
				for (f in files)
				{
					if (!f.endsWith('.replay.json')) continue;
					
					var p = replayFolderCheck + '/' + f;
					try
					{
						var content:String = File.getContent(p);
						var obj:Dynamic = Json.parse(content);
						var meta:Dynamic = Reflect.field(obj, 'meta');
						if (meta != null && Reflect.hasField(meta, 'song'))
						{
							var replaySongName:String = Reflect.field(meta, 'song');
							var chartPath:Dynamic = (meta != null && Reflect.hasField(meta, 'chartPath')) ? Reflect.field(meta, 'chartPath') : null;
							var replayDifficulty:String = getDifficultyFromChartPath(chartPath, meta);
							
							// 濡偓閺屻儲鐡曢弴鎻掓倳缁夋澘鎷伴梾鎯у閺勵垰鎯侀柈钘夊爱闁?
							if (Paths.formatToSongPath(replaySongName) == currentSongName && replayDifficulty == currentDifficultyName)
							{
								matchedReplayCount++;
							}
						}
					}
					catch(e:Dynamic)
					{
						trace('Failed to read replay file ${f}: ' + e);
					}
				}
				
				if (matchedReplayCount > 0)
				{
					bottomText.text = bottomString + ' | ${matchedReplayCount} replay(s) found for this song (${currentDifficultyName}) - Press F7 to watch latest replay.';
				}
				else
				{
					// No replay matching current song and difficulty, but still show total replay count (for reference)
					var totalReplayFiles:Array<String> = files.filter(f -> f.endsWith('.replay.json'));
					var totalReplayCount:Int = totalReplayFiles.length;
					if (totalReplayCount > 0)
					{
						bottomText.text = bottomString + ' | ${totalReplayCount} replay(s) in mod (not for this song/difficulty).';
					}
					else
					{
						bottomText.text = bottomString;
					}
				}
			}
			else
			{
				bottomText.text = bottomString;
			}
		}
		else
		{
			bottomText.text = bottomString;
		}
		#end
	}

	private function positionHighscore()
	{
		scoreText.x = FlxG.width - scoreText.width - 6;
		scoreBG.scale.x = FlxG.width - scoreText.x + 6;
		scoreBG.x = FlxG.width - (scoreBG.scale.x / 2);
		diffText.x = Std.int(scoreBG.x + (scoreBG.width / 2));
		diffText.x -= diffText.width / 2;
	}

	var _drawDistance:Int = 4;
	var _lastVisibles:Array<Int> = [];
	public function updateTexts(elapsed:Float = 0.0)
	{
		lerpSelected = FlxMath.lerp(curSelected, lerpSelected, Math.exp(-elapsed * 9.6));
		for (i in _lastVisibles)
		{
			grpSongs.members[i].visible = grpSongs.members[i].active = false;
			iconArray[i].visible = iconArray[i].active = false;
		}
		_lastVisibles = [];

		var min:Int = Math.round(Math.max(0, Math.min(songs.length, lerpSelected - _drawDistance)));
		var max:Int = Math.round(Math.max(0, Math.min(songs.length, lerpSelected + _drawDistance)));
		for (i in min...max)
		{
			var item:Alphabet = grpSongs.members[i];
			item.visible = item.active = true;
			item.x = ((item.targetY - lerpSelected) * item.distancePerItem.x) + item.startPosition.x;
			item.y = ((item.targetY - lerpSelected) * 1.3 * item.distancePerItem.y) + item.startPosition.y;

			var icon:HealthIcon = iconArray[i];
			icon.visible = icon.active = true;
			_lastVisibles.push(i);
		}
	}

	override function stepHit():Void
	{
		super.stepHit();
		
		// 每4步（每拍）触发背景缩放动画
		if (curStep % 4 == 0)
		{
			//trace('Step hit: ' + curStep + ', songPosition: ' + Conductor.songPosition + ', calling beatHit');
			beatHit();
		}
	}
	
	private var lastBeatHit:Int = -1;
	override function beatHit():Void
	{
		//trace('beatHit called, curBeat: ' + curBeat + ', lastBeatHit: ' + lastBeatHit + ', playingMusic: ' + player.playingMusic);
		if (lastBeatHit >= curBeat || !player.playingMusic) {
			//trace('beatHit blocked: lastBeatHit >= curBeat = ' + (lastBeatHit >= curBeat) + ', !playingMusic = ' + (!player.playingMusic));
			return;
		}
		
		lastBeatHit = curBeat;
		
		// 背景立刻缩放到1.05，然后开始lerp回1
		if (bg != null)
		{
			//trace('Beat hit! Scaling bg to 1.05, crochet: ' + Conductor.crochet);
			bg.scale.set(1.05, 1.05);
			bgBeatElapsed = 0;
			bgBeatDuration = Conductor.crochet / 1000; // 转换为秒
		}
	}
	
	override function destroy():Void
	{
		// 清理背景缩放状态
		bgScaleLerp = 0;
		bgBeatElapsed = 0;
		bgBeatDuration = 0;
		
		super.destroy();

		FlxG.autoPause = ClientPrefs.data.autoPause;
		if (!FlxG.sound.music.playing && !stopMusicPlay)
			FlxG.sound.playMusic(Paths.music('freakyMenu'));
			
		// 清理BPM提示
		bpmText = null;
		bpmTextBG = null;
	}	
}
