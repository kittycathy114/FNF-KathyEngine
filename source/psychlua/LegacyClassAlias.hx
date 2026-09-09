package psychlua;

/**
 * 旧版 Psych Engine (0.6.3 / 0.7.3) 脚本兼容层
 * --------------------------------------------------
 * 新版引擎把核心类拆分进了 `objects.` / `states.` / `backend.` / `substates.` / `shaders.` 等子包，
 * 而旧版 mod 普遍用「顶层短类名」调用，例如：
 *   - `addHaxeLibrary('Note')`              (新版应为 `objects.Note`)
 *   - `getPropertyFromClass('PlayState', ...)` (新版应为 `states.PlayState`)
 *   - `runHaxeCode` 里直接裸写 `new Note()`
 *
 * 这些调用在 `Type.resolveClass('Note')` 时会返回 null，导致旧模组直接失效。
 * 本类维护一份「旧短名 -> 当前全路径」的别名表，所有类解析入口在原生解析失败(null)时
 * 回退到本表，从而让 0.6.3 / 0.7.3 的旧模组无需改写即可运行。
 *
 * 设计原则：
 *   - 仅在 `Type.resolveClass` 返回 null 时才查别名表，新版 mod 的规范写法完全不受影响，可常开。
 *   - 别名解析失败仍返回 null，保留原有「Class not found」报错，不吞错。
 *   - 单一数据源，后续新增旧类名只需改 `aliases` 一处。
 */
class LegacyClassAlias
{
	/**
	 * 旧版(0.6.3/0.7.3) 顶层短类名 -> 当前引擎完整包路径
	 * 仅收录【仍存在、仅包路径变化】的类。已移除/改名的类见下方注释，不在表中。
	 */
	public static final aliases:Map<String, String> = [
		// ---- objects 包 ----
		// Boyfriend 已在 1.0 移除并并入 Character；这里做最佳努力兼容，使旧模组能 new Boyfriend(...) / addHaxeLibrary('Boyfriend')
		'Boyfriend' => 'objects.Character',
		'Note' => 'objects.Note',
		'StrumNote' => 'objects.StrumNote',
		'NoteSplash' => 'objects.NoteSplash',
		'Character' => 'objects.Character',
		'Alphabet' => 'objects.Alphabet',
		'HealthIcon' => 'objects.HealthIcon',
		'BGSprite' => 'objects.BGSprite',
		'AttachedSprite' => 'objects.AttachedSprite',
		'AttachedText' => 'objects.AttachedText',
		// 旧版常用但 KG 放在 objects/ 下的辅助类
		'Bar' => 'objects.Bar',
		'MenuItem' => 'objects.MenuItem',
		'MenuCharacter' => 'objects.MenuCharacter',
		'MusicPlayer' => 'objects.MusicPlayer',
		'TypedAlphabet' => 'objects.TypedAlphabet',
		'CheckboxThingie' => 'objects.CheckboxThingie',
		'AchievementPopup' => 'objects.AchievementPopup',

		// ---- states 包 ----
		'PlayState' => 'states.PlayState',
		'TitleState' => 'states.TitleState',
		'MainMenuState' => 'states.MainMenuState',
		'StoryMenuState' => 'states.StoryMenuState',
		'FreeplayState' => 'states.FreeplayState',
		'AchievementsMenuState' => 'states.AchievementsMenuState',
		'CreditsState' => 'states.CreditsState',
		'FlashingState' => 'states.FlashingState',
		'LoadingState' => 'states.LoadingState',
		'ModsMenuState' => 'states.ModsMenuState',
		// 0.6.3 的旧 ChartingState 被移入 `states.editors.ChartingState`
		'ChartingState' => 'states.editors.ChartingState',

		// ---- substates 包 ----
		'GameOverSubstate' => 'substates.GameOverSubstate',
		'PauseSubState' => 'substates.PauseSubState',
		'ResetScoreSubState' => 'substates.ResetScoreSubState',
		// 旧版 OutdatedState 在 KG 中重命名为 OutdatedSubState
		'OutdatedState' => 'substates.OutdatedSubState',

		// ---- options 包 ----
		// GameplayChangersSubstate 旧版在 substates/，KG 移到了 options/
		'GameplayChangersSubstate' => 'options.GameplayChangersSubstate',
		'OptionsState' => 'options.OptionsState',
		'BaseOptionsMenu' => 'options.BaseOptionsMenu',

		// ---- backend 包 ----
		'Conductor' => 'backend.Conductor',
		'Paths' => 'backend.Paths',
		'ClientPrefs' => 'backend.ClientPrefs',
		'CoolUtil' => 'backend.CoolUtil',
		'MusicBeatState' => 'backend.MusicBeatState',
		'Mods' => 'backend.Mods',
		'ModManager' => 'backend.Mods',     // 0.6.3 的 ModManager 已并入 backend.Mods，旧模组多为该名
		'WeekData' => 'backend.WeekData',
		'Song' => 'backend.Song',
		'BaseStage' => 'backend.BaseStage',
		// 旧版常用但原不在别名表中的 backend 类
		'Achievements' => 'backend.Achievements',
		'Controls' => 'backend.Controls',
		'Highscore' => 'backend.Highscore',
		'Difficulty' => 'backend.Difficulty',
		'Rating' => 'backend.Rating',
		'StageData' => 'backend.StageData',
		'MusicBeatSubstate' => 'backend.MusicBeatSubstate',   // 区别于 MusicBeatState
		'DiscordClient' => 'backend.Discord',                // KG 中类名是 DiscordClient
		'CustomFadeTransition' => 'backend.CustomFadeTransition',
		'InputFormatter' => 'backend.InputFormatter',
		'PsychAnimationController' => 'backend.animation.PsychAnimationController',

		// ---- shaders 包 ----
		'ColorSwap' => 'shaders.ColorSwap',
		'PsychCamera' => 'backend.PsychCamera',
		'WiggleEffect' => 'shaders.WiggleEffect',
		'OverlayShader' => 'shaders.OverlayShader',
		'BlendModeEffect' => 'shaders.BlendModeEffect'
	];

