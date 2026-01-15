package states;

import sys.thread.Thread;
import backend.Highscore;
import backend.StageData;
import backend.WeekData;
import backend.Song;
import backend.Rating;

import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.FlxSubState;
import flixel.util.FlxSort;
import flixel.util.FlxStringUtil;
import flixel.util.FlxSave;
import flixel.input.keyboard.FlxKey;
import flixel.animation.FlxAnimationController;
import lime.utils.Assets;
import openfl.utils.Assets as OpenFlAssets;
import openfl.events.KeyboardEvent;
import haxe.Json;

import cutscenes.DialogueBoxPsych;

import states.StoryMenuState;
import states.FreeplayState;
import states.editors.ChartingState;
import states.editors.CharacterEditorState;

import substates.PauseSubState;
import substates.GameOverSubstate;
import substates.ResultsScreen;

#if !flash
import openfl.filters.ShaderFilter;
#end

import shaders.ErrorHandledShader;

import objects.VideoSprite;
import objects.Note.EventNote;
import objects.*;
import states.stages.*;
import states.stages.objects.*;

#if LUA_ALLOWED
import psychlua.*;
#else
import psychlua.LuaUtils;
import psychlua.HScript;
#end

#if HSCRIPT_ALLOWED
import psychlua.HScript.HScriptInfos;
import crowplexus.iris.Iris;
import crowplexus.hscript.Expr.Error as IrisError;
import crowplexus.hscript.Printer;
#end
import lime.app.Application;
import backend.Native;

import funkin.vis.dsp.SpectralAnalyzer;
import funkin.vis.audioclip.frontends.LimeAudioClip;
import objects.Bar as Bar;

/**
 * This is where all the Gameplay stuff happens and is managed
 *
 * here's some useful tips if you are making a mod in source:
 *
 * If you want to add your stage to the game, copy states/stages/Template.hx,
 * and put your stage code there, then, on PlayState, search for
 * "switch (curStage)", and add your stage to that list.
 *
 * If you want to code Events, you can either code it on a Stage file or on PlayState, if you're doing the latter, search for:
 *
 * "function eventPushed" - Only called *one time* when the game loads, use it for precaching events that use the same assets, no matter the values
 * "function eventPushedUnique" - Called one time per event, use it for precaching events that uses different assets based on its values
 * "function eventEarlyTrigger" - Used for making your event start a few MILLISECONDS earlier
 * "function triggerEvent" - Called when the song hits your event's timestamp, this is probably what you were looking for
**/

// 回放数据类型定义
typedef ReplayData = {
	time:Float,				// 按下时间（相对于歌曲开始）
	key:Int,				// 按下的键（0-3）
	noteTime:Null<Float>,	// 音符时间（如果是打击音符），null表示空按
	late:Null<Float>,		// 延迟（ms），正数表示晚，负数表示早
	judge:String,			// 判定结果（sick/good/bad/shit/miss/ghost/release）
	releaseTime:Null<Float>	// 按键抬起的绝对时间，null表示未抬起
}

class PlayState extends MusicBeatState
{
	//杂七杂八的新特性
	var notesHitArray:Array<Date> = [];
	var nps:Int = 0;
	var maxNPS:Int = 0;
	var npsCheck:Int = 0;
	var allNotesMs:Float = 0;
	var averageMs:Float = 0;
	var msTimeTxt:FlxText;
	var msTimeTxtTween1:FlxTween;
	var msTimeTxtTween2:FlxTween;
	var scoreTxtTweenAngle:FlxTween;

	// 存储打击数据供 HitGraph 使用 [diff, judge, time]
	public var hitHistory:Array<Array<Dynamic>> = [];
	
	// 回放系统
	public var replayData:Array<ReplayData> = [];	// 回放数据
	public var isReplaying:Bool = false;			// 是否正在回放
	public var currentReplayIndex:Int = 0;			// 当前回放索引
	var replayHeldKeys:Array<Bool> = [false, false, false, false];	// 回放时按下的键状态（用于长按）
	var keyPressIndices:Array<Int> = [-1, -1, -1, -1];	// 记录每个按键最后一次按下对应的replayData索引
	var replayNoteDelays:Array<Array<{strumTime:Float, late:Float}>> = [[], [], [], []];	// 存储每个键对应的音符延迟
	var currentNoteDelayOverride:Null<Float> = null;	// 当前音符的延迟覆盖值（replay模式使用）
	
	// 静态变量用于传递回放数据
	public static var pendingReplayData:Array<ReplayData> = null;	// 待加载的回放数据
	public static var shouldStartReplay:Bool = false;			// 是否应该启动回放
	
	var dancingLeft:Bool = false;
	var icondancingLeft:Bool = false;
	public var iconBopEnabled:Bool = true;
	var ratingexspr:String = '';
	var exratingexspr:String = '-extra';
	var numexspr:String = '';
	var ratingAlpha:Float = ClientPrefs.data.ratingsAlpha;
	var iconP1InitialY:Float;
	var iconP2InitialY:Float;
	var botCheck:Bool = false; // 默认血条范围是0-2
	var totalEvents:Int = 0; // 添加在类变量区
	var eventAlerts:Array<FlxText> = [];
	var debugTexts:FlxTypedGroup<FlxText>;
	var chartingInfo:FlxText;
	var fpsVarInitialX:Float = 10;
	
	//专为仿LE设计的时间条多颜色（大概吧）
	var timeBarLeftColor:FlxColor = FlxColor.BLACK;
	var timeBarRightColor:FlxColor = FlxColor.WHITE;
	var timeBarLeftColorTarget:FlxColor = FlxColor.BLACK;
	var timeBarRightColorTarget:FlxColor = FlxColor.WHITE;

	public var eventDebugGroup:FlxTypedGroup<FlxText>; // 存储事件文本的组

	// 事件处理器
	public var eventHandler:EventHandler;

	//可以被lua调用的杂项
    public var targetZoom:Float = ClientPrefs.data.hudSize;

	//MRE特有的小图标角度变化
	var iconP1TargetAngle:Float = 0;
	var iconP2TargetAngle:Float = 0;
	var iconP1AngleLerpSpeed:Float = 0.11;
	var iconP2AngleLerpSpeed:Float = 0.11;



	// 丝滑血条
	var displayedHealth:Float = 1; // 用于显示的血量
	var healthLerp:Float = 1; // 用于平滑过渡的血量
	var maxHealth:Float = 2; // 默认血条最大值
	//var iconsAnimations:Bool = true; // 控制图标动画的开关
	var cpuHits:Int = 0;

	public static var STRUM_X = 42;
	public static var STRUM_X_MIDDLESCROLL = -278;

	public static var ratingStuff:Array<Dynamic> = [
		['You Suck!', 0.2], //From 0% to 19%
		['Shit', 0.4], //From 20% to 39%
		['Bad', 0.5], //From 40% to 49%
		['Bruh', 0.6], //From 50% to 59%
		['Meh', 0.69], //From 60% to 68%
		['Nice', 0.7], //69%
		['Good', 0.8], //From 70% to 79%
		['Great', 0.9], //From 80% to 89%
		['Sick!', 1], //From 90% to 99%
		['Perfect!!', 1] //The value on this one isn't used actually, since Perfect is always "1"
	];
	public var ratingStuffKE:Array<Dynamic> = 
    [
		["D", 0.6], // accuracy < 60
		["C", 0.7], // accuracy >= 60
		["B", 0.80], // accuracy >= 70
		["A", 0.85], // accuracy >= 80
		["A.", 0.9], // accuracy >= 85
		["A:", 0.93], // accuracy >= 90
		["AA", 0.965], // accuracy >= 93
		["AA.", 0.99], // accuracy >= 96.50
		["AA:", 0.997], // accuracy >= 99
		["AAA", 0.998], // accuracy >= 99.70
		["AAA.", 0.999], // accuracy >= 99.80
		["AAA:", 0.99955], // accuracy >= 99.90
		["AAAA", 0.99970], // accuracy >= 99.955
		["AAAA.", 0.99980], // accuracy >= 99.970
		["AAAA:", 0.999935], // accuracy >= 99.980
		["AAAAA", 1], // accuracy >= 99.9935
		["AAAAA", 1], // accuracy >= 99.9935    
		];

	//event variables
	public var isCameraOnForcedPos:Bool = false;

	public var boyfriendMap:Map<String, Character> = new Map<String, Character>();
	public var dadMap:Map<String, Character> = new Map<String, Character>();
	public var gfMap:Map<String, Character> = new Map<String, Character>();

	#if HSCRIPT_ALLOWED
	public var hscriptArray:Array<HScript> = [];
	#end

	public var BF_X:Float = 770;
	public var BF_Y:Float = 100;
	public var DAD_X:Float = 100;
	public var DAD_Y:Float = 100;
	public var GF_X:Float = 400;
	public var GF_Y:Float = 130;

	public var songSpeedTween:FlxTween;
	public var songSpeed(default, set):Float = 1;
	public var songSpeedType:String = "multiplicative";
	public var noteKillOffset:Float = 350;

	public var playbackRate(default, set):Float = 1;

	public var eventsPushed(get, never):Array<String>;
	private function get_eventsPushed():Array<String> { return eventHandler != null ? eventHandler.eventsPushed : []; }

	public var boyfriendGroup:FlxSpriteGroup;
	public var dadGroup:FlxSpriteGroup;
	public var gfGroup:FlxSpriteGroup;
	public static var curStage:String = '';
	public static var stageUI(default, set):String = "normal";
	public static var uiPrefix:String = "";
	public static var uiPostfix:String = "";
	public static var isPixelStage(get, never):Bool;

	@:noCompletion
	static function set_stageUI(value:String):String
	{
		uiPrefix = uiPostfix = "";
		if (value != "normal")
		{
			uiPrefix = value.split("-pixel")[0].trim();
			if (value == "pixel" || value.endsWith("-pixel")) uiPostfix = "-pixel";
		}
		return stageUI = value;
	}

	@:noCompletion
	static function get_isPixelStage():Bool
		return stageUI == "pixel" || stageUI.endsWith("-pixel");

	public static var SONG:SwagSong = null;
	public static var isStoryMode:Bool = false;
	public static var storyWeek:Int = 0;
	public static var storyPlaylist:Array<String> = [];
	public static var storyDifficulty:Int = 1;

	public var spawnTime:Float = 2000;

	public var inst:FlxSound;
	public var vocals:FlxSound;
	public var opponentVocals:FlxSound;

	public var dad:Character = null;
	public var gf:Character = null;
	public var boyfriend:Character = null;

	public var notes:FlxTypedGroup<Note>;
	public var unspawnNotes:Array<Note> = [];
	public var eventNotes:Array<EventNote> = [];

	public var camFollow:FlxObject;
	private static var prevCamFollow:FlxObject;

	public var strumLineNotes:FlxTypedGroup<StrumNote> = new FlxTypedGroup<StrumNote>();
	public var opponentStrums:FlxTypedGroup<StrumNote> = new FlxTypedGroup<StrumNote>();
	public var playerStrums:FlxTypedGroup<StrumNote> = new FlxTypedGroup<StrumNote>();
	public var grpNoteSplashes:FlxTypedGroup<NoteSplash> = new FlxTypedGroup<NoteSplash>();

	public var camZooming:Bool = false;
	public var camZoomingMult:Float = 1;
	public var camZoomingDecay:Float = 1;
	private var curSong:String = "";

	public var gfSpeed:Int = 1;
	public var health(default, set):Float = 1;
	public var combo:Int = 0;

	public var healthBar:Bar;
	public var timeBar:Bar;
	var songPercent:Float = 0;

	public var ratingsData:Array<Rating> = Rating.loadDefault();

	private var generatedMusic:Bool = false;
	public var endingSong:Bool = false;
	public var startingSong:Bool = false;
	private var updateTime:Bool = true;
	public static var changedDifficulty:Bool = false;
	public static var chartingMode:Bool = false;

	//Gameplay settings
	public var healthGain:Float = 1;
	public var healthLoss:Float = 1;

	public var guitarHeroSustains:Bool = false;
	public var instakillOnMiss:Bool = false;
	public var cpuControlled:Bool = false;
	public var practiceMode:Bool = false;
	public var pressMissDamage:Float = 0.05;

	public var botplaySine:Float = 0;
	public var botplayTxt:FlxText;
	public var replayTxt:FlxText;
	public var watermarkText:FlxText;
	public var ratingCounter:FlxText;

	public var iconP1:HealthIcon;
	public var iconP2:HealthIcon;
	public var camHUD:FlxCamera;
	public var camGame:FlxCamera;
	public var camOther:FlxCamera;
	public var camArchived:FlxCamera;
	public var luaTpadCam:FlxCamera;
	public var cameraSpeed:Float = 1;

	public var songScore:Int = 0;
	public var songHits:Int = 0;
	public var songMisses:Int = 0;
	public var scoreTxt:FlxText;
	var timeTxt:FlxText;
	var scoreTxtTween:FlxTween;

	public static var campaignScore:Int = 0;
	public static var campaignMisses:Int = 0;
	public static var seenCutscene:Bool = false;
	public static var deathCounter:Int = 0;

	public var defaultCamZoom:Float = 1.05;

	// how big to stretch the pixel art assets
	public static var daPixelZoom:Float = 6;
	private var singAnimations:Array<String> = ['singLEFT', 'singDOWN', 'singUP', 'singRIGHT'];

	public var inCutscene:Bool = false;
	public var skipCountdown:Bool = false;
	var songLength:Float = 0;

	public var boyfriendCameraOffset:Array<Float> = null;
	public var opponentCameraOffset:Array<Float> = null;
	public var girlfriendCameraOffset:Array<Float> = null;

	#if DISCORD_ALLOWED
	// Discord RPC variables
	var storyDifficultyText:String = "";
	var detailsText:String = "";
	var detailsPausedText:String = "";
	#end

	//Achievement shit
	var keysPressed:Array<Int> = [];
	var boyfriendIdleTime:Float = 0.0;
	var boyfriendIdled:Bool = false;

	// Lua shit
	public static var instance:PlayState;
	#if LUA_ALLOWED public var luaArray:Array<FunkinLua> = []; #end

	#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
	private var luaDebugGroup:FlxTypedGroup<psychlua.DebugLuaText>;
	#end
	public var introSoundsSuffix:String = '';

	// Less laggy controls
	private var keysArray:Array<String>;
	public var songName:String;

	// Callbacks for stages
	public var startCallback:Void->Void = null;
	public var endCallback:Void->Void = null;

	private var shutdownThread:Bool = false;
	private var gameFroze:Bool = false;
	private var requiresSyncing:Bool = false;
	private var lastCorrectSongPos:Float = -1.0;

	private static var _lastLoadedModDirectory:String = '';
	public static var nextReloadAll:Bool = false;

	public var luaTouchPad:TouchPad;

	// 添加一个变量用于平滑血条
	private var smoothHealth:Float = 1;

	public var audioAnalyzer:SpectralAnalyzer;

	public function initAnalyzer(barCount:Int, maxDelta:Float = 0.01, peakHold:Int = 30) {
		@:privateAccess
		if (FlxG.sound.music == null || FlxG.sound.music._channel == null || FlxG.sound.music._channel.__audioSource == null) return;

		@:privateAccess
		audioAnalyzer = new SpectralAnalyzer(FlxG.sound.music._channel.__audioSource, barCount, maxDelta, peakHold);

		#if desktop
		audioAnalyzer.fftN = 256;
		#end
	}

	public function getAudioLevels() {
		var levels = audioAnalyzer.getLevels();
		return [for (i in levels) i.value];
	}

