package psychlua.compat;

#if LUA_ALLOWED
/**
 * 运行探针（可选「深度检测」）。
 *
 * 把模组 .lua 脚本放进一个【全新独立的沙箱 lua_State】里执行，通过给 _G 设置
 * __index 元方法拦截「对未定义全局名的访问」，从而捕获静态分析抓不到的动态调用
 * （例如 _G["xxx"]、变量拼接调用、条件分支里才出现的调用）。
 *
 * 安全性：
 *  - 独立 state，不接触游戏逻辑/全局状态，执行完立即 Lua.close 释放
 *  - 未定义的全局名返回「可调用、可索引、可迭代的空表桩」，脚本不会因 nil 报错中断
 *  - 整段脚本包在 pcall 里，运行时错误全部吞掉
 *  - 断开 os/io/require/dofile/loadfile 等可能造成副作用或加载外部文件的能力
 *  - 安装指令预算钩子，防止脚本里的死循环卡死游戏
 *
 * 局限：探针只能捕获「实际执行到」的路径；探针结果作为静态结果的补充。
 */
class CompatProbe
{
	public static function run(files:Array<String>):Map<String, Bool>
	{
		var seen:Map<String, Bool> = new Map();
		#if sys
		for (abs in files)
		{
			if (!abs.toLowerCase().endsWith('.lua')) continue;

			var content:String = null;
			try
			{
				content = sys.io.File.getContent(abs);
			}
			catch (e:Dynamic) continue;

			if (content == null || content.length == 0) continue;
			probeOne(content, seen);
		}
		#end
		return seen;
	}

	static function probeOne(content:String, seen:Map<String, Bool>):Void
	{
		var l:State = LuaL.newstate();
		LuaL.openlibs(l);

		// 沙箱预置环境；失败就直接放弃这个文件
		if (LuaL.dostring(l, PRELUDE) != 0)
		{
			Lua.close(l);
			return;
		}

		// 包在 pcall 里执行，脚本内的任何错误都不会抛出到引擎
		LuaL.dostring(l, 'pcall(function()\n' + content + '\nend)');

		// 读取 __compatSeen 表里记录下来的全局名
		Lua.getglobal(l, '__compatSeen');
		if (Lua.type(l, -1) == Lua.LUA_TTABLE)
		{
			Lua.pushnil(l);
			while (Lua.next(l, -2) != 0)
			{
				if (Lua.type(l, -2) == Lua.LUA_TSTRING)
				{
					var k:String = Lua.tostring(l, -2);
					if (k != null && k != '') seen.set(k, true);
				}
				Lua.pop(l, 1);
			}
			Lua.pop(l, 1); // 弹出 table
		}
		else
		{
			Lua.pop(l, 1);
		}

		Lua.close(l);
	}

	// 沙箱预置脚本（用数组拼装，避免 Haxe 多行字符串限制）
	static var PRELUDE:String = [
		'local _seen = {}',
		'rawset(_G, "__compatSeen", _seen)',
		'',
		'-- 返回一个「可调用/可索引/可迭代」的空表桩，尽量让脚本继续往下跑',
		'local _mk',
		'_mk = function(k)',
		'\tif type(k) == "string" and k ~= "" then _seen[k] = true end',
		'\tlocal mt = {}',
		'\tmt.__index = function(_, kk) return _mk(kk) end',
		'\tmt.__newindex = function() end',
		'\tmt.__call = function() return _mk(nil) end',
		'\tmt.__len = function() return 0 end',
		'\tmt.__tostring = function() return "" end',
		'\tmt.__concat = function() return "" end',
		'\tmt.__add = function() return 0 end',
		'\tmt.__sub = function() return 0 end',
		'\tmt.__mul = function() return 1 end',
		'\tmt.__div = function() return 1 end',
		'\tmt.__mod = function() return 0 end',
		'\tmt.__pow = function() return 1 end',
		'\tmt.__unm = function() return 0 end',
		'\tmt.__eq = function() return false end',
		'\tmt.__lt = function() return false end',
		'\tmt.__le = function() return false end',
		'\treturn setmetatable({}, mt)',
		'end',
		'setmetatable(_G, {__index = function(_, k) return _mk(k) end})',
		'',
		'-- 断开可能造成副作用的库',
		'if os then',
		'\tos.exit = function() end',
		'\tos.execute = function() end',
		'\tos.remove = function() end',
		'\tos.rename = function() end',
		'\tos.tmpname = function() return "" end',
		'end',
		'if io then',
		'\tio.open = function() return nil end',
		'\tio.popen = function() return nil end',
		'\tio.write = function() end',
		'\tio.read = function() return nil end',
		'end',
		'rawset(_G, "require", nil)',
		'rawset(_G, "dofile", nil)',
		'rawset(_G, "loadfile", nil)',
		'',
		'-- 指令预算：每 20000 条指令检查一次，超过约 1000 万条就中止该脚本',
		'do',
		'\tlocal n = 0',
		'\tpcall(function()',
		'\t\tdebug.sethook(function() n = n + 1 if n > 500 then error("probe: instruction budget exceeded") end end, "", 20000)',
		'\tend)',
		'end',
		'rawset(_G, "debug", nil)'
	].join('\n');
}
#end
