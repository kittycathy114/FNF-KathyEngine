package debug;

import flixel.FlxG;
import openfl.Lib;
import haxe.Timer;
import openfl.text.TextField;
import openfl.text.TextFormat;
import lime.system.System as LimeSystem;
import states.MainMenuState;
import debug.GameVersion;
import debug.HaxelibInfo;
import openfl.display.Sprite;
import flixel.FlxState;
import openfl.utils.Assets;
import backend.ClientPrefs;
import backend.Paths;
#if cpp
#if windows
@:cppFileCode('#include <windows.h>')
#elseif (ios || mac)
@:cppFileCode('#include <mach-o/arch.h>')
#else
@:headerInclude('sys/utsname.h')
#end
#end
class FPSCounter extends Sprite
{
	public var currentFPS(default, null):Int = 0;

	public var memoryMegas(get, never):Float;
	public var memoryPeakMegas(default, null):Float = 0;

	@:noCompletion private var times:Array<Float>;
	@:noCompletion private var lastFramerateUpdateTime:Float;
	@:noCompletion private var updateTime:Int;
	@:noCompletion private var framesCount:Int;
	@:noCompletion private var prevTime:Int;
	@:noCompletion private var currentTime:Float;
	@:noCompletion private var cacheCount:Int;

	public var objectCount(default, null):Int = 0;

	@:noCompletion private var lastObjectCountUpdate:Float = 0;
	@:noCompletion private var lastDelayUpdateTime:Float = 0;
	@:noCompletion private var currentDelay:Float = 0;

	public var os:String = '';

	// 文本字段
	private var allInfoText:TextField;

	// 布局参数
	private var lineHeight:Float = 18;

	// 性能优化变量
	private var lastFpsUpdateTime:Float = 0;

	public var fontName:String = Paths.font("vcr.ttf");

	public function new(x:Float = 10, y:Float = 10, color:Int = 0x000000)
	{
		super();

		// 创建单个文本字段，显示所有信息
		allInfoText = createTextField(18, 0xFFFFFF);
		addChild(allInfoText);

		#if !officialBuild
		if (LimeSystem.platformName == LimeSystem.platformVersion || LimeSystem.platformVersion == null)
			os = 'OS: ${LimeSystem.platformName}' #if cpp + ' ${getArch() != 'Unknown' ? getArch() : ''}' #end;
		else
			os = 'OS: ${LimeSystem.platformName}' #if cpp + ' ${getArch() != 'Unknown' ? getArch() : ''}' #end + ' - ${LimeSystem.platformVersion}';
		#end

		positionFPS(x, y);

		// 初始化 FPS 计算变量
		times = [];
		lastFramerateUpdateTime = Timer.stamp();
		prevTime = Lib.getTimer();
		updateTime = prevTime + 500;
		framesCount = 0;
		currentTime = 0;
		cacheCount = 0;

		// 初始化更新时间
		lastFpsUpdateTime = Timer.stamp();
	}

	private function createTextField(size:Int, color:Int, bold:Bool = false):TextField
	{
		var tf = new TextField();
		tf.selectable = false;
		tf.mouseEnabled = false;
		tf.defaultTextFormat = new TextFormat(fontName, size, color, bold);
		tf.autoSize = LEFT;
		return tf;
	}

	public dynamic function updateText():Void
	{
		var currentTime = Timer.stamp();
		var memory = memoryMegas;

		// 更新内存峰值
		if (memory > memoryPeakMegas)
		{
			memoryPeakMegas = memory;
		}

		// 构建所有信息的文本
		var allText = '';

		// FPS信息 - 所有文本统一为白色
		allText += 'FPS: $currentFPS\n';
		allText += 'Delay: ${currentDelay}ms\n';
		allText += 'RAM: ${flixel.util.FlxStringUtil.formatBytes(memory)}\n';
		allText += 'MEM Peak: ${flixel.util.FlxStringUtil.formatBytes(memoryPeakMegas)}\n';
		allText += 'Objects: $objectCount\n';
		// 版本信息
		if (ClientPrefs.data.exgameversion)
		{
			allText += '\n';
			allText += 'Psych ${MainMenuState.psychEngineVersion}\n';
			allText += 'Kathy ${MainMenuState.kathyEngineVersion}\n';
			allText += 'Commit: ${GameVersion.getGitCommitCount()} (${GameVersion.getGitCommitHash()})\n';
			allText += 'Build: ${GameVersion.getBuildTime()}\n';
			if (ClientPrefs.data.showHaxelibs) {
				allText += '\n';
				allText += 'Libs:\n${HaxelibInfo.getHaxelibInfo()}\n';
			}

			if (ClientPrefs.data.showRunningOS)
			{
				allText += '\n' + os;
			}

			// 系统信息（默认一直显示）
			allText += '\n';

			// 平台信息
			#if cpp
			var arch = getArch() != 'Unknown' ? ' (${getArch()})' : '';
			#else
			var arch = '';
			#end
			allText += 'Platform: ${LimeSystem.platformName}$arch\n';

			// 平台版本
			if (LimeSystem.platformVersion != null && LimeSystem.platformVersion != LimeSystem.platformName)
				allText += 'OS Ver.: ${LimeSystem.platformVersion}\n';

			// 显示器信息
			try
			{
				var display = LimeSystem.getDisplay(0);
				if (display != null)
				{
					allText += 'Resolution: ${display.currentMode.width}x${display.currentMode.height}\n';
					allText += 'Refresh: ${display.currentMode.refreshRate}Hz\n';
				}
			}
			catch (e:Dynamic)
			{
				// 忽略显示器信息错误
			}
		}
		else
		{
			// 如果版本信息不显示，只显示操作系统信息
			if (ClientPrefs.data.showRunningOS)
			{
				allText += '\n' + os;
			}
		}

		allInfoText.htmlText = '<font color="#E6CAFF">$allText</font>';
	}

