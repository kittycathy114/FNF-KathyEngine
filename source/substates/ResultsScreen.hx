package substates;

import haxe.Exception;
/*#if FEATURE_STEPMANIA
import smTools.SMFile;
#end*/
#if FEATURE_FILESYSTEM
import sys.FileSystem;
import sys.io.File;
#end

import states.StoryMenuState;
import states.FreeplayState;
import states.PlayState;
import backend.Rating;
import backend.ClientPrefs;

import openfl.geom.Matrix;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.text.TextFieldAutoSize;
import flixel.system.FlxSound;
import flixel.util.FlxAxes;
import flixel.FlxSubState;
import flixel.input.FlxInput;
import flixel.input.keyboard.FlxKey;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import lime.app.Application;
import flixel.math.FlxMath;

import backend.HitGraph;

using StringTools;

class ResultsScreen extends FlxSubState
{
	// OpenFL 层容器
	public var overlaySprite:Sprite;

	public var background:FlxSprite;
	public var text:TextField;

	public var graph:HitGraph;

	public var comboText:TextField;
	public var contText:TextField;
	public var settingsText:TextField;
	public var replayText:TextField;

	public var music:FlxSound;

	public var graphData:BitmapData;

	public var ranking:String;
	public var accuracy:String;

	public var canReplay:Bool = false;	// 是否可以回放
	public var replayPressed:Bool = false;	// 是否按下了回放键

