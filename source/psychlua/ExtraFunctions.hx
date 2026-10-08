package psychlua;

import flixel.util.FlxSave;
import flixel.FlxObject;
import flixel.util.FlxColor;
import openfl.utils.Assets;
import openfl.geom.Point;
#if sys
import sys.FileSystem;
#end
import backend.Paths;
import backend.CoolUtil;
import states.PlayState;
import objects.Character;

//
// Things to trivialize some dumb stuff like splitting strings on older Lua
//

class ExtraFunctions
{
	// G 类：帧计数器 — 由 PlayState 每帧 update 时自增，供 Lua getFrameCount 使用
	public static var frameCount:Int = 0;

	public static function implement(funk:FunkinLua)
	{
		var lua:State = funk.lua;
		// Keyboard & Gamepads
		Lua_helper.add_callback(lua, "keyboardJustPressed", function(name:String)
		{
			var n = name.toUpperCase();
			if (checkExtraKeyState(n, 0)) return true; // 额外键绑定的物理键(justPressed)
			return Reflect.getProperty(FlxG.keys.justPressed, n);
		});
		Lua_helper.add_callback(lua, "keyboardPressed", function(name:String)
		{
			var n = name.toUpperCase();
			if (checkExtraKeyState(n, 1)) return true; // 额外键绑定的物理键(pressed)
			return Reflect.getProperty(FlxG.keys.pressed, n);
		});
		Lua_helper.add_callback(lua, "keyboardReleased", function(name:String)
		{
			var n = name.toUpperCase();
			if (checkExtraKeyState(n, 2)) return true; // 额外键绑定的物理键(justReleased)
			return Reflect.getProperty(FlxG.keys.justReleased, n);
		});
	
		Lua_helper.add_callback(lua, "anyGamepadJustPressed", function(name:String) return FlxG.gamepads.anyJustPressed(name.toUpperCase()));
		Lua_helper.add_callback(lua, "anyGamepadPressed", function(name:String) return FlxG.gamepads.anyPressed(name.toUpperCase()));
		Lua_helper.add_callback(lua, "anyGamepadReleased", function(name:String) return FlxG.gamepads.anyJustReleased(name.toUpperCase()));

		Lua_helper.add_callback(lua, "gamepadAnalogX", function(id:Int, ?leftStick:Bool = true)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return 0.0;

			return controller.getXAxis(leftStick ? LEFT_ANALOG_STICK : RIGHT_ANALOG_STICK);
		});
		Lua_helper.add_callback(lua, "gamepadAnalogY", function(id:Int, ?leftStick:Bool = true)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return 0.0;

			return controller.getYAxis(leftStick ? LEFT_ANALOG_STICK : RIGHT_ANALOG_STICK);
		});
		Lua_helper.add_callback(lua, "gamepadJustPressed", function(id:Int, name:String)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return false;

			return Reflect.getProperty(controller.justPressed, name) == true;
		});
		Lua_helper.add_callback(lua, "gamepadPressed", function(id:Int, name:String)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return false;

			return Reflect.getProperty(controller.pressed, name) == true;
		});
		Lua_helper.add_callback(lua, "gamepadReleased", function(id:Int, name:String)
		{
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null) return false;

			return Reflect.getProperty(controller.justReleased, name) == true;
		});

		Lua_helper.add_callback(lua, "keyJustPressed", function(?name:String = null) {
			if (name == null) name = LuaCompatRouter.defaultKeyName();
			if (name == null) name = '';
			name = name.toLowerCase().trim();
			switch(name) {
				case 'left': return PlayState.instance.controls.NOTE_LEFT_P;
				case 'down': return PlayState.instance.controls.NOTE_DOWN_P;
				case 'up': return PlayState.instance.controls.NOTE_UP_P;
				case 'right': return PlayState.instance.controls.NOTE_RIGHT_P;
				default:
					if (checkExtraKeyState(name.toUpperCase(), 0)) return true; // 额外键绑定的物理键(justPressed)
					return PlayState.instance.controls.justPressed(name);
			}
			return false;
		});
		Lua_helper.add_callback(lua, "keyPressed", function(?name:String = null) {
			if (name == null) name = LuaCompatRouter.defaultKeyName();
			if (name == null) name = '';
			name = name.toLowerCase().trim();
			switch(name) {
				case 'left': return PlayState.instance.controls.NOTE_LEFT;
				case 'down': return PlayState.instance.controls.NOTE_DOWN;
				case 'up': return PlayState.instance.controls.NOTE_UP;
				case 'right': return PlayState.instance.controls.NOTE_RIGHT;
				default:
					if (checkExtraKeyState(name.toUpperCase(), 1)) return true; // 额外键绑定的物理键(pressed)
					return PlayState.instance.controls.pressed(name);
			}
			return false;
		});
		Lua_helper.add_callback(lua, "keyReleased", function(?name:String = null) {
			if (name == null) name = LuaCompatRouter.defaultKeyName();
			if (name == null) name = '';
			name = name.toLowerCase().trim();
			switch(name) {
				case 'left': return PlayState.instance.controls.NOTE_LEFT_R;
				case 'down': return PlayState.instance.controls.NOTE_DOWN_R;
				case 'up': return PlayState.instance.controls.NOTE_UP_R;
				case 'right': return PlayState.instance.controls.NOTE_RIGHT_R;
				default:
					if (checkExtraKeyState(name.toUpperCase(), 2)) return true; // 额外键绑定的物理键(justReleased)
					return PlayState.instance.controls.justReleased(name);
			}
			return false;
		});

		// Save data management
		Lua_helper.add_callback(lua, "initSaveData", function(name:String, ?folder:String = 'psychenginemods') {
			var variables = MusicBeatState.getVariables();
			if(!variables.exists('save_$name'))
			{
				var save:FlxSave = new FlxSave();
				// folder goes unused for flixel 5 users. @BeastlyGhost
				save.bind(name, CoolUtil.getSavePath() + '/' + folder);
				variables.set('save_$name', save);
				return;
			}
			FunkinLua.luaTrace('initSaveData: Save file already initialized: ' + name);
		});
		Lua_helper.add_callback(lua, "flushSaveData", function(name:String) {
			var variables = MusicBeatState.getVariables();
			if(variables.exists('save_$name'))
			{
				variables.get('save_$name').flush();
				return;
			}
			FunkinLua.luaTrace('flushSaveData: Save file not initialized: ' + name, false, false, FlxColor.RED);
		});
		Lua_helper.add_callback(lua, "getDataFromSave", function(name:String, field:String, ?defaultValue:Dynamic = null) {
			var variables = MusicBeatState.getVariables();
			if(variables.exists('save_$name'))
			{
				var saveData = variables.get('save_$name').data;
				if(Reflect.hasField(saveData, field))
					return Reflect.field(saveData, field);
				else
					return defaultValue;
			}
			FunkinLua.luaTrace('getDataFromSave: Save file not initialized: ' + name, false, false, FlxColor.RED);
			return defaultValue;
		});
		Lua_helper.add_callback(lua, "setDataFromSave", function(name:String, field:String, value:Dynamic) {
			var variables = MusicBeatState.getVariables();
			if(variables.exists('save_$name'))
			{
				Reflect.setField(variables.get('save_$name').data, field, value);
				return;
			}
			FunkinLua.luaTrace('setDataFromSave: Save file not initialized: ' + name, false, false, FlxColor.RED);
		});
		Lua_helper.add_callback(lua, "eraseSaveData", function(name:String)
		{
			var variables = MusicBeatState.getVariables();
			if (variables.exists('save_$name'))
			{
				variables.get('save_$name').erase();
				return;
			}
			FunkinLua.luaTrace('eraseSaveData: Save file not initialized: ' + name, false, false, FlxColor.RED);
		});

		// File management
		Lua_helper.add_callback(lua, "checkFileExists", function(filename:String, ?absolute:Bool = false) {
			#if MODS_ALLOWED
			if(absolute) return FileSystem.exists(filename);

			return FileSystem.exists(Paths.getPath(filename, TEXT));

			#else
			if(absolute) return Assets.exists(filename, TEXT);

			return Assets.exists(Paths.getPath(filename, TEXT));
			#end
		});
		Lua_helper.add_callback(lua, "saveFile", function(path:String, content:String, ?absolute:Bool = false)
		{
			try {
				#if MODS_ALLOWED
				if(!absolute)
					File.saveContent(Paths.mods(path), content);
				else
				#end
					File.saveContent(path, content);

				return true;
			} catch (e:Dynamic) {
				FunkinLua.luaTrace("saveFile: Error trying to save " + path + ": " + e, false, false, FlxColor.RED);
			}
			return false;
		});
		Lua_helper.add_callback(lua, "deleteFile", function(path:String, ?ignoreModFolders:Bool = false, ?absolute:Bool = false)
		{
			try {
				var lePath:String = path;
				if(!absolute) lePath = Paths.getPath(path, TEXT, !ignoreModFolders);
				if(FileSystem.exists(lePath))
				{
					FileSystem.deleteFile(lePath);
					return true;
				}
			} catch (e:Dynamic) {
				FunkinLua.luaTrace("deleteFile: Error trying to delete " + path + ": " + e, false, false, FlxColor.RED);
			}
			return false;
		});
		Lua_helper.add_callback(lua, "getTextFromFile", function(path:String, ?ignoreModFolders:Bool = false) {
			return Paths.getTextFromFile(path, ignoreModFolders);
		});
		Lua_helper.add_callback(lua, "directoryFileList", function(folder:String) {
			var list:Array<String> = [];
			#if sys
			if(FileSystem.exists(folder)) {
				for (folder in Paths.readDirectory(folder)) {
					if (!list.contains(folder)) {
						list.push(folder);
					}
				}
			}
			#end
			return list;
		});

		// String tools
		Lua_helper.add_callback(lua, "stringStartsWith", function(str:String, start:String) {
			return str.startsWith(start);
		});
		Lua_helper.add_callback(lua, "stringEndsWith", function(str:String, end:String) {
			return str.endsWith(end);
		});
		Lua_helper.add_callback(lua, "stringSplit", function(str:String, split:String) {
			return str.split(split);
		});
		Lua_helper.add_callback(lua, "stringTrim", function(str:String) {
			return str.trim();
		});

		// Randomization
		Lua_helper.add_callback(lua, "getRandomInt", function(min:Int, max:Int = FlxMath.MAX_VALUE_INT, exclude:String = '') {
			var excludeArray:Array<String> = exclude.split(',');
			var toExclude:Array<Int> = [];
			for (i in 0...excludeArray.length)
			{
				if (exclude == '') break;
				toExclude.push(Std.parseInt(excludeArray[i].trim()));
			}
			return FlxG.random.int(min, max, toExclude);
		});
		Lua_helper.add_callback(lua, "getRandomFloat", function(min:Float, max:Float = 1, exclude:String = '') {
			var excludeArray:Array<String> = exclude.split(',');
			var toExclude:Array<Float> = [];
			for (i in 0...excludeArray.length)
			{
				if (exclude == '') break;
				toExclude.push(Std.parseFloat(excludeArray[i].trim()));
			}
			return FlxG.random.float(min, max, toExclude);
		});
		Lua_helper.add_callback(lua, "getRandomBool", function(chance:Float = 50) {
			return FlxG.random.bool(chance);
		});

		// Launch External EXE (Windows only)
		// 首先尝试在模组包中查找 exe 文件，如果没有找到则使用传入的路径
		Lua_helper.add_callback(lua, "launchExternalExe", function(exePath:String, ?args:String = null, ?waitForExit:Bool = false, ?windowMode:Int = 0, ?activateMainWindow:Bool = true):Bool {
			#if (cpp && windows)
				#if MODS_ALLOWED
				// 尝试在模组包中查找 exe 文件
				var modExePath:String = Paths.modFolders(exePath);
				if (FileSystem.exists(modExePath)) {
					return backend.Native.launchExternalExe(modExePath, args, waitForExit, windowMode, activateMainWindow);
				}
				#end
				// 如果模组包中没有找到，使用传入的原始路径
				return backend.Native.launchExternalExe(exePath, args, waitForExit, windowMode, activateMainWindow);
			#else
				FunkinLua.luaTrace("launchExternalExe: This function is only available on Windows!", false, false, FlxColor.RED);
				return false;
			#end
		});

		// ============ D 类：数学/向量工具函数 ============

		Lua_helper.add_callback(lua, "distance", function(a:Dynamic, b:Dynamic, ?c:Dynamic = null, ?d:Dynamic = null):Float {
			if (c != null && d != null)
			{
				var dx:Float = c - a;
				var dy:Float = d - b;
				return Math.sqrt(dx * dx + dy * dy);
			}
			var obj1:FlxObject = LuaUtils.getObjectDirectly(a);
			var obj2:FlxObject = LuaUtils.getObjectDirectly(b);
			if (obj1 != null && obj2 != null)
			{
				// 不用 getMidpoint()，直接用 x/y 计算，避免 Haxe 编译器类型转换问题
				var dx:Float = obj1.x - obj2.x;
				var dy:Float = obj1.y - obj2.y;
				return Math.sqrt(dx * dx + dy * dy);
			}
			var dx2:Float = b - a;
			return Math.sqrt(dx2 * dx2);
		});

		Lua_helper.add_callback(lua, "angleBetween", function(a:Dynamic, b:Dynamic, ?c:Dynamic = null, ?d:Dynamic = null):Float {
			if (c != null && d != null)
				return Math.atan2(d - b, c - a) * 180 / Math.PI;
			var obj1:FlxObject = LuaUtils.getObjectDirectly(a);
			var obj2:FlxObject = LuaUtils.getObjectDirectly(b);
			if (obj1 != null && obj2 != null)
			{
				// 直接用 x/y 计算角度，避免 Haxe 编译器类型转换问题
				return Math.atan2(obj2.y - obj1.y, obj2.x - obj1.x) * 180 / Math.PI;
			}
			return 0;
		});

		Lua_helper.add_callback(lua, "lerp", function(a:Float, b:Float, t:Float):Float {
			return a + (b - a) * t;
		});

		Lua_helper.add_callback(lua, "clamp", function(v:Float, min:Float, max:Float):Float {
			if (v < min) return min;
			if (v > max) return max;
			return v;
		});

		Lua_helper.add_callback(lua, "makeFlxPoint", function(x:Float = 0, y:Float = 0):openfl.geom.Point {
			return new openfl.geom.Point(x, y);
		});

		Lua_helper.add_callback(lua, "hueShift", function(color:String, amount:Float):String {
			var c:FlxColor = CoolUtil.colorFromString(color);
			var r:Float = c.red / 255;
			var g:Float = c.green / 255;
			var bl:Float = c.blue / 255;
			var maxVal:Float = Math.max(r, Math.max(g, bl));
			var minVal:Float = Math.min(r, Math.min(g, bl));
			var d:Float = maxVal - minVal;
			var h:Float = 0;
			if (d != 0)
			{
				if (maxVal == r) h = ((g - bl) / d) % 6;
				else if (maxVal == g) h = ((bl - r) / d) + 2;
				else h = ((r - g) / d) + 4;
				h *= 60;
				if (h < 0) h += 360;
			}
			var s:Float = maxVal == 0 ? 0 : d / maxVal;
			var v:Float = maxVal;
			h = (h + amount + 360) % 360;
			var c2:Float = v * s;
			var x2:Float = c2 * (1 - Math.abs((h / 60) % 2 - 1));
			var m:Float = v - c2;
			var rp:Float = 0, gp:Float = 0, bp:Float = 0;
			if (h < 60) { rp = c2; gp = x2; }
			else if (h < 120) { rp = x2; gp = c2; }
			else if (h < 180) { gp = c2; bp = x2; }
			else if (h < 240) { gp = x2; bp = c2; }
			else if (h < 300) { rp = x2; bp = c2; }
			else { rp = c2; bp = x2; }
			return FlxColor.fromRGB(Std.int((rp + m) * 255), Std.int((gp + m) * 255), Std.int((bp + m) * 255)).toHexString(false, false);
		});

		// ============ G 类：其他实用函数 ============

		Lua_helper.add_callback(lua, "getFPS", function():Float {
			// Flixel 5.9.0 的 FlxG 没有 fps 字段，用帧间隔估算
			return FlxG.elapsed > 0 ? 1.0 / FlxG.elapsed : 0.0;
		});

		// Flixel 5.9.0 的 FlxG 没有帧计数字段，用 ExtraFunctions.frameCount 统计
		Lua_helper.add_callback(lua, "getFrameCount", function():Int {
			return ExtraFunctions.frameCount;
		});

		Lua_helper.add_callback(lua, "getPlayingCharacterAnim", function(character:String):String {
			var game:PlayState = PlayState.instance;
			if (game == null) return '';
			var char:Character = switch(character.toLowerCase()) {
				case 'dad' | 'opponent': game.dad;
				case 'gf' | 'girlfriend': game.gf;
				default: game.boyfriend;
			};
			if (char != null && char.animation != null && char.animation.curAnim != null)
				return char.animation.curAnim.name;
			return '';
		});

		Lua_helper.add_callback(lua, "characterExists", function(name:String):Bool {
			#if MODS_ALLOWED
			var paths:Array<String> = [
				Paths.getPath('characters/' + name + '.xml'),
				Paths.modFolders('characters/' + name + '.xml'),
				Paths.getSharedPath('characters/' + name + '.xml'),
				Paths.getSharedPath('characters/' + name + '.txt'),
				Paths.modFolders('characters/' + name + '.txt')
			];
			for (p in paths) if (FileSystem.exists(p)) return true;
			return false;
			#else
			var xmlPath:String = Paths.getPath('characters/' + name + '.xml');
			var txtPath:String = Paths.getPath('characters/' + name + '.txt');
			return Assets.exists(xmlPath) || Assets.exists(txtPath);
			#end
		});
	}

	/**
	 * 检测指定物理键名是否被某个额外键绑定，返回该额外键按钮的状态。
	 * @param name     物理键名（大写）
	 * @param mode     0=justPressed, 1=pressed, 2=justReleased
	 */
	public static function checkExtraKeyState(name:String, mode:Int):Bool
	{
		if (MusicBeatState.getState().mobileControls == null) return false;

		var mc = MusicBeatState.getState().mobileControls;
		var keyReturns:Array<String> = [
			ClientPrefs.data.extraKeyReturn1, ClientPrefs.data.extraKeyReturn2,
			ClientPrefs.data.extraKeyReturn3, ClientPrefs.data.extraKeyReturn4
		];
		var btns:Array<Dynamic> = [mc.buttonExtra, mc.buttonExtra2, mc.buttonExtra3, mc.buttonExtra4];

		for (i in 0...4)
		{
			if (btns[i] == null) continue;
			if (name == keyReturns[i].toUpperCase())
			{
				switch (mode)
				{
					case 0: return btns[i].justPressed;
					case 1: return btns[i].pressed;
					case 2: return btns[i].justReleased;
				}
			}
		}
		return false;
	}
}
