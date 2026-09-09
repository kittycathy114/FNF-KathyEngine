package psychlua;

import flixel.util.FlxSave;
import openfl.utils.Assets;
#if sys
import sys.FileSystem;
#end
import backend.Paths;

//
// Things to trivialize some dumb stuff like splitting strings on older Lua
//

class ExtraFunctions
{
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
