package backend;

import sys.thread.Mutex;
import sys.io.File;

/**
 * 后台线程预读 PlayState.create() 用到的 Lua / HScript 脚本文件内容，create() 主线程命中缓存避免同步读盘。
 *
 * 设计原则（「只预编译不执行」，最安全）：
 * - 后台线程只做**线程安全的纯 I/O**（读文件内容 / 探存在性），不创建 Lua VM、不编译字节码、不执行脚本顶层、不触发 flixel 回调。
 *   彻底规避后台线程触碰 flixel/渲染上下文的风险（如 `ycbu text.lua` 的 onCreate 访问 cameras 之类）。
 * - Lua：`new FunkinLua(scriptName)` 的 `LuaL.dofile` 会读盘 + 编译 + 执行顶层。低端机上**读盘是大头**（冷 I/O）。
 *   后台把文件内容读进内存后，主线程用 `LuaL.dostring(预读内容)` 代替 `dofile`，跳过同步读盘（编译+执行仍在主线程，语义不变）。
 * - HScript：`new HScript(file)` 的 `File.getContent()` 是同步读盘，后台预读后主线程直接取用缓存文本。
 *
 * 线程安全：Mutex 保护内部 Map，后台写入与主线程读取可并发。
 */
class ScriptPreload
{
	static var _luaContents:Map<String, String> = null;
	static var _hContents:Map<String, String> = null;
	static var _mutex:Mutex = new Mutex();

	/// 取预读的 Lua 文件内容（命中后保留，同一歌曲内可能多次 new FunkinLua 同名脚本）。
	/// 返回 null 表示未命中（主线程走原 dofile 读盘路径）。
	public static function takeLuaContent(scriptName:String)
	{
		_mutex.acquire();
		var content:String = _luaContents != null ? _luaContents.get(scriptName.trim()) : null;
		_mutex.release();
		return content;
	}

	/// 取预读的 HScript 文件内容（命中后保留）。返回 null 表示未命中。
	public static function takeHContent(file:String)
	{
		_mutex.acquire();
		var content:String = _hContents != null ? _hContents.get(file) : null;
		_mutex.release();
		return content;
	}

	/// 后台线程调用：预读 Lua 脚本文件内容（线程安全 I/O，不创建 VM / 不编译 / 不执行）。
	public static function preloadLua(scriptName:String)
	{
		_mutex.acquire();
		_mutex.release();
		try
		{
			if (!FileSystem.exists(scriptName)) return;
			var content:String = File.getContent(scriptName);
			_mutex.acquire();
			if (_luaContents == null) _luaContents = new Map();
			_luaContents.set(scriptName.trim(), content);
			_mutex.release();
		}
		catch (e:Dynamic)
		{
		}
	}

	/// 后台线程调用：预读 HScript 文件内容（线程安全 I/O）。
	public static function preloadHScript(file:String)
	{
		_mutex.acquire();
		_mutex.release();
		try
		{
			if (!FileSystem.exists(file)) return;
			var content:String = File.getContent(file);
			_mutex.acquire();
			if (_hContents == null) _hContents = new Map();
			_hContents.set(file, content);
			_mutex.release();
		}
		catch (e:Dynamic)
		{
		}
	}

	/// 切歌 / 模组切换时调用，清空预读产物，避免跨歌曲误命中。
	public static function invalidate()
	{
		_mutex.acquire();
		_luaContents = null;
		_hContents = null;
		_mutex.release();
	}
}
