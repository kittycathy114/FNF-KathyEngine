package options;

import flixel.text.FlxText;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxTimer;

class ExtraGameplaySettingSubState extends BaseOptionsMenu
{
	var errorText:FlxText = null;
	var errorBg:FlxSprite = null;
	var errorTimer:FlxTimer = null;

	public function new()
	{
		title = 'Extra Options\n\nNot Done';
		rpcTitle = 'Extra Gameplay Settings Menu'; //for Discord Rich Presence

		// BOOL 类型设置
		var option:Option = new Option('show Game Version',
			Language.get("show_version_desc"),
			'exgameversion',
			BOOL);
		option.onChange = function() {
			if(Main.fpsVar != null) {
				Main.fpsVar.updateText();
			}
		};
		addOption(option);

		/*Psych Engine v1.0.4已经有这个了，故隐藏此项
		option = new Option('Focus Game',
			Language.get("focus_game_desc"),
			'autoPause',
			BOOL);
		addOption(option);
		*/
		option = new Option('Show Extra-Rating',
			Language.get("show_exrating_desc"),
			'exratingDisplay',
			BOOL);
		addOption(option);

		option = new Option('Rating Bounce',
			Language.get("rating_bounce_desc"),
			'ratbounce',
			BOOL);
		addOption(option);

		option = new Option('Extra-Rating Bounce',
			Language.get("exrating_bounce_desc"),
			'exratbounce',
			BOOL);
		addOption(option);

		option = new Option('Remove Perfect! Note Judgement',
			Language.get("rm_perfect_judge_desc"),
			'rmPerfect',
			BOOL);
		addOption(option);

		option = new Option('Remove the "ms" offset',
			Language.get("rm_ms_offset_desc"),
			'rmmsTimeTxt',
			BOOL);

		addOption(option);
		option = new Option('Show NPS',
			Language.get("nps_desc"),
			'showNPS',
			BOOL);
		addOption(option);

		option = new Option('ScoreTxt bounce',
			Language.get("scoretxt_bounce_desc"),
			'scoretxtbounce',
			BOOL);
		addOption(option);

		option = new Option('Single Note Splash Anim',
			Language.get("single_splashanim_desc"),
			'forceSingleSplashAnim',
			BOOL);
		addOption(option);

		option = new Option('smooth HP Bar',
			Language.get("smooth_hpbar_desc"),
			'smoothHP',
			BOOL);
		addOption(option);

		option = new Option('CPU Strums',
			Language.get("cpu_strums_desc"),
			'cpuStrums',
			BOOL);
		addOption(option);

		option = new Option('Legacy Note Position',
			Language.get("legacy_notepos_desc"),
			'legacynotepos',
			BOOL);
		addOption(option);

		option = new Option('Score Incrase When BotPlay',
			Language.get("bot_addscore_desc"),
			'botplayScore',
			BOOL);
		addOption(option);

		option = new Option('Show "Combo" Sprite',
			Language.get("gameplay_combospr_desc"),
			'comboSprDisplay',
			BOOL);
		addOption(option);

		option = new Option('Rating Fall Style',
			Language.get("rating_fall_style_desc"),
			'ratingFallStyle',
			STRING,
			['Simple', 'Legacy', 'MintRhythm', 'MintRhythm(Legacy)']);
		addOption(option);

		option = new Option('Show Event Information',
			Language.get("events_debug_desc"),
			'eventDebug',
			BOOL);
		addOption(option);

		option = new Option('Background Volume',
			Language.get("bgvol_desc"),
			'backgroundVolume',
			BOOL);
		addOption(option);

		option = new Option('Fixed Timestep',
			Language.get("fixed_timestep_desc"),
			'fixedTimestep',
			BOOL);
		addOption(option);
		option.onChange = function() {
			FlxG.fixedTimestep = ClientPrefs.data.fixedTimestep;
			trace("Fixed timestep changed to: " + FlxG.fixedTimestep);
		};

		option = new Option('Background Volume Level',
			Language.get("bgvol_level_desc"),
			'backgroundVolumeLevel',
			PERCENT);
		option.scrollSpeed = 2;
		option.minValue = 0;
		option.maxValue = 1;
		option.changeValue = 0.02;
		option.decimals = 2;
		addOption(option);

		option = new Option('Rating Counter',
			Language.get("ratcounter_desc"),
			'ratCounter',
			BOOL);
		addOption(option);

		option = new Option('Show Watermark',
			Language.get("watermark_desc"),
			'waterMarkPlay',
			BOOL);
		addOption(option);

		option = new Option('Enable Game Log Display',
			'Enable in-game log display (Press F3 to toggle)',
			'enableGameLog',
			BOOL);
		option.onChange = function() {
			if(Main.gameLogVar != null) {
				Main.gameLogVar.setEnabled(ClientPrefs.data.enableGameLog);
			}
		};
		addOption(option);

		option = new Option('Mouse Trail Size',
			'Adjust the size of mouse trail effects',
			'mouseTrailSize',
			FLOAT);
		option.displayFormat = '%v X';
		option.scrollSpeed = 1.5;
		option.minValue = 0.5;
		option.maxValue = 5.0;
		option.changeValue = 0.05;
		option.decimals = 2;
		option.onChange = function() {
			Main.setMouseTrailSize(ClientPrefs.data.mouseTrailSize);
		};
		addOption(option);

		option = new Option('Mouse Trail Enabled',
			'Enable mouse trail effects (both PC and Mobile)',
			'mouseTrailEnabled',
			BOOL);
		option.onChange = function() {
			Main.setMouseTrailVisible(ClientPrefs.data.mouseTrailEnabled);
		};
		addOption(option);

	// PERCENT 类型设置
		option = new Option('Ratings Opacity',
			Language.get("rating_opac_desc"),
			'ratingsAlpha',
			PERCENT);
		option.scrollSpeed = 1.6;
		option.minValue = 0.0;
		option.maxValue = 1;
		option.changeValue = 0.1;
		option.decimals = 1;
		addOption(option);

		// STRING 类型设置
		option = new Option('HealthBar Style',
			Language.get("healthbar_style_desc"),
			'healthbarstyle',
			STRING,
			['Psych', 'OS', 'Kade']);
		addOption(option);

		option = new Option('IconBop Style',
			Language.get("iconbop_style_desc"),
			'iconbopstyle',
			STRING,
			['Psych', 'OS', 'MintRhythm', 'Leather', 'SB', 'Vanilla', 'VSlice(New)', 'VSlice(Old)', 'Codename', 'Dave', 'NovaFlare', 'NONE']);
		addOption(option);

		option = new Option('ScoreTxt Style',
			Language.get("scoretxt_style_desc"),
			'scoretxtstyle',
			STRING,
			['Psych', 'OS', 'MintRhythm', 'Kade', 'V-Slice']);
		addOption(option);

		option = new Option('Loading Style',
			Language.get("loading_style_desc"),
			'customFadeStyle',
			STRING,
			['V-Slice', 'NovaFlare Move', 'NovaFlare Alpha', 'MintRhythm', 'BA_Schale_Glow']);
		addOption(option);

		option = new Option('TimeBar Style',
			Language.get("timebar_style_desc"),
			'timebarStyle',
			STRING,
			['default', 'Kade (Legacy)', 'Leather']);
		addOption(option);

		option = new Option('BotPlayTxt Style',
			Language.get("botplaytxt_style_desc"),
			'botplayStyle',
			STRING,
			['Kade', 'Psych']);
		addOption(option);

		option = new Option('ShowCase Style',
			Language.get("showcase_style_desc"),
			'showcaseStyle',
			STRING,
			['Kade', 'Psych']);
		addOption(option);

		/*
		// 修复 FPS 字体选项
		option = new Option('FPS-Counter Font',
			Language.get("fpstxt_style_desc"),
			'fpsFont',
			STRING,
			['default', 'Kade']);
		option.onChange = function() {
			if (Main.fpsVar != null) {
				Main.fpsVar.updateFont(); // 调用字体更新方法
				Main.fpsVar.positionFPS(10, 3); // 重新定位确保布局正确
			}
		};
		addOption(option);*/

		option = new Option('Ratings Position',
			Language.get("ratings_pos_desc"),
			'ratingsPos',
			STRING,
			['camHUD', 'camGame']);
		addOption(option);

		option = new Option('HUD Zoom Speed',
			Language.get("hud_zoomstyle_desc"),
			'hudZoomStyle',
			STRING,
			['default', 'Fast', 'Slow', 'Kade']);
		addOption(option);

		option = new Option('HUD Zoom',
			Language.get("camhud_zoom_desc"),
			'hudSize',
			FLOAT);
		option.displayFormat = '%v X';
		option.scrollSpeed = 1;
		option.minValue = 0.5;
		option.maxValue = 1.2;
		option.changeValue = 0.005;
		option.decimals = 3; //小数点后三位
		addOption(option);

		option = new Option('FPS Position',
			Language.get("fps_position_desc"),
			'fpsPosition',
			STRING,
			['TOP_LEFT', 'TOP_RIGHT', 'BOTTOM_LEFT', 'BOTTOM_RIGHT']);
		option.onChange = function() {
			if(Main.fpsVar != null) {
				Main.fpsVar.positionFPS(10, 3);
			}
		};
		addOption(option);

		option = new Option('FPS Spacing',
			Language.get("fps_spacing_desc"),
			'fpsSpacing',
			INT);
		option.scrollSpeed = 1;
		option.minValue = 0;
		option.maxValue = 200;
		option.changeValue = 5;
		option.onChange = function() {
			if(Main.fpsVar != null) {
				Main.fpsVar.positionFPS(10, 3);
			}
		};
		addOption(option);

		// 语言设置放在最后
		option = new Option("Engine Language",
			Language.get("change_language_desc"),
			'language',
			STRING,
			["en_us", "zh_cn", "zh_tw"]);
		option.onChange = function() {
			ClientPrefs.saveSettings();
			Language.load();
			refreshAllTexts();
			
			// 由于父状态在运行,直接获取并刷新
			var parentState = cast(FlxG.state, OptionsState);
			if(parentState != null) {
				parentState.options = [
					Language.get("note_colors"),
					Language.get("controls"),
					Language.get("adjust_delay_combo"),
					Language.get("graphics"),
					Language.get("visuals"), 
					Language.get("gameplay"),
					Language.get("extra_options")
					#if mobile , Language.get("mobile_options") #end
				];
				
				parentState.optionDescriptions = [
					Language.get("note_colors_desc"),
					Language.get("controls_desc"),
					Language.get("adjust_delay_combo_desc"),
					Language.get("graphics_desc"),
					Language.get("visuals_desc"),
					Language.get("gameplay_desc"),
					Language.get("extra_options_desc")
					#if mobile , Language.get("mobile_options_desc") #end
				];
				
				parentState.refreshTexts();
			}
		};
		addOption(option);

		#if !mobile
		option = new Option('Mods Import',
			Language.get("mods_import_desc"),
			'enableModsImport',
			BOOL);
		addOption(option);
		#end

		option = new Option('Use System Cursor',
			Language.get("use_system_cursor_desc"),
			'systemCursor',
			BOOL);
		option.onChange = function() {
			FlxG.mouse.useSystemCursor = ClientPrefs.data.systemCursor;
			ClientPrefs.saveSettings();
		};
		addOption(option);

		super();
	}