	private override function __enterFrame(deltaTime:Float):Void
	{
		if (!visible)
			return;

		// 限制 Delay 更新频率为每 0.2 秒
		if (Timer.stamp() - lastDelayUpdateTime > 0.2)
		{
			// 更新延迟时间（以毫秒为单位）
			currentDelay = Math.round(deltaTime * 1000) / 1000;
			lastDelayUpdateTime = Timer.stamp();
		}

		// 持续追踪时间（用于 FPS 计算）
		currentTime += deltaTime;
		times.push(currentTime);

		while (times[0] < currentTime - 1000)
		{
			times.shift();
		}

		var currentCount = times.length;
		// 只在显示更新时更新 FPS 值，避免数值跳动
		if (Timer.stamp() - lastFpsUpdateTime > 0.5)
		{
			currentFPS = Math.round((currentCount + cacheCount) / 2);
			cacheCount = currentCount;
			lastFpsUpdateTime = Timer.stamp();
			updateText();
		}

		if (Timer.stamp() - lastObjectCountUpdate > 2.0)
		{
			objectCount = countObjects(FlxG.state);
			lastObjectCountUpdate = Timer.stamp();
		}

		if (ClientPrefs.data.fpsRework)
		{
			if (FlxG.stage.window.frameRate != ClientPrefs.data.framerate && FlxG.stage.window.frameRate != FlxG.game.focusLostFramerate)
				FlxG.stage.window.frameRate = ClientPrefs.data.framerate;

			var nowTime = openfl.Lib.getTimer();
			framesCount++;

			if (nowTime >= updateTime)
			{
				var elapsed = nowTime - prevTime;
				framesCount = 0;
				prevTime = nowTime;
				updateTime = nowTime + 500;
			}

			if ((FlxG.updateFramerate >= currentFPS + 5 || FlxG.updateFramerate <= currentFPS - 5)
				&& haxe.Timer.stamp() - lastFramerateUpdateTime >= 1.5
				&& currentFPS >= 30)
			{
				FlxG.updateFramerate = FlxG.drawFramerate = currentFPS;
				lastFramerateUpdateTime = haxe.Timer.stamp();
			}
		}
	}

	private function countObjects(state:FlxState, depth:Int = 0):Int
	{
		if (depth > 10)
			return 0;

		var count:Int = 0;

		if (state == null)
			return 0;

		count += countGroupMembers(state.members, depth + 1);

		if (state.subState != null)
		{
			count += countGroupMembers(state.subState.members, depth + 1);
		}

		return count;
	}

	private function countGroupMembers(members:Array<flixel.FlxBasic>, depth:Int = 0):Int
	{
		if (depth > 10)
			return 0;

		var count:Int = 0;

		if (members == null)
			return 0;

		for (member in members)
		{
			if (member != null && member.exists)
			{
				count++;

				if (Std.isOfType(member, flixel.group.FlxGroup.FlxTypedGroup))
				{
					var group:flixel.group.FlxGroup.FlxTypedGroup<flixel.FlxBasic> = cast member;
					count += countGroupMembers(group.members, depth + 1);
				}
			}
		}

		return count;
	}

	inline function get_memoryMegas():Float
		return cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE);

	public inline function positionFPS(X:Float, Y:Float, ?scale:Float = 1)
	{
		scaleX = scaleY = #if android (scale > 1 ? scale : 1) #else (scale < 1 ? scale : 1) #end;

		var spacing = ClientPrefs.data.fpsSpacing;
		var isRight = ClientPrefs.data.fpsPosition.indexOf("RIGHT") != -1;
		var isBottom = ClientPrefs.data.fpsPosition.indexOf("BOTTOM") != -1;

		// 使用 OpenFL stage 坐标系而非 FlxG.game
		var stage = Lib.current.stage;
		if (stage != null)
		{
			if (isRight)
			{
				x = stage.stageWidth - 200 - spacing;
			}
			else
			{
				x = spacing;
			}

			if (isBottom)
			{
				var textHeight = allInfoText.height;
				y = stage.stageHeight - textHeight - spacing;
			}
			else
			{
				y = spacing;
			}
		}
	}

	#if cpp
	#if windows
	@:functionCode('
        SYSTEM_INFO osInfo;
        GetSystemInfo(&osInfo);
        switch(osInfo.wProcessorArchitecture)
        {
            case 9: return ::String("x86_64");
            case 5: return ::String("ARM");
            case 12: return ::String("ARM64");
            case 6: return ::String("IA-64");
            case 0: return ::String("x86");
            default: return ::String("Unknown");
        }
    ')
	#elseif (ios || mac)
	@:functionCode('
        const NXArchInfo *archInfo = NXGetLocalArchInfo();
        return ::String(archInfo == NULL ? "Unknown" : archInfo->name);
    ')
	#else
	@:functionCode('
        struct utsname osInfo{}; 
        uname(&osInfo);
        return ::String(osInfo.machine);
    ')
	#end
	@:noCompletion
	private function getArch():String
	{
		return "Unknown";
	}
	#end
}