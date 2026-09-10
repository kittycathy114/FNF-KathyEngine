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
import StringTools;
import lime.app.Application;
import debug.PsychFPSCounter;
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
	
	// 背景
	private var bgSprite:Sprite;

	// 原版 FunkinDebugDisplay 风格（"Debug" fpsStyle）独立面板
	public var debugDisplay:FunkinDebugDisplay;

	// 原版 Psych 风格实例（fpsStyle == "Psych" 时显示）
	private var psychInstance:PsychFPSCounter;

	// 布局参数
	private var lineHeight:Float = 18;

	// 性能优化变量
	private var lastFpsUpdateTime:Float = 0;

	public var fontName:String = Paths.font("vcr.ttf");

	public function new(x:Float = 10, y:Float = 10, color:flixel.util.FlxColor = 0xFF000000)
	{
		super();

		// 创建背景
		bgSprite = new Sprite();
		addChild(bgSprite);

		// 创建单个文本字段，显示所有信息
		allInfoText = createTextField(ClientPrefs.data.fpsFontSize, ClientPrefs.data.fpsColor);
		addChild(allInfoText);

		// 创建原版 Debug 面板（默认隐藏，fpsStyle == "Debug" 时显示）
		debugDisplay = new FunkinDebugDisplay(10, 10);
		debugDisplay.visible = false;
		addChild(debugDisplay);

		// 创建原版 Psych 风格实例（初始隐藏，fpsStyle == "Psych" 时显示）
		psychInstance = new PsychFPSCounter(x, y, 0xFFFFFF);
		psychInstance.visible = (ClientPrefs.data.fpsStyle == "Psych");
		addChild(psychInstance);

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

	private function createTextField(size:Int, color:flixel.util.FlxColor, bold:Bool = false):TextField
	{
		var tf = new TextField();
		tf.selectable = false;
		tf.mouseEnabled = false;
		tf.defaultTextFormat = new TextFormat(fontName, size, (color.red << 16) | (color.green << 8) | color.blue, bold);
		tf.autoSize = LEFT;
		return tf;
	}

	public dynamic function updateText():Void
	{
		// Psych 原版风格：委托给 PsychFPSCounter
		if (ClientPrefs.data.fpsStyle == "Psych")
		{
			psychInstance.visible = true;
			allInfoText.visible = false;
			bgSprite.visible = false;
			if (debugDisplay != null) debugDisplay.visible = false;
			return;
		}
		else if (psychInstance != null)
		{
			psychInstance.visible = false;
		}

		// 原版 FunkinDebugDisplay 风格：完全交给独立面板渲染
		if (ClientPrefs.data.fpsStyle == "V-Slice")
		{
			bgSprite.visible = false;
			allInfoText.visible = false;
			debugDisplay.visible = true;
			return;
		}
		else if (debugDisplay != null)
		{
			debugDisplay.visible = false;
		}

		// 切回 Kathy / Simple 时，需把文本与背景重新显示（之前切到 V-Slice 时被隐藏）
		allInfoText.visible = true;
		bgSprite.visible = true;

		// Simple/Leather 模式：使用 _sans 字体，简洁格式（与 SimpleInfoDisplay 一致）
		if (ClientPrefs.data.fpsStyle == "Simple")
		{
			var currentTime = Timer.stamp();
			var memory:Float = 0;
			try
			{
				memory = memoryMegas;
				if (memory < 0 || !Std.is(memory, Float)) memory = 0;
			}
			catch (e:Dynamic) { memory = 0; }

			if (memory > memoryPeakMegas) memoryPeakMegas = memory;

			var textLines:Array<String> = [];

			if (ClientPrefs.data.simpleInfoShowFPS) textLines.push(currentFPS + " fps" + gcStateLabel());
			if (ClientPrefs.data.simpleInfoShowMem) textLines.push(formatSimpleMemory(memory) + " / " + formatSimpleMemory(memoryPeakMegas));
			if (ClientPrefs.data.simpleInfoShowVersion)
			{
				var version:String = Application.current.meta.get('version');
				if (version == null) version = "0.0.0";
				textLines.push("v" + version);
			}

			var allText = textLines.join('\n');

			// 颜色（Simple 模式使用自己的颜色设置）
			var simpleColorInt = (ClientPrefs.data.simpleInfoColor.red << 16) | (ClientPrefs.data.simpleInfoColor.green << 8) | ClientPrefs.data.simpleInfoColor.blue;
			var colorHex = StringTools.hex(simpleColorInt, 6);
			allInfoText.htmlText = '<font color="#$colorHex">$allText</font>';

			// _sans 字体和字号（Simple 模式使用系统 _sans 字体，而非 vcr.ttf）
			allInfoText.defaultTextFormat = new TextFormat("_sans", ClientPrefs.data.simpleInfoFontSize, simpleColorInt, false);

			// 隐藏背景（Simple 模式没有背景）
			bgSprite.visible = false;
			this.alpha = 1;

			return;
		}

		// Psych 风格：详细信息（原有逻辑）
		var currentTime = Timer.stamp();
		var memory:Float = 0;
		
		try
		{
			memory = memoryMegas;
			// 确保内存值是有效的数字
			if (memory < 0 || !Std.is(memory, Float))
			{
				memory = 0;
			}
		}
		catch (e:Dynamic)
		{
			memory = 0;
		}

		// 更新内存峰值
		if (memory > memoryPeakMegas)
		{
			memoryPeakMegas = memory;
		}

		// 构建所有信息的文本 - 使用数组避免多余空行
		var textLines:Array<String> = [];

		// FPS信息 - 根据设置显示（附带原生GC开关状态标记）
		if (ClientPrefs.data.fpsShowFPS) textLines.push('FPS: $currentFPS ${gcStateLabel()}');
		if (ClientPrefs.data.fpsShowDelay) textLines.push('Delay: ${currentDelay}ms');
		if (ClientPrefs.data.fpsShowRAM) textLines.push('RAM: ${formatMemory(memory)}');
		if (ClientPrefs.data.fpsShowMemPeak) textLines.push('MEM Peak: ${formatMemory(memoryPeakMegas)}');
		if (ClientPrefs.data.fpsShowObjects) textLines.push('Objects: $objectCount');
		
		// 版本信息
		if (ClientPrefs.data.exgameversion)
		{
			textLines.push('');
			textLines.push('Psych ${MainMenuState.psychEngineVersion}');
			textLines.push('Kathy ${MainMenuState.kathyEngineVersion}');
			textLines.push('Commit: ${GameVersion.getGitCommitCount()} (${GameVersion.getGitCommitHash()})');
			textLines.push('Build: ${GameVersion.getBuildTime()}');
		}
		
		// 显示haxelib信息 - 独立于版本信息
		if (ClientPrefs.data.showHaxelibs)
		{
			textLines.push('');
			textLines.push('Libs:');
			textLines.push(HaxelibInfo.getHaxelibInfo());
		}

		// 显示操作系统信息
		if (ClientPrefs.data.showRunningOS)
		{
			textLines.push('');
			textLines.push(os);
		}

		// 系统信息 - 只有当显示版本信息或者显示haxelib或者显示操作系统信息时才添加
		if (ClientPrefs.data.exgameversion || ClientPrefs.data.showHaxelibs || ClientPrefs.data.showRunningOS)
		{
			var hasSystemInfo = false;
			var lastWasBlank:Bool = textLines.length > 0 && textLines[textLines.length - 1] == '';

			// 平台信息
			if (ClientPrefs.data.fpsShowPlatform)
			{
				if (!hasSystemInfo && !lastWasBlank)
				{
					textLines.push('');
					lastWasBlank = true;
					hasSystemInfo = true;
				}
				else
				{
					hasSystemInfo = true;
				}
				#if cpp
				var arch = getArch() != 'Unknown' ? ' (${getArch()})' : '';
				#else
				var arch = '';
				#end
				textLines.push('Platform: ${LimeSystem.platformName}$arch');
				lastWasBlank = false;
			}

			// 平台版本
			if (ClientPrefs.data.fpsShowOSVersion)
			{
				if (LimeSystem.platformVersion != null && LimeSystem.platformVersion != LimeSystem.platformName)
				{
					if (!hasSystemInfo && !lastWasBlank)
					{
						textLines.push('');
						lastWasBlank = true;
						hasSystemInfo = true;
					}
					else
					{
						hasSystemInfo = true;
					}
					textLines.push('OS Ver.: ${LimeSystem.platformVersion}');
					lastWasBlank = false;
				}
			}

			// 显示器信息
			try
			{
				var display = LimeSystem.getDisplay(0);
				if (display != null)
				{
					if (ClientPrefs.data.fpsShowResolution)
					{
						if (!hasSystemInfo && !lastWasBlank)
						{
							textLines.push('');
							lastWasBlank = true;
							hasSystemInfo = true;
						}
						else
						{
							hasSystemInfo = true;
						}
						textLines.push('Resolution: ${display.currentMode.width}x${display.currentMode.height}');
						lastWasBlank = false;
					}

					if (ClientPrefs.data.fpsShowRefreshRate)
					{
						if (!hasSystemInfo && !lastWasBlank)
						{
							textLines.push('');
							lastWasBlank = true;
							hasSystemInfo = true;
						}
						else
						{
							hasSystemInfo = true;
						}
						textLines.push('Refresh: ${display.currentMode.refreshRate}Hz');
						lastWasBlank = false;
					}
				}
			}
			catch (e:Dynamic)
			{
			}
		}

		// 移除末尾的空行
		while (textLines.length > 0 && textLines[textLines.length - 1] == '')
		{
			textLines.pop();
		}

		var allText = textLines.join('\n');

		// 转换颜色为十六进制字符串
		var colorHex = StringTools.hex((ClientPrefs.data.fpsColor.red << 16) | (ClientPrefs.data.fpsColor.green << 8) | ClientPrefs.data.fpsColor.blue, 6);
		allInfoText.htmlText = '<font color="#$colorHex">$allText</font>';
		
		// 更新字体大小
		var textColorInt = (ClientPrefs.data.fpsColor.red << 16) | (ClientPrefs.data.fpsColor.green << 8) | ClientPrefs.data.fpsColor.blue;
		allInfoText.defaultTextFormat = new TextFormat(fontName, ClientPrefs.data.fpsFontSize, textColorInt, false);
		
		// 更新透明度
		this.alpha = ClientPrefs.data.fpsOpacity;
		
		// 更新背景
		updateBackground();
	}
	
	private function updateBackground():Void
	{
		// Psych 模式下重新显示背景
		bgSprite.visible = true;

		bgSprite.graphics.clear();
		
		if (ClientPrefs.data.fpsBgEnabled)
		{
			var padding = ClientPrefs.data.fpsBgPadding;
			var w = allInfoText.width + padding * 2;
			var h = allInfoText.height + padding * 2;
			
			var bgColorInt = (ClientPrefs.data.fpsBgColor.red << 16) | (ClientPrefs.data.fpsBgColor.green << 8) | ClientPrefs.data.fpsBgColor.blue;
			bgSprite.graphics.beginFill(bgColorInt, ClientPrefs.data.fpsBgOpacity);
			bgSprite.graphics.drawRect(-padding, -padding, w, h);
			bgSprite.graphics.endFill();
		}
	}
	
	// 重新应用所有设置
	public function applySettings():Void
	{
		// 若切换到 Psych 模式，重建 psychInstance 以应用新位置
		if (ClientPrefs.data.fpsStyle == "Psych" && psychInstance != null)
		{
			removeChild(psychInstance);
			psychInstance = new PsychFPSCounter(10, 3, 0xFFFFFF);
			addChild(psychInstance);
		}

		updateText();
		positionFPS(x, y);

		// Debug 风格需要重建面板以吸收新增设定
		if (ClientPrefs.data.fpsStyle == "V-Slice" && debugDisplay != null)
		{
			debugDisplay.mode = ClientPrefs.data.fpsDebugMode;
			debugDisplay.applySettings();
			updateDebugPosition();
		}
	}

	// ============ 原版 FunkinDebugDisplay 风格 ============

	/**
	 * 独立开关+热键：在 Off / Simple / Advanced 之间循环当前 Debug 面板模式。
	 * 仅当 fpsStyle 为 "Debug" 时生效。
	 */
	public function cycleDebugMode():Void
	{
		if (ClientPrefs.data.fpsStyle != "V-Slice") return;

		var modes:Array<String> = ["Off", "Simple", "Advanced"];
		var i:Int = modes.indexOf(ClientPrefs.data.fpsDebugMode);
		if (i < 0) i = 0;
		ClientPrefs.data.fpsDebugMode = modes[(i + 1) % modes.length];
		ClientPrefs.saveSettings();
		applySettings();
	}

	/**
	 * 手动设置 Debug 面板模式（供设置界面使用）。
	 */
	public function setDebugMode(mode:String):Void
	{
		if (ClientPrefs.data.fpsDebugMode != mode)
		{
			ClientPrefs.data.fpsDebugMode = mode;
			ClientPrefs.saveSettings();
			applySettings();
		}
	}

	function updateDebugPosition():Void
	{
		if (debugDisplay != null)
		{
			var scale:Float = 1;
			debugDisplay.setScaleFactor(scale);
			debugDisplay.reposition(ClientPrefs.data.fpsPosition, ClientPrefs.data.fpsSpacing);
		}
	}

	private override function __enterFrame(deltaTime:Float):Void
	{
		if (!visible)
			return;

		// Psych 原版风格：显式驱动 psychInstance（引擎不自动向子节点传递 __enterFrame）
		if (ClientPrefs.data.fpsStyle == "Psych")
		{
			if (psychInstance != null) psychInstance.__enterFrame(deltaTime);
			return;
		}

		// 原版 Debug(V-Slice) 风格：本类覆写了 __enterFrame 且不调用 super，
		// OpenFL 不会把帧回调链式传到子面板，故这里显式驱动 debugDisplay 刷新。
		if (ClientPrefs.data.fpsStyle == "V-Slice")
		{
			if (debugDisplay != null) debugDisplay.step(deltaTime);
			return;
		}

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
		// Simple/Leather 模式更新频率更高（每 0.1 秒），Psych 模式保持原频率（每 0.5 秒）
		var updateInterval:Float = (ClientPrefs.data.fpsStyle == "Simple") ? 0.1 : 0.5;
		if (Timer.stamp() - lastFpsUpdateTime > updateInterval)
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

		// 仅在设备"无法达到"设定帧率时（实测明显偏低）才下调引擎帧率；
		// 绝不允许把帧率"拉高"到实测值，否则一旦短时超标就会把引擎永久锁定到超过设定值的帧率。
		//石山AI发力了——牢喵_202608.15
		/*if (FlxG.updateFramerate > currentFPS + 5
			&& haxe.Timer.stamp() - lastFramerateUpdateTime >= 1.5
			&& currentFPS >= 30)
		{
			var clamped = Std.int(Math.min(currentFPS, ClientPrefs.data.framerate));
			FlxG.updateFramerate = FlxG.drawFramerate = clamped;
			lastFramerateUpdateTime = haxe.Timer.stamp();
		}*/

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

	// 原生GC开关状态标记：仅当关闭时在 FPS 行显示 "NO GC" 提示
	inline function gcStateLabel():String
	{
		return (ClientPrefs.data != null && !ClientPrefs.data.garbageCollectorEnabled) ? "(No GC)" : "";
	}

	function get_memoryMegas():Float
	{
		#if cpp
		try
		{
			var memValue:Dynamic = cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE);
			if (Std.is(memValue, Float) || Std.is(memValue, Int))
			{
				var mem:Float = cast memValue;
				if (Math.isFinite(mem) && mem >= 0)
					return mem;
			}
		}
		catch (e:Dynamic) {}

		try
		{
			var memValue:Dynamic = cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_USAGE);
			if (Std.is(memValue, Float) || Std.is(memValue, Int))
			{
				var mem:Float = cast memValue;
				if (Math.isFinite(mem) && mem >= 0)
					return mem;
			}
		}
		catch (e:Dynamic) {}
		#end

		return 0;
	}

	public inline function positionFPS(X:Float, Y:Float, ?scale:Float = 1)
	{
		scaleX = scaleY = #if android (scale > 1 ? scale : 1) #else (scale < 1 ? scale : 1) #end;

		var spacing = ClientPrefs.data.fpsSpacing;

		// 原版 Debug 风格：面板按自身尺寸贴边
		if (ClientPrefs.data.fpsStyle == "V-Slice")
		{
			updateDebugPosition();
			return;
		}

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
	private function getArch():String
	{
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
		return "Unknown";
	}
	#elseif (ios || mac)
	private function getArch():String
	{
		@:functionCode('
        const NXArchInfo *archInfo = NXGetLocalArchInfo();
        return ::String(archInfo == NULL ? "Unknown" : archInfo->name);
    ')
		return "Unknown";
	}
	#else
	private function getArch():String
	{
		@:functionCode('
        struct utsname osInfo{};
        uname(&osInfo);
        return ::String(osInfo.machine);
    ')
		return "Unknown";
	}
	#end
	#else
	private function getArch():String
	{
		var platform = LimeSystem.platformName;
		if (platform != null && (platform.indexOf("x86_64") >= 0 || platform.indexOf("arm64") >= 0 || platform.indexOf("ARM64") >= 0))
			return platform;
		return "Unknown";
	}
	#end

	/**
	 * 格式化内存显示，根据设置决定是否强制显示MB
	 */
	private function formatMemory(memoryInBytes:Float):String
	{
		if (memoryInBytes < 0 || memoryInBytes != memoryInBytes)
		{
			memoryInBytes = 0;
		}

		if (ClientPrefs.data.fpsForceMB)
		{
			var memoryInMB = memoryInBytes / (1024 * 1024);
			return Std.string(Math.round(memoryInMB)) + "MB";
		}

		try
		{
			return flixel.util.FlxStringUtil.formatBytes(memoryInBytes);
		}
		catch (e:Dynamic)
		{
			var memoryInMB = memoryInBytes / (1024 * 1024);
			return Std.string(Math.round(memoryInMB)) + "MB";
		}
	}

	/**
	 * Simple/Leather 模式的内存格式化：MB/GB 自动切换，保留两位小数
	 */
	private function formatSimpleMemory(memoryInBytes:Float):String
	{
		if (memoryInBytes < 0 || memoryInBytes != memoryInBytes) memoryInBytes = 0;

		var memoryInMB:Float = memoryInBytes / (1024 * 1024);

		if (memoryInMB < 1024)
			return Math.round(memoryInMB * 100) / 100 + "MB";
		else
			return Math.round((memoryInMB / 1024) * 100) / 100 + "GB";
	}
}