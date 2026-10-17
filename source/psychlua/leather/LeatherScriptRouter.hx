#if LUA_ALLOWED
package psychlua.leather;

import backend.ClientPrefs;

/**
 * Leather Engine 脚本 API 兼容路由。
 *
 * 背景：
 *   LE（Leather Engine）的 mod 脚本是 lua 文件（mods/{mod}/scripts/*.lua），
 *   调用的是 LE 自己的一套 API（见 LE 源码 ModchartUtilities.hx / LuaScript.hx），
 *   与 Psych 的 FunkinLua API 函数名/全局变量名不同。
 *
 * 本路由负责：
 *   1. 读 ClientPrefs.leatherScriptCompat 设置（off/auto/official/lts）
 *   2. 结合当前谱面 format（LEATHER / LEATHER LTS），决定是否加载 LE 脚本层、
 *      以及用 Official 系还是 LTS 系 API。
 *
 * LE 原版参考：
 *   Official 0.5.0 : D:\VibeCode\LeatherEngine-Official\source\modding\ModchartUtilities.hx
 *   LTS  1.1.9    : D:\VibeCode\LeatherEngine-LTS\LeatherEngine-main\source\modding\scripts\languages\LuaScript.hx
 */
class LeatherScriptRouter
{
	public static final MODE_OFF:String = 'off';
	public static final MODE_AUTO:String = 'auto';
	public static final MODE_OFFICIAL:String = 'official';
	public static final MODE_LTS:String = 'lts';

	public static final MODES:Array<String> = [MODE_OFF, MODE_AUTO, MODE_OFFICIAL, MODE_LTS];

	/** 谱面 format：Official 系 */
	public static final FMT_LEATHER:String = 'LEATHER';
	/** 谱面 format：LTS 系 */
	public static final FMT_LEATHER_LTS:String = 'LEATHER LTS';

	/** 设置原始值（非法时回落 auto）。 */
	public static function rawMode():String
	{
		var v:String = ClientPrefs.data.leatherScriptCompat;
		if (v == null || MODES.indexOf(v) < 0)
			return MODE_AUTO;
		return v;
	}

	/**
	 * 当前谱面是否应启用 LE 脚本层。
	 * @param chartFormat  当前谱面的 format 字段（Song.format，可能为 null/Psych 空串）
	 */
	public static function isActive(chartFormat:String):Bool
	{
		var m:String = rawMode();
		if (m == MODE_OFF)
			return false;
		if (m == MODE_OFFICIAL || m == MODE_LTS)
			return true; // 强制启用：非 off 即加载（强制模式下即使谱面是 Psych 也尝试？保守：仍要求是 LE 谱面）
		// auto：仅当谱面确实是 LE 谱面时启用
		return isLeatherChart(chartFormat);
	}

	/** 谱面 format 是否为 LE 系（Official 或 LTS）。 */
	public static function isLeatherChart(chartFormat:String):Bool
	{
		if (chartFormat == null)
			return false;
		return chartFormat == FMT_LEATHER || chartFormat == FMT_LEATHER_LTS;
	}

	/**
	 * 解析实际生效的 API 版本：official / lts。
	 * auto 模式按谱面 format 判定；强制模式按设置。
	 */
	public static function resolveVersion(chartFormat:String):String
	{
		var m:String = rawMode();
		if (m == MODE_OFFICIAL)
			return MODE_OFFICIAL;
		if (m == MODE_LTS)
			return MODE_LTS;
		// auto：按谱面
		if (chartFormat == FMT_LEATHER_LTS)
			return MODE_LTS;
		// 默认（含 FMT_LEATHER 与未知）走 Official 系（REC 0.4.x 属此系）
		return MODE_OFFICIAL;
	}
}
#end