	/**
	 * 解析类：先按原生全路径解析（覆盖新版规范写法），失败(null)再查别名表。
	 * @param name 可能是全路径(如 'objects.Note')，也可能是旧版短名(如 'Note')
	 * @return 解析到的类，或全部失败时为 null
	 */
	public static function resolve(name:String):Dynamic
	{
		var c:Dynamic = Type.resolveClass(name);
		if (c != null)
			return c;

		// 旧版短类名兼容层：可通过设置中「旧版短类名兼容」选项关闭
		if (backend.ClientPrefs.data.enableLegacyClassAlias)
		{
			var alias:String = aliases.get(name);
			if (alias != null)
			{
				c = Type.resolveClass(alias);
				if (c != null)
					return c;
			}
		}
		return null;
	}
}

/*
 * ===================== 已移除 / 改名的旧类（别名层无法救，需模组侧改写） =====================
 *
 * Boyfriend
 *   旧版 `Boyfriend` 类在 1.0 架构已移除，角色统一由 `objects.Character` 处理。
 *   别名表已将其映射到 `objects.Character`，使 `new Boyfriend(...)` / `addHaxeLibrary('Boyfriend')` 能继续工作。
 *   如果旧脚本依赖 Boyfriend 特有的静态字段/类型判断（极少见），仍需手动改写。
 *
 * Section
 *   旧版 `Section` 类已移除，谱面段落数据结构改为 `backend.Song.SwagSection`（嵌套在 Song 内）。
 *   直接引用 `Section` 的脚本需改用 `Song.SwagSection`。
 *
 * ModManager
 *   旧版 0.6.3 的 `ModManager` 已并入 `backend.Mods`。方法名/签名有差异，需按新 API 改写。
 *
 * ColorblindFilter
 *   旧版色盲滤镜类已移除，功能由 `shaders.ColorSwap` 承担（HSV/色盲切换）。
 *
 * Splash
 *   旧版独立 `Splash` 类对应 `objects.NoteSplash`，旧写法需改写。
 *
 * Prompt
 *   旧版 `Prompt` 是独立顶层类；KG 中 `Prompt` 被移入 `states.editors.content.Prompt`，不再是顶层类，
 *   无法通过 `Type.resolveClass('Prompt')` 解析，旧脚本需改用完整路径。
 *
 * GameOverSubstate（0.7.3）
 *   0.7.3 中 `GameOverSubstate` 从顶层移入 `substates/`；KG 保留了该路径所以别名可直接生效。
 *
 * FlxTrail / FlxRuntimeShader / FlxCamera 等
 *   属于 flixel 核心库（如 `flixel.addons.effects.FlxTrail` / `flixel.addons.display.FlxRuntimeShader`），
 *   并非本项目定义；`FlxRuntimeShader` 已在 preset() 中预注册，`FlxCamera` 同理，无需别名。
 *
 * 注意：即便 `Paths` / `Song` / `WeekData` / `Conductor` 等类名通过别名兼容成功解析，
 *      其方法签名与数据结构在 1.0 架构下与 0.6.3 已不同，这部分仍需模组脚本逐处适配。
 */