	override public function create()
	{
		//trace('Playback Rate: ' + playbackRate);
		_lastLoadedModDirectory = Mods.currentModDirectory;
		Paths.clearStoredMemory();
		if(nextReloadAll)
		{
			Paths.clearUnusedMemory();
			LanguageBasic.reloadPhrases();
		}
		nextReloadAll = false;

		// 检查是否有待加载的回放数据
		if(shouldStartReplay && pendingReplayData != null)
		{
			isReplaying = true;
			replayData = pendingReplayData;
			currentReplayIndex = 0;
			shouldStartReplay = false;
			pendingReplayData = null;
			// 重置按键状态
			replayHeldKeys = [false, false, false, false];
			keyPressIndices = [-1, -1, -1, -1];
			// 初始化延迟存储数组
			replayNoteDelays = [[], [], [], []];
			// 预填充延迟数据，以便在 popUpScore 中快速查找
			for(action in replayData)
			{
				if(action.noteTime != null && action.late != null && action.key >= 0 && action.key < 4)
				{
					// 存储延迟值 {strumTime:Float, late:Float}
					replayNoteDelays[action.key].push({strumTime: action.noteTime, late: action.late});
				}
			}
		}
		else
		{
			isReplaying = false;
			replayData = [];
			currentReplayIndex = 0;
			replayHeldKeys = [false, false, false, false];
			keyPressIndices = [-1, -1, -1, -1];
			replayNoteDelays = [[], [], [], []];
		}

		startCallback = startCountdown;
		endCallback = endSong;

		// for lua
		instance = this;

		PauseSubState.songName = null; //Reset to default
		playbackRate = ClientPrefs.getGameplaySetting('songspeed');

		keysArray = [
			'note_left',
			'note_down',
			'note_up',
			'note_right'
		];

		if(FlxG.sound.music != null)
			FlxG.sound.music.stop();

		// Gameplay settings
		healthGain = ClientPrefs.getGameplaySetting('healthgain');
		healthLoss = ClientPrefs.getGameplaySetting('healthloss');
		instakillOnMiss = ClientPrefs.getGameplaySetting('instakill');
		practiceMode = ClientPrefs.getGameplaySetting('practice');
		cpuControlled = ClientPrefs.getGameplaySetting('botplay');
		guitarHeroSustains = ClientPrefs.data.guitarHeroSustains;

		// var gameCam:FlxCamera = FlxG.camera;
		camGame = initPsychCamera();
		camHUD = new FlxCamera();
		camOther = new FlxCamera();
		camArchived = new FlxCamera();
		luaTpadCam = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		camOther.bgColor.alpha = 0;
		camArchived.bgColor.alpha = 0;
		luaTpadCam.bgColor.alpha = 0;
		if(ClientPrefs.data.hudSize != 1.0) {
    		camHUD.zoom = ClientPrefs.data.hudSize;
		}

		FlxG.cameras.add(camHUD, false);
		FlxG.cameras.add(camOther, false);
		FlxG.cameras.add(camArchived, false);
		FlxG.cameras.add(luaTpadCam, false);

		persistentUpdate = true;
		persistentDraw = true;

		Conductor.mapBPMChanges(SONG);
		Conductor.bpm = SONG.bpm;

		#if DISCORD_ALLOWED
		// String that contains the mode defined here so it isn't necessary to call changePresence for each mode
		storyDifficultyText = Difficulty.getString();

		if (isStoryMode)
			detailsText = "Story Mode: " + WeekData.getCurrentWeek().weekName;
		else
			detailsText = "Freeplay";

		// String for when the game is paused
		detailsPausedText = "Paused - " + detailsText;
		#end

		GameOverSubstate.resetVariables();
		songName = Paths.formatToSongPath(SONG.song);
		if(SONG.stage == null || SONG.stage.length < 1)
			SONG.stage = StageData.vanillaSongStage(Paths.formatToSongPath(Song.loadedSongName));

		curStage = SONG.stage;

		var stageData:StageFile = StageData.getStageFile(curStage);
		defaultCamZoom = stageData.defaultZoom;

		stageUI = "normal";
		if (stageData.stageUI != null && stageData.stageUI.trim().length > 0)
			stageUI = stageData.stageUI;
		else if (stageData.isPixelStage == true) //Backward compatibility
			stageUI = "pixel";

		BF_X = stageData.boyfriend[0];
		BF_Y = stageData.boyfriend[1];
		GF_X = stageData.girlfriend[0];
		GF_Y = stageData.girlfriend[1];
		DAD_X = stageData.opponent[0];
		DAD_Y = stageData.opponent[1];

		if(stageData.camera_speed != null)
			cameraSpeed = stageData.camera_speed;

		boyfriendCameraOffset = stageData.camera_boyfriend;
		if(boyfriendCameraOffset == null) //Fucks sake should have done it since the start :rolling_eyes:
			boyfriendCameraOffset = [0, 0];

		opponentCameraOffset = stageData.camera_opponent;
		if(opponentCameraOffset == null)
			opponentCameraOffset = [0, 0];

		girlfriendCameraOffset = stageData.camera_girlfriend;
		if(girlfriendCameraOffset == null)
			girlfriendCameraOffset = [0, 0];

		boyfriendGroup = new FlxSpriteGroup(BF_X, BF_Y);
		dadGroup = new FlxSpriteGroup(DAD_X, DAD_Y);
		gfGroup = new FlxSpriteGroup(GF_X, GF_Y);

		switch (curStage)
		{
			case 'stage': new StageWeek1(); 			//Week 1
			case 'spooky': new Spooky();				//Week 2
			case 'philly': new Philly();				//Week 3
			case 'limo': new Limo();					//Week 4
			case 'mall': new Mall();					//Week 5 - Cocoa, Eggnog
			case 'mallEvil': new MallEvil();			//Week 5 - Winter Horrorland
			case 'school': new School();				//Week 6 - Senpai, Roses
			case 'schoolEvil': new SchoolEvil();		//Week 6 - Thorns
			case 'tank': new Tank();					//Week 7 - Ugh, Guns, Stress
			case 'phillyStreets': new PhillyStreets(); 	//Weekend 1 - Darnell, Lit Up, 2Hot
			case 'phillyBlazin': new PhillyBlazin();	//Weekend 1 - Blazin
		}
		if(isPixelStage) introSoundsSuffix = '-pixel';

		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		luaDebugGroup = new FlxTypedGroup<psychlua.DebugLuaText>();
		luaDebugGroup.cameras = [camArchived];
		add(luaDebugGroup);
		#end

		if (!stageData.hide_girlfriend)
		{
			if(SONG.gfVersion == null || SONG.gfVersion.length < 1) SONG.gfVersion = 'gf'; //Fix for the Chart Editor
			gf = new Character(0, 0, SONG.gfVersion);
			startCharacterPos(gf);
			gfGroup.scrollFactor.set(0.95, 0.95);
			gfGroup.add(gf);
		}

		dad = new Character(0, 0, SONG.player2);
		startCharacterPos(dad, true);
		dadGroup.add(dad);

		boyfriend = new Character(0, 0, SONG.player1, true);
		startCharacterPos(boyfriend);
		boyfriendGroup.add(boyfriend);
		
		if(stageData.objects != null && stageData.objects.length > 0)
		{
			var list:Map<String, FlxSprite> = StageData.addObjectsToState(stageData.objects, !stageData.hide_girlfriend ? gfGroup : null, dadGroup, boyfriendGroup, this);
			for (key => spr in list)
				if(!StageData.reservedNames.contains(key))
					variables.set(key, spr);
		}
		else
		{
			add(gfGroup);
			add(dadGroup);
			add(boyfriendGroup);
		}
		
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		// "SCRIPTS FOLDER" SCRIPTS
		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'scripts/'))
			#if linux
			for (file in CoolUtil.sortAlphabetically(Paths.readDirectory(folder)))
			#else
			for (file in Paths.readDirectory(folder))
			#end
			{
				#if LUA_ALLOWED
				if(file.toLowerCase().endsWith('.lua'))
					new FunkinLua(folder + file);
				#end

				#if HSCRIPT_ALLOWED
				if(file.toLowerCase().endsWith('.hx'))
					initHScript(folder + file);
				#end
			}
		#end
			
		eventDebugGroup = new FlxTypedGroup<FlxText>();
		eventDebugGroup.cameras = [camArchived];
		add(eventDebugGroup);

		// 初始化事件处理器
		eventHandler = new EventHandler(this);

		var camPos:FlxPoint = FlxPoint.get(girlfriendCameraOffset[0], girlfriendCameraOffset[1]);
		if(gf != null)
		{
			camPos.x += gf.getGraphicMidpoint().x + gf.cameraPosition[0];
			camPos.y += gf.getGraphicMidpoint().y + gf.cameraPosition[1];
		}

		if(dad.curCharacter.startsWith('gf')) {
			dad.setPosition(GF_X, GF_Y);
			if(gf != null)
				gf.visible = false;
		}
		
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		// STAGE SCRIPTS
		#if LUA_ALLOWED startLuasNamed('stages/' + curStage + '.lua'); #end
		#if HSCRIPT_ALLOWED startHScriptsNamed('stages/' + curStage + '.hx'); #end

		// CHARACTER SCRIPTS
		if(gf != null) startCharacterScripts(gf.curCharacter);
		startCharacterScripts(dad.curCharacter);
		startCharacterScripts(boyfriend.curCharacter);
		#end

		uiGroup = new FlxSpriteGroup();
		comboGroup = new FlxSpriteGroup();
		noteGroup = new FlxTypedGroup<FlxBasic>();
		add(comboGroup);
		add(uiGroup);
		add(noteGroup);

		Conductor.songPosition = -Conductor.crochet * 5 + Conductor.offset;
		var showTime:Bool = (ClientPrefs.data.timeBarType != 'Disabled');

		timeTxt = new FlxText(STRUM_X + (FlxG.width / 2) - 248, 19, 640, "", 32);
		timeTxt.setFormat(Paths.font("vcr.ttf"), ClientPrefs.data.timebarStyle == "Leather" ? 16 : 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE,
			FlxColor.BLACK);
		timeTxt.scrollFactor.set();
		timeTxt.alpha = 0;
		timeTxt.borderSize = ClientPrefs.data.timebarStyle == "Leather" ? 1 : 2;
		timeTxt.visible = updateTime = showTime;
		timeTxt.screenCenter(X);

		if (ClientPrefs.data.downScroll)
			timeTxt.y = FlxG.height - 44;

		if (ClientPrefs.data.timeBarType == 'Song Name' && ClientPrefs.data.timebarStyle != "Leather")
		{
			timeTxt.text = SONG.song;
		}

		// 确定条样式
		var barStyle:String = "timeBar";
		if (ClientPrefs.data.timebarStyle == "Kade (Legacy)")
		{
			barStyle = "barKEL";
		}
		else if (ClientPrefs.data.timebarStyle == "Leather")
		{
			barStyle = "barLE";
		}

		timeBar = new Bar(0, timeTxt.y + (timeTxt.height / 4), barStyle, function() return songPercent, 0, 1);
		timeBar.scrollFactor.set();
		timeBar.screenCenter(X);
		timeBar.alpha = 0;
		timeBar.visible = showTime;

		// 特殊处理Leather样式
		if (ClientPrefs.data.timebarStyle == "Leather")
		{
			timeTxt.size = 16;
			timeBar.y = FlxG.height - (timeBar.height + 1);
			timeTxt.y = timeBar.y - (timeTxt.height);
			timeTxt.text = SONG.song + " ~ " + Difficulty.getString().toUpperCase() + " (0:00)";
		}
		
		else
		{
			timeBar.y = timeTxt.y + (timeTxt.height / 4);
		}

		uiGroup.add(timeBar);
		uiGroup.add(timeTxt);

		noteGroup.add(strumLineNotes);

		// 处理Song Name类型的调整（排除Leather样式）
		if (ClientPrefs.data.timeBarType == 'Song Name' && ClientPrefs.data.timebarStyle != "Leather")
		{
			timeTxt.size = 24;
			timeTxt.y += 3;
		}

		generateSong();

		noteGroup.add(grpNoteSplashes);

		camFollow = new FlxObject();
		camFollow.setPosition(camPos.x, camPos.y);
		camPos.put();

		if (prevCamFollow != null)
		{
			camFollow = prevCamFollow;
			prevCamFollow = null;
		}
		add(camFollow);

		FlxG.camera.follow(camFollow, LOCKON, 0);
		FlxG.camera.zoom = defaultCamZoom;
		FlxG.camera.snapToTarget();

		FlxG.worldBounds.set(0, 0, FlxG.width, FlxG.height);
		moveCameraSection();

		healthBar = new Bar(0, FlxG.height * (!ClientPrefs.data.downScroll ? 0.89 : 0.11), 'healthBar', function() return health, 0, 2);
		healthBar.screenCenter(X);
		healthBar.leftToRight = false;
		healthBar.scrollFactor.set();
		healthBar.visible = !ClientPrefs.data.hideHud;
		healthBar.alpha = ClientPrefs.data.healthBarAlpha;
		reloadHealthBarColors();
		uiGroup.add(healthBar);

		msTimeTxt = new FlxText(0, 0, 250, "", 32);
		msTimeTxt.setFormat(Paths.font('vcr.ttf'), 24, FlxColor.WHITE, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		msTimeTxt.scrollFactor.set();
		msTimeTxt.alpha = 0;
		msTimeTxt.visible = true;
		msTimeTxt.borderSize = 1.3;
		/*mstimeTxt.y = comboSpr.y + 20;
		mstimeTxt.x += comboSpr.x + 100;*/
		msTimeTxt.x = ClientPrefs.data.comboOffset[2] + 480;
		msTimeTxt.y = -ClientPrefs.data.comboOffset[3] + 480 ;
		uiGroup.add(msTimeTxt);

		iconP1 = new HealthIcon(boyfriend.healthIcon, true);
		iconP1.y = healthBar.y - 75;
		iconP1.visible = !ClientPrefs.data.hideHud;
		iconP1.alpha = ClientPrefs.data.healthBarAlpha;
		uiGroup.add(iconP1);

		iconP2 = new HealthIcon(dad.healthIcon, false);
		iconP2.y = healthBar.y - 75;
		iconP2.visible = !ClientPrefs.data.hideHud;
		iconP2.alpha = ClientPrefs.data.healthBarAlpha;
		uiGroup.add(iconP2);

		if(ClientPrefs.data.scoretxtstyle == 'Kade') 
		{
		scoreTxt = new FlxText(0, healthBar.y + 50, FlxG.width, "", 20);
		scoreTxt.screenCenter(X);
		scoreTxt.scrollFactor.set();
		scoreTxt.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		}
		else if (ClientPrefs.data.scoretxtstyle == 'V-Slice')	
		{
			scoreTxt = new FlxText(FlxG.width / 2 - 235, healthBar.y + 50, 0, "", 20);
			scoreTxt.screenCenter(X);
			scoreTxt.x += 100;
			scoreTxt.scrollFactor.set();
			scoreTxt.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		}
		else 
		{
		scoreTxt = new FlxText(0, healthBar.y + 40, FlxG.width, "", 20);
		scoreTxt.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		scoreTxt.scrollFactor.set();
		scoreTxt.borderSize = 1.25;
		scoreTxt.visible = !ClientPrefs.data.hideHud;
		}
		uiGroup.add(scoreTxt);

		botplayTxt = new FlxText(400, ClientPrefs.data.botplayStyle == 'Kade' ? healthBar.y - 120 : healthBar.y - 90, FlxG.width - 800, "BOTPLAY", 32);
		//botplayTxt = new FlxText(400, healthBar.y - 90, FlxG.width - 800, LanguageBasic.getPhrase("Botplay").toUpperCase(), 32);
		botplayTxt.setFormat(Paths.font("vcr.ttf"), ClientPrefs.data.botplayStyle == 'Kade' ? 37 : 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		botplayTxt.scrollFactor.set();
		botplayTxt.borderSize = ClientPrefs.data.botplayStyle == 'Kade' ? 2 : 1.25;
		botplayTxt.visible = cpuControlled;
		uiGroup.add(botplayTxt);

		// 创建回放模式指示文本
		replayTxt = new FlxText(400, ClientPrefs.data.botplayStyle == 'Kade' ? healthBar.y - 120 : healthBar.y - 90, FlxG.width - 800, "RECAP", 32);
		replayTxt.setFormat(Paths.font("vcr.ttf"), 37, 0xFF00FF00, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		replayTxt.scrollFactor.set();
		replayTxt.borderSize = 2;
		replayTxt.color = FlxColor.fromRGB(boyfriend.healthColorArray[0], boyfriend.healthColorArray[1], boyfriend.healthColorArray[2]);
		replayTxt.visible = isReplaying;
		uiGroup.add(replayTxt);
		if(ClientPrefs.data.downScroll)
			botplayTxt.y = ClientPrefs.data.botplayStyle == 'Kade' ? healthBar.y + 120 : healthBar.y + 70;

		watermarkText = new FlxText(20, FlxG.height - 20, 0,
			(ClientPrefs.data.timebarStyle == 'Leather' ? 'M.R.E v${Application.current.meta.get('version')}' : '${SONG.song}-${Difficulty.getString().toUpperCase()} | PE-MRE ${MainMenuState.mrExtendVersion}'),
			14);
		watermarkText.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		watermarkText.scrollFactor.set();
		watermarkText.borderSize = 1.2;
		watermarkText.y = !ClientPrefs.data.downScroll ? 20 : FlxG.height - 20;
		watermarkText.alpha = 0.8;
		watermarkText.visible = !ClientPrefs.data.hideHud;
		if (ClientPrefs.data.waterMarkPlay)	uiGroup.add(watermarkText);

		ratingCounter = new FlxText(6, 0, 0, "", 20);
		ratingCounter.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		//ratingCounter.borderSize = 1;
		ratingCounter.scrollFactor.set();
		ratingCounter.visible = !ClientPrefs.data.hideHud;
		//ratingCounter.y = (FlxG.height - ratingCounter.height * 5) / 2;
		ratingCounter.screenCenter(Y);
		uiGroup.add(ratingCounter);

		uiGroup.cameras = [camHUD];
		noteGroup.cameras = [camHUD];
		//comboGroup.cameras = [camHUD];
		comboGroup.cameras = [ClientPrefs.data.ratingsPos == 'camHUD' ? camHUD : camGame];
		msTimeTxt.cameras = [ClientPrefs.data.ratingsPos == 'camHUD' ? camHUD : camGame];
		startingSong = true;

		#if LUA_ALLOWED
		for (notetype in noteTypes)
			startLuasNamed('custom_notetypes/' + notetype + '.lua');
		for (event in eventsPushed)
			startLuasNamed('custom_events/' + event + '.lua');
		#end

		#if HSCRIPT_ALLOWED
		for (notetype in noteTypes)
			startHScriptsNamed('custom_notetypes/' + notetype + '.hx');
		for (event in eventsPushed)
			startHScriptsNamed('custom_events/' + event + '.hx');
		#end
		noteTypes = null;

		// SONG SPECIFIC SCRIPTS
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'data/$songName/'))
			#if linux
			for (file in CoolUtil.sortAlphabetically(Paths.readDirectory(folder)))
			#else
			for (file in Paths.readDirectory(folder))
			#end
			{
				#if LUA_ALLOWED
				if(file.toLowerCase().endsWith('.lua'))
					new FunkinLua(folder + file);
				#end

				#if HSCRIPT_ALLOWED
				if(file.toLowerCase().endsWith('.hx'))
					initHScript(folder + file);
				#end
			}
		#end
		
		addMobileControls();
		mobileControls.instance.visible = true;
		mobileControls.onButtonDown.add(onButtonPress);
		mobileControls.onButtonUp.add(onButtonRelease);

		if(eventNotes.length > 0)
		{
			for (event in eventNotes) event.strumTime -= eventHandler.eventEarlyTrigger(event);
			eventNotes.sort(sortByTime);
		}

		startCallback();
		RecalculateRating(false, false);

		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyRelease);

		//PRECACHING THINGS THAT GET USED FREQUENTLY TO AVOID LAGSPIKES
		if(ClientPrefs.data.hitsoundVolume > 0) Paths.sound('hitsound');
		if(!ClientPrefs.data.ghostTapping) for (i in 1...4) Paths.sound('missnote$i');
		Paths.image('alphabet');

		if (PauseSubState.songName != null)
			Paths.music(PauseSubState.songName);
		else if(Paths.formatToSongPath(ClientPrefs.data.pauseMusic) != 'none')
			Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic));

		resetRPC();

		stagesFunc(function(stage:BaseStage) stage.createPost());
		callOnScripts('onCreatePost');
		
		var splash:NoteSplash = new NoteSplash();
		grpNoteSplashes.add(splash);
		splash.alpha = 0.000001; //cant make it invisible or it won't allow precaching

		#if !android
		addTouchPad('NONE', 'P');
		addTouchPadCamera();
		#end

		super.create();
		iconP1InitialY = iconP1.y;
   	 	iconP2InitialY = iconP2.y;
		Paths.clearUnusedMemory();

		cacheCountdown();
		cachePopUpScore();

		if(eventNotes.length < 1) eventHandler.checkEventNote();
	}

	function set_songSpeed(value:Float):Float
	{
		if(generatedMusic)
		{
			var ratio:Float = value / songSpeed; //funny word huh
			if(ratio != 1)
			{
				for (note in notes.members) note.resizeByRatio(ratio);
				for (note in unspawnNotes) note.resizeByRatio(ratio);
			}
		}
		songSpeed = value;
		noteKillOffset = Math.max(Conductor.stepCrochet, 350 / songSpeed * playbackRate);
		return value;
	}

	function set_playbackRate(value:Float):Float
	{
		#if FLX_PITCH
		if(generatedMusic)
		{
			vocals.pitch = value;
			opponentVocals.pitch = value;
			FlxG.sound.music.pitch = value;

			var ratio:Float = playbackRate / value; //funny word huh
			if(ratio != 1)
			{
				for (note in notes.members) note.resizeByRatio(ratio);
				for (note in unspawnNotes) note.resizeByRatio(ratio);
			}
		}
		playbackRate = value;
		FlxG.animationTimeScale = value;
		Conductor.offset = Reflect.hasField(PlayState.SONG, 'offset') ? (PlayState.SONG.offset / value) : 0;
		Conductor.safeZoneOffset = (ClientPrefs.data.safeFrames / 60) * 1000 * value;
		#if VIDEOS_ALLOWED
		if(videoCutscene != null && videoCutscene.videoSprite != null) videoCutscene.videoSprite.bitmap.rate = value;
		#end
		setOnScripts('playbackRate', playbackRate);
		#else
		playbackRate = 1.0; // ensuring -Crow
		#end
		return playbackRate;
	}

	#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
	public function addTextToDebug(text:String, color:FlxColor) {
		var newText:psychlua.DebugLuaText = luaDebugGroup.recycle(psychlua.DebugLuaText);
		newText.text = text;
		newText.color = color;
		newText.disableTime = 6;
		newText.alpha = 1;
		newText.setPosition(10, 8 - newText.height);

		luaDebugGroup.forEachAlive(function(spr:psychlua.DebugLuaText) {
			spr.y += newText.height + 2;
		});
		luaDebugGroup.add(newText);

		Sys.println(text);
		
		// 同时输出到游戏日志显示
		if (Main.gameLogVar != null && Main.gameLogVar.isEnabled)
		{
			Main.gameLogVar.addLogWithColor(text, color);
		}
	}
	#end

	public function reloadHealthBarColors() {
		healthBar.setColors(FlxColor.fromRGB(dad.healthColorArray[0], dad.healthColorArray[1], dad.healthColorArray[2]),
			FlxColor.fromRGB(boyfriend.healthColorArray[0], boyfriend.healthColorArray[1], boyfriend.healthColorArray[2]));
	}

	public function addCharacterToList(newCharacter:String, type:Int) {
		switch(type) {
			case 0:
				if(!boyfriendMap.exists(newCharacter)) {
					var newBoyfriend:Character = new Character(0, 0, newCharacter, true);
					boyfriendMap.set(newCharacter, newBoyfriend);
					boyfriendGroup.add(newBoyfriend);
					startCharacterPos(newBoyfriend);
					newBoyfriend.alpha = 0.00001;
					startCharacterScripts(newBoyfriend.curCharacter);
				}

			case 1:
				if(!dadMap.exists(newCharacter)) {
					var newDad:Character = new Character(0, 0, newCharacter);
					dadMap.set(newCharacter, newDad);
					dadGroup.add(newDad);
					startCharacterPos(newDad, true);
					newDad.alpha = 0.00001;
					startCharacterScripts(newDad.curCharacter);
				}

			case 2:
				if(gf != null && !gfMap.exists(newCharacter)) {
					var newGf:Character = new Character(0, 0, newCharacter);
					newGf.scrollFactor.set(0.95, 0.95);
					gfMap.set(newCharacter, newGf);
					gfGroup.add(newGf);
					startCharacterPos(newGf);
					newGf.alpha = 0.00001;
					startCharacterScripts(newGf.curCharacter);
				}
		}
	}

	function startCharacterScripts(name:String)
	{
		// Lua
		#if LUA_ALLOWED
		var doPush:Bool = false;
		var luaFile:String = 'characters/$name.lua';
		#if MODS_ALLOWED
		var replacePath:String = Paths.modFolders(luaFile);
		if(FileSystem.exists(replacePath))
		{
			luaFile = replacePath;
			doPush = true;
		}
		else
		{
			luaFile = Paths.getSharedPath(luaFile);
			if(FileSystem.exists(luaFile))
				doPush = true;
		}
		#else
		luaFile = Paths.getSharedPath(luaFile);
		if(Assets.exists(luaFile)) doPush = true;
		#end

		if(doPush)
		{
			for (script in luaArray)
			{
				if(script.scriptName == luaFile)
				{
					doPush = false;
					break;
				}
			}
			if(doPush) new FunkinLua(luaFile);
		}
		#end

		// HScript
		#if HSCRIPT_ALLOWED
		var doPush:Bool = false;
		var scriptFile:String = 'characters/' + name + '.hx';
		#if MODS_ALLOWED
		var replacePath:String = Paths.modFolders(scriptFile);
		if(FileSystem.exists(replacePath))
		{
			scriptFile = replacePath;
			doPush = true;
		}
		else
		#end
		{
			scriptFile = Paths.getSharedPath(scriptFile);
			if(FileSystem.exists(scriptFile))
				doPush = true;
		}

		if(doPush)
		{
			if(Iris.instances.exists(scriptFile))
				doPush = false;

			if(doPush) initHScript(scriptFile);
		}
		#end
	}

	public function getLuaObject(tag:String):Dynamic
		return variables.get(tag);

	function startCharacterPos(char:Character, ?gfCheck:Bool = false) {
		if(gfCheck && char.curCharacter.startsWith('gf')) { //IF DAD IS GIRLFRIEND, HE GOES TO HER POSITION
			char.setPosition(GF_X, GF_Y);
			char.scrollFactor.set(0.95, 0.95);
			char.danceEveryNumBeats = 2;
		}
		char.x += char.positionArray[0];
		char.y += char.positionArray[1];
	}

	public var videoCutscene:VideoSprite = null;
	public function startVideo(name:String, forMidSong:Bool = false, canSkip:Bool = true, loop:Bool = false, playOnLoad:Bool = true)
	{
		#if VIDEOS_ALLOWED
		inCutscene = !forMidSong;
		canPause = forMidSong;

		var foundFile:Bool = false;
		var fileName:String = Paths.video(name);

		#if sys
		if (FileSystem.exists(fileName))
		#else
		if (OpenFlAssets.exists(fileName))
		#end
		foundFile = true;

		if (foundFile)
		{
			videoCutscene = new VideoSprite(fileName, forMidSong, canSkip, loop);
			if(forMidSong) videoCutscene.videoSprite.bitmap.rate = playbackRate;

			// Finish callback
			if (!forMidSong)
			{
				function onVideoEnd()
				{
					if (!isDead && generatedMusic && PlayState.SONG.notes[Std.int(curStep / 16)] != null && !endingSong && !isCameraOnForcedPos)
					{
						moveCameraSection();
						FlxG.camera.snapToTarget();
					}
					videoCutscene = null;
					canPause = true;
					inCutscene = false;
					startAndEnd();
				}
				videoCutscene.finishCallback = onVideoEnd;
				videoCutscene.onSkip = onVideoEnd;
			}
			if (GameOverSubstate.instance != null && isDead) GameOverSubstate.instance.add(videoCutscene);
			else add(videoCutscene);

			if (playOnLoad)
				videoCutscene.play();
			return videoCutscene;
		}
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		else addTextToDebug("Video not found: " + fileName, FlxColor.RED);
		#else
		else FlxG.log.error("Video not found: " + fileName);
		#end
		#else
		FlxG.log.warn('Platform not supported!');
		startAndEnd();
		#end
		return null;
	}

	function startAndEnd()
	{
		if(endingSong)
			endSong();
		else
			startCountdown();
	}

	var dialogueCount:Int = 0;
	public var psychDialogue:DialogueBoxPsych;
	//You don't have to add a song, just saying. You can just do "startDialogue(DialogueBoxPsych.parseDialogue(Paths.json(songName + '/dialogue')))" and it should load dialogue.json
	public function startDialogue(dialogueFile:DialogueFile, ?song:String = null):Void
	{
		// TO DO: Make this more flexible, maybe?
		if(psychDialogue != null) return;

		if(dialogueFile.dialogue.length > 0) {
			inCutscene = true;
			psychDialogue = new DialogueBoxPsych(dialogueFile, song);
			psychDialogue.scrollFactor.set();
			if(endingSong) {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					endSong();
				}
			} else {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					startCountdown();
				}
			}
			psychDialogue.nextDialogueThing = startNextDialogue;
			psychDialogue.skipDialogueThing = skipDialogue;
			psychDialogue.cameras = [camHUD];
			add(psychDialogue);
		} else {
			FlxG.log.warn('Your dialogue file is badly formatted!');
			startAndEnd();
		}
	}

	var startTimer:FlxTimer;
	var finishTimer:FlxTimer = null;

	// For being able to mess with the sprites on Lua
	public var countdownReady:FlxSprite;
	public var countdownSet:FlxSprite;
	public var countdownGo:FlxSprite;
	public static var startOnTime:Float = 0;

	function cacheCountdown()
	{
		var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
		var introImagesArray:Array<String> = switch(stageUI) {
			case "pixel": ['pixelUI/ready-pixel', 'pixelUI/set-pixel', 'pixelUI/date-pixel'];
			case "normal": ["ready", "set" ,"go"];
			default: ['${uiPrefix}UI/ready${uiPostfix}', '${uiPrefix}UI/set${uiPostfix}', '${uiPrefix}UI/go${uiPostfix}'];
		}
		introAssets.set(stageUI, introImagesArray);
		var introAlts:Array<String> = introAssets.get(stageUI);
		for (asset in introAlts) Paths.image(asset);

		Paths.sound('intro3' + introSoundsSuffix);
		Paths.sound('intro2' + introSoundsSuffix);
		Paths.sound('intro1' + introSoundsSuffix);
		Paths.sound('introGo' + introSoundsSuffix);
	}

	public function startCountdown()
	{
		if(startedCountdown) {
			callOnScripts('onStartCountdown');
			return false;
		}

		seenCutscene = true;
		inCutscene = false;
		var ret:Dynamic = callOnScripts('onStartCountdown', null, true);
		if(ret != LuaUtils.Function_Stop) {
			if (skipCountdown || startOnTime > 0) skipArrowStartTween = true;

			canPause = true;
			generateStaticArrows(0);
			generateStaticArrows(1);
			for (i in 0...playerStrums.length) {
				setOnScripts('defaultPlayerStrumX' + i, playerStrums.members[i].x);
				setOnScripts('defaultPlayerStrumY' + i, playerStrums.members[i].y);
			}
			for (i in 0...opponentStrums.length) {
				setOnScripts('defaultOpponentStrumX' + i, opponentStrums.members[i].x);
				setOnScripts('defaultOpponentStrumY' + i, opponentStrums.members[i].y);
				//if(ClientPrefs.data.middleScroll) opponentStrums.members[i].visible = false;
			}

			startedCountdown = true;
			Conductor.songPosition = -Conductor.crochet * 5 + Conductor.offset;
			setOnScripts('startedCountdown', true);
			callOnScripts('onCountdownStarted');

			var swagCounter:Int = 0;
			if (startOnTime > 0) {
				clearNotesBefore(startOnTime);
				setSongTime(startOnTime - 350);
				return true;
			}
			else if (skipCountdown)
			{
				setSongTime(0);
				return true;
			}
			moveCameraSection();

			startTimer = new FlxTimer().start(Conductor.crochet / 1000 / playbackRate, function(tmr:FlxTimer)
			{
				characterBopper(tmr.loopsLeft);

				var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
				var introImagesArray:Array<String> = switch(stageUI) {
					case "pixel": ['pixelUI/ready-pixel', 'pixelUI/set-pixel', 'pixelUI/date-pixel'];
					case "normal": ["ready", "set" ,"go"];
					default: ['${uiPrefix}UI/ready${uiPostfix}', '${uiPrefix}UI/set${uiPostfix}', '${uiPrefix}UI/go${uiPostfix}'];
				}
				introAssets.set(stageUI, introImagesArray);

				var introAlts:Array<String> = introAssets.get(stageUI);
				var antialias:Bool = (ClientPrefs.data.antialiasing && !isPixelStage);
				var tick:Countdown = THREE;

				switch (swagCounter)
				{
					case 0:
						FlxG.sound.play(Paths.sound('intro3' + introSoundsSuffix), 0.6);
						tick = THREE;
					case 1:
						countdownReady = createCountdownSprite(introAlts[0], antialias);
						FlxG.sound.play(Paths.sound('intro2' + introSoundsSuffix), 0.6);
						tick = TWO;
					case 2:
						countdownSet = createCountdownSprite(introAlts[1], antialias);
						FlxG.sound.play(Paths.sound('intro1' + introSoundsSuffix), 0.6);
						tick = ONE;
					case 3:
						countdownGo = createCountdownSprite(introAlts[2], antialias);
						FlxG.sound.play(Paths.sound('introGo' + introSoundsSuffix), 0.6);
						tick = GO;
					case 4:
						tick = START;
				}

				if(!skipArrowStartTween)
				{
					notes.forEachAlive(function(note:Note) {
						if(ClientPrefs.data.opponentStrums || note.mustPress)
						{
							note.copyAlpha = false;
							note.alpha = note.multAlpha;
							if(ClientPrefs.data.middleScroll && !note.mustPress)
								note.alpha *= 0.35;
						}
					});
				}

				stagesFunc(function(stage:BaseStage) stage.countdownTick(tick, swagCounter));
				callOnLuas('onCountdownTick', [swagCounter]);
				callOnHScript('onCountdownTick', [tick, swagCounter]);

				swagCounter += 1;
			}, 5);
		}
		return true;
	}

	inline private function createCountdownSprite(image:String, antialias:Bool):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite().loadGraphic(Paths.image(image));
		spr.cameras = [camHUD];
		spr.scrollFactor.set();
		spr.updateHitbox();

		if (PlayState.isPixelStage)
			spr.setGraphicSize(Std.int(spr.width * daPixelZoom));

		spr.screenCenter();
		spr.antialiasing = antialias;
		insert(members.indexOf(noteGroup), spr);
		FlxTween.tween(spr, {/*y: spr.y + 100,*/ alpha: 0}, Conductor.crochet / 1000, {
			ease: FlxEase.cubeInOut,
			onComplete: function(twn:FlxTween)
			{
				remove(spr);
				spr.destroy();
			}
		});
		return spr;
	}

	public function addBehindGF(obj:FlxBasic)
	{
		insert(members.indexOf(gfGroup), obj);
	}
	public function addBehindBF(obj:FlxBasic)
	{
		insert(members.indexOf(boyfriendGroup), obj);
	}
	public function addBehindDad(obj:FlxBasic)
	{
		insert(members.indexOf(dadGroup), obj);
	}

	public function clearNotesBefore(time:Float)
	{
		var i:Int = unspawnNotes.length - 1;
		while (i >= 0) {
			var daNote:Note = unspawnNotes[i];
			if(daNote.strumTime - 350 < time)
			{
				daNote.active = false;
				daNote.visible = false;
				daNote.ignoreNote = true;

				if(!ClientPrefs.data.lowQuality/* || !cpuControlled*/) daNote.kill();
				unspawnNotes.remove(daNote);
				daNote.destroy();
			}
			--i;
		}

		i = notes.length - 1;
		while (i >= 0) {
			var daNote:Note = notes.members[i];
			if(daNote.strumTime - 350 < time)
			{
				daNote.active = false;
				daNote.visible = false;
				daNote.ignoreNote = true;
				invalidateNote(daNote);
			}
			--i;
		}
	}

	// fun fact: Dynamic Functions can be overriden by just doing this
	// `updateScore = function(miss:Bool = false) { ... }
	// its like if it was a variable but its just a function!
	// cool right? -Crow
	public dynamic function updateScore(miss:Bool = false, scoreBop:Bool = true)
	{
		var ret:Dynamic = callOnScripts('preUpdateScore', [miss], true);
		if (ret == LuaUtils.Function_Stop)
			return;

		updateScoreText();
		if (!miss/* && !cpuControlled*/ && scoreBop)
			doScoreBop();

		callOnScripts('onUpdateScore', [miss]);
	}

	public dynamic function updateScoreText()
	{
		var str:String = LanguageBasic.getPhrase('rating_$ratingName', ratingName);
        var percent:Float = 0; // 提前声明并初始化
        if(totalPlayed != 0)
        {
            percent = CoolUtil.floorDecimal(ratingPercent * 100, 2);
            str += ' (${percent}%) - ' + LanguageBasic.getPhrase(ratingFC);
        }

        var tempScore:String;
        if(!instakillOnMiss) {
            if (ClientPrefs.data.scoretxtstyle == 'MintRhythm')
			{
    			if (!cpuControlled || ClientPrefs.data.botplayScore)
    			{
        			tempScore = '| ';
        			if (ClientPrefs.data.showNPS)
            			tempScore += 'NPS: ${nps} (${maxNPS}) | ';
        			tempScore += 'Score: ${songScore}';
        			if (!instakillOnMiss)
            			tempScore += ' | Miss: ${songMisses}';
        			tempScore += ' | Acc: ${percent}% | ${ratingFC} |';
    			}
    			else {
        			if (ClientPrefs.data.showNPS)
            			tempScore = '| NPS: ${nps} (${maxNPS}) |';
        			else
            			tempScore = ''; // 不显示竖线
    			}
    			//if (cpuControlled) tempScore += ' AUTOPLAY |';
			}
            else if (ClientPrefs.data.scoretxtstyle == 'Kade')
            {
                if (!cpuControlled || ClientPrefs.data.botplayScore)
                {
                    tempScore = '';
                    if (ClientPrefs.data.showNPS)
                        tempScore += 'NPS: ${nps} (Max: ${maxNPS}) | ';
                    tempScore += 'Score: ${songScore}';
                    if (!instakillOnMiss)
                        tempScore += ' | Combo Breaks: ${songMisses}';
                    tempScore += ' | Accuracy: ${percent}% | (${ratingFC}) ${ratingNameKE}';
                } else {
                    tempScore = ClientPrefs.data.showNPS ? 'NPS: ${nps} (Max: ${maxNPS})' : '';
                }
                //if (cpuControlled) tempScore += ' | BOTPLAY';
            }
			else if (ClientPrefs.data.scoretxtstyle == 'V-Slice')
            {
                    tempScore = 'Score: ${songScore}';
            }
            else
                tempScore = LanguageBasic.getPhrase('score_text', 'Score: {1} | Misses: {2} | Rating: {3}', [songScore, songMisses, str]);
        }
        else tempScore = LanguageBasic.getPhrase('score_text_instakill', 'Score: {1} | Rating: {2}', [songScore, str]);
        scoreTxt.text = tempScore;
    }

	public dynamic function fullComboFunction()
	{
		var sicks:Int = ratingsData[0].hits;
		var goods:Int = ratingsData[1].hits;
		var bads:Int = ratingsData[2].hits;
		var shits:Int = ratingsData[3].hits;
        var perfects:Int = !ClientPrefs.data.rmPerfect ? ratingsData[4].hits : 0;    

		//ratingFC = "";
		ratingFC = /*ClientPrefs.data.scoretxtstyle == 'Psych' ? "?" : */"?";
		if(ClientPrefs.data.scoretxtstyle == 'MintRhythm') ratingFC = "IDK";
		if(ClientPrefs.data.scoretxtstyle == 'Kade') ratingFC = "PFC";
		if(songMisses == 0)
		{
			if (bads > 0 || shits > 0) ratingFC = 'FC';
			else if (goods > 0) ratingFC = 'GFC';
			else if (sicks > 0) ratingFC = 'SFC';
			else if (perfects > 0) ratingFC = 'PFC';
		}
		else {
			if (songMisses < 10) ratingFC = 'SDCB';
			else ratingFC = 'Clear';
		}
	}

	public function doScoreBop():Void {
		if (!ClientPrefs.data.scoreZoom || ClientPrefs.data.scoretxtstyle == 'Kade')
			return;

		if(scoreTxtTween != null)
			scoreTxtTween.cancel();
		if(scoreTxtTweenAngle != null)
			scoreTxtTweenAngle.cancel();

		scoreTxt.scale.x = 1.075;
		scoreTxt.scale.y = 1.075;
		scoreTxtTween = FlxTween.tween(scoreTxt.scale, {x: 1, y: 1}, 0.2, {
			onComplete: function(twn:FlxTween) {
				scoreTxtTween = null;
			}
		});

		if (ClientPrefs.data.scoretxtbounce) 
		{
			scoreTxt.angle = (Math.random() * 2.5) * (Math.random() > .5 ? 1 : -1);
			scoreTxtTweenAngle = FlxTween.tween(scoreTxt, {angle: 0}, ClientPrefs.data.scoretxtstyle == 'MintRhythm' ? 0.15 : 0.2, {
				onComplete: function (twn: FlxTween) {
					scoreTxtTweenAngle = null;
				}
			});
		}

	}

	public function setSongTime(time:Float)
	{
		FlxG.sound.music.pause();
		vocals.pause();
		opponentVocals.pause();

		FlxG.sound.music.time = time - Conductor.offset;
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		FlxG.sound.music.play();

		if (Conductor.songPosition < vocals.length)
		{
			vocals.time = time - Conductor.offset;
			#if FLX_PITCH vocals.pitch = playbackRate; #end
			vocals.play();
		}
		else vocals.pause();

		if (Conductor.songPosition < opponentVocals.length)
		{
			opponentVocals.time = time - Conductor.offset;
			#if FLX_PITCH opponentVocals.pitch = playbackRate; #end
			opponentVocals.play();
		}
		else opponentVocals.pause();
		Conductor.songPosition = time;
	}

	public function startNextDialogue() {
		dialogueCount++;
		callOnScripts('onNextDialogue', [dialogueCount]);
	}

	public function skipDialogue() {
		callOnScripts('onSkipDialogue', [dialogueCount]);
	}

	function startSong():Void
	{
		startingSong = false;

		@:privateAccess
		FlxG.sound.playMusic(inst._sound, 1, false);
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		FlxG.sound.music.onComplete = finishSong.bind();
		vocals.play();
		opponentVocals.play();

		setSongTime(Math.max(0, startOnTime - 500) + Conductor.offset);
		startOnTime = 0;

		if(paused) {
			//trace('Oopsie doopsie! Paused sound');
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}

		stagesFunc(function(stage:BaseStage) stage.startSong());

		// Song duration in a float, useful for the time left feature
		songLength = FlxG.sound.music.length;
		FlxTween.tween(timeBar, {alpha: 1}, 0.5, {ease: FlxEase.circOut});
		FlxTween.tween(timeTxt, {alpha: 1}, 0.5, {ease: FlxEase.circOut});

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence (with Time Left)
		if(autoUpdateRPC) DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter(), true, songLength);
		#end
		setOnScripts('songLength', songLength);
		callOnScripts('onSongStart');

		runSongSyncThread();
	}

	private var noteTypes:Array<String> = [];
	private var totalColumns: Int = 4;

	private function generateSong():Void
	{
		// FlxG.log.add(ChartParser.parse());
		songSpeed = PlayState.SONG.speed;
		songSpeedType = ClientPrefs.getGameplaySetting('scrolltype');
		switch(songSpeedType)
		{
			case "multiplicative":
				songSpeed = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed');
			case "constant":
				songSpeed = ClientPrefs.getGameplaySetting('scrollspeed');
		}

		var songData = SONG;
		Conductor.bpm = songData.bpm;

		curSong = songData.song;

		vocals = new FlxSound();
		opponentVocals = new FlxSound();
		try
		{
			if (songData.needsVoices)
			{
				var playerVocals = Paths.voices(songData.song, (boyfriend.vocalsFile == null || boyfriend.vocalsFile.length < 1) ? 'Player' : boyfriend.vocalsFile);
				vocals.loadEmbedded(playerVocals != null ? playerVocals : Paths.voices(songData.song));
				
				var oppVocals = Paths.voices(songData.song, (dad.vocalsFile == null || dad.vocalsFile.length < 1) ? 'Opponent' : dad.vocalsFile);
				if(oppVocals != null && oppVocals.length > 0) opponentVocals.loadEmbedded(oppVocals);
			}
		}
		catch (e:Dynamic) {}

		#if FLX_PITCH
		vocals.pitch = playbackRate;
		opponentVocals.pitch = playbackRate;
		#end
		FlxG.sound.list.add(vocals);
		FlxG.sound.list.add(opponentVocals);

		inst = new FlxSound();
		try
		{
			inst.loadEmbedded(Paths.inst(songData.song));
		}
		catch (e:Dynamic) {}
		FlxG.sound.list.add(inst);

		notes = new FlxTypedGroup<Note>();
		noteGroup.add(notes);

		try
		{
			var eventsChart:SwagSong = Song.getChart('events', songName);
			if(eventsChart != null)
				for (event in eventsChart.events) //Event Notes
					for (i in 0...event[1].length)
						makeEvent(event, i);
		}
		catch(e:Dynamic) {}

		var oldNote:Note = null;
		var sectionsData:Array<SwagSection> = PlayState.SONG.notes;
		var ghostNotesCaught:Int = 0;
		var daBpm:Float = Conductor.bpm;
	
		for (section in sectionsData)
		{
			if (section.changeBPM != null && section.changeBPM && section.bpm != null && daBpm != section.bpm)
				daBpm = section.bpm;

			for (i in 0...section.sectionNotes.length)
			{
				final songNotes: Array<Dynamic> = section.sectionNotes[i];
				var spawnTime: Float = songNotes[0];
				var noteColumn: Int = Std.int(songNotes[1] % totalColumns);
				var holdLength: Float = songNotes[2];
				var noteType: String = !Std.isOfType(songNotes[3], String) ? Note.defaultNoteTypes[songNotes[3]] : songNotes[3];
				if (Math.isNaN(holdLength))
					holdLength = 0.0;

				var gottaHitNote:Bool = (songNotes[1] < totalColumns);

				if (i != 0) {
					// CLEAR ANY POSSIBLE GHOST NOTES
					for (evilNote in unspawnNotes) {
						var matches: Bool = (noteColumn == evilNote.noteData && gottaHitNote == evilNote.mustPress && evilNote.noteType == noteType);
						if (matches && Math.abs(spawnTime - evilNote.strumTime) < flixel.math.FlxMath.EPSILON) {
							if (evilNote.tail.length > 0)
								for (tail in evilNote.tail)
								{
									tail.destroy();
									unspawnNotes.remove(tail);
								}
							evilNote.destroy();
							unspawnNotes.remove(evilNote);
							ghostNotesCaught++;
							//continue;
						}
					}
				}

				var swagNote:Note = new Note(spawnTime, noteColumn, oldNote);
				var isAlt: Bool = section.altAnim && !gottaHitNote;
				swagNote.gfNote = (section.gfSection && gottaHitNote == section.mustHitSection);
				swagNote.animSuffix = isAlt ? "-alt" : "";
				swagNote.mustPress = gottaHitNote;
				swagNote.sustainLength = holdLength;
				swagNote.noteType = noteType;
	
				swagNote.scrollFactor.set();
				unspawnNotes.push(swagNote);

				var curStepCrochet:Float = 60 / daBpm * 1000 / 4.0;
				final roundSus:Int = Math.round(swagNote.sustainLength / curStepCrochet);
				if(roundSus > 0)
				{
					for (susNote in 0...roundSus)
					{
						oldNote = unspawnNotes[Std.int(unspawnNotes.length - 1)];

						var sustainNote:Note = new Note(spawnTime + (curStepCrochet * susNote), noteColumn, oldNote, true);
						sustainNote.animSuffix = swagNote.animSuffix;
						sustainNote.mustPress = swagNote.mustPress;
						sustainNote.gfNote = swagNote.gfNote;
						sustainNote.noteType = swagNote.noteType;
						sustainNote.scrollFactor.set();
						sustainNote.parent = swagNote;
						unspawnNotes.push(sustainNote);
						swagNote.tail.push(sustainNote);

						sustainNote.correctionOffset = swagNote.height / 2;
						if(!PlayState.isPixelStage)
						{
							if(oldNote.isSustainNote)
							{
								oldNote.scale.y *= Note.SUSTAIN_SIZE / oldNote.frameHeight;
								oldNote.scale.y /= playbackRate;
								oldNote.resizeByRatio(curStepCrochet / Conductor.stepCrochet);
							}

							if(ClientPrefs.data.downScroll)
								sustainNote.correctionOffset = 0;
						}
						else if(oldNote.isSustainNote)
						{
							oldNote.scale.y /= playbackRate;
							oldNote.resizeByRatio(curStepCrochet / Conductor.stepCrochet);
						}

						if (sustainNote.mustPress) sustainNote.x += FlxG.width / 2; // general offset
						else if(ClientPrefs.data.middleScroll)
						{
							sustainNote.x += 310;
							if(noteColumn > 1) //Up and Right
								sustainNote.x += FlxG.width / 2 + 25;
						}
					}
				}

				if (swagNote.mustPress)
				{
					swagNote.x += FlxG.width / 2; // general offset
				}
				else if(ClientPrefs.data.middleScroll)
				{
					swagNote.x += 310;
					if(noteColumn > 1) //Up and Right
					{
						swagNote.x += FlxG.width / 2 + 25;
					}
				}
				if(!noteTypes.contains(swagNote.noteType))
					noteTypes.push(swagNote.noteType);

				oldNote = swagNote;
			}
		}
		trace('["${SONG.song.toUpperCase()}" CHART INFO]: Ghost Notes Cleared: $ghostNotesCaught');
		for (event in songData.events) //Event Notes
			for (i in 0...event[1].length)
				makeEvent(event, i);

		unspawnNotes.sort(sortByTime);
		generatedMusic = true;
	}

	public static function sortByTime(Obj1:Dynamic, Obj2:Dynamic):Int
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1.strumTime, Obj2.strumTime);

	public function triggerEvent(eventName:String, value1:String, value2:String, value3:String, value4:String, strumTime:Float) {
		eventHandler.triggerEvent(eventName, value1, value2, value3, value4, strumTime);
	}

	override public function stagesFunc(func:BaseStage->Void) {
		for (stage in stages)
			if(stage != null && stage.exists && stage.active)
				func(stage);
	}

	function makeEvent(event:Array<Dynamic>, i:Int)
	{
		var subEvent:EventNote = {
			strumTime: event[0] + ClientPrefs.data.noteOffset,
			event: event[1][i][0],
			value1: event[1][i][1],
			value2: event[1][i][2],
			value3: event[1][i][3],
			value4: event[1][i][4]
		};
		eventNotes.push(subEvent);
		eventHandler.eventPushed(subEvent);
		callOnScripts('onEventPushed', [subEvent.event, subEvent.value1 != null ? subEvent.value1 : '', subEvent.value2 != null ? subEvent.value2 : '', subEvent.value3 != null ? subEvent.value3 : '', subEvent.value4 != null ? subEvent.value4 : '', subEvent.strumTime]);
	}

	public var skipArrowStartTween:Bool = false; //for lua
	private function generateStaticArrows(player:Int):Void
{
    var strumLineX:Float = ClientPrefs.data.middleScroll ? STRUM_X_MIDDLESCROLL : STRUM_X;
    var strumLineY:Float = ClientPrefs.data.downScroll ? (FlxG.height - 150) : 50;
    
    // 应用传统音符位置偏移
    var legacyOffset:Float = ClientPrefs.data.legacynotepos ? 50 : 0;
    
    for (i in 0...4)
    {
        // FlxG.log.add(i);
        var targetAlpha:Float = 1;
        if (player < 1)
        {
            if(!ClientPrefs.data.opponentStrums) targetAlpha = 0;
            else if(ClientPrefs.data.middleScroll) targetAlpha = 0.35;
        }

        var babyArrow:StrumNote = new StrumNote(strumLineX, strumLineY, i, player);
        babyArrow.downScroll = ClientPrefs.data.downScroll;

        // 应用传统音符位置偏移
        babyArrow.x -= legacyOffset;

        if (!isStoryMode && !skipArrowStartTween)
        {
            //babyArrow.y -= 10;
            babyArrow.alpha = 0;
            FlxTween.tween(babyArrow, {/*y: babyArrow.y + 10,*/ alpha: targetAlpha}, 1, {ease: FlxEase.circOut, startDelay: 0.5 + (0.2 * i)});
        }
        else babyArrow.alpha = targetAlpha;

        if (player == 1)
            playerStrums.add(babyArrow);
        else
        {
            if(ClientPrefs.data.middleScroll)
            {
                babyArrow.x += 310;
                if(i > 1) { //Up and Right
                    babyArrow.x += FlxG.width / 2 + 25;
                }
            }
            opponentStrums.add(babyArrow);
        }

        strumLineNotes.add(babyArrow);
        babyArrow.playerPosition();
    }
}

	override function openSubState(SubState:FlxSubState)
	{
		stagesFunc(function(stage:BaseStage) stage.openSubState(SubState));
		if (paused)
		{
			if (FlxG.sound.music != null)
			{
				FlxG.sound.music.pause();
				vocals.pause();
				opponentVocals.pause();
			}
			FlxTimer.globalManager.forEach(function(tmr:FlxTimer) if(!tmr.finished) tmr.active = false);
			FlxTween.globalManager.forEach(function(twn:FlxTween) if(!twn.finished) twn.active = false);
		}

		super.openSubState(SubState);
	}

	public var canResync:Bool = true;
	override function closeSubState()
	{
		super.closeSubState();
		
		stagesFunc(function(stage:BaseStage) stage.closeSubState());
		if (paused)
		{
			if (FlxG.sound.music != null && !startingSong && canResync)
			{
				resyncVocals();
			}
			FlxTimer.globalManager.forEach(function(tmr:FlxTimer) if(!tmr.finished) tmr.active = true);
			FlxTween.globalManager.forEach(function(twn:FlxTween) if(!twn.finished) twn.active = true);

			paused = false;
			callOnScripts('onResume');
			resetRPC(startTimer != null && startTimer.finished);
			runSongSyncThread();
		}
	}

	#if DISCORD_ALLOWED
	override public function onFocus():Void
	{
		super.onFocus();
		if (!paused && health > 0)
		{
			resetRPC(Conductor.songPosition > 0.0);
		}
		shutdownThread = false;
		runSongSyncThread();
	}

	override public function onFocusLost():Void
	{
		super.onFocusLost();
		if (!paused && health > 0 && autoUpdateRPC)
		{
			DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		}
		shutdownThread = true;
	}
	#end

	// Updating Discord Rich Presence.
	public var autoUpdateRPC:Bool = true; //performance setting for custom RPC things
	function resetRPC(?showTime:Bool = false)
	{
		#if DISCORD_ALLOWED
		if(!autoUpdateRPC) return;

		if (showTime)
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter(), true, songLength - Conductor.songPosition - ClientPrefs.data.noteOffset);
		else
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end
	}

	function resyncVocals():Void
	{
		if(finishTimer != null) return;

		trace('resynced vocals at ' + Math.floor(Conductor.songPosition));

		FlxG.sound.music.play();
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		Conductor.songPosition = FlxG.sound.music.time + Conductor.offset;

		var checkVocals = [vocals, opponentVocals];
		for (voc in checkVocals)
		{
			if (FlxG.sound.music.time < vocals.length)
			{
				voc.time = FlxG.sound.music.time;
				#if FLX_PITCH voc.pitch = playbackRate; #end
				voc.play();
			}
			else voc.pause();
		}
	}

	public var paused:Bool = false;
	public var canReset:Bool = true;
	var startedCountdown:Bool = false;
	var canPause:Bool = true;
	var freezeCamera:Bool = false;
	var allowDebugKeys:Bool = true;

	override public function update(elapsed:Float)
	{
		// 回放模式下的自动按键逻辑
		if(isReplaying && startedCountdown && !paused && !endingSong)
		{
			// 检查是否需要抬起按键（检查当前索引及之前的所有动作）
			for (i in 0...currentReplayIndex)
			{
				var action = replayData[i];
				// 检查是否有releaseTime且已到时间（ghost操作需要至少50ms的延迟）
				if(action.releaseTime != null && Conductor.songPosition >= action.releaseTime)
				{
					// 抬起按键
					replayHeldKeys[action.key] = false;
					action.releaseTime = null; // 标记为已处理

					// 播放static动画
					var spr:StrumNote = playerStrums.members[action.key];
					if(spr != null)
					{
						spr.playAnim('static');
						spr.resetAnim = 0;
					}
				}
			}
			
			// 检查长按音符，保持按键按下状态
			if(guitarHeroSustains)
			{
				var holdArray:Array<Bool> = [];
				for (i in 0...keysArray.length)
					holdArray.push(replayHeldKeys[i]);

				if(notes.length > 0) {
					for (n in notes) {
						var canHit:Bool = (n != null && !strumsBlocked[n.noteData] && n.canBeHit
							&& n.mustPress && !n.tooLate && !n.wasGoodHit && !n.blockHit);

						if (canHit && n.isSustainNote) {
							var released:Bool = !replayHeldKeys[n.noteData];
							if (!released && n.parent != null && n.parent.wasGoodHit) {
								// 持续按下长按音符
								goodNoteHit(n);
							}
						}
					}
				}
			}
			
			while(currentReplayIndex < replayData.length)
			{
				var replayAction = replayData[currentReplayIndex];
				// 检查是否到了按下时间
				if(Conductor.songPosition >= replayAction.time)
				{
					// 根据回放数据执行相应的按键
					if(replayAction.judge == 'ghost')
					{
						// 标记按键为按下状态
						replayHeldKeys[replayAction.key] = true;

						// 空按 - 播放pressed动画
						var spr:StrumNote = playerStrums.members[replayAction.key];
						if(spr != null && strumsBlocked[replayAction.key] != true && spr.animation.curAnim.name != 'confirm')
						{
							spr.playAnim('pressed');
							spr.resetAnim = 0; // 不自动重置，由按键释放时重置
						}

						// 根据当前的ghostTapping设置决定是否调用noteMissPress和onGhostTap
						if(ClientPrefs.data.ghostTapping)
						{
							callOnScripts('onGhostTap', [replayAction.key]);
						}
						else
						{
							noteMissPress(replayAction.key);
						}

						// 调用onKeyPress回调（与正常模式保持一致）
						callOnScripts('onKeyPress', [replayAction.key]);

						// 更新keysPressed数组（与正常模式保持一致）
						if(!keysPressed.contains(replayAction.key)) keysPressed.push(replayAction.key);
					}
					else if(replayAction.judge == 'miss')
					{
						// Miss，不需要按键
					}
					else
					{
						// 标记按键为按下状态
						replayHeldKeys[replayAction.key] = true;
						
						// 播放pressed动画（会在goodNoteHit中被confirm覆盖）
						var spr:StrumNote = playerStrums.members[replayAction.key];
						if(spr != null && strumsBlocked[replayAction.key] != true)
						{
							spr.playAnim('pressed');
							spr.resetAnim = 0;
						}
						
						// 正常按键，找到对应的音符并打击
						var targetNotes:Array<Note> = notes.members.filter(function(n:Note):Bool {
							// 使用小容差（5ms）来匹配音符，避免浮点数精度问题
							return n != null && n.mustPress && n.noteData == replayAction.key && !n.wasGoodHit
								&& Math.abs(n.strumTime - replayAction.noteTime) < 5;
						});
						for(note in targetNotes)
						{
							// 设置延迟覆盖值，确保使用原始记录的延迟
							if(replayAction.late != null)
							{
								currentNoteDelayOverride = replayAction.late;
							}
							goodNoteHit(note);
						}
					}
					currentReplayIndex++;
				}
				else
				{
					// 还没到时间，跳出循环
					break;
				}
			}
		}
		
		if(!inCutscene && !paused && !freezeCamera) {
			FlxG.camera.followLerp = 0.04 * cameraSpeed * playbackRate;
			var idleAnim:Bool = (boyfriend.getAnimationName().startsWith('idle') || boyfriend.getAnimationName().startsWith('danceLeft') || boyfriend.getAnimationName().startsWith('danceRight'));
			if(!startingSong && !endingSong && idleAnim) {
				boyfriendIdleTime += elapsed;
				if(boyfriendIdleTime >= 0.15) { // Kind of a mercy thing for making the achievement easier to get as it's apparently frustrating to some playerss
					boyfriendIdled = true;
				}
			} else {
				boyfriendIdleTime = 0;
			}
		}
		else FlxG.camera.followLerp = 0;
		callOnScripts('onUpdate', [elapsed]);

		super.update(elapsed);

		if (ClientPrefs.data.iconbopstyle == "MintRhythm") {
        iconP1.angle = FlxMath.lerp(iconP1.angle, iconP1TargetAngle, elapsed / iconP1AngleLerpSpeed);
        iconP2.angle = FlxMath.lerp(iconP2.angle, iconP2TargetAngle, elapsed / iconP2AngleLerpSpeed);
   	 	}

		setOnScripts('curDecStep', curDecStep);
		setOnScripts('curDecBeat', curDecBeat);

		if(botplayTxt != null && botplayTxt.visible && ClientPrefs.data.botplayStyle != 'Kade') {
			botplaySine += 180 * elapsed;
			botplayTxt.alpha = 1 - Math.sin((Math.PI * botplaySine) / 180);
		} else botplayTxt.alpha = 1;

		// 更新回放文本可见性
		if(replayTxt != null) {
			replayTxt.visible = isReplaying;
			if(isReplaying && ClientPrefs.data.botplayStyle == 'Kade') {
				replayTxt.y = healthBar.y + 120;
			} else if(isReplaying) {
				replayTxt.y = healthBar.y + 70;
			}
		}

		if (controls.PAUSE #if android || FlxG.android.justReleased.BACK #end && startedCountdown && canPause)
		{
			var ret:Dynamic = callOnScripts('onPause', null, true);
			if(ret != LuaUtils.Function_Stop) {
				openPauseMenu();
			}
		}

		if(!endingSong && !inCutscene && allowDebugKeys)
		{
			if (controls.justPressed('debug_1'))
				openChartEditor();
			else if (controls.justPressed('debug_2'))
				openCharacterEditor();
			else if (controls.justPressed('debug_3'))
				eventDebugGroup.visible = !eventDebugGroup.visible;
			else if (controls.justPressed('debug_4'))
				cpuControlled = !cpuControlled;
				botplayTxt.visible = cpuControlled;

		}

		if (healthBar.bounds.max != null && health > healthBar.bounds.max)
			health = healthBar.bounds.max;

		// 平滑血条逻辑
		if (ClientPrefs.data.smoothHP)
		{
			smoothHealth += (health - smoothHealth) * elapsed * 10; // 平滑过渡
			healthBar.percent = FlxMath.remapToRange(smoothHealth, healthBar.bounds.min, healthBar.bounds.max, 0, 100);
		}
		else
		{
			healthBar.percent = FlxMath.remapToRange(health, healthBar.bounds.min, healthBar.bounds.max, 0, 100);
		}

		updateIconsScale(elapsed);
		updateIconsPosition();

		if (startedCountdown && !paused)
		{
			Conductor.songPosition += elapsed * 1000 * playbackRate;
			if (Conductor.songPosition >= Conductor.offset)
			{
				Conductor.songPosition = FlxMath.lerp(FlxG.sound.music.time + Conductor.offset, Conductor.songPosition, Math.exp(-elapsed * 5));
				var timeDiff:Float = Math.abs((FlxG.sound.music.time + Conductor.offset) - Conductor.songPosition);
				if (timeDiff > 1000 * playbackRate)
					Conductor.songPosition = Conductor.songPosition + 1000 * FlxMath.signOf(timeDiff);
			}
		}

		if (startingSong)
		{
			if (startedCountdown && Conductor.songPosition >= Conductor.offset)
				startSong();
			else if(!startedCountdown)
				Conductor.songPosition = -Conductor.crochet * 5 + Conductor.offset;
		}
		else if (!paused && updateTime)
		{
			var curTime:Float = Math.max(0, Conductor.songPosition - ClientPrefs.data.noteOffset);
			songPercent = (curTime / songLength);

			if (ClientPrefs.data.timebarStyle == "Leather")
			{
				// 计算剩余时间
				var timeLeft:Float = Math.max(0, songLength - curTime);
				var secondsLeft:Int = Math.floor(timeLeft / 1000);
				if (secondsLeft < 0)
					secondsLeft = 0;

				// 构建显示文本
				var timeString:String = FlxStringUtil.formatTime(secondsLeft, false);
				var displayText:String = SONG.song + " ~ " + Difficulty.getString().toUpperCase() + " (" + timeString + ")";

				// 添加模式标识
				if (cpuControlled)
					displayText += " (BOT)";
				if (practiceMode)
					displayText += " (NO DEATH)";

				timeTxt.text = displayText;
			}
			else if (ClientPrefs.data.timeBarType != 'Song Name')
			{
				var songCalc:Float = (songLength - curTime);
				if (ClientPrefs.data.timeBarType == 'Time Elapsed')
					songCalc = curTime;

				var secondsTotal:Int = Math.floor(songCalc / 1000);
				if (secondsTotal < 0)
					secondsTotal = 0;

				timeTxt.text = FlxStringUtil.formatTime(secondsTotal, false);
			}
		}

		//if (camZooming)
		//{
			//FlxG.camera.zoom = FlxMath.lerp(defaultCamZoom, FlxG.camera.zoom, Math.exp(-elapsed * 3.125 * camZoomingDecay * playbackRate));
    		/*if(ClientPrefs.data.hudSize != 1.0) 	targetZoom = ClientPrefs.data.hudSize;*/
    		//camHUD.zoom = FlxMath.lerp(targetZoom, camHUD.zoom, Math.exp(-elapsed * 3.125 * camZoomingDecay * playbackRate));
		//}
		if (camZooming)
		{
    		// 先定义一个映射表，或者用简单的switch/if
    		var styleNum:Float = switch (ClientPrefs.data.hudZoomStyle)
    		{
        		case "Kade": 8;
        		case "Fast": 12;
        		case "Slow": 1.5;
        		default: 3.125; // 默认
    		}
    		var zoomLerp = Math.exp(-elapsed * styleNum * camZoomingDecay * playbackRate);
    		var hudLerp = zoomLerp;
    		FlxG.camera.zoom = FlxMath.lerp(defaultCamZoom, FlxG.camera.zoom, zoomLerp);
    		camHUD.zoom = FlxMath.lerp(targetZoom, camHUD.zoom, hudLerp);
		}

		FlxG.watch.addQuick("secShit", curSection);
		FlxG.watch.addQuick("beatShit", curBeat);
		FlxG.watch.addQuick("stepShit", curStep);

		// RESET = Quick Game Over Screen
		if (!ClientPrefs.data.noReset && controls.RESET && canReset && !inCutscene && startedCountdown && !endingSong)
		{
			health = 0;
			trace("RESET = True");
		}
		doDeathCheck();

		if (unspawnNotes[0] != null)
		{
			var time:Float = spawnTime * playbackRate;
			if(songSpeed < 1) time /= songSpeed;
			if(unspawnNotes[0].multSpeed < 1) time /= unspawnNotes[0].multSpeed;

			while (unspawnNotes.length > 0 && unspawnNotes[0].strumTime - Conductor.songPosition < time)
			{
				var dunceNote:Note = unspawnNotes[0];
				notes.insert(0, dunceNote);
				dunceNote.spawned = true;

				callOnLuas('onSpawnNote', [notes.members.indexOf(dunceNote), dunceNote.noteData, dunceNote.noteType, dunceNote.isSustainNote, dunceNote.strumTime]);
				callOnHScript('onSpawnNote', [dunceNote]);

				var index:Int = unspawnNotes.indexOf(dunceNote);
				unspawnNotes.splice(index, 1);
			}
		}

		{
			var balls = notesHitArray.length - 1;
			while (balls >= 0)
			{
				var cock:Date = notesHitArray[balls];
				if (cock != null && cock.getTime() + 1000 < Date.now().getTime())
					notesHitArray.remove(cock);
				else
					balls = 0;
				balls--;
			}
			nps = notesHitArray.length;
			if (nps > maxNPS)
				maxNPS = nps;
			if (ClientPrefs.data.showNPS && npsCheck != nps && ClientPrefs.data.scoretxtstyle == 'MintRhythm' || ClientPrefs.data.scoretxtstyle == 'Kade') {
				npsCheck = nps;
			    updateScoreText();
			}
			setOnLuas('nps', nps);
			setOnLuas('maxFPS', maxNPS);	

		}

		if (ClientPrefs.data.timebarStyle == 'Leather')
		{
			// 使用FlxColor.interpolate进行颜色插值
			timeBarLeftColor = FlxColor.interpolate(timeBarLeftColor, timeBarLeftColorTarget, elapsed * 5);
			timeBarRightColor = FlxColor.interpolate(timeBarRightColor, timeBarRightColorTarget, elapsed * 5);
			timeBar.setColors(timeBarRightColor, timeBarLeftColor); //不是，timebar的颜色是反着来的吗？
		}

		if (generatedMusic)
		{
			if(!inCutscene)
			{
				if(!cpuControlled)
					keysCheck();
				else
					playerDance();

				if(notes.length > 0)
				{
					if(startedCountdown)
					{
						var fakeCrochet:Float = (60 / SONG.bpm) * 1000;
						var i:Int = 0;
						while(i < notes.length)
						{
							var daNote:Note = notes.members[i];
							if(daNote == null) continue;

							var strumGroup:FlxTypedGroup<StrumNote> = playerStrums;
							if(!daNote.mustPress) strumGroup = opponentStrums;

							var strum:StrumNote = strumGroup.members[daNote.noteData];
							daNote.followStrumNote(strum, fakeCrochet, songSpeed / playbackRate);

							if(daNote.mustPress)
							{
								if(cpuControlled && !daNote.blockHit && daNote.canBeHit && (daNote.isSustainNote || daNote.strumTime <= Conductor.songPosition))
									goodNoteHit(daNote);
							}
							else if (daNote.wasGoodHit && !daNote.hitByOpponent && !daNote.ignoreNote)
								opponentNoteHit(daNote);

							if(daNote.isSustainNote && strum.sustainReduce) daNote.clipToStrumNote(strum);

							// Kill extremely late notes and cause misses
							if (Conductor.songPosition - daNote.strumTime > noteKillOffset)
							{
								if (daNote.mustPress /*&& !cpuControlled */&& !daNote.ignoreNote && !endingSong && (daNote.tooLate || !daNote.wasGoodHit))
									noteMiss(daNote);

								daNote.active = daNote.visible = false;
								invalidateNote(daNote);
							}
							if(daNote.exists) i++;
						}
					}
					else
					{
						notes.forEachAlive(function(daNote:Note)
						{
							daNote.canBeHit = false;
							daNote.wasGoodHit = false;
						});
					}
				}
			}
			eventHandler.checkEventNote();
		}

		#if debug
		if(!endingSong && !startingSong) {
			if (FlxG.keys.justPressed.ONE) {
				KillNotes();
				FlxG.sound.music.onComplete();
			}
			if(FlxG.keys.justPressed.TWO) { //Go 10 seconds into the future :O
				setSongTime(Conductor.songPosition + 10000);
				clearNotesBefore(Conductor.songPosition);
			}
		}
		#end

		setOnScripts('botPlay', cpuControlled);
		callOnScripts('onUpdatePost', [elapsed]);
	}

	// Health icon updaters
	public dynamic function updateIconsScale(elapsed:Float)
{
    // MintRhythm 专属缩放逻辑
    if (ClientPrefs.data.iconbopstyle == "MintRhythm") {
        var healthPercent:Float = healthBar.percent;
        var targetScale:Float = 1.0;
        
        // 根据血量动态调整缩放强度
        var scaleIntensity:Float = 1 - Math.abs(healthPercent - 50) / 50;
        targetScale += 0.1 * scaleIntensity;
        
        // 平滑缩放过渡
        iconP1.scale.x = FlxMath.lerp(iconP1.scale.x, targetScale, elapsed * 12);
        iconP1.scale.y = FlxMath.lerp(iconP1.scale.y, targetScale, elapsed * 12);
        iconP2.scale.x = FlxMath.lerp(iconP2.scale.x, targetScale, elapsed * 12);
        iconP2.scale.y = FlxMath.lerp(iconP2.scale.y, targetScale, elapsed * 12);
    } else {
			var speedMultiplier:Float = switch (ClientPrefs.data.iconbopstyle)
			{
				case "Codename": 20;
				case "Leather": 6;
				case "SB": 20;
				case "VSlice(New)": 14;
				case "VSlice(Old)": 36;
				case "Dave": 22;
				case "NovaFlare": 22;
				default: 9;
			}

			// 定义缩放上限
			final ICON_BOUND:Float = 1.2; // 1 + 0.2

			if (["VSlice(New)", "VSlice(Old)", "Dave", "Codename", "Leather"].contains(ClientPrefs.data.iconbopstyle))
			{
				var rate:Float = elapsed * speedMultiplier * playbackRate;
				iconP1.scale.x = FlxMath.lerp(iconP1.scale.x, 1, rate);
				iconP1.scale.y = FlxMath.lerp(iconP1.scale.y, 1, rate);
				iconP2.scale.x = FlxMath.lerp(iconP2.scale.x, 1, rate);
				iconP2.scale.y = FlxMath.lerp(iconP2.scale.y, 1, rate);

				// 添加边界限制和碰撞箱更新
				iconP1.scale.x = FlxMath.bound(iconP1.scale.x, Math.NEGATIVE_INFINITY, ICON_BOUND);
				iconP1.scale.y = FlxMath.bound(iconP1.scale.y, Math.NEGATIVE_INFINITY, ICON_BOUND);
				iconP2.scale.x = FlxMath.bound(iconP2.scale.x, Math.NEGATIVE_INFINITY, ICON_BOUND);
				iconP2.scale.y = FlxMath.bound(iconP2.scale.y, Math.NEGATIVE_INFINITY, ICON_BOUND);

			}
			else
			{
				var mult:Float = FlxMath.lerp(1, iconP1.scale.x, Math.exp(-elapsed * speedMultiplier * playbackRate));
				iconP1.scale.set(mult, mult);
				mult = FlxMath.lerp(1, iconP2.scale.x, Math.exp(-elapsed * speedMultiplier * playbackRate));
				iconP2.scale.set(mult, mult);

				// 添加边界限制
				iconP1.scale.x = FlxMath.bound(iconP1.scale.x, Math.NEGATIVE_INFINITY, ICON_BOUND);
				iconP1.scale.y = FlxMath.bound(iconP1.scale.y, Math.NEGATIVE_INFINITY, ICON_BOUND);
				iconP2.scale.x = FlxMath.bound(iconP2.scale.x, Math.NEGATIVE_INFINITY, ICON_BOUND);
				iconP2.scale.y = FlxMath.bound(iconP2.scale.y, Math.NEGATIVE_INFINITY, ICON_BOUND);

			}
    }
    
    // 统一更新碰撞框
    iconP1.updateHitbox();
    iconP2.updateHitbox();
}

	public dynamic function updateIconsPosition()
	{
		var iconOffset:Int = 26;

		// MintRhythm专属动效
		//不要了，不好看
		/*if(ClientPrefs.data.iconbopstyle == "MintRhythm") {
			iconP1.x = healthBar.barCenter + (150 * iconP1.scale.x - 150)/2 - iconOffset;
			iconP2.x = healthBar.barCenter - (150 * iconP2.scale.x)/2 - iconOffset*2;

			// 垂直浮动效果
			var wave = Math.sin(Conductor.songPosition / 400) * 1.5;
			iconP1.y = iconP1InitialY + wave;
			iconP2.y = iconP2InitialY - wave;
		} else */
		{

			iconP1.x = healthBar.barCenter + (150 * iconP1.scale.x - 150)/2 - iconOffset;
			iconP2.x = healthBar.barCenter - (150 * iconP2.scale.x)/2 - iconOffset*2;
			/*iconP1.y = iconP1InitialY;
			iconP2.y = iconP2InitialY;*/
			if (ClientPrefs.data.iconbopstyle == "Kade" || ClientPrefs.data.iconbopstyle == "VSlice(Old)") {
        		iconP1.y = iconP1InitialY + (iconP1.scale.y - 1) * 80;
        		iconP2.y = iconP2InitialY + (iconP2.scale.y - 1) * 80;
    		}
			else if (ClientPrefs.data.iconbopstyle == "Leather") {
        		iconP1.y = iconP1InitialY + (iconP1.scale.y - 1) * 60;
        		iconP2.y = iconP2InitialY + (iconP2.scale.y - 1) * 60;
    		}
			else if (ClientPrefs.data.iconbopstyle == "Codename") {
        		if(ClientPrefs.data.downScroll){
				iconP1.y = iconP1InitialY - (iconP1.scale.y - 1) * 70;
        		iconP2.y = iconP2InitialY - (iconP2.scale.y - 1) * 70;
    			} else {
				iconP1.y = iconP1InitialY + (iconP1.scale.y - 1) * 70;
        		iconP2.y = iconP2InitialY + (iconP2.scale.y - 1) * 70;
				}
			}
		}
	}

	var iconsAnimations:Bool = true;
	function set_health(value:Float):Float // You can alter how icon animations work here
	{
		value = FlxMath.roundDecimal(value, 5); //Fix Float imprecision
		if(!iconsAnimations || healthBar == null || !healthBar.enabled || healthBar.valueFunction == null)
		{
			health = value;
			return health;
		}

		// update health bar
		health = value;
		var newPercent:Null<Float> = FlxMath.remapToRange(FlxMath.bound(healthBar.valueFunction(), healthBar.bounds.min, healthBar.bounds.max), healthBar.bounds.min, healthBar.bounds.max, 0, 100);
		healthBar.percent = (newPercent != null ? newPercent : 0);

		iconP1.animation.curAnim.curFrame = (healthBar.percent < 20) ? 1 : 0; //If health is under 20%, change player icon to frame 1 (losing icon), otherwise, frame 0 (normal)
		iconP2.animation.curAnim.curFrame = (healthBar.percent > 80) ? 1 : 0; //If health is over 80%, change opponent icon to frame 1 (losing icon), otherwise, frame 0 (normal)
		return health;
	}

	function openPauseMenu()
	{
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		persistentDraw = true;
		paused = true;

		if(FlxG.sound.music != null) {
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}
		if(!cpuControlled)
		{
			for (note in playerStrums)
				if(note.animation.curAnim != null && note.animation.curAnim.name != 'static')
				{
					note.playAnim('static');
					note.resetAnim = 0;
				}
		}
		openSubState(new PauseSubState());

		#if DISCORD_ALLOWED
		if(autoUpdateRPC) DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end
	}

	public function openChartEditor()
	{
		canResync = false;
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		chartingMode = true;
		paused = true;

		if(FlxG.sound.music != null)
			FlxG.sound.music.stop();
		if(vocals != null)
			vocals.pause();
		if(opponentVocals != null)
			opponentVocals.pause();

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Chart Editor", null, null, true);
		DiscordClient.resetClientID();
		#end

		MusicBeatState.switchState(new ChartingState());
	}

	function openCharacterEditor()
	{
		canResync = false;
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		paused = true;

		if(FlxG.sound.music != null)
			FlxG.sound.music.stop();
		if(vocals != null)
			vocals.pause();
		if(opponentVocals != null)
			opponentVocals.pause();

		#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
		MusicBeatState.switchState(new CharacterEditorState(SONG.player2));
	}

	public var isDead:Bool = false; //Don't mess with this on Lua!!!
	public var gameOverTimer:FlxTimer;
	function doDeathCheck(?skipHealthCheck:Bool = false) {
		if (((skipHealthCheck && instakillOnMiss) || health <= 0) && !practiceMode && !isDead && gameOverTimer == null)
		{
			var ret:Dynamic = callOnScripts('onGameOver', null, true);
			if(ret != LuaUtils.Function_Stop)
			{
				FlxG.animationTimeScale = 1;
				boyfriend.stunned = true;
				deathCounter++;

				paused = true;
				canResync = false;
				canPause = false;
				#if VIDEOS_ALLOWED
				if(videoCutscene != null)
				{
					videoCutscene.destroy();
					videoCutscene = null;
				}
				#end

				persistentUpdate = false;
				persistentDraw = false;
				FlxTimer.globalManager.clear();
				FlxTween.globalManager.clear();
				FlxG.camera.setFilters([]);

				if(GameOverSubstate.deathDelay > 0)
				{
					gameOverTimer = new FlxTimer().start(GameOverSubstate.deathDelay, function(_)
					{
						vocals.stop();
						opponentVocals.stop();
						FlxG.sound.music.stop();
						openSubState(new GameOverSubstate(boyfriend));
						gameOverTimer = null;
					});
				}
				else
				{
					vocals.stop();
					opponentVocals.stop();
					FlxG.sound.music.stop();
					openSubState(new GameOverSubstate(boyfriend));
				}

				// MusicBeatState.switchState(new GameOverState(boyfriend.getScreenPosition().x, boyfriend.getScreenPosition().y));

				#if DISCORD_ALLOWED
				// Game Over doesn't get his its variable because it's only used here
				if(autoUpdateRPC) DiscordClient.changePresence("Game Over - " + detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
				#end
				isDead = true;
				return true;
			}
		}
		return false;
	}

	public function moveCameraSection(?sec:Null<Int>):Void {
		if(sec == null) sec = curSection;
		if(sec < 0) sec = 0;

		if(SONG.notes[sec] == null) return;

		if (gf != null && SONG.notes[sec].gfSection)
		{
			moveCameraToGirlfriend();
			callOnScripts('onMoveCamera', ['gf']);
			return;
		}

		var isDad:Bool = (SONG.notes[sec].mustHitSection != true);
		moveCamera(isDad);
		if (isDad)
			callOnScripts('onMoveCamera', ['dad']);
		else
			callOnScripts('onMoveCamera', ['boyfriend']);
	}
	
	public function moveCameraToGirlfriend()
	{
		camFollow.setPosition(gf.getMidpoint().x, gf.getMidpoint().y);
		camFollow.x += gf.cameraPosition[0] + girlfriendCameraOffset[0];
		camFollow.y += gf.cameraPosition[1] + girlfriendCameraOffset[1];
		tweenCamIn();
	}

	var cameraTwn:FlxTween;
	public function moveCamera(isDad:Bool)
	{
		if(isDad)
		{
			if(dad == null) return;
			camFollow.setPosition(dad.getMidpoint().x + 150, dad.getMidpoint().y - 100);
			camFollow.x += dad.cameraPosition[0] + opponentCameraOffset[0];
			camFollow.y += dad.cameraPosition[1] + opponentCameraOffset[1];
			tweenCamIn();
		}
		else
		{
			if(boyfriend == null) return;
			camFollow.setPosition(boyfriend.getMidpoint().x - 100, boyfriend.getMidpoint().y - 100);
			camFollow.x -= boyfriend.cameraPosition[0] - boyfriendCameraOffset[0];
			camFollow.y += boyfriend.cameraPosition[1] + boyfriendCameraOffset[1];

			if (songName == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1)
			{
				cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
					function (twn:FlxTween)
					{
						cameraTwn = null;
					}
				});
			}
		}
	}

	public function tweenCamIn() {
		if (songName == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1.3) {
			cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1.3}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
				function (twn:FlxTween) {
					cameraTwn = null;
				}
			});
		}
	}

	public function finishSong(?ignoreNoteOffset:Bool = false):Void
	{
		updateTime = false;
		FlxG.sound.music.volume = 0;

		vocals.volume = 0;
		vocals.pause();
		opponentVocals.volume = 0;
		opponentVocals.pause();

		if(ClientPrefs.data.noteOffset <= 0 || ignoreNoteOffset) {
			endCallback();
		} else {
			finishTimer = new FlxTimer().start(ClientPrefs.data.noteOffset / 1000, function(tmr:FlxTimer) {
				endCallback();
			});
		}
	}


	public var transitioning = false;
	public function endSong()
	{
		// 重置回放按键状态
		replayHeldKeys = [false, false, false, false];
		
		mobileControls.instance.visible = #if !android touchPad.visible = #end false;
		//Should kill you if you tried to cheat
		if(!startingSong)
		{
			notes.forEachAlive(function(daNote:Note)
			{
				if(daNote.strumTime < songLength - Conductor.safeZoneOffset)
					health -= 0.05 * healthLoss;
			});
			for (daNote in unspawnNotes)
			{
				if(daNote != null && daNote.strumTime < songLength - Conductor.safeZoneOffset)
					health -= 0.05 * healthLoss;
			}

			if(doDeathCheck()) {
				return false;
			}
		}

		timeBar.visible = false;
		timeTxt.visible = false;
		canPause = false;
		endingSong = true;
		camZooming = false;
		inCutscene = false;
		updateTime = false;

		deathCounter = 0;
		seenCutscene = false;

		#if ACHIEVEMENTS_ALLOWED
		var weekNoMiss:String = WeekData.getWeekFileName() + '_nomiss';
		checkForAchievement([weekNoMiss, 'ur_bad', 'ur_good', 'hype', 'two_keys', 'toastie' #if BASE_GAME_FILES, 'debugger' #end]);
		#end

		var ret:Dynamic = callOnScripts('onEndSong', null, true);
		if(ret != LuaUtils.Function_Stop && !transitioning)
		{
			#if !switch
			if(cpuHits == 0)
			{
			var percent:Float = ratingPercent;
			if(Math.isNaN(percent)) percent = 0;
			Highscore.saveScore(Song.loadedSongName, songScore, storyDifficulty, percent);
			}
			#end
			playbackRate = 1;

			if (chartingMode)
			{
				openChartEditor();
				return false;
			}

			if (isStoryMode)
			{
				campaignScore += songScore;
				campaignMisses += songMisses;

				storyPlaylist.remove(storyPlaylist[0]);

				if (storyPlaylist.length <= 0)
				{
					Mods.loadTopMod();
					FlxG.sound.playMusic(Paths.music('freakyMenu'));
					#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end

					canResync = false;
					MusicBeatState.switchState(new StoryMenuState());

					// if ()
					if(!ClientPrefs.getGameplaySetting('practice') && !ClientPrefs.getGameplaySetting('botplay') && cpuHits != 0) {
						StoryMenuState.weekCompleted.set(WeekData.weeksList[storyWeek], true);
						Highscore.saveWeekScore(WeekData.getWeekFileName(), campaignScore, storyDifficulty);

						FlxG.save.data.weekCompleted = StoryMenuState.weekCompleted;
						FlxG.save.flush();
					}
					changedDifficulty = false;
				}
				else
				{
					var difficulty:String = Difficulty.getFilePath();

					trace('LOADING NEXT SONG');
					trace(Paths.formatToSongPath(PlayState.storyPlaylist[0]) + difficulty);

					FlxTransitionableState.skipNextTransIn = true;
					FlxTransitionableState.skipNextTransOut = true;
					prevCamFollow = camFollow;

					Song.loadFromJson(PlayState.storyPlaylist[0] + difficulty, PlayState.storyPlaylist[0]);
					FlxG.sound.music.stop();

					canResync = false;
					LoadingState.prepareToSong();
					LoadingState.loadAndSwitchState(new PlayState(), false, false);
				}
			}
			else
			{
				openSubState(new ResultsScreen());
				/*trace('WENT BACK TO FREEPLAY??');
				Mods.loadTopMod();
				#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end

				canResync = false;
				MusicBeatState.switchState(new FreeplayState());
				FlxG.sound.playMusic(Paths.music('freakyMenu'));
				changedDifficulty = false;*/
			}
			transitioning = true;
		}
		return true;
	}

	public function KillNotes() {
		while(notes.length > 0) {
			var daNote:Note = notes.members[0];
			daNote.active = false;
			daNote.visible = false;
			invalidateNote(daNote);
		}
		unspawnNotes = [];
		eventNotes = [];
	}

	public var totalPlayed:Int = 0;
	public var totalNotesHit:Float = 0.0;

	public var showCombo:Bool = ClientPrefs.data.comboSprDisplay;
	public var showComboNum:Bool = true;
	public var showRating:Bool = true;
	public var showEXRating:Bool = ClientPrefs.data.exratingDisplay;

	// Stores Ratings and Combo Sprites in a group
	public var comboGroup:FlxSpriteGroup;
	// Stores HUD Objects in a Group
	public var uiGroup:FlxSpriteGroup;
	// Stores Note Objects in a Group
	public var noteGroup:FlxTypedGroup<FlxBasic>;

	private function cachePopUpScore()
	{
		var uiFolder:String = "";
		if (stageUI != "normal")
			uiFolder = uiPrefix + "UI/";

		for (rating in ratingsData)
			Paths.image(uiFolder + rating.image + uiPostfix + ratingexspr);
		for (theEXrating in ratingsData)
			Paths.image(uiFolder + theEXrating.image + uiPostfix + exratingexspr);
		for (i in 0...10)
			Paths.image(uiFolder + 'num' + i + uiPostfix + numexspr);
	}

	private function popUpScore(note:Note = null):Void
	{
		// 移除Math.abs()来允许显示负值
		var noteDiff:Float = note.strumTime - Conductor.songPosition + ClientPrefs.data.ratingOffset;

		// 在回放模式下，优先使用延迟覆盖值（最高优先级）
		if(isReplaying && currentNoteDelayOverride != null)
		{
			noteDiff = currentNoteDelayOverride;
			currentNoteDelayOverride = null; // 使用后清空
		}
		// 备用方案：从预填充的延迟数组中查找对应音符的记录
		else if(isReplaying && note.noteData >= 0 && note.noteData < 4)
		{
			for(delayData in replayNoteDelays[note.noteData])
			{
				if(delayData.strumTime == note.strumTime)
				{
					// 找到匹配的记录，使用原始记录的延迟值
					noteDiff = delayData.late;
					break;
				}
			}
		}

		allNotesMs += noteDiff;
		averageMs = allNotesMs/songHits;

		// 存储打击数据供 HitGraph 使用
		var daRating:Rating = Conductor.judgeNote(ratingsData, noteDiff / playbackRate);
		if(!cpuControlled || ClientPrefs.data.botplayScore)
		{
			if(!note.ratingDisabled)
			{
				hitHistory.push([noteDiff, daRating.name, note.strumTime]);
				
				// 记录回放数据（仅在非回放模式下）
				if(!isReplaying)
				{
					replayData.push({
						time: Conductor.songPosition,
						key: note.noteData,
						noteTime: note.strumTime,
						late: noteDiff,
						judge: daRating.name,
						releaseTime: null
					});
				}
			}
		}

		vocals.volume = 1;

		if (!ClientPrefs.data.comboStacking && comboGroup.members.length > 0)
		{
			for (spr in comboGroup)
			{
				if(spr == null) continue;

				comboGroup.remove(spr);
				spr.destroy();
			}
		}

		if (!ClientPrefs.data.rmmsTimeTxt) {
			if (isPixelStage) {
				msTimeTxt.font = Paths.font("pixel.otf");
				msTimeTxt.size = 16;

			}
			msTimeTxt.alpha = ratingAlpha;
			msTimeTxt.y = -ClientPrefs.data.comboOffset[3] + 480;
			// 调整显示格式，保留两位小数
			if(cpuControlled) msTimeTxt.text = Std.string(CoolUtil.floorDecimal(noteDiff, 2)) + "ms(BOT)";
			else msTimeTxt.text = Std.string(CoolUtil.floorDecimal(noteDiff, 2)) + "ms";
			msTimeTxt.color = noteDiff < 0 ? FlxColor.ORANGE : FlxColor.CYAN;

			if (msTimeTxtTween1 != null){
				msTimeTxtTween1.cancel(); msTimeTxtTween1.destroy(); // top 10 awesome code
			}
			msTimeTxtTween1 = FlxTween.tween(msTimeTxt, {alpha: 0}, 0.5, {
				onComplete: function(tw:FlxTween) {msTimeTxtTween1 = null;}, startDelay: (60 / Conductor.bpm) * 0.5
			});

			if (msTimeTxtTween2 != null){
				msTimeTxtTween2.cancel(); msTimeTxtTween2.destroy(); // top 10 awesome code
			}
			msTimeTxtTween2 = FlxTween.tween(msTimeTxt, {y: msTimeTxt.y + 10}, 0.2, {
				ease: FlxEase.quintOut,
			});
		}

		var placement:Float = FlxG.width * 0.35;
		var rating:FlxSprite = new FlxSprite();
		var theEXrating:FlxSprite = new FlxSprite();
		var score:Int = 350;

		//tryna do MS based judgment due to popular demand
		var daRating:Rating = Conductor.judgeNote(ratingsData, noteDiff / playbackRate);

		totalNotesHit += daRating.ratingMod;
		note.ratingMod = daRating.ratingMod;
		if(!note.ratingDisabled) daRating.hits++;
		note.rating = daRating.name;
		score = daRating.score;

		if(daRating.noteSplash && !note.noteSplashData.disabled && ClientPrefs.data.cpuStrums)
			spawnNoteSplashOnNote(note);

		/*if(!cpuControlled) */
		if(!cpuControlled || ClientPrefs.data.botplayScore)
		{
    		songScore += score;
    		if(!note.ratingDisabled) 
    		{
        		songHits++;
        		totalPlayed++; 
        		RecalculateRating(false);
    		}
		}

		if(cpuControlled) cpuHits++;
		if (ClientPrefs.data.ratCounter)	updateRatingCounters();

		var uiFolder:String = "";
		var antialias:Bool = ClientPrefs.data.antialiasing;
		if (stageUI != "normal")
		{
			uiFolder = uiPrefix + "UI/";
			antialias = !isPixelStage;
		}

		if (ClientPrefs.data.popUpRating)
		{
			rating.loadGraphic(Paths.image(uiFolder + daRating.image + ratingexspr + uiPostfix));
			rating.screenCenter();
			rating.x = placement - 40;
			rating.y -= 60;
			//rating.acceleration.y = 550 * playbackRate * playbackRate;
			//rating.velocity.y -= FlxG.random.int(140, 175) * playbackRate;
			//rating.velocity.x -= FlxG.random.int(0, 10) * playbackRate;
			rating.visible = (!ClientPrefs.data.hideHud && showRating);
			rating.x += ClientPrefs.data.comboOffset[0] - 30;
			rating.y -= ClientPrefs.data.comboOffset[1] - 130;
			rating.antialiasing = antialias;

			theEXrating.loadGraphic(Paths.image(uiFolder + daRating.image + exratingexspr + uiPostfix));
			theEXrating.screenCenter();
			theEXrating.x = placement - 40;
			theEXrating.y -= 60;
			//theEXrating.acceleration.y = 550 * playbackRate * playbackRate;
			//theEXrating.velocity.y -= FlxG.random.int(140, 175) * playbackRate;
			//theEXrating.velocity.x -= FlxG.random.int(0, 10) * playbackRate;
			theEXrating.visible = (!ClientPrefs.data.hideHud && showEXRating);
			theEXrating.x += ClientPrefs.data.comboOffset[4] - 220;
			theEXrating.y += -ClientPrefs.data.comboOffset[5] + 150;
			theEXrating.antialiasing = antialias;
			theEXrating.angle = 0;

	
			var comboSpr:FlxSprite = new FlxSprite().loadGraphic(Paths.image(uiFolder + 'combo' + uiPostfix));
			comboSpr.screenCenter();
			comboSpr.x = placement;
			//comboSpr.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
			//comboSpr.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
			//comboSpr.velocity.x += FlxG.random.int(1, 10) * playbackRate;
			comboSpr.visible = (!ClientPrefs.data.hideHud && showCombo);
			comboSpr.x += ClientPrefs.data.comboOffset[0] + 60;
			comboSpr.y -= ClientPrefs.data.comboOffset[1];
			comboSpr.antialiasing = antialias;
			comboSpr.y += 160;

			if (ClientPrefs.data.comboStacking)
			{
				// 原版向上跳跃逻辑
				rating.acceleration.y = 550 * playbackRate * playbackRate;
				rating.velocity.y -= FlxG.random.int(140, 175) * playbackRate;

				theEXrating.acceleration.y = 550 * playbackRate * playbackRate;
				theEXrating.velocity.y -= FlxG.random.int(140, 150) * playbackRate;

				comboSpr.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
				comboSpr.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
			}
			else
			{
				if (ClientPrefs.data.ratingFallStyle == "Legacy")
				{
					rating.acceleration.y = 550 * playbackRate * playbackRate;
					rating.velocity.y -= FlxG.random.int(140, 175) * playbackRate;

					theEXrating.acceleration.y = 550 * playbackRate * playbackRate;
					theEXrating.velocity.y -= FlxG.random.int(140, 150) * playbackRate;

					comboSpr.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
					comboSpr.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
				}
				else if (ClientPrefs.data.ratingFallStyle == "MintRhythm" || ClientPrefs.data.ratingFallStyle == "MintRhythm(Legacy)")
				{
					rating.velocity.y = 0;
					theEXrating.velocity.y = 0;
					comboSpr.velocity.y = 0;
				}
				else if (ClientPrefs.data.ratingFallStyle == "Leather")
				{
					rating.velocity.y = FlxG.random.int(30, 60);
					theEXrating.velocity.y = FlxG.random.int(40, 80);
					comboSpr.velocity.y = FlxG.random.int(30, 60);
					//呃呃没改完
				}
				else
				{
					rating.acceleration.y = 550 * playbackRate * playbackRate;
					rating.velocity.y -= FlxG.random.int(140, 175) * playbackRate;

					theEXrating.acceleration.y = 550 * playbackRate * playbackRate;
					theEXrating.velocity.y -= FlxG.random.int(140, 150) * playbackRate;

					comboSpr.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
					comboSpr.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
				}
			}

			if (!PlayState.isPixelStage)
			{
				rating.setGraphicSize(Std.int(rating.width * 0.7));
				theEXrating.setGraphicSize(Std.int(theEXrating.width * 0.7));
				comboSpr.setGraphicSize(Std.int(comboSpr.width * 0.65));
			}
			else
			{
				rating.setGraphicSize(Std.int(rating.width * daPixelZoom * 0.7));
				theEXrating.setGraphicSize(Std.int(theEXrating.width * daPixelZoom * 0.7));
				comboSpr.setGraphicSize(Std.int(comboSpr.width * daPixelZoom * 0.7));
			}


			if (ratingAlpha != 1)
			{
				rating.alpha = ratingAlpha;
				theEXrating.alpha = ratingAlpha;
				comboSpr.alpha = ratingAlpha;
			}

			if (ClientPrefs.data.ratingFallStyle == "MintRhythm(Legacy)")
			{
				comboGroup.add(rating);
				if (ClientPrefs.data.exratingDisplay)	comboGroup.add(theEXrating);
			}
			else
			{
				if (ClientPrefs.data.exratingDisplay)	comboGroup.add(theEXrating);
					comboGroup.add(rating);
			}
		

			if (ClientPrefs.data.comboStacking)
			{
				if (ClientPrefs.data.ratbounce == true && !PlayState.isPixelStage)
				{
					rating.scale.set(0.85, 0.8);
					FlxTween.tween(rating.scale, {x: 0.7, y: 0.7}, 0.35, {ease: FlxEase.quartOut});
				}

				if(ClientPrefs.data.exratbounce == true && ClientPrefs.data.exratingDisplay)
				{
					theEXrating.angle = (Math.random() * 10) * (Math.random() > .5 ? 1 : -1);
					theEXrating.scale.set(0.85, 0.85);
					FlxTween.tween(theEXrating, {angle: 0}, 0.4, {ease: FlxEase.backOut});
					FlxTween.tween(theEXrating.scale, {x: 0.7, y: 0.7}, 0.4, {ease: FlxEase.quartOut});
				}
			}
			else
			{
				// Combo Stacking禁用时，统一切换符号
				if (ClientPrefs.data.ratbounce == true && !PlayState.isPixelStage && ClientPrefs.data.ratingFallStyle != "MintRhythm(Legacy)")
				{
					rating.angle = (Math.random() * 7) * (Math.random() > .5 ? 1 : -1);
				}

				if(ClientPrefs.data.exratbounce == true && ClientPrefs.data.exratingDisplay && ClientPrefs.data.ratingFallStyle != "MintRhythm(Legacy)")
				{
					theEXrating.angle = (Math.random() * 7) * (Math.random() > .5 ? 1 : -1);
				}

				if ((ClientPrefs.data.ratingFallStyle == "MintRhythm" || ClientPrefs.data.ratingFallStyle == "MintRhythm(Legacy)"))
				{
					if (ClientPrefs.data.ratingFallStyle == "MintRhythm(Legacy)")
					{
						rating.angle = -4.5;
						rating.x -= 100;
						theEXrating.x = rating.x + ((rating.width / 2.1));
						theEXrating.y = rating.y - 50;
						theEXrating.alpha = (rating.alpha / 1.2);
						theEXrating.angle = 2;
						// theEXrating.x += ClientPrefs.data.comboOffset[0] - 30;
						// theEXrating.y -= ClientPrefs.data.comboOffset[1] - 130;
					}
					
					FlxTween.tween(rating, {y: rating.y + FlxG.random.int(12, 18)}, 0.2, {ease: FlxEase.quintOut});
					FlxTween.tween(theEXrating, {y: theEXrating.y + FlxG.random.int(15, 20)}, 0.2, {ease: FlxEase.quintOut});
					FlxTween.tween(comboSpr, {y: comboSpr.y + FlxG.random.int(12, 18)}, 0.2, {ease: FlxEase.quintOut});

				}

			}
	
			comboSpr.updateHitbox();
			rating.updateHitbox();
			theEXrating.updateHitbox();

			var daLoop:Int = 0;
			var xThing:Float = 0;
			if (showCombo)
				comboGroup.add(comboSpr);

			var separatedScore:String = Std.string(combo).lpad('0', 3);
			for (i in 0...separatedScore.length)
			{
				var numScore:FlxSprite = new FlxSprite().loadGraphic(Paths.image(uiFolder + 'num' + Std.parseInt(separatedScore.charAt(i)) + uiPostfix));
				numScore.screenCenter();
				numScore.x = placement + (43 * daLoop) - 70 + ClientPrefs.data.comboOffset[2];
				numScore.y += 80 - ClientPrefs.data.comboOffset[3] + 110;
				numScore.alpha = ratingAlpha;

				if (!PlayState.isPixelStage)
					numScore.setGraphicSize(Std.int(numScore.width * 0.5));
				else
					numScore.setGraphicSize(Std.int(numScore.width * daPixelZoom));
				numScore.updateHitbox();

				if (ClientPrefs.data.comboStacking)
				{
					// 原版向上跳跃逻辑
					numScore.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
					numScore.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
					numScore.velocity.x = FlxG.random.float(-5, 5) * playbackRate;
				}
				else
				{
					if (ClientPrefs.data.ratingFallStyle == "Legacy")
					{
						numScore.velocity.y = FlxG.random.int(30, 60);
						numScore.velocity.x = FlxG.random.float(-5, 5) * playbackRate;
					}
					else if (ClientPrefs.data.ratingFallStyle == "MintRhythm" || ClientPrefs.data.ratingFallStyle == "MintRhythm(Legacy)")
					{
						numScore.velocity.y = 0;
						numScore.velocity.x = 0;
						FlxTween.tween(numScore, {y: numScore.y + FlxG.random.int(12, 18)}, 0.2, {ease: FlxEase.quintOut});
					}
					else 
					{
						numScore.velocity.y = FlxG.random.int(20, 40);
						numScore.velocity.x = FlxG.random.float(-5, 5) * playbackRate;
					}
				}
				numScore.visible = !ClientPrefs.data.hideHud;
				numScore.antialiasing = antialias;

				// if (combo >= 10 || combo == 0)
				if (showComboNum)
					comboGroup.add(numScore);

				// 根据不同的跳动风格设置渐隐延迟
				var numScoreFadeDelay:Float = Conductor.crochet * 0.002 / playbackRate;
				if (!ClientPrefs.data.comboStacking && (ClientPrefs.data.ratingFallStyle == "MintRhythm" || ClientPrefs.data.ratingFallStyle == "MintRhythm(Legacy)"))
				{
					// MintRhythm模式下，跳动完成后才开始渐隐
					numScoreFadeDelay += 0.2;
				}

				FlxTween.tween(numScore, {alpha: 0}, 0.2 / playbackRate, {
					onComplete: function(tween:FlxTween)
					{
						numScore.destroy();
					},
					startDelay: numScoreFadeDelay
				});

				daLoop++;
				if (numScore.x > xThing)
					xThing = numScore.x;
			}
			comboSpr.x = xThing + 50;

			// 根据不同的跳动风格设置渐隐延迟
			var ratingFadeDelay:Float = Conductor.crochet * 0.001 / playbackRate;
			var exRatingFadeDelay:Float = Conductor.crochet * 0.0008 / playbackRate;
			var comboFadeDelay:Float = Conductor.crochet * 0.0015 / playbackRate;

			if (!ClientPrefs.data.comboStacking && (ClientPrefs.data.ratingFallStyle == "MintRhythm" || ClientPrefs.data.ratingFallStyle == "MintRhythm(Legacy)"))
			{
				// MintRhythm模式下，跳动完成后才开始渐隐
				ratingFadeDelay += 0.2;
				exRatingFadeDelay += 0.2;
				comboFadeDelay += 0.2;
			}

			FlxTween.tween(rating, {alpha: 0}, 0.2 / playbackRate, {
				onComplete: function(tween:FlxTween)
				{
					FlxTween.cancelTweensOf(rating);
					rating.destroy();
				},
				startDelay: ratingFadeDelay
			});
			FlxTween.tween(theEXrating, {alpha: 0}, 0.2 / playbackRate, {
				onComplete: function(tween:FlxTween)
				{
					FlxTween.cancelTweensOf(theEXrating);
					theEXrating.destroy();
				},
				startDelay: exRatingFadeDelay
			});

			FlxTween.tween(comboSpr, {alpha: 0}, 0.2 / playbackRate, {
				onComplete: function(tween:FlxTween)
				{
					FlxTween.cancelTweensOf(comboSpr);
					comboSpr.destroy();
				},
				startDelay: comboFadeDelay
			});
		}
	}

	function updateRatingCounters() {
	// 获取各评分数量
	var perfects = !ClientPrefs.data.rmPerfect ? ratingsData[4].hits : 0;
	var sicks = ratingsData[0].hits;
	var goods = ratingsData[1].hits;
	var bads = ratingsData[2].hits;
	var shits = ratingsData[3].hits;
	
	// 计算分母
	var MA_denominator = sicks + goods + bads + shits; // 非完美总数
	var PA_denominator = goods + bads + shits;         // 良好及以下总数
	
	// 构建文本
	ratingCounter.text = (!ClientPrefs.data.rmPerfect ? "Perfects: " + perfects + "\n" : "")
		+ "Sicks: " + sicks
		+ "\nGoods: " + goods
		+ "\nBads: " + bads
		+ "\nShits: " + shits
		
		// 添加MA/PA计算
		+ (ClientPrefs.data.rmPerfect ? "" : 
			(perfects > 0 && MA_denominator > 0 ? 
				"\nMA: " + FlxMath.roundDecimal(perfects / MA_denominator, 2) : ""))
				
		+ (PA_denominator > 0 ? 
			"\nPA: " + FlxMath.roundDecimal((perfects + sicks) / PA_denominator, 2) : "");
}

	public var strumsBlocked:Array<Bool> = [];
	private function onKeyPress(event:KeyboardEvent):Void
	{

		var eventKey:FlxKey = event.keyCode;
		var key:Int = getKeyFromEvent(keysArray, eventKey);

		if (!controls.controllerMode)
		{
			#if debug
			//Prevents crash specifically on debug without needing to try catch shit
			@:privateAccess if (!FlxG.keys._keyListMap.exists(eventKey)) return;
			#end

			if(FlxG.keys.checkStatus(eventKey, JUST_PRESSED)) keyPressed(key);
		}
	}

	private function keyPressed(key:Int)
	{
		if(cpuControlled || paused || inCutscene || key < 0 || key >= playerStrums.length || !generatedMusic || endingSong || boyfriend.stunned || isReplaying) return;

		var ret:Dynamic = callOnScripts('onKeyPressPre', [key]);
		if(ret == LuaUtils.Function_Stop) return;

		// more accurate hit time for the ratings?
		//判定修改（？）
		//var lastTime:Float = Conductor.songPosition;
		//if(Conductor.songPosition >= 0) Conductor.songPosition = FlxG.sound.music.time + Conductor.offset;

		// obtain notes that the player can hit
		var plrInputNotes:Array<Note> = notes.members.filter(function(n:Note):Bool {
			var canHit:Bool = n != null && !strumsBlocked[n.noteData] && n.canBeHit && n.mustPress && !n.tooLate && !n.wasGoodHit && !n.blockHit;
			return canHit && !n.isSustainNote && n.noteData == key;
		});
		plrInputNotes.sort(sortHitNotes);

		// 记录按键按下的索引（用于后续记录抬起动作）- 在判断是否有音符之后设置，以确保索引正确
		if(!isReplaying && key >= 0 && key < 4)
		{
			// 先记录索引
			keyPressIndices[key] = replayData.length;
		}

		if (plrInputNotes.length != 0) { // slightly faster than doing `> 0` lol
			var funnyNote:Note = plrInputNotes[0]; // front note

			if (plrInputNotes.length > 1) {
				var doubleNote:Note = plrInputNotes[1];

				if (doubleNote.noteData == funnyNote.noteData) {
					// if the note has a 0ms distance (is on top of the current note), kill it
					if (Math.abs(doubleNote.strumTime - funnyNote.strumTime) < 1.0)
						invalidateNote(doubleNote);
					else if (doubleNote.strumTime < funnyNote.strumTime)
					{
						// replace the note if its ahead of time (or at least ensure "doubleNote" is ahead)
						funnyNote = doubleNote;
					}
				}
			}
			goodNoteHit(funnyNote);
		}
		else
		{
			if (ClientPrefs.data.ghostTapping)
			{
				// ghostTapping开启时，也需要记录回放数据
				if(!isReplaying)
				{
					replayData.push({
						time: Conductor.songPosition,
						key: key,
						noteTime: null,
						late: null,
						judge: 'ghost',
						releaseTime: null
					});
				}
				callOnScripts('onGhostTap', [key]);
			}
			else
			{
				noteMissPress(key);
			}
		}

		// Needed for the  "Just the Two of Us" achievement.
		//									- Shadow Mario
		if(!keysPressed.contains(key)) keysPressed.push(key);

		//more accurate hit time for the ratings? part 2 (Now that the calculations are done, go back to the time it was before for not causing a note stutter)
		//判定修改（？）
		//Conductor.songPosition = lastTime;

		var spr:StrumNote = playerStrums.members[key];
		if(strumsBlocked[key] != true && spr != null && spr.animation.curAnim.name != 'confirm')
		{
			spr.playAnim('pressed');
			spr.resetAnim = 0; // 不自动重置，由按键释放时重置
		}
		callOnScripts('onKeyPress', [key]);
	}

	public static function sortHitNotes(a:Note, b:Note):Int
	{
		if (a.lowPriority && !b.lowPriority)
			return 1;
		else if (!a.lowPriority && b.lowPriority)
			return -1;

		return FlxSort.byValues(FlxSort.ASCENDING, a.strumTime, b.strumTime);
	}

	private function onKeyRelease(event:KeyboardEvent):Void
	{
		var eventKey:FlxKey = event.keyCode;
		var key:Int = getKeyFromEvent(keysArray, eventKey);
		if(!controls.controllerMode && key > -1) keyReleased(key);
	}

	private function keyReleased(key:Int)
	{
		if(cpuControlled || !startedCountdown || paused || key < 0 || key >= playerStrums.length || isReplaying) return;

		var ret:Dynamic = callOnScripts('onKeyReleasePre', [key]);
		if(ret == LuaUtils.Function_Stop) return;

		// 记录按键抬起动作
		if(!isReplaying && key >= 0 && key < 4 && keyPressIndices[key] >= 0)
		{
			// 更新对应按下记录的抬起时间
			if(keyPressIndices[key] < replayData.length)
			{
				replayData[keyPressIndices[key]].releaseTime = Conductor.songPosition;
			}
			keyPressIndices[key] = -1;
		}

		var spr:StrumNote = playerStrums.members[key];
		if(spr != null)
		{
			spr.playAnim('static');
			spr.resetAnim = 0;
		}
		callOnScripts('onKeyRelease', [key]);
	}

	public static function getKeyFromEvent(arr:Array<String>, key:FlxKey):Int
	{
		if(key != NONE)
		{
			for (i in 0...arr.length)
			{
				var note:Array<FlxKey> = Controls.instance.keyboardBinds[arr[i]];
				for (noteKey in note)
					if(key == noteKey)
						return i;
			}
		}
		return -1;
	}

	private function onButtonPress(button:TouchButton):Void
	{
		if (button.IDs.filter(id -> id.toString().startsWith("EXTRA")).length > 0)
			return;

		var buttonCode:Int = (button.IDs[0].toString().startsWith('NOTE')) ? button.IDs[0] : button.IDs[1];
		callOnScripts('onButtonPressPre', [buttonCode]);
		if (button.justPressed) keyPressed(buttonCode);
		callOnScripts('onButtonPress', [buttonCode]);
	}

	private function onButtonRelease(button:TouchButton):Void
	{
		if (button.IDs.filter(id -> id.toString().startsWith("EXTRA")).length > 0)
			return;

		var buttonCode:Int = (button.IDs[0].toString().startsWith('NOTE')) ? button.IDs[0] : button.IDs[1];
		callOnScripts('onButtonReleasePre', [buttonCode]);
		if(buttonCode > -1) keyReleased(buttonCode);
		callOnScripts('onButtonRelease', [buttonCode]);
	}

	// Hold notes
	private function keysCheck():Void
	{
		// HOLDING
		var holdArray:Array<Bool> = [];
		var pressArray:Array<Bool> = [];
		var releaseArray:Array<Bool> = [];
		for (i in 0...keysArray.length)
		{
			// 在回放模式下使用replayHeldKeys，否则使用controls.pressed
			if(isReplaying)
			{
				holdArray.push(replayHeldKeys[i]);
				pressArray.push(false); // 回放模式下不使用justPressed
				releaseArray.push(false); // 回放模式下不使用justReleased
			}
			else
			{
				holdArray.push(controls.pressed(keysArray[i]));
				pressArray.push(controls.justPressed(keysArray[i]));
				releaseArray.push(controls.justReleased(keysArray[i]));
			}
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if(controls.controllerMode && pressArray.contains(true))
			for (i in 0...pressArray.length)
				if(pressArray[i] && strumsBlocked[i] != true)
					keyPressed(i);

		if (startedCountdown && !inCutscene && !boyfriend.stunned && generatedMusic)
		{
			if (notes.length > 0) {
				for (n in notes) { // I can't do a filter here, that's kinda awesome
					var canHit:Bool = (n != null && !strumsBlocked[n.noteData] && n.canBeHit
						&& n.mustPress && !n.tooLate && !n.wasGoodHit && !n.blockHit);

					if (guitarHeroSustains)
						canHit = canHit && n.parent != null && n.parent.wasGoodHit;

					if (canHit && n.isSustainNote) {
						var released:Bool = !holdArray[n.noteData];

						if (!released)
							goodNoteHit(n);
					}
				}
			}

			if (!holdArray.contains(true) || endingSong)
				playerDance();

			#if ACHIEVEMENTS_ALLOWED
			else checkForAchievement(['oversinging']);
			#end
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if((controls.controllerMode || strumsBlocked.contains(true)) && releaseArray.contains(true))
			for (i in 0...releaseArray.length)
				if(releaseArray[i] || strumsBlocked[i] == true)
					keyReleased(i);
	}

	function noteMiss(daNote:Note):Void { //You didn't hit the key and let it go offscreen, also used by Hurt Notes
		// 记录回放数据（仅在非回放模式下）
		if(!isReplaying && daNote.mustPress && !daNote.isSustainNote)
		{
			replayData.push({
				time: Conductor.songPosition,
				key: daNote.noteData,
				noteTime: daNote.strumTime,
				late: null,
				judge: 'miss',
				releaseTime: null
			});
		}
		
		//Dupe note remove
		notes.forEachAlive(function(note:Note) {
			if (daNote != note && daNote.mustPress && daNote.noteData == note.noteData && daNote.isSustainNote == note.isSustainNote && Math.abs(daNote.strumTime - note.strumTime) < 1)
				invalidateNote(note);
		});

		noteMissCommon(daNote.noteData, daNote);
		stagesFunc(function(stage:BaseStage) stage.noteMiss(daNote));
		var result:Dynamic = callOnLuas('noteMiss', [notes.members.indexOf(daNote), daNote.noteData, daNote.noteType, daNote.isSustainNote]);
		if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) callOnHScript('noteMiss', [daNote]);
	}

	function noteMissPress(direction:Int = 1):Void //You pressed a key when there was no notes to press for this key
	{
		if(ClientPrefs.data.ghostTapping) return; //fuck it

		noteMissCommon(direction);
		FlxG.sound.play(Paths.soundRandom('missnote', 1, 3), FlxG.random.float(0.1, 0.2));
		stagesFunc(function(stage:BaseStage) stage.noteMissPress(direction));
		callOnScripts('noteMissPress', [direction]);
	}

	function noteMissCommon(direction:Int, note:Note = null)
	{
		// score and data
		var subtract:Float = pressMissDamage;
		if(note != null) subtract = note.missHealth;

		// GUITAR HERO SUSTAIN CHECK LOL!!!!
		if (note != null && guitarHeroSustains && note.parent == null) {
			if(note.tail.length > 0) {
				note.alpha = 0.35;
				for(childNote in note.tail) {
					childNote.alpha = note.alpha;
					childNote.missed = true;
					childNote.canBeHit = false;
					childNote.ignoreNote = true;
					childNote.tooLate = true;
				}
				note.missed = true;
				note.canBeHit = false;

				//subtract += 0.385; // you take more damage if playing with this gameplay changer enabled.
				// i mean its fair :p -Crow
				subtract *= note.tail.length + 1;
				// i think it would be fair if damage multiplied based on how long the sustain is -[REDACTED]
			}

			if (note.missed)
				return;
		}
		if (note != null && guitarHeroSustains && note.parent != null && note.isSustainNote) {
			if (note.missed)
				return;

			var parentNote:Note = note.parent;
			if (parentNote.wasGoodHit && parentNote.tail.length > 0) {
				for (child in parentNote.tail) if (child != note) {
					child.missed = true;
					child.canBeHit = false;
					child.ignoreNote = true;
					child.tooLate = true;
				}
			}
		}

		if(instakillOnMiss)
		{
			vocals.volume = 0;
			opponentVocals.volume = 0;
			doDeathCheck(true);
		}

		var lastCombo:Int = combo;
		combo = 0;

		health -= subtract * healthLoss;
		songScore -= 10;
		if(!endingSong) songMisses++;
		totalPlayed++;
		RecalculateRating(true);

		// play character anims
		var char:Character = boyfriend;
		if((note != null && note.gfNote) || (SONG.notes[curSection] != null && SONG.notes[curSection].gfSection)) char = gf;

		if(char != null && (note == null || !note.noMissAnimation) && char.hasMissAnimations)
		{
			var postfix:String = '';
			if(note != null) postfix = note.animSuffix;

			var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, direction)))] + 'miss' + postfix;
			char.playAnim(animToPlay, true);

			if(char != gf && lastCombo > 5 && gf != null && gf.hasAnimation('sad'))
			{
				gf.playAnim('sad');
				gf.specialAnim = true;
			}
		}
		vocals.volume = 0;
	}

	function opponentNoteHit(note:Note):Void
	{
		var result:Dynamic = callOnLuas('opponentNoteHitPre', [notes.members.indexOf(note), Math.abs(note.noteData), note.noteType, note.isSustainNote]);
		if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) result = callOnHScript('opponentNoteHitPre', [note]);

		if(result == LuaUtils.Function_Stop) return;

		if (songName != 'tutorial')
			camZooming = true;

		if(note.noteType == 'Hey!' && dad.hasAnimation('hey'))
		{
			dad.playAnim('hey', true);
			dad.specialAnim = true;
			dad.heyTimer = 0.6;
		}
		else if(!note.noAnimation)
		{
			var char:Character = dad;
			var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, note.noteData)))] + note.animSuffix;
			if(note.gfNote) char = gf;

			if(char != null)
			{
				var canPlay:Bool = true;
				if(note.isSustainNote)
				{
					var holdAnim:String = animToPlay + '-hold';
					if(char.animation.exists(holdAnim)) animToPlay = holdAnim;
					if(char.getAnimationName() == holdAnim || char.getAnimationName() == holdAnim + '-loop') canPlay = false;
				}

				if(canPlay) char.playAnim(animToPlay, true);
				char.holdTimer = 0;
			}
		}

		if(opponentVocals.length <= 0) vocals.volume = 1;
		strumPlayAnim(true, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / playbackRate);
		note.hitByOpponent = true;
		
		stagesFunc(function(stage:BaseStage) stage.opponentNoteHit(note));
		var result:Dynamic = callOnLuas('opponentNoteHit', [notes.members.indexOf(note), Math.abs(note.noteData), note.noteType, note.isSustainNote]);
		if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) callOnHScript('opponentNoteHit', [note]);

		if (!note.isSustainNote) invalidateNote(note);
	}

	public function goodNoteHit(note:Note):Void
	{
		if(note.wasGoodHit) return;
		if(/*cpuControlled && */note.ignoreNote) return;

		var isSus:Bool = note.isSustainNote; //GET OUT OF MY HEAD, GET OUT OF MY HEAD, GET OUT OF MY HEAD
		var leData:Int = Math.round(Math.abs(note.noteData));
		var leType:String = note.noteType;

		var result:Dynamic = callOnLuas('goodNoteHitPre', [notes.members.indexOf(note), leData, leType, isSus]);
		if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) result = callOnHScript('goodNoteHitPre', [note]);

		if(result == LuaUtils.Function_Stop) return;

		note.wasGoodHit = true;

		if (note.hitsoundVolume > 0 && !note.hitsoundDisabled)
			FlxG.sound.play(Paths.sound(note.hitsound), note.hitsoundVolume);

		if(!note.hitCausesMiss) //Common notes
		{
			if(!note.noAnimation)
			{
				var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, note.noteData)))] + note.animSuffix;

				var char:Character = boyfriend;
				var animCheck:String = 'hey';
				if(note.gfNote)
				{
					char = gf;
					animCheck = 'cheer';
				}

				if(char != null)
				{
					var canPlay:Bool = true;
					if(note.isSustainNote)
					{
						var holdAnim:String = animToPlay + '-hold';
						if(char.animation.exists(holdAnim)) animToPlay = holdAnim;
						if(char.getAnimationName() == holdAnim || char.getAnimationName() == holdAnim + '-loop') canPlay = false;
					}
	
					if(canPlay) char.playAnim(animToPlay, true);
					char.holdTimer = 0;

					if(note.noteType == 'Hey!')
					{
						if(char.hasAnimation(animCheck))
						{
							char.playAnim(animCheck, true);
							char.specialAnim = true;
							char.heyTimer = 0.6;
						}
					}
				}
			}

			if(!cpuControlled)
			{
				var spr = playerStrums.members[note.noteData];
				if(spr != null) spr.playAnim('confirm', true);
			}
			else strumPlayAnim(false, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / playbackRate);
			vocals.volume = 1;

			if (!note.isSustainNote)
			{
				combo++;
				//if(combo > 9999) combo = 9999;
				notesHitArray.unshift(Date.now());
				popUpScore(note);
			}
			var gainHealth:Bool = true; // prevent health gain, *if* sustains are treated as a singular note
			if (guitarHeroSustains && note.isSustainNote) gainHealth = false;
			if (gainHealth) health += note.hitHealth * healthGain;

		}
		else //Notes that count as a miss if you hit them (Hurt notes for example)
		{
			if(!note.noMissAnimation)
			{
				switch(note.noteType)
				{
					case 'Hurt Note':
						if(boyfriend.hasAnimation('hurt'))
						{
							boyfriend.playAnim('hurt', true);
							boyfriend.specialAnim = true;
						}
				}
			}

			noteMiss(note);
			if(!note.noteSplashData.disabled && !note.isSustainNote && ClientPrefs.data.cpuStrums) spawnNoteSplashOnNote(note);
		}

		stagesFunc(function(stage:BaseStage) stage.goodNoteHit(note));
		var result:Dynamic = callOnLuas('goodNoteHit', [notes.members.indexOf(note), leData, leType, isSus]);
		if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) callOnHScript('goodNoteHit', [note]);
		if(!note.isSustainNote) invalidateNote(note);
	}

	public function invalidateNote(note:Note):Void {
		if(!ClientPrefs.data.lowQuality || !cpuControlled) note.kill();
		notes.remove(note, true);
		note.destroy();
	}

	public function spawnNoteSplashOnNote(note:Note) {
		if(note != null) {
			var strum:StrumNote = playerStrums.members[note.noteData];
			if(strum != null)
				spawnNoteSplash(strum.x, strum.y, note.noteData, note, strum);
		}
	}

	public function spawnNoteSplash(x:Float = 0, y:Float = 0, ?data:Int = 0, ?note:Note, ?strum:StrumNote) {
		var splash:NoteSplash = grpNoteSplashes.recycle(NoteSplash);
		splash.babyArrow = strum;
		splash.spawnSplashNote(x, y, data, note);
		grpNoteSplashes.add(splash);
	}

	override function destroy() {
		if (psychlua.CustomSubstate.instance != null)
		{
			closeSubState();
			resetSubState();
		}

		#if LUA_ALLOWED
		for (lua in luaArray)
		{
			lua.call('onDestroy', []);
			lua.stop();
		}
		luaArray = null;
		FunkinLua.customFunctions.clear();
		#end

		#if HSCRIPT_ALLOWED
		for (script in hscriptArray)
			if(script != null)
			{
				if(script.exists('onDestroy')) script.call('onDestroy');
				script.destroy();
			}

		hscriptArray = null;
		#end
		stagesFunc(function(stage:BaseStage) stage.destroy());

		#if VIDEOS_ALLOWED
		if(videoCutscene != null)
		{
			videoCutscene.destroy();
			videoCutscene = null;
		}
		#end

		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP, onKeyRelease);

		FlxG.camera.filters = [];

		#if FLX_PITCH FlxG.sound.music.pitch = 1; #end
		FlxG.animationTimeScale = 1;

		Note.globalRgbShaders = [];
		backend.NoteTypesConfig.clearNoteTypesData();

		NoteSplash.configs.clear();
		instance = null;
		shutdownThread = true;
		FlxG.signals.preUpdate.remove(checkForResync);
		super.destroy();
	}

	var lastStepHit:Int = -1;
	override function stepHit()
	{
		if (ClientPrefs.data.timebarStyle == 'Leather')
		{
			var section = SONG.notes[curSection];
			if (section != null)
			{
				if (section.mustHitSection)
				{
					timeBarRightColorTarget = FlxColor.fromRGB(boyfriend.healthColorArray[0], boyfriend.healthColorArray[1], boyfriend.healthColorArray[2]);
				}
				else
				{
					timeBarRightColorTarget = FlxColor.fromRGB(dad.healthColorArray[0], dad.healthColorArray[1], dad.healthColorArray[2]);
				}
			}
		}

		super.stepHit();

		if(curStep == lastStepHit) {
			return;
		}

		lastStepHit = curStep;
		setOnScripts('curStep', curStep);
		callOnScripts('onStepHit');
	}

	var lastBeatHit:Int = -1;

	override function beatHit()
	{
		if(lastBeatHit >= curBeat) {
			//trace('BEAT HIT: ' + curBeat + ', LAST HIT: ' + lastBeatHit);
			return;
		}

		if (generatedMusic)
			notes.sort(FlxSort.byY, ClientPrefs.data.downScroll ? FlxSort.ASCENDING : FlxSort.DESCENDING);

		if (iconBopEnabled)
		{
			if (ClientPrefs.data.iconbopstyle != "NONE")
			{
				switch (ClientPrefs.data.iconbopstyle)
				{
					case "Kade":
						iconP1.scale.set(1.4, 1.4);
						iconP2.scale.set(1.4, 1.4);

            	case /*"Leather" | */"VSlice(New)" | "Codename" | "VSlice(Old)" | "NovaFlare" | "MintRhythm":
						iconP1.scale.set(1.3, 1.3);
						iconP2.scale.set(1.3, 1.3);

					case "Vanilla":
						iconP1.scale.set(1.1, 1.1);
						iconP2.scale.set(1.1, 1.1);

					case "Dave":
						var funny:Float = Math.max(Math.min(2.4, 3.8), 0.1);
						iconP1.setGraphicSize(Std.int(iconP1.width + (100 * (funny + 0.1))), Std.int(iconP1.height - (35 * funny))); // 调整宽度和高度
                    iconP2.setGraphicSize(Std.int(iconP2.width + (100 * ((2 - funny) + 0.1))), Std.int(iconP2.height - (35 * ((2 - funny) + 0.1)))); // 调整宽度和高度
					default:
						iconP1.scale.set(1.2, 1.2);
						iconP2.scale.set(1.2, 1.2);
				}
			}
			dancingLeft = !dancingLeft;

			if (ClientPrefs.data.iconbopstyle == "OS")
			{
				if (dancingLeft)
				{
					iconP1.angle = 8;
					iconP2.angle = 8; // maybe i should do it with tweens, but i'm lazy // i'll make it in -1.0.0, i promise //这是OS引擎的作者写的，然而OS已经停更了（悲）
				}
				else
				{
					iconP1.angle = -8;
					iconP2.angle = -8;
				}
			}
			else if (ClientPrefs.data.iconbopstyle == "SB")
			{
				if (dancingLeft)
				{
					iconP1.angle = -15;
					iconP2.angle = 15;
				}
				else
				{
					iconP1.angle = 15;
					iconP2.angle = -15;
				}
			}
			else if (ClientPrefs.data.iconbopstyle == "MintRhythm")
			{
				var healthPercent:Float = healthBar.percent;
				if (healthPercent < 20)
				{
					if (curBeat % 2 == 0)
					{
						iconP2.angle += icondancingLeft ? -17 : 17;
						icondancingLeft = !icondancingLeft;
					}
				}
				else if (healthPercent > 80)
				{
					if (curBeat % 2 == 0)
					{
						iconP1.angle += icondancingLeft ? -17 : 17;
						icondancingLeft = !icondancingLeft;
					}
				}
			}
		}

		iconP1.updateHitbox();
		iconP2.updateHitbox();

		characterBopper(curBeat);

		super.beatHit();
		lastBeatHit = curBeat;

		setOnScripts('curBeat', curBeat);
		callOnScripts('onBeatHit');
	}

	public function iconBopNow():Void
	{
		if (ClientPrefs.data.iconbopstyle != "NONE")
    	{
        	switch(ClientPrefs.data.iconbopstyle) {
            	case "Kade":
                	iconP1.scale.set(1.4, 1.4);
                	iconP2.scale.set(1.4, 1.4);

            	case /*"Leather" | */"VSlice(New)" | "Codename" | "VSlice(Old)" | "NovaFlare" | "MintRhythm":
                	iconP1.scale.set(1.3, 1.3);
                	iconP2.scale.set(1.3, 1.3);
                
            	case "Vanilla":
                	iconP1.scale.set(1.1, 1.1);
                	iconP2.scale.set(1.1, 1.1);
                
            	case "Dave": 
                    var funny:Float = Math.max(Math.min(1.2, 1.9), 0.1);
                    iconP1.setGraphicSize(Std.int(iconP1.width + (70 * (funny + 0.1))), Std.int(iconP1.height - (35 * funny)));
                    iconP2.setGraphicSize(Std.int(iconP2.width + (70 * ((2 - funny) + 0.1))), Std.int(iconP2.height - (35 * ((2 - funny) + 0.1))));
            	default:
                	iconP1.scale.set(1.2, 1.2);
                	iconP2.scale.set(1.2, 1.2);
        	}
    	}
    	dancingLeft = !dancingLeft;

    	if (ClientPrefs.data.iconbopstyle == "OS") {
    		if (dancingLeft){
    			iconP1.angle = 8; iconP2.angle = 8;
    		} else { 
    			iconP1.angle = -8; iconP2.angle = -8;
    		}
    	} 	
    	else if (ClientPrefs.data.iconbopstyle == "SB") {
    		if (dancingLeft){
    			iconP1.angle = -15; iconP2.angle = 15;
    		} else { 
    			iconP1.angle = 15; iconP2.angle = -15;
    		}
    	}
    	else if (ClientPrefs.data.iconbopstyle == "MintRhythm")
    	{
    		var healthPercent:Float = healthBar.percent;
    		if (healthPercent < 20)
    		{
    			iconP2.angle += icondancingLeft ? -17 : 17;
    			icondancingLeft = !icondancingLeft;
    		}
    		else if (healthPercent > 80)
    		{
    			iconP1.angle += icondancingLeft ? -17 : 17;
    			icondancingLeft = !icondancingLeft;
    		}
    	}
    	iconP1.updateHitbox();
    	iconP2.updateHitbox();
	}

	public function characterBopper(beat:Int):Void
	{
		if (gf != null && beat % Math.round(gfSpeed * gf.danceEveryNumBeats) == 0 && !gf.getAnimationName().startsWith('sing') && !gf.stunned)
			gf.dance();
		if (boyfriend != null && beat % boyfriend.danceEveryNumBeats == 0 && !boyfriend.getAnimationName().startsWith('sing') && !boyfriend.stunned)
			boyfriend.dance();
		if (dad != null && beat % dad.danceEveryNumBeats == 0 && !dad.getAnimationName().startsWith('sing') && !dad.stunned)
			dad.dance();
	}

	public function playerDance():Void
	{
		var anim:String = boyfriend.getAnimationName();
		if(boyfriend.holdTimer > Conductor.stepCrochet * (0.0011 #if FLX_PITCH / FlxG.sound.music.pitch #end) * boyfriend.singDuration && anim.startsWith('sing') && !anim.endsWith('miss'))
			boyfriend.dance();
	}

	override function sectionHit()
{
    if (SONG.notes[curSection] != null)
    {
        if (generatedMusic && !endingSong && !isCameraOnForcedPos)
            moveCameraSection();

        if (camZooming /*&& FlxG.camera.zoom < 1.35 */&& ClientPrefs.data.camZooms)
        {
            FlxG.camera.zoom += 0.015 * camZoomingMult;
            camHUD.zoom += 0.03 * camZoomingMult;
        }

        if (ClientPrefs.data.iconbopstyle == "MintRhythm" && iconBopEnabled)
			{
				var healthPercent:Float = healthBar.percent;
				if (healthPercent < 20)
				{
					iconP1.angle += 30;
				}
				else if (healthPercent > 80)
				{
					iconP2.angle -= 30;
				}
				else
				{
					iconP1.angle -= 25;
					iconP2.angle += 25;
				}
			}

        if (SONG.notes[curSection].changeBPM)
        {
            Conductor.bpm = SONG.notes[curSection].bpm;
            setOnScripts('curBpm', Conductor.bpm);
            setOnScripts('crochet', Conductor.crochet);
            setOnScripts('stepCrochet', Conductor.stepCrochet);
        }
        setOnScripts('mustHitSection', SONG.notes[curSection].mustHitSection);
        setOnScripts('altAnim', SONG.notes[curSection].altAnim);
        setOnScripts('gfSection', SONG.notes[curSection].gfSection);
    }
    super.sectionHit();

    setOnScripts('curSection', curSection);
    callOnScripts('onSectionHit');
}

	#if LUA_ALLOWED
	public function startLuasNamed(luaFile:String)
	{
		#if MODS_ALLOWED
		var luaToLoad:String = Paths.modFolders(luaFile);
		if(!FileSystem.exists(luaToLoad))
			luaToLoad = Paths.getSharedPath(luaFile);

		if(FileSystem.exists(luaToLoad))
		#elseif sys
		var luaToLoad:String = Paths.getSharedPath(luaFile);
		if(OpenFlAssets.exists(luaToLoad))
		#end
		{
			for (script in luaArray)
				if(script.scriptName == luaToLoad) return false;

			new FunkinLua(luaToLoad);
			return true;
		}
		return false;
	}
	#end

	#if HSCRIPT_ALLOWED
	public function startHScriptsNamed(scriptFile:String)
	{
		#if MODS_ALLOWED
		var scriptToLoad:String = Paths.modFolders(scriptFile);
		if(!FileSystem.exists(scriptToLoad))
			scriptToLoad = Paths.getSharedPath(scriptFile);
		#else
		var scriptToLoad:String = Paths.getSharedPath(scriptFile);
		#end

		if(FileSystem.exists(scriptToLoad))
		{
			if (Iris.instances.exists(scriptToLoad)) return false;

			initHScript(scriptToLoad);
			return true;
		}
		return false;
	}

	public function initHScript(file:String)
	{
		var newScript:HScript = null;
		try
		{
			newScript = new HScript(null, file);
			if (newScript.exists('onCreate')) newScript.call('onCreate');
			trace('initialized hscript interp successfully: $file');
			hscriptArray.push(newScript);
		}
		catch(e:IrisError)
		{
			var pos:HScriptInfos = cast {fileName: file, showLine: false};
			Iris.error(Printer.errorToString(e, false), pos);
			var newScript:HScript = cast (Iris.instances.get(file), HScript);
			if(newScript != null)
				newScript.destroy();
		}
	}
	#end

	public function callOnScripts(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;
		if(args == null) args = [];
		if(exclusions == null) exclusions = [];
		if(excludeValues == null) excludeValues = [LuaUtils.Function_Continue];

		var result:Dynamic = callOnLuas(funcToCall, args, ignoreStops, exclusions, excludeValues);
		if(result == null || excludeValues.contains(result)) result = callOnHScript(funcToCall, args, ignoreStops, exclusions, excludeValues);
		return result;
	}

	public function callOnLuas(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;
		#if LUA_ALLOWED
		if(args == null) args = [];
		if(exclusions == null) exclusions = [];
		if(excludeValues == null) excludeValues = [LuaUtils.Function_Continue];

		var arr:Array<FunkinLua> = [];
		for (script in luaArray)
		{
			if(script.closed)
			{
				arr.push(script);
				continue;
			}

			if(exclusions.contains(script.scriptName))
				continue;

			var myValue:Dynamic = script.call(funcToCall, args);
			if((myValue == LuaUtils.Function_StopLua || myValue == LuaUtils.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
			{
				returnVal = myValue;
				break;
			}

			if(myValue != null && !excludeValues.contains(myValue))
				returnVal = myValue;

			if(script.closed) arr.push(script);
		}

		if(arr.length > 0)
			for (script in arr)
				luaArray.remove(script);
		#end
		return returnVal;
	}

	public function callOnHScript(funcToCall:String, args:Array<Dynamic> = null, ?ignoreStops:Bool = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;

		#if HSCRIPT_ALLOWED
		if(exclusions == null) exclusions = new Array();
		if(excludeValues == null) excludeValues = new Array();
		excludeValues.push(LuaUtils.Function_Continue);

		var len:Int = hscriptArray.length;
		if (len < 1)
			return returnVal;

		for(script in hscriptArray)
		{
			@:privateAccess
			if(script == null || !script.exists(funcToCall) || exclusions.contains(script.origin))
				continue;

			var callValue = script.call(funcToCall, args);
			if(callValue != null)
			{
				var myValue:Dynamic = callValue.returnValue;

				if((myValue == LuaUtils.Function_StopHScript || myValue == LuaUtils.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
				{
					returnVal = myValue;
					break;
				}

				if(myValue != null && !excludeValues.contains(myValue))
					returnVal = myValue;
			}
		}
		#end

		return returnVal;
	}

	public function setOnScripts(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		if(exclusions == null) exclusions = [];
		setOnLuas(variable, arg, exclusions);
		setOnHScript(variable, arg, exclusions);
	}

	public function setOnLuas(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		#if LUA_ALLOWED
		if(exclusions == null) exclusions = [];
		for (script in luaArray) {
			if(exclusions.contains(script.scriptName))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	public function setOnHScript(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		#if HSCRIPT_ALLOWED
		if(exclusions == null) exclusions = [];
		for (script in hscriptArray) {
			if(exclusions.contains(script.origin))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	function strumPlayAnim(isDad:Bool, id:Int, time:Float) {
		var spr:StrumNote = null;
		if(isDad) {
			spr = opponentStrums.members[id];
		} else {
			spr = playerStrums.members[id];
		}

		if(spr != null && ClientPrefs.data.cpuStrums) {
			spr.playAnim('confirm', true);
			spr.resetAnim = time;
		}
	}

	public var ratingName:String = '?';
	public var ratingNameKE:String = 'AAAAA';
	public var ratingPercent:Float;
	public var ratingFC:String;
	public function RecalculateRating(badHit:Bool = false, scoreBop:Bool = true) {
		setOnScripts('score', songScore);
		setOnScripts('misses', songMisses);
		setOnScripts('hits', songHits);
		setOnScripts('combo', combo);

		var ret:Dynamic = callOnScripts('onRecalculateRating', null, true);
		if(ret != LuaUtils.Function_Stop)
		{
			ratingName = '?';
			if(totalPlayed != 0) //Prevent divide by 0
			{
				// Rating Percent
				ratingPercent = Math.min(1, Math.max(0, totalNotesHit / totalPlayed));
				//trace((totalNotesHit / totalPlayed) + ', Total: ' + totalPlayed + ', notes hit: ' + totalNotesHit);

				// Rating Name
				ratingName = ratingStuff[ratingStuff.length-1][0]; //Uses last string
				if(ratingPercent < 1)
					for (i in 0...ratingStuff.length-1)
						if(ratingPercent < ratingStuff[i][1])
						{
							ratingName = ratingStuff[i][0];
							break;
						}
				ratingNameKE = ratingStuffKE[ratingStuffKE.length-1][0]; //Uses last string
					if(ratingPercent < 1)
						for (i in 0...ratingStuffKE.length-1)
						if(ratingPercent < ratingStuffKE[i][1])
						{
							ratingNameKE = ratingStuffKE[i][0];
							break;
						}
			}
			fullComboFunction();
		}
		setOnScripts('rating', ratingPercent);
		setOnScripts('ratingName', ratingName);
		setOnScripts('ratingFC', ratingFC);
		setOnScripts('totalPlayed', totalPlayed);
		setOnScripts('totalNotesHit', totalNotesHit);
		updateScore(badHit, scoreBop); // score will only update after rating is calculated, if it's a badHit, it shouldn't bounce
	}

	#if ACHIEVEMENTS_ALLOWED
	private function checkForAchievement(achievesToCheck:Array<String> = null)
	{
		if(chartingMode) return;

		var usedPractice:Bool = (ClientPrefs.getGameplaySetting('practice') || ClientPrefs.getGameplaySetting('botplay'));
		if(cpuControlled) return;

		for (name in achievesToCheck) {
			if(!Achievements.exists(name)) continue;

			var unlock:Bool = false;
			if (name != WeekData.getWeekFileName() + '_nomiss') // common achievements
			{
				switch(name)
				{
					case 'ur_bad':
						unlock = (ratingPercent < 0.2 && !practiceMode);

					case 'ur_good':
						unlock = (ratingPercent >= 1 && !usedPractice);

					case 'oversinging':
						unlock = (boyfriend.holdTimer >= 10 && !usedPractice);

					case 'hype':
						unlock = (!boyfriendIdled && !usedPractice);

					case 'two_keys':
						unlock = (!usedPractice && keysPressed.length <= 2);

					case 'toastie':
						unlock = (!ClientPrefs.data.cacheOnGPU && !ClientPrefs.data.shaders && ClientPrefs.data.lowQuality && !ClientPrefs.data.antialiasing);

					#if BASE_GAME_FILES
					case 'debugger':
						unlock = (songName == 'test' && !usedPractice);
					#end
				}
			}
			else // any FC achievements, name should be "weekFileName_nomiss", e.g: "week3_nomiss";
			{
				if(isStoryMode && campaignMisses + songMisses < 1 && Difficulty.getString().toUpperCase() == 'HARD'
					&& storyPlaylist.length <= 1 && !changedDifficulty && !usedPractice)
					unlock = true;
			}

			if(unlock) Achievements.unlock(name);
		}
	}
	#end

	#if (!flash && sys)
	public var runtimeShaders:Map<String, Array<String>> = new Map<String, Array<String>>();
	#end
	public function createRuntimeShader(shaderName:String):ErrorHandledRuntimeShader
	{
		#if (!flash && sys)
		if(!ClientPrefs.data.shaders) return new ErrorHandledRuntimeShader(shaderName);

		if(!runtimeShaders.exists(shaderName) && !initLuaShader(shaderName))
		{
			FlxG.log.warn('Shader $shaderName is missing!');
			return new ErrorHandledRuntimeShader(shaderName);
		}

		var arr:Array<String> = runtimeShaders.get(shaderName);
		return new ErrorHandledRuntimeShader(shaderName, arr[0], arr[1]);
		#else
		FlxG.log.warn("Platform unsupported for Runtime Shaders!");
		return null;
		#end
	}

	public function initLuaShader(name:String, ?glslVersion:Int = 120)
	{
		if(!ClientPrefs.data.shaders) return false;

		#if (!flash && sys)
		if(runtimeShaders.exists(name))
		{
			FlxG.log.warn('Shader $name was already initialized!');
			return true;
		}

		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'shaders/'))
		{
			var frag:String = folder + name + '.frag';
			var vert:String = folder + name + '.vert';
			var found:Bool = false;
			if(FileSystem.exists(frag))
			{
				frag = File.getContent(frag);
				found = true;
			}
			else frag = null;

			if(FileSystem.exists(vert))
			{
				vert = File.getContent(vert);
				found = true;
			}
			else vert = null;

			if(found)
			{
				runtimeShaders.set(name, [frag, vert]);
				//trace('Found shader $name!');
				return true;
			}
		}
			#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
			addTextToDebug('Missing shader $name .frag AND .vert files!', FlxColor.RED);
			#else
			FlxG.log.warn('Missing shader $name .frag AND .vert files!');
			#end
		#else
		FlxG.log.warn('This platform doesn\'t support Runtime Shaders!');
		#end
		return false;
	}

	public function makeLuaTouchPad(DPadMode:String, ActionMode:String) {
		if(members.contains(luaTouchPad)) return;

		if(!variables.exists("luaTouchPad"))
			variables.set("luaTouchPad", luaTouchPad);

		luaTouchPad = new TouchPad(DPadMode, ActionMode, NONE);
		luaTouchPad.alpha = ClientPrefs.data.controlsAlpha;
	}
	
	public function addLuaTouchPad() {
		if(luaTouchPad == null || members.contains(luaTouchPad)) return;

		var target = LuaUtils.getTargetInstance();
		target.insert(target.members.length + 1, luaTouchPad);
	}

	public function addLuaTouchPadCamera() {
		if(luaTouchPad != null)
			luaTouchPad.cameras = [luaTpadCam];
	}

	public function removeLuaTouchPad() {
		if (luaTouchPad != null) {
			luaTouchPad.kill();
			luaTouchPad.destroy();
			remove(luaTouchPad);
			luaTouchPad = null;
		}
	}

	public function luaTouchPadPressed(button:Dynamic):Bool {
		if(luaTouchPad != null) {
			if(Std.isOfType(button, String))
				return luaTouchPad.buttonPressed(MobileInputID.fromString(button));
			else if(Std.isOfType(button, Array)){
				var FUCK:Array<String> = button; // haxe said "You Can't Iterate On A Dyanmic Value Please Specificy Iterator or Iterable *insert nerd emoji*" so that's the only i foud to fix
				var idArray:Array<MobileInputID> = [];
				for(strId in FUCK)
					idArray.push(MobileInputID.fromString(strId));
				return luaTouchPad.anyPressed(idArray);
			} else
				return false;
		}
		return false;
	}

	public function luaTouchPadJustPressed(button:Dynamic):Bool {
		if(luaTouchPad != null) {
			if(Std.isOfType(button, String))
				return luaTouchPad.buttonJustPressed(MobileInputID.fromString(button));
			else if(Std.isOfType(button, Array)){
				var FUCK:Array<String> = button;
				var idArray:Array<MobileInputID> = [];
				for(strId in FUCK)
					idArray.push(MobileInputID.fromString(strId));
				return luaTouchPad.anyJustPressed(idArray);
			} else
				return false;
		}
		return false;
	}
	
	public function luaTouchPadJustReleased(button:Dynamic):Bool {
		if(luaTouchPad != null) {
			if(Std.isOfType(button, String))
				return luaTouchPad.buttonJustReleased(MobileInputID.fromString(button));
			else if(Std.isOfType(button, Array)){
				var FUCK:Array<String> = button;
				var idArray:Array<MobileInputID> = [];
				for(strId in FUCK)
					idArray.push(MobileInputID.fromString(strId));
				return luaTouchPad.anyJustReleased(idArray);
			} else
				return false;
		}
		return false;
	}

	public function luaTouchPadReleased(button:Dynamic):Bool {
		if(luaTouchPad != null) {
			if(Std.isOfType(button, String))
				return luaTouchPad.buttonJustReleased(MobileInputID.fromString(button));
			else if(Std.isOfType(button, Array)){
				var FUCK:Array<String> = button;
				var idArray:Array<MobileInputID> = [];
				for(strId in FUCK)
					idArray.push(MobileInputID.fromString(strId));
				return luaTouchPad.anyReleased(idArray);
			} else
				return false;
		}
		return false;
	}

	function checkForResync()
	{
		if (endingSong || paused || shutdownThread)
			return;

		if (requiresSyncing)
		{
			requiresSyncing = false;
			setSongTime(lastCorrectSongPos);
		}

		gameFroze = false;
	}

	public function runSongSyncThread()
	{
		Thread.create(function()
		{
			while (!endingSong && !paused && !shutdownThread)
			{
				if (requiresSyncing)
					continue;

				if (gameFroze)
				{
					lastCorrectSongPos = Conductor.songPosition;
					requiresSyncing = true;
					continue;
				}
				gameFroze = true;

				Sys.sleep(0.25);
			}
		});

		if (!FlxG.signals.preUpdate.has(checkForResync))
			FlxG.signals.preUpdate.add(checkForResync);
	}
}