	override function create()
	{
		// 创建 OpenFL 层容器
		overlaySprite = new Sprite();

		// 创建背景（Flixel 对象）
		background = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		background.alpha = 0;
		background.scrollFactor.set();
		add(background);

		// 将 overlay 添加到 OpenFL stage 的最顶层
		if (FlxG.stage != null)
		{
			FlxG.stage.addChild(overlaySprite);
		}

		// 获取实际的物理屏幕尺寸
		var stageWidth:Float = FlxG.stage.stageWidth;
		var stageHeight:Float = FlxG.stage.stageHeight;

		// 计算缩放比例（基于逻辑分辨率到物理分辨率的比例）
		var scaleX:Float = stageWidth / 1280;
		var scaleY:Float = stageHeight / 720;
		var scale:Float = Math.min(scaleX, scaleY); // 保持宽高比

		// 创建 HitGraph（偏右上角，宽度放大一倍，高度适中）
		graph = new HitGraph(
			Math.floor(stageWidth - 560 * scale),
			Math.floor(20 * scale),
			Math.floor(500 * scale),
			Math.floor(250 * scale)
		);
		graph.alpha = 0;
		overlaySprite.addChild(graph);

		//if (!PlayState.inResults)
		{
			music = new FlxSound().loadEmbedded(Paths.music('breakfast'), true, true);
			music.volume = 0;
			music.play(false, FlxG.random.int(0, Std.int(music.length / 2)));
			FlxG.sound.list.add(music);
		}

	// 统计判定数量
	var perfects = 0;
	var sicks = 0;
	var goods = 0;
	var bads = 0;
	var shits = 0;
	for (r in PlayState.instance.ratingsData) {
    		switch (r.name) {
        		case "perfect": perfects = r.hits;
        		case "sick": sicks = r.hits;
        		case "good": goods = r.hits;
        		case "bad": bads = r.hits;
        		case "shit": shits = r.hits;
    		}
	}

	// 创建标题文本（偏左上角）
	text = createTextField(
		Math.floor(20 * scale),
		Math.floor(-80 * scale),
		Math.floor(stageWidth - 300 * scale),
		FlxColor.WHITE,
		Math.floor(42 * scale)
	);
	text.text = "Song Cleared!";
	overlaySprite.addChild(text);

	var score = PlayState.instance.songScore;
	if (PlayState.isStoryMode)
	{
		score = PlayState.campaignScore;
		text.text = "Week Cleared!";
	}

	// 组合文本
	var comboStr = 'Judgements:\n'
    + (!ClientPrefs.data.rmPerfect ? 'Perfects - ${perfects}\n' : "")
    + 'Sicks - ${sicks}\n'
    + 'Goods - ${goods}\n'
    + 'Bads - ${bads}\n'
    + 'Shits - ${shits}\n\n'
    + 'Combo Breaks: ${PlayState.instance.songMisses}\n'
    + 'Score: ${PlayState.instance.songScore}\n'
    + 'Accuracy: ${Std.string(Math.floor(PlayState.instance.ratingPercent * 10000) / 100)}%\n\n\n'
    + 'Note Rate: ${PlayState.instance.songSpeed} x';

	// 创建判定文本（偏左并垂直居中）
	var comboTextY = (stageHeight - Math.floor(150 * scale)) / 2;
	comboText = createTextField(
		Math.floor(20 * scale),
		Math.floor(-100 * scale),
		Math.floor(stageWidth - 300 * scale),
		FlxColor.WHITE,
		Math.floor(32 * scale)
	);
	comboText.text = comboStr;
	overlaySprite.addChild(comboText);

	// 为每个判定添加不同颜色
	var idx = 0;
	if (!ClientPrefs.data.rmPerfect) {
		idx = comboStr.indexOf('Perfects');
		comboText.setTextFormat(new TextFormat("assets/fonts/vcr.ttf", Math.floor(32 * scale), 0xFFFFC0CB), idx, idx + ('Perfects - ${perfects}'.length));
	}
	idx = comboStr.indexOf('Sicks');
	comboText.setTextFormat(new TextFormat("assets/fonts/vcr.ttf", Math.floor(32 * scale), 0xFF87CEFA), idx, idx + ('Sicks - ${sicks}'.length));
	idx = comboStr.indexOf('Goods');
	comboText.setTextFormat(new TextFormat("assets/fonts/vcr.ttf", Math.floor(32 * scale), 0xFF66CDAA), idx, idx + ('Goods - ${goods}'.length));
	idx = comboStr.indexOf('Bads');
	comboText.setTextFormat(new TextFormat("assets/fonts/vcr.ttf", Math.floor(32 * scale), 0xFFF4A460), idx, idx + ('Bads - ${bads}'.length));
	idx = comboStr.indexOf('Shits');
	comboText.setTextFormat(new TextFormat("assets/fonts/vcr.ttf", Math.floor(32 * scale), 0xFFFF4500), idx, idx + ('Shits - ${shits}'.length));

	// contText（偏右下角）
	contText = createTextField(
		Math.floor(stageWidth - 520 * scale),
		Math.floor(stageHeight + 80 * scale),
		Math.floor(500 * scale),
		FlxColor.WHITE,
		Math.floor(32 * scale)
	);
	contText.text = #if mobile 'Touch Screen to continue.' #else 'Press \'ENTER\' to continue or \'F8\' to recap.'#end;
	overlaySprite.addChild(contText);

	// 检查是否有回放数据
	canReplay = PlayState.instance.replayData != null && PlayState.instance.replayData.length > 0;

	// 填充 HitGraph 数据（graph 已经添加到 overlaySprite 了）
		if (PlayState.instance.hitHistory != null && PlayState.instance.hitHistory.length > 0)
		{
			for (hitData in PlayState.instance.hitHistory)
			{
				graph.addToHistory(hitData[0], hitData[1], hitData[2]);
			}
			graph.update();
		}

		/*var sicks = PlayState.sicks;
		var goods = PlayState.goods;
	*/
		if (sicks == Math.POSITIVE_INFINITY)
			sicks = 0;
		if (goods == Math.POSITIVE_INFINITY)
			goods = 0;

		// 创建设置文本（偏左下角）
		var averageMs:Float = 0;
		//if (PlayState.instance.songHits > 0)
    	@:privateAccess
		averageMs = PlayState.instance.allNotesMs / PlayState.instance.songHits;

		settingsText = createTextField(
			Math.floor(20 * scale),
			Math.floor(stageHeight + 60 * scale),
			Math.floor(stageWidth - 300 * scale),
			FlxColor.WHITE,
			Math.floor(18 * scale)
		);
		settingsText.text = 'Avg: ${Math.round(averageMs * 100) / 100}ms (${!ClientPrefs.data.rmPerfect ? "PERFECT:" + ClientPrefs.data.perfectWindow + "ms," : ""}SICK:${ClientPrefs.data.sickWindow}ms,GOOD:${ClientPrefs.data.goodWindow}ms,BAD:${ClientPrefs.data.badWindow}ms)';
		overlaySprite.addChild(settingsText);

	/*var sicks = PlayState.sicks;
		var goods = PlayState.goods;
	*/

	// 动画效果（需要手动实现 OpenFL 对象的动画）
	FlxTween.tween(background, {alpha: 0.5}, 0.5);
	// OpenFL 对象的动画
	FlxTween.num(-80 * scale, 20 * scale, 0.5, {ease: FlxEase.expoInOut}, (val) -> text.y = val);
	FlxTween.num(-100 * scale, comboTextY, 0.5, {ease: FlxEase.expoInOut}, (val) -> comboText.y = val);
	FlxTween.num(stageHeight + 60 * scale, stageHeight - 60 * scale, 0.5, {ease: FlxEase.expoInOut}, (val) -> contText.y = val);
	FlxTween.num(stageHeight + 60 * scale, stageHeight - 50 * scale, 0.5, {ease: FlxEase.expoInOut}, (val) -> settingsText.y = val);
	FlxTween.num(0, 1.0, 0.5, {ease: FlxEase.expoInOut}, (val) -> graph.alpha = val);

	cameras = [FlxG.cameras.list[FlxG.cameras.list.length - 1]];

	super.create();
}