	function showError(msg:String)
	{
		if (errorText == null) {
			errorText = new FlxText(0, 0, 400, "", 24);
			errorText.setFormat(Language.get("game_font"), 24, 0xFFFFFFFF, "center");
			errorText.scrollFactor.set();
			errorText.borderStyle = FlxTextBorderStyle.OUTLINE;
			errorText.borderColor = 0xFF000000;
			errorText.alpha = 1;
			errorText.cameras = [FlxG.cameras.list[FlxG.cameras.list.length-1]];
			errorBg = new FlxSprite().makeGraphic(420, 40, 0xFFFF4444);
			errorBg.alpha = 0.85;
			errorBg.scrollFactor.set();
			errorBg.cameras = errorText.cameras;
			add(errorBg);
			add(errorText);
		}
		errorText.text = Language.get("error_title") + ": " + msg;
		errorText.x = FlxG.width - errorText.width - 30;
		errorText.y = 30;
		errorBg.x = errorText.x - 10;
		errorBg.y = errorText.y - 5;
		errorBg.visible = errorText.visible = true;
		if (errorTimer != null) errorTimer.cancel();
		errorTimer = new FlxTimer().start(1.5, function(_) {
			if (errorText != null) errorText.visible = false;
			if (errorBg != null) errorBg.visible = false;
		});
	}

	function onChangeAutoPause()
		FlxG.autoPause = ClientPrefs.data.autoPause;

	override function update(elapsed:Float)
	{
		super.update(elapsed);
	}
}