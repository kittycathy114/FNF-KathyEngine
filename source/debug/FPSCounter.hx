package debug;

import flixel.FlxG;
import openfl.Lib;
import haxe.Timer;
import openfl.text.TextField;
import openfl.text.TextFormat;
import lime.system.System as LimeSystem;
import states.MainMenuState;
import debug.GameVersion;
import openfl.display.Sprite;
import openfl.display.Shape;
import flixel.FlxState;
import flixel.util.FlxColor;
import openfl.utils.Assets;
import backend.ClientPrefs;
import backend.Paths;
import flixel.math.FlxMath;

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
	public var currentFPS(default, null):Int;
	public var memoryMegas(get, never):Float;
	public var memoryPeakMegas(default, null):Float = 0;

	@:noCompletion private var times:Array<Float>;
	@:noCompletion private var lastFramerateUpdateTime:Float;
	@:noCompletion private var updateTime:Int;
	@:noCompletion private var framesCount:Int;
	@:noCompletion private var prevTime:Int;

	public var objectCount(default, null):Int = 0;

	@:noCompletion private var lastObjectCountUpdate:Float = 0;
	@:noCompletion private var lastDelayUpdateTime:Float = 0;
	@:noCompletion private var currentDelay:Float = 0;

	public var os:String = '';

	// 文本字段
	private var fpsInfoText:TextField;
	private var versionText:TextField;

	// 背景元素
	private var fpsBackground:Shape;
	private var versionBackground:Shape;

	// 布局参数
	private var padding:Float = 8;
	private var cornerRadius:Float = 8;
	private var panelGap:Float = 10; // 两个面板之间的间隔

	// 性能优化变量
	private var lastFpsUpdateTime:Float = 0;
	private var lastRamUpdateTime:Float = 0;
	private var lastObjectsUpdateTime:Float = 0;

	// 背景平滑过渡变量（FPS面板）
	private var targetFpsHeight:Float = 120;
	private var currentFpsHeight:Float = 120;
	private var lerpSpeed:Float = 0.2;

	// 背景平滑过渡变量（版本面板）
	private var targetVersionHeight:Float = 80;
	private var currentVersionHeight:Float = 80;

	// 版本面板显示/隐藏动画变量
	private var versionPanelVisible:Bool = true;
	private var versionPanelAlpha:Float = 1.0;
	private var versionPanelOffset:Float = 0;
	private var targetVersionAlpha:Float = 1.0;
	private var targetVersionOffset:Float = 0;

	// 修复：添加缺失的变量声明
	@:noCompletion private var lastExGameVersion:Bool;
	@:noCompletion private var lastShowRunningOS:Bool;

	public var fontName:String = Paths.font("vcr.ttf");

	public function new(x:Float = 10, y:Float = 10, color:Int = 0x000000)
	{
		super();

		// 创建FPS信息背景
		fpsBackground = new Shape();
		drawFpsBackground(0x222222, 0.85, 200, 120);
		addChild(fpsBackground);

		// 创建版本信息背景
		versionBackground = new Shape();
		drawVersionBackground(0x222222, 0.85, 200, 80);
		addChild(versionBackground);

		// 创建文本字段 - 统一字体大小为16
		fpsInfoText = createTextField(16, 0xFFFFFF);
		versionText = createTextField(16, 0xCCCCCC);
		addChild(fpsInfoText);
		addChild(versionText);

		#if !officialBuild
		if (LimeSystem.platformName == LimeSystem.platformVersion || LimeSystem.platformVersion == null)
			os = 'OS: ${LimeSystem.platformName}' #if cpp + ' ${getArch() != 'Unknown' ? getArch() : ''}' #end;
		else
			os = 'OS: ${LimeSystem.platformName}' #if cpp + ' ${getArch() != 'Unknown' ? getArch() : ''}' #end + ' - ${LimeSystem.platformVersion}';
		#end

		// 修复：初始化设置跟踪变量
		lastExGameVersion = ClientPrefs.data.exgameversion;
		lastShowRunningOS = ClientPrefs.data.showRunningOS;

		positionFPS(x, y);

		currentFPS = 0;
		times = [];
		lastFramerateUpdateTime = Timer.stamp();
		prevTime = Lib.getTimer();
		updateTime = prevTime + 500;
		framesCount = 0;

		// 初始化更新时间
		lastFpsUpdateTime = Timer.stamp();
		lastRamUpdateTime = Timer.stamp();
		lastObjectsUpdateTime = Timer.stamp();
		
		// 初始化背景尺寸
		positionTextElements();
	}

	private function getVersionText():String
	{
		var versionTextContent = '';
		if (ClientPrefs.data.exgameversion)
		{
			versionTextContent = 'Psych v${MainMenuState.psychEngineVersion}';
			versionTextContent += '\nMR v${MainMenuState.mrExtendVersion}';
			versionTextContent += '\nCommit: ${GameVersion.getGitCommitCount()} (${GameVersion.getGitCommitHash()})';
			versionTextContent += '\nBuild: ${GameVersion.getBuildTime()}';
		}

		if (ClientPrefs.data.showRunningOS)
			versionTextContent += '\n' + os;

		return versionTextContent;
	}

	private function drawFpsBackground(color:Int, alpha:Float, width:Float, height:Float):Void
	{
		fpsBackground.graphics.clear();
		fpsBackground.graphics.beginFill(color, alpha);
		fpsBackground.graphics.drawRoundRect(0, 0, width, height, cornerRadius);
		fpsBackground.graphics.endFill();

		// 添加边框
		fpsBackground.graphics.lineStyle(1, 0xFFFFFF, 0.2);
		fpsBackground.graphics.drawRoundRect(0, 0, width, height, cornerRadius);
	}

	private function drawVersionBackground(color:Int, alpha:Float, width:Float, height:Float):Void
	{
		versionBackground.graphics.clear();

		// 如果高度为0或透明度为0，不绘制
		if (height <= 0.5 || alpha <= 0.01)
			return;

		versionBackground.graphics.beginFill(color, alpha);
		versionBackground.graphics.drawRoundRect(0, 0, width, height, cornerRadius);
		versionBackground.graphics.endFill();

		// 添加边框
		versionBackground.graphics.lineStyle(1, 0xFFFFFF, 0.2 * versionPanelAlpha);
		versionBackground.graphics.drawRoundRect(0, 0, width, height, cornerRadius);
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

		// 检查设置是否变化
		if (ClientPrefs.data.exgameversion != lastExGameVersion)
		{
			lastExGameVersion = ClientPrefs.data.exgameversion;

			// 设置版本面板显示/隐藏动画目标
			if (ClientPrefs.data.exgameversion)
			{
				// 显示版本面板
				targetVersionAlpha = 1.0;
				targetVersionOffset = 0;
				versionPanelVisible = true;
			}
			else
			{
				// 隐藏版本面板
				targetVersionAlpha = 0.0;
				targetVersionOffset = 50; // 飞出距离
				versionPanelVisible = false;
			}
		}

		if (ClientPrefs.data.showRunningOS != lastShowRunningOS)
		{
			lastShowRunningOS = ClientPrefs.data.showRunningOS;
		}

		// 更新内存峰值
		if (memory > memoryPeakMegas)
		{
			memoryPeakMegas = memory;
		}

		// 更新FPS信息文本
		var fpsColor:String;
		if (currentFPS < FlxG.stage.window.frameRate * 0.5)
		{
			fpsColor = "#FF4444";
		}
		else if (currentFPS < FlxG.stage.window.frameRate * 0.75)
		{
			fpsColor = "#FFFF66";
		}
		else
		{
			fpsColor = "#66FF66";
		}

		var ramColor = memory > 1024 * 1024 * 500 ? "#FF6666" : "#66AAFF";
		var delayColor = currentDelay > 16.7 ? "#FF6666" : "#FFFF66";
		var objectsColor = objectCount > 2000 ? "#FF6666" : "#66FF66";

		var fpsInfoContent = '';

		// FPS
		fpsInfoContent += '<font color="$fpsColor">FPS: $currentFPS</font>\n';

		// Delay
		fpsInfoContent += '<font color="$delayColor">Delay: ${currentDelay}ms</font>\n';

		// RAM
		fpsInfoContent += '<font color="$ramColor">RAM: ${flixel.util.FlxStringUtil.formatBytes(memory)}</font>\n';

		// MEM Peak
		fpsInfoContent += '<font color="#FFA500">MEM Peak: ${flixel.util.FlxStringUtil.formatBytes(memoryPeakMegas)}</font>\n';

		// Objects
		fpsInfoContent += '<font color="$objectsColor">Objects: $objectCount</font>';

		fpsInfoText.htmlText = fpsInfoContent;

		// 更新版本信息文本
		var versionInfo = getVersionText();
		versionText.htmlText = '<font color="#CCCCCC">$versionInfo</font>';

		// 更新背景尺寸
		positionTextElements();
	}

	private function positionTextElements()
	{
		// 定位FPS信息
		fpsInfoText.x = padding;
		fpsInfoText.y = padding;

		// 计算FPS背景所需高度
		var fpsHeight = padding * 2;
		fpsHeight += fpsInfoText.height + 6;

		// 设置目标高度
		targetFpsHeight = fpsHeight;

		// 只在版本面板可见时计算尺寸
		if (versionPanelVisible)
		{
			// 定位版本信息（在FPS信息下方）
			versionText.x = padding;
			versionText.y = currentFpsHeight + panelGap + padding;

			// 计算版本背景所需高度
			var versionHeight = padding * 2;
			versionHeight += versionText.height + 6;

			// 设置版本背景目标高度
			targetVersionHeight = versionHeight;
		}
		else
		{
			// 隐藏版本面板时，目标高度为0
			targetVersionHeight = 0;
		}
	}

	var deltaTimeout:Float = 0.0;

	private override function __enterFrame(deltaTime:Float):Void
	{
		if (!visible)
			return;

		if (Timer.stamp() - lastObjectCountUpdate > 2.0)
		{
			objectCount = countObjects(FlxG.state);
			lastObjectCountUpdate = Timer.stamp();
		}

		// FPS面板背景尺寸平滑过渡
		if (currentFpsHeight != targetFpsHeight)
		{
			currentFpsHeight = FlxMath.lerp(currentFpsHeight, targetFpsHeight, lerpSpeed);
			if (Math.abs(currentFpsHeight - targetFpsHeight) < 0.5)
				currentFpsHeight = targetFpsHeight;

			drawFpsBackground(0x222222, 0.85, 200, currentFpsHeight);
		}

		// 版本面板背景尺寸平滑过渡
		if (currentVersionHeight != targetVersionHeight)
		{
			currentVersionHeight = FlxMath.lerp(currentVersionHeight, targetVersionHeight, lerpSpeed);
			if (Math.abs(currentVersionHeight - targetVersionHeight) < 0.5)
				currentVersionHeight = targetVersionHeight;

			versionBackground.y = currentFpsHeight + panelGap + versionPanelOffset;
			drawVersionBackground(0x222222, 0.85, 200, currentVersionHeight);
		}

		// 版本面板透明度和平移动画
		if (versionPanelAlpha != targetVersionAlpha || versionPanelOffset != targetVersionOffset)
		{
			versionPanelAlpha = FlxMath.lerp(versionPanelAlpha, targetVersionAlpha, 0.15);
			versionPanelOffset = FlxMath.lerp(versionPanelOffset, targetVersionOffset, 0.15);

			if (Math.abs(versionPanelAlpha - targetVersionAlpha) < 0.01)
				versionPanelAlpha = targetVersionAlpha;
			if (Math.abs(versionPanelOffset - targetVersionOffset) < 0.5)
				versionPanelOffset = targetVersionOffset;

			// 应用透明度
			versionBackground.alpha = versionPanelAlpha * 0.85;
			versionText.alpha = versionPanelAlpha;

			// 更新位置
			versionBackground.y = currentFpsHeight + panelGap + versionPanelOffset;
			versionText.y = versionBackground.y + padding;
		}

		if (ClientPrefs.data.fpsRework)
		{
			if (FlxG.stage.window.frameRate != ClientPrefs.data.framerate && FlxG.stage.window.frameRate != FlxG.game.focusLostFramerate)
				FlxG.stage.window.frameRate = ClientPrefs.data.framerate;

			var currentTime = openfl.Lib.getTimer();
			framesCount++;

			if (currentTime >= updateTime)
			{
				var elapsed = currentTime - prevTime;
				currentFPS = Math.ceil((framesCount * 1000) / elapsed);
				framesCount = 0;
				prevTime = currentTime;
				updateTime = currentTime + 500;
			}

			if ((FlxG.updateFramerate >= currentFPS + 5 || FlxG.updateFramerate <= currentFPS - 5)
				&& haxe.Timer.stamp() - lastFramerateUpdateTime >= 1.5
				&& currentFPS >= 30)
			{
				FlxG.updateFramerate = FlxG.drawFramerate = currentFPS;
				lastFramerateUpdateTime = haxe.Timer.stamp();
			}
		}
		else
		{
			final now:Float = haxe.Timer.stamp() * 1000;
			times.push(now);
			while (times[0] < now - 1000)
				times.shift();
			if (deltaTimeout < 50)
			{
				deltaTimeout += deltaTime;
				return;
			}

			currentFPS = times.length < FlxG.updateFramerate ? times.length : FlxG.updateFramerate;
			deltaTimeout = 0.0;
		}

		if (Timer.stamp() - lastFpsUpdateTime > 0.05)
		{
			updateText();
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
				var totalHeight = currentFpsHeight + panelGap + currentVersionHeight;
				y = stage.stageHeight - totalHeight - spacing;
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