	var frames = 0;

	// 处理继续的逻辑
	private function handleContinue():Void
	{
		trace('WENT BACK TO FREEPLAY??');
		#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
		PlayState.instance.canResync = false;
		PlayState.changedDifficulty = false;
		Mods.loadTopMod();
		FlxG.sound.playMusic(Paths.music('freakyMenu'));
		MusicBeatState.switchState(new FreeplayState());
		close(); // 关闭substate
	}

	// 处理回放逻辑
	private function handleReplay():Void
	{
		trace('STARTING REPLAY...');
		
		if (music != null)
			music.fadeOut(0.3);

		// 设置静态变量，传递回放数据到新的PlayState
		PlayState.pendingReplayData = PlayState.instance.replayData.copy();
		PlayState.shouldStartReplay = true;

		// 关闭substate并重新加载PlayState
		close();

		// 切换到新的PlayState（会自动加载回放数据）
		LoadingState.loadAndSwitchState(new PlayState());
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (music != null)
			if (music.volume < 0.5)
				music.volume += 0.01 * elapsed;

		// keybinds

		/*if (PlayerSettings.player1.controls.ACCEPT)
		{
			if (music != null)
				music.fadeOut(0.3);

			PlayState.loadRep = false;
			PlayState.stageTesting = false;
			PlayState.rep = null;

			#if !switch
			Highscore.saveScore(PlayState.SONG.songId, Math.round(PlayState.instance.songScore), PlayState.storyDifficulty);
			Highscore.saveCombo(PlayState.SONG.songId, Ratings.GenerateLetterRank(PlayState.instance.accuracy), PlayState.storyDifficulty);
			#end

			if (PlayState.isStoryMode)
			{
				FlxG.sound.playMusic(Paths.music('freakyMenu'));
				Conductor.changeBPM(102);
				FlxG.switchState(new MainMenuState());
			}
			else
				FlxG.switchState(new FreeplayState());
			PlayState.instance.clean();
		}*/

		/*if (FlxG.keys.justPressed.F1 && !PlayState.loadRep)
		{
			PlayState.rep = null;

			PlayState.loadRep = false;
			PlayState.stageTesting = false;

			#if !switch
			Highscore.saveScore(PlayState.SONG.songId, Math.round(PlayState.instance.songScore), PlayState.storyDifficulty);
			Highscore.saveCombo(PlayState.SONG.songId, Ratings.GenerateLetterRank(PlayState.instance.accuracy), PlayState.storyDifficulty);
			#end

			if (music != null)
				music.fadeOut(0.3);

			PlayState.isStoryMode = false;
			PlayState.storyDifficulty = PlayState.storyDifficulty;
			LoadingState.loadAndSwitchState(new PlayState());
			PlayState.instance.clean();
		}*/

		// 桌面端：ENTER键继续，R键回放
		if (FlxG.keys.justPressed.ENTER)
		{
			handleContinue();
		}
		else if (FlxG.keys.justPressed.F8 && canReplay && !replayPressed)
		{
			replayPressed = true;
			handleReplay();
		}

		// 移动端：触摸屏幕
		#if !desktop
		// 检测触摸或点击
		if (FlxG.mouse.justPressed || FlxG.touches.justStarted().length > 0)
		{
			handleContinue();
		}
		#end
	}

	override function destroy()
	{
		// 从 OpenFL stage 移除 overlay
		if (overlaySprite != null && FlxG.stage != null && FlxG.stage.contains(overlaySprite))
		{
			FlxG.stage.removeChild(overlaySprite);
			overlaySprite = null;
		}

		super.destroy();
	}

	// 创建 OpenFL TextField 的辅助函数
	private function createTextField(X:Float = 0, Y:Float = 0, Width:Float = 0, Color:FlxColor = FlxColor.WHITE, Size:Int = 12):TextField
	{
		var tf = new TextField();
		tf.x = X;
		tf.y = Y;
		tf.width = Width;
		tf.multiline = true;
		tf.wordWrap = true;
		tf.embedFonts = true;
		tf.selectable = false;
		tf.defaultTextFormat = new TextFormat("assets/fonts/vcr.ttf", Size, Color.to24Bit());
		tf.alpha = Color.alphaFloat;
		tf.autoSize = TextFieldAutoSize.LEFT;
		return tf;
	}
}
