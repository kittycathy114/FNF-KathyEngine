package;

import debug.FPSCounter;
import backend.Highscore;
import flixel.FlxGame;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.display.StageScaleMode;
#if FLX_SOUND_TRAY
import flixel.system.ui.FlxSoundTray;
#end
import lime.app.Application;
import states.TitleState;
#if HSCRIPT_ALLOWED
import crowplexus.iris.Iris;
import psychlua.HScript.HScriptInfos;
#end
import mobile.backend.MobileScaleMode;
import openfl.events.KeyboardEvent;
import lime.system.System as LimeSystem;
#if (linux || mac)
import lime.graphics.Image;
#end
#if COPYSTATE_ALLOWED
import states.CopyState;
#end
import backend.Highscore;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import backend.ClientPrefs;

// NATIVE API STUFF, YOU CAN IGNORE THIS AND SCROLL //
#if (linux && !debug)
@:cppInclude('./external/gamemode_client.h')
@:cppFileCode('#define GAMEMODE_AUTO')
#end
// // // // // // // // //
class Main extends Sprite
{
	public static final game = {
		width: 1280, // WINDOW width
		height: 720, // WINDOW height
		initialState: TitleState, // initial game state
		framerate: 90, // default framerate
		skipSplash: true, // if the default flixel splash screen should be skipped
		startFullscreen: false // if the game should start at fullscreen mode
	};

	public static var fpsVar:FPSCounter;

	#if FLX_SOUND_TRAY
	public static var openflSoundTray:FlxSoundTray;
	#end

	public static final platform:String = #if mobile "Phones" #else "PCs" #end;

	// Background volume control variables
	private var backgroundVolumeTween:FlxTween;
	private var originalVolume:Float = 1.0;
	private var isInBackground:Bool = false;

	// You can pretty much ignore everything from here on - your code should go in your states.

	public static function main():Void
	{
		Lib.current.addChild(new Main());
		#if cpp
		cpp.NativeGc.enable(true);
		#elseif hl
		hl.Gc.enable(true);
		#end
	}

	public function new()
	{
		super();
		#if mobile
		#if android
		StorageUtil.requestPermissions();
		#end
		Sys.setCwd(StorageUtil.getStorageDirectory());
		#end
		backend.CrashHandler.init();

		#if (cpp && windows)
		backend.Native.fixScaling();
		#end

		#if VIDEOS_ALLOWED
		hxvlc.util.Handle.init(#if (hxvlc >= "1.8.0") ['--no-lua'] #end);
		#end

		#if LUA_ALLOWED
		Mods.pushGlobalMods();
		#end
		Mods.loadTopMod();

		FlxG.save.bind('funkin', CoolUtil.getSavePath());
		Highscore.load();

		#if HSCRIPT_ALLOWED
		Iris.warn = function(x, ?pos:haxe.PosInfos)
		{
			Iris.logLevel(WARN, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null)
				newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '') + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true)
			{
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true)
			{
				msgInfo += '${newPos.lineNumber}:';
			}
			msgInfo += ' $x';
			if (PlayState.instance != null)
				PlayState.instance.addTextToDebug('WARNING: $msgInfo', FlxColor.YELLOW);
		}
		Iris.error = function(x, ?pos:haxe.PosInfos)
		{
			Iris.logLevel(ERROR, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null)
				newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '') + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true)
			{
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true)
			{
				msgInfo += '${newPos.lineNumber}:';
			}
			msgInfo += ' $x';
			if (PlayState.instance != null)
				PlayState.instance.addTextToDebug('ERROR: $msgInfo', FlxColor.RED);
		}
		Iris.fatal = function(x, ?pos:haxe.PosInfos)
		{
			Iris.logLevel(FATAL, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null)
				newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '') + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true)
			{
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true)
			{
				msgInfo += '${newPos.lineNumber}:';
			}
			msgInfo += ' $x';
			if (PlayState.instance != null)
				PlayState.instance.addTextToDebug('FATAL: $msgInfo', 0xFFBB0000);
		}
		#end

		#if LUA_ALLOWED Lua.set_callbacks_function(cpp.Callable.fromStaticFunction(psychlua.CallbackHandler.call)); #end
		Controls.instance = new Controls();
		ClientPrefs.loadDefaultKeys();
		#if ACHIEVEMENTS_ALLOWED Achievements.load(); #end
		#if mobile
		FlxG.signals.postGameStart.addOnce(() ->
		{
			FlxG.scaleMode = new MobileScaleMode();
		});
		#end
		// addChild(new FlxGame(game.width, game.height, #if COPYSTATE_ALLOWED !CopyState.checkExistingFiles() ? CopyState : #end game.initialState, game.framerate, game.framerate, game.skipSplash, game.startFullscreen));

		var game:FlxGame = new FlxGame(game.width, game.height, game.initialState, #if (flixel < "5.0.0") game.zoom, #end game.framerate, game.framerate,
			game.skipSplash, game.startFullscreen);
		//#if BASE_GAME_FILES
		//@:privateAccess
		//game._customSoundTray = backend.FunkinSoundTray;
		//#end
		addChild(game);

	fpsVar = new FPSCounter(10, 3, 0xFFFFFF);
	Lib.current.stage.addChild(fpsVar);
	Lib.current.stage.align = "tl";
	Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;
		if (fpsVar != null)
		{
			fpsVar.visible = ClientPrefs.data.showFPS;
		}

		Language.load();

		#if (linux || mac) // fix the app icon not showing up on the Linux Panel / Mac Dock
		var icon = Image.fromFile("icon.png");
		Lib.current.stage.window.setIcon(icon);
		#end

		#if html5
		FlxG.autoPause = false;
		FlxG.mouse.visible = false;
		#end

		FlxG.fixedTimestep = false;
		FlxG.game.focusLostFramerate = #if mobile 30 #else 60 #end;
		#if web
		FlxG.keys.preventDefaultKeys.push(TAB);
		#else
		FlxG.keys.preventDefaultKeys = [TAB];
		#end

		#if DISCORD_ALLOWED
		DiscordClient.prepare();
		#end

		#if desktop FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, toggleFullScreen); #end

		#if mobile
		#if android FlxG.android.preventDefaultKeys = [BACK]; #end
		LimeSystem.allowScreenTimeout = ClientPrefs.data.screensaver;
		#end

		// Application.current.window.vsync = ClientPrefs.data.vsync;

		// shader coords fix
		FlxG.signals.gameResized.add(function(w, h)
		{
			if (fpsVar != null)
				fpsVar.positionFPS(10, 3, Math.min(w / FlxG.width, h / FlxG.height));
			if (FlxG.cameras != null)
			{
				for (cam in FlxG.cameras.list)
				{
					if (cam != null && cam.filters != null)
						resetSpriteCache(cam.flashSprite);
				}
			}

			if (FlxG.game != null)
				resetSpriteCache(FlxG.game);
		});

		// 监听 stage 窗口大小变化，更新 FPS 计数器位置
		Lib.current.stage.addEventListener(Event.RESIZE, function(e:Event):Void
		{
			if (fpsVar != null)
			{
				fpsVar.positionFPS(10, 3, 1);
			}
		});

		#if (desktop && !mobile)
		setCustomCursor();
		#end

		// 添加应用激活/停用事件监听
		Lib.current.stage.addEventListener(Event.DEACTIVATE, onAppDeactivate);
		Lib.current.stage.addEventListener(Event.ACTIVATE, onAppActivate);
	}
	
	// 应用进入后台时调用
	private function onAppDeactivate(e:Event):Void
	{
		if (isInBackground || !ClientPrefs.data.backgroundVolume) return;
		isInBackground = true;
		
		// 取消正在进行的恢复动画（如果存在）
		if (backgroundVolumeTween != null) {
			backgroundVolumeTween.cancel();
			backgroundVolumeTween = null;
		}
		
		// 保存当前音量
		originalVolume = FlxG.sound.volume;
		
		// 创建降低音量的动画
		backgroundVolumeTween = FlxTween.tween(FlxG.sound, {volume: ClientPrefs.data.backgroundVolumeLevel}, 1, {
			ease: FlxEase.quadOut,
			onComplete: function(twn:FlxTween) {
				backgroundVolumeTween = null;
			}
		});
	}
	
	// 应用回到前台时调用
	private function onAppActivate(e:Event):Void
	{
		if (!isInBackground || !ClientPrefs.data.backgroundVolume) return;
		isInBackground = false;
		
		// 取消正在进行的降低动画（如果存在）
		if (backgroundVolumeTween != null) {
			backgroundVolumeTween.cancel();
			backgroundVolumeTween = null;
		}
		
		// 创建恢复音量的动画
		backgroundVolumeTween = FlxTween.tween(FlxG.sound, {volume: originalVolume}, 0.5, {
			ease: FlxEase.quadOut,
			onComplete: function(twn:FlxTween) {
				backgroundVolumeTween = null;
			}
		});
	}

	static function resetSpriteCache(sprite:Sprite):Void
	{
		@:privateAccess {
			sprite.__cacheBitmap = null;
			sprite.__cacheBitmapData = null;
		}
	}

	function toggleFullScreen(event:KeyboardEvent)
	{
		if (Controls.instance.justReleased('fullscreen'))
			FlxG.fullscreen = !FlxG.fullscreen;
	}

	function setCustomCursor():Void
	{
		FlxG.mouse.load('assets/shared/images/cursor.png');
	}
}