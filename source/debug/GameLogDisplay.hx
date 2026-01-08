package debug;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.Lib;
import flixel.FlxG;
import haxe.Timer;
import backend.ClientPrefs;
import backend.Paths;

/**
 * Game Log Display - 显示游戏内的trace日志
 * 通过F3键切换显示状态
 */
class GameLogDisplay extends Sprite
{
	// 日志条目
	private var logs:Array<LogEntry>;
	private var maxLogs:Int = 50;

	// 文本字段
	private var logText:TextField;

	// 字体和颜色
	private var fontName:String;
	private var fontSize:Int = 16;

	// 是否可见（由设置和按键控制）
	public var isEnabled:Bool = false;
	public var isVisible:Bool = false;

	// 原始函数
	private var originalTrace:Dynamic->?haxe.PosInfos->Void;

	// 静态回调函数，用于从外部添加日志
	public static var onLogAdded:Dynamic = null;

	public function new()
	{
		super();

		logs = [];

		// 使用Paths.font获取字体
		fontName = Paths.font('unifont-16.0.02.otf');

		// 创建文本字段
		logText = new TextField();
		logText.selectable = false;
		logText.mouseEnabled = false;
		logText.defaultTextFormat = new TextFormat(fontName, fontSize, 0xFFFFFF);
		logText.autoSize = "left";
		logText.multiline = true;
		logText.wordWrap = false;
		addChild(logText);

		// 设置初始位置和大小
		x = 10;
		y = 10;
		visible = false;

		// 劫持trace函数
		hookTrace();
	}
	
	/**
	 * 劫持trace函数，将日志同时输出到终端和界面
	 */
	private function hookTrace():Void
	{
		originalTrace = haxe.Log.trace;
		haxe.Log.trace = function(v:Dynamic, ?pos:haxe.PosInfos):Void
		{
			// 调用原始trace函数，输出到终端
			if (originalTrace != null)
			{
				originalTrace(v, pos);
			}
			
			// 添加到日志显示
			addLog(v, pos);
		};
	}
	
	/**
	 * 添加日志条目（从trace）
	 */
	public function addLog(message:Dynamic, ?pos:haxe.PosInfos):Void
	{
		var timestamp = Timer.stamp();
		var timeStr = StringTools.lpad(Std.string(Math.floor(timestamp % 3600)), "0", 2) + ":" +
		             StringTools.lpad(Std.string(Math.floor((timestamp % 60) * 60)), "0", 2);
		
		var location = "";
		if (pos != null)
		{
			location = pos.fileName + ":" + pos.lineNumber;
		}
		
		var entry:LogEntry = {
			timestamp: timestamp,
			message: Std.string(message),
			location: location,
			source: "trace",
			color: null
		};
		
		logs.push(entry);
		
		// 限制日志数量
		if (logs.length > maxLogs)
		{
			logs.shift();
		}
		
		// 更新显示
		updateDisplay();
		
		// 触发回调
		if (onLogAdded != null)
		{
			try
			{
				onLogAdded(message);
			}
			catch (e:Dynamic)
			{
				// 忽略回调错误
			}
		}
	}
	
	/**
	 * 添加日志条目（从Lua调试输出）
	 */
	public function addLogWithColor(message:String, color:flixel.util.FlxColor):Void
	{
		var timestamp = Timer.stamp();
		
		var entry:LogEntry = {
			timestamp: timestamp,
			message: message,
			location: "",
			source: "lua",
			color: color
		};
		
		logs.push(entry);
		
		// 限制日志数量
		if (logs.length > maxLogs)
		{
			logs.shift();
		}
		
		// 更新显示
		updateDisplay();
	}
	
	/**
	 * 更新显示内容
	 */
	private function updateDisplay():Void
	{
		if (!isVisible || !isEnabled)
		{
			visible = false;
			return;
		}

		visible = true;

		var displayText = '<font face="$fontName" size="$fontSize">';
		
		for (i in 0...logs.length)
		{
			var entry = logs[i];
			var timeStr = StringTools.lpad(Std.string(Math.floor((entry.timestamp % 60) * 60)), "0", 2) + ":" +
			             StringTools.lpad(Std.string(Math.floor((entry.timestamp * 1000) % 1000)), "0", 3);
			
			// 如果有指定颜色，使用指定颜色；否则根据日志内容设置颜色
			var colorHex = "#FFFFFF";
			if (entry.color != null)
			{
				colorHex = '#' + StringTools.hex(entry.color, 6);
			}
			else
			{
				var msg = entry.message.toLowerCase();
				if (msg.indexOf("error") != -1 || msg.indexOf("错误") != -1)
					colorHex = "#FF4444";
				else if (msg.indexOf("warn") != -1 || msg.indexOf("warning") != -1)
					colorHex = "#FFAA00";
				else if (msg.indexOf("debug") != -1)
					colorHex = "#AAAAAA";
			}
			
			var prefix = "[LOG]";
			if (entry.source == "lua")
				prefix = "[LUA]";
			
			displayText += '<font color="$colorHex">[$timeStr] $prefix ${entry.message}</font>\n';
		}
		
		displayText += "</font>";
		logText.htmlText = displayText;
		
		// 调整大小以适应文本
		logText.width = 800;
		logText.height = 500;
		
		// 设置背景（半透明黑色）
		graphics.clear();
		graphics.beginFill(0x000000, 0.85);
		graphics.drawRect(0, 0, logText.width + 20, logText.height + 20);
		graphics.endFill();
		
		logText.x = 10;
		logText.y = 10;
		
		// 更新位置
		updatePosition();
	}
	
	/**
	 * 更新显示位置（屏幕中间）
	 */
	private function updatePosition():Void
	{
		var stage = Lib.current.stage;
		
		if (stage != null)
		{
			// 放在屏幕中间
			x = (stage.stageWidth - this.width) / 2;
			y = (stage.stageHeight - this.height) / 2;
		}
	}
	
	/**
	 * 切换显示状态
	 */
	public function toggleVisibility():Void
	{
		if (isEnabled)
		{
			isVisible = !isVisible;
			updateDisplay();
		}
	}
	
	/**
	 * 启用/禁用日志显示功能
	 */
	public function setEnabled(enabled:Bool):Void
	{
		isEnabled = enabled;
		if (!enabled)
		{
			isVisible = false;
			visible = false;
		}
	}
	
	/**
	 * 更新位置（当窗口大小改变时调用）
	 */
	public function updatePositionOnResize():Void
	{
		updatePosition();
		updateDisplay();
	}
}

/**
 * 日志条目结构
 */
typedef LogEntry = {
	timestamp:Float,
	message:String,
	location:String,
	source:String,
	?color:flixel.util.FlxColor
}

