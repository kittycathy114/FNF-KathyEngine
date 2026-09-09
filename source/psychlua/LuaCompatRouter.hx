package psychlua;

import backend.ClientPrefs;

/**
 * Lua API 兼容版本路由：
 *  - '1.0.4'  -> KathyEngine 原生行为（默认）
 *  - '0.7.3'  -> 兼容 PE 0.7.3 旧脚本（默认参数与 0.7.3 一致）
 *  - '0.6.3'  -> 兼容 PE 0.6.3 旧脚本（默认参数与 0.6.3 一致）
 *  - 'auto'   -> 暂时回落到 1.0.4（未来可扩展自动识别）
 *
 * 仿照 source/states/editors/ChartingRouter.hx 的设计。
 */
class LuaCompatRouter
{
	public static final VERSION_1_0_4:String = '1.0.4';
	public static final VERSION_0_7_3:String = '0.7.3';
	public static final VERSION_0_6_3:String = '0.6.3';
	public static final VERSION_AUTO:String = 'auto';

	public static final VERSIONS:Array<String> =
		[VERSION_1_0_4, VERSION_0_7_3, VERSION_0_6_3, VERSION_AUTO];

	/** 解析出实际生效的兼容版本（'auto' 暂时映射为 1.0.4）。 */
	public static function resolveVersion():String
	{
		var v:String = ClientPrefs.data.luaCompatVersion;
		if (v == null || VERSIONS.indexOf(v) < 0)
			return VERSION_1_0_4;
		if (v == VERSION_AUTO)
			return VERSION_1_0_4;
		return v;
	}

	/** setObjectCamera 默认 camera 字符串。0.6.3/0.7.3 是空字符串，1.0.4 是 'game'。 */
	public static function defaultCamera():String
	{
		return switch (resolveVersion())
		{
			case VERSION_0_6_3, VERSION_0_7_3: '';
			default: 'game';
		};
	}

	/** doTween* / noteTween* 默认 ease 字符串。0.6.3/0.7.3 旧版无默认值（必填），1.0.4 是 'linear'。 */
	public static function defaultEase():String
	{
		return switch (resolveVersion())
		{
			case VERSION_0_6_3, VERSION_0_7_3: null;
			default: 'linear';
		};
	}

	/**
	 * 在 doTween* / noteTween* 函数入口处调用，把 null ease 解析为当前兼容版本下的默认值；
	 * 若默认值仍为 null（0.6.3/0.7.3 模式下未传 ease），最终回落到 'linear'，
	 * 以保持运行时可行性（旧版无默认但脚本通常都会传值）。
	 */
	public static function resolveEase(?ease:String):String
	{
		if (ease != null) return ease;
		var def:String = defaultEase();
		return def != null ? def : 'linear';
	}

	/** makeAnimatedLuaSprite / makeLuaSprite 默认 spriteType。0.6.3/0.7.3 是 'sparrow'，1.0.4 是 'auto'。 */
	public static function defaultSpriteType():String
	{
		return switch (resolveVersion())
		{
			case VERSION_0_6_3, VERSION_0_7_3: 'sparrow';
			default: 'auto';
		};
	}

	/** setHealth 默认 value。0.6.3 是 0，0.7.3/1.0.4 是 1。 */
	public static function defaultHealth():Float
	{
		return resolveVersion() == VERSION_0_6_3 ? 0 : 1;
	}

	/** mouseClicked/Pressed/Released 默认 button。0.6.3/0.7.3 必填无默认，1.0.4 是 'left'。 */
	public static function defaultMouseButton():String
	{
		return switch (resolveVersion())
		{
			case VERSION_0_6_3, VERSION_0_7_3: null;
			default: 'left';
		};
	}

	/** getMouseX/Y 默认 camera。0.6.3/0.7.3 必填无默认，1.0.4 是 'game'。 */
	public static function defaultMouseCamera():String
	{
		return switch (resolveVersion())
		{
			case VERSION_0_6_3, VERSION_0_7_3: null;
			default: 'game';
		};
	}

	/** keyJustPressed/Pressed/Released 默认 name。0.6.3 必填无默认，0.7.3/1.0.4 是空字符串。 */
	public static function defaultKeyName():String
	{
		return switch (resolveVersion())
		{
			case VERSION_0_6_3: null;
			default: '';
		};
	}

	/** precacheImage 是否支持 allowGPU 参数（仅 1.0.4 支持）。 */
	public static function supportsAllowGPU():Bool
	{
		return resolveVersion() == VERSION_1_0_4;
	}
}
