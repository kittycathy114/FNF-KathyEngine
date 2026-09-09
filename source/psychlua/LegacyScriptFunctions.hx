package psychlua;

//
// Legacy script-function compatibility layer for mods written against older
// Psych Engine versions (0.6.3 / 0.7.3).
//
// These global functions existed in old versions but were removed or renamed
// when the engine moved to the 1.0-based architecture. They are registered
// here (additive, zero-risk) so old mods keep working without edits.
//
// Note: runHaxeCode / addHaxeLibrary on the LUA side are NOT bridged here, but they
// DO work from Lua already (registered via FunkinLua/HScript::addLocalCallback so they
// surface as global Lua callbacks). No action needed; this note just documents that.
// Note: doTweenZoom 2nd arg semantics changed (object -> camera) in 1.0.4;
// legacy mode overrides it with the old object-based behavior (see doTweenZoom block below).
//

class LegacyScriptFunctions
{
	public static function implement(funk:FunkinLua)
	{
		var lua:State = funk.lua;
		var game:PlayState = PlayState.instance;

		// 0.6.3 used `changePresence`, current renamed it to `changeDiscordPresence`.
		// Both delegate to DiscordClient.changePresence with the same scatter params,
		// so the old name is just an alias.
		#if DISCORD_ALLOWED
		Lua_helper.add_callback(lua, "changePresence", function(details:String, ?state:String, ?smallImageKey:String, ?hasStartTimestamp:Bool, ?endTimestamp:Float) {
			DiscordClient.changePresence(details, state, smallImageKey, hasStartTimestamp, endTimestamp);
		});
		#end

		// 0.6.3 / 0.7.3 cross-script global read/write, removed in current.
		// Re-implemented by locating the target script in the running lua array.
		Lua_helper.add_callback(lua, "getGlobalFromScript", function(luaFile:String, global:String):Dynamic {
			if(game == null) return null;
			for (inst in game.luaArray) {
				if(inst.scriptName == luaFile || inst.scriptName.endsWith(luaFile)) {
					if(inst.lua == null) return null;
					Lua.getglobal(inst.lua, global);
					var result:Dynamic = Convert.fromLua(inst.lua, -1);
					Lua.pop(inst.lua, 1);
					return result;
				}
			}
			return null;
		});

		Lua_helper.add_callback(lua, "setGlobalFromScript", function(luaFile:String, global:String, val:Dynamic) {
			if(game == null) return;
			for (inst in game.luaArray) {
				if(inst.scriptName == luaFile || inst.scriptName.endsWith(luaFile)) {
					inst.set(global, val);
				}
			}
		});

		// 更早期 PE (0.4/0.5) 的静态类属性链访问 API（参数为逗号分隔的 "Class,a,b,c"），
		// 0.6.3 起已在官方源码中被注释禁用，1.0.4 完全移除。
		// 补回以兼容极老脚本；仅在旧版兼容模式下注册。
		if(LuaCompatRouter.isLegacy())
		{
			Lua_helper.add_callback(lua, "getPropertyAdvanced", function(varsStr:String) {
				var variables:Array<String> = varsStr.replace(' ', '').split(',');
				var leClass:Class<Dynamic> = Type.resolveClass(variables[0]);
				if(variables.length > 2) {
					var curProp:Dynamic = Reflect.getProperty(leClass, variables[1]);
					if(variables.length > 3) {
						for (i in 2...variables.length-1)
							curProp = Reflect.getProperty(curProp, variables[i]);
					}
					return Reflect.getProperty(curProp, variables[variables.length-1]);
				} else if(variables.length == 2) {
					return Reflect.getProperty(leClass, variables[variables.length-1]);
				}
				return null;
			});

			Lua_helper.add_callback(lua, "setPropertyAdvanced", function(varsStr:String, value:Dynamic) {
				var variables:Array<String> = varsStr.replace(' ', '').split(',');
				var leClass:Class<Dynamic> = Type.resolveClass(variables[0]);
				if(variables.length > 2) {
					var curProp:Dynamic = Reflect.getProperty(leClass, variables[1]);
					if(variables.length > 3) {
						for (i in 2...variables.length-1)
							curProp = Reflect.getProperty(curProp, variables[i]);
					}
					Reflect.setProperty(curProp, variables[variables.length-1], value);
				} else if(variables.length == 2) {
					Reflect.setProperty(leClass, variables[variables.length-1], value);
				}
			});

			// 旧版 PE (0.6.3/0.7.3) 兼容：doTweenZoom 第2参是对象名，zoom该对象的缩放比例；
			// 1.0.4 改为第2参=camera名，zoom相机本身。老脚本传入对象名时会因误匹配 camera 而行为异常，
			// 故在 legacy 模式用同名回调覆盖，保持旧语义。
			Lua_helper.add_callback(lua, "doTweenZoom", function(tag:String, obj:String, value:Dynamic, duration:Float, ?ease:String = null) {
				ease = LuaCompatRouter.resolveEase(ease);
				funk.oldTweenFunction(tag, obj, {zoom: value}, duration, ease, 'doTweenZoom');
			});

			// 旧版 PE (0.6.3/0.7.3) 兼容：keyJustPressed/KeyPressed/Released 只认 left/down/up/right 四个音符键，
			// 不认识自定义物理键（accept/back 等）也不会额外键绑定。当前版本支持自定义键会导致老 mod 响应错误输入。
			// 注意：旧版默认 key 为空字符串，此处复用 LuaCompatRouter.defaultKeyName() 保持一致。
			Lua_helper.add_callback(lua, "keyJustPressed", function(?name:String = null) {
				if (name == null) name = LuaCompatRouter.defaultKeyName();
				if (name == null) name = '';
				name = name.toLowerCase().trim();
				switch(name) {
					case 'left': return PlayState.instance.controls.NOTE_LEFT_P;
					case 'down': return PlayState.instance.controls.NOTE_DOWN_P;
					case 'up': return PlayState.instance.controls.NOTE_UP_P;
					case 'right': return PlayState.instance.controls.NOTE_RIGHT_P;
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
				}
				return false;
			});

			// 旧版 PE (0.6.3/0.7.3) 兼容：addAnimationByIndices 内部固定 loop=true，
			// 1.0.4 改为参数默认 loop=false，导致老 mod 制作的非循环动画意外循环播放。
			// addAnimationByPrefixes 三个版本均未实现，跳过。
			Lua_helper.add_callback(lua, "addAnimationByIndices", function(obj:String, name:String, prefix:String, indices:Any, framerate:Float = 24, ?loop:Bool = null) {
				if (loop == null) loop = true; // legacy: always loop
				return LuaUtils.addAnimByIndices(obj, name, prefix, indices, framerate, loop);
			});
		}
	}
}
