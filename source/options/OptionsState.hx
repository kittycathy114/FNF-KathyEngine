package options;

import states.MainMenuState;
import backend.StageData;
import flixel.FlxG;
import flixel.math.FlxMath;
import flixel.tweens.FlxTween;
import flixel.input.mouse.FlxMouse;

class OptionsState extends MusicBeatState
{
	public var options:Array<String> = [
		Language.get("note_colors"),
		Language.get("controls"),
		Language.get("adjust_delay_combo"),
		Language.get("graphics"),
		Language.get("visuals"),
		Language.get("gameplay"),
		Language.get("extra_options")
		//#if TRANSLATIONS_ALLOWED , Language.get("language") #end
		#if mobile , Language.get("mobile_options") #end
	];
	
	public var optionDescriptions:Array<String> = [
		Language.get("note_colors_desc"),
		Language.get("controls_desc"),
		Language.get("adjust_delay_combo_desc"),
		Language.get("graphics_desc"),
		Language.get("visuals_desc"),
		Language.get("gameplay_desc"),
		Language.get("extra_options_desc")
		#if mobile , Language.get("mobile_options_desc") #end
	];
	
	private var grpOptions:FlxTypedGroup<FlxText>;
	private static var curSelected:Int = 0;
	public static var menuBG:FlxSprite;
	public static var onPlayState:Bool = false;

	var selectorLeft:FlxText;
	var selectorRight:FlxText;
	var descriptionText:FlxText;

	private var _inSubState:Bool = false;

	private var itemSpacing:Int = 72; // 减小垂直间距
	private var startY:Float = 0;

	private var selectorLeftTargetX:Float = 0;
	private var selectorLeftTargetY:Float = 0;
	private var selectorRightTargetX:Float = 0;
	private var selectorRightTargetY:Float = 0;

	private var allowInput:Bool = true;
	private var descriptionTween:FlxTween;

	private var lastClickTime:Float = 0;
	private var lastClickIndex:Int = -1;

	function openSelectedSubstate(label:String) {
		_inSubState = true; // 标记进入子状态，阻止主界面UI操作

		if (label != Language.get("adjust_delay_combo") && label != Language.get("extra_options")) {
			removeTouchPad();
			persistentUpdate = false;
		} else if (label == Language.get("extra_options")) {
			persistentUpdate = true;
		}

		var substateMap:Map<String, () -> Void> = [
			Language.get("note_colors") => () -> openSubState(new options.NotesColorSubState()),
			Language.get("controls") => () -> openSubState(new options.ControlsSubState()),
			Language.get("graphics") => () -> openSubState(new options.GraphicsSettingsSubState()),
			Language.get("visuals") => () -> openSubState(new options.VisualsSettingsSubState()),
			Language.get("gameplay") => () -> openSubState(new options.GameplaySettingsSubState()),
			Language.get("extra_options") => () -> {
				persistentUpdate = true;
				openSubState(new options.ExtraGameplaySettingSubState());
			},
			Language.get("adjust_delay_combo") => () -> MusicBeatState.switchState(new options.NoteOffsetState()),
			Language.get("mobile_options") => () -> openSubState(new mobile.options.MobileOptionsSubState())
		];

		if (substateMap.exists(label)) {
			substateMap.get(label)();
		}
	}

	override function create()
	{
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Options Menu", null);
		#end

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.color = 0xFF00BFFF;
		bg.updateHitbox();

		bg.screenCenter();
		add(bg);

		if (controls.mobileC)
		{
			var tipText:FlxText = new FlxText(150, FlxG.height - 24, 0, 'Press ' + (FlxG.onMobile ? 'C' : 'CTRL or C') + ' to Go Mobile Controls Menu', 16);
			tipText.setFormat(Paths.font("ResourceHanRoundedCN-Bold.ttf"), 17, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			tipText.borderSize = 1.25;
			tipText.scrollFactor.set();
			tipText.antialiasing = ClientPrefs.data.antialiasing;
			add(tipText);
		}

		grpOptions = new FlxTypedGroup<FlxText>();
		add(grpOptions);

		itemSpacing = OptionsConfig.ITEM_SPACING;
		var totalHeight = itemSpacing * options.length;
		startY = (FlxG.height - totalHeight) / 2 + itemSpacing / 2;

		var leftMargin = OptionsConfig.LEFT_MARGIN;

		for (num => option in options)
		{
			var optionText:FlxText = new FlxText(leftMargin, 0, 0, LanguageBasic.getPhrase('options_$option', option), 48);
			optionText.setFormat(Paths.font("ResourceHanRoundedCN-Bold.ttf"), 48, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			optionText.borderSize = 2;
			optionText.antialiasing = ClientPrefs.data.antialiasing;
			optionText.x = leftMargin;
			optionText.y = startY + num * itemSpacing;
			grpOptions.add(optionText);
		}

		selectorLeft = new FlxText(0, 0, 0, ">", 48);
		selectorLeft.setFormat(Paths.font("ResourceHanRoundedCN-Bold.ttf"), 48, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		selectorLeft.borderSize = 2;
		selectorLeft.antialiasing = ClientPrefs.data.antialiasing;
		add(selectorLeft);

		selectorRight = new FlxText(0, 0, 0, "<", 48);
		selectorRight.setFormat(Paths.font("ResourceHanRoundedCN-Bold.ttf"), 48, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		selectorRight.borderSize = 2;
		selectorRight.antialiasing = ClientPrefs.data.antialiasing;
		add(selectorRight);

		// 添加描述文本
		descriptionText = new FlxText(300, FlxG.height - 300, FlxG.width - 400, optionDescriptions[curSelected], 24);
		descriptionText.setFormat(Paths.font("ResourceHanRoundedCN-Bold.ttf"), 24, FlxColor.WHITE, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		descriptionText.borderSize = 1;
		descriptionText.antialiasing = ClientPrefs.data.antialiasing;
		descriptionText.scrollFactor.set();
		add(descriptionText);

		// 初始化选择器目标位置
		changeSelection();

		// 直接设置选择器初始位置
		selectorLeft.x = selectorLeftTargetX;
		selectorLeft.y = selectorLeftTargetY;
		selectorRight.x = selectorRightTargetX;
		selectorRight.y = selectorRightTargetY;

		ClientPrefs.saveSettings();

		addTouchPad('UP_DOWN', 'A_B_C');

		super.create();
		FlxG.mouse.visible = true;

		// 默认选中中间项
		curSelected = Std.int(options.length / 2);
		changeSelection(0); // 刷新高亮和描述
	}

	override function closeSubState()
	{
		super.closeSubState();
		ClientPrefs.saveSettings();
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Options Menu", null);
		#end
		controls.isInSubstate = false;
		removeTouchPad();
		addTouchPad('UP_DOWN', 'A_B_C');
		persistentUpdate = true;
		allowInput = true;
		_inSubState = false; // 退出子状态
	}

	var exiting = false;
	override function update(elapsed:Float) {
		super.update(elapsed);

		// 如果在子状态中，阻止所有UI操作
		if (_inSubState) return;

		// 始终显示鼠标指针
		FlxG.mouse.visible = true;

		// 仅在允许输入时处理按键
		if (allowInput) {
			if (!exiting) {
				if (controls.UI_UP_P)
					changeSelection(-1);
				if (controls.UI_DOWN_P)
					changeSelection(1);

				if (touchPad.buttonC.justPressed || FlxG.keys.justPressed.CONTROL && controls.mobileC)
				{
					persistentUpdate = false;
					openSubState(new mobile.substates.MobileControlSelectSubState());
				}

				if (controls.BACK)
				{
					exiting = true;
					FlxG.sound.play(Paths.sound('cancelMenu'));
					if (onPlayState)
					{
						StageData.loadDirectory(PlayState.SONG);
						LoadingState.loadAndSwitchState(new PlayState());
						FlxG.sound.music.volume = 0;
					}
					else MusicBeatState.switchState(new MainMenuState());
				}
				else if (controls.ACCEPT) openSelectedSubstate(options[curSelected]);
			}
		}

		// --- 鼠标拖动与点击选项 ---
		var mouse:FlxMouse = FlxG.mouse;
		var mouseOverOption:Int = -1;
		for (i in 0...grpOptions.length) {
			var opt = grpOptions.members[i];
			if (mouse.x >= opt.x && mouse.x <= opt.x + opt.width && mouse.y >= opt.y && mouse.y <= opt.y + opt.height) {
				mouseOverOption = i;
				break;
			}
		}

		// 鼠标单击选项自动更改选中项
		if (mouseOverOption != -1 && mouse.justPressed) {
			if (curSelected != mouseOverOption) {
				changeSelection(mouseOverOption - curSelected);
			}
			// 双击检测
			var now = FlxG.game.ticks / 1000.0;
			if (lastClickIndex == mouseOverOption && (now - lastClickTime) < OptionsConfig.DOUBLE_CLICK_THRESHOLD) {
				openSelectedSubstate(options[mouseOverOption]);
		}
		lastClickTime = now;
		lastClickIndex = mouseOverOption;
	}

		// 鼠标右键双击也可进入
		if (mouseOverOption != -1 && mouse.justPressedRight) {
			openSelectedSubstate(options[mouseOverOption]);
		}

		// 选中项动效
		for (i in 0...grpOptions.length)
		{
			var item = grpOptions.members[i];
			if (i == curSelected)
			{
				item.scale.x = FlxMath.lerp(OptionsConfig.SELECTED_SCALE, item.scale.x, Math.exp(-elapsed * OptionsConfig.SCALE_LERP_SPEED));
				item.scale.y = FlxMath.lerp(OptionsConfig.SELECTED_SCALE, item.scale.y, Math.exp(-elapsed * OptionsConfig.SCALE_LERP_SPEED));
			}
			else
			{
				item.scale.x = FlxMath.lerp(OptionsConfig.NORMAL_SCALE, item.scale.x, Math.exp(-elapsed * OptionsConfig.SCALE_LERP_SPEED));
				item.scale.y = FlxMath.lerp(OptionsConfig.NORMAL_SCALE, item.scale.y, Math.exp(-elapsed * OptionsConfig.SCALE_LERP_SPEED));
			}
		}

		// 更新选择器位置，使其跟随当前选中选项
		var selectedOption = grpOptions.members[curSelected];
		if (selectedOption != null)
		{
			selectorLeftTargetX = selectedOption.x - 63;
			selectorLeftTargetY = selectedOption.y;
			selectorRightTargetX = selectedOption.x + selectedOption.width + 15;
			selectorRightTargetY = selectedOption.y;
		}

		// < 和 > 选择器平滑动画
		selectorLeft.x = FlxMath.lerp(selectorLeftTargetX, selectorLeft.x, Math.exp(-elapsed * OptionsConfig.SELECTOR_LERP_SPEED));
		selectorLeft.y = FlxMath.lerp(selectorLeftTargetY, selectorLeft.y, Math.exp(-elapsed * OptionsConfig.SELECTOR_LERP_SPEED));
		selectorRight.x = FlxMath.lerp(selectorRightTargetX, selectorRight.x, Math.exp(-elapsed * OptionsConfig.SELECTOR_LERP_SPEED));
		selectorRight.y = FlxMath.lerp(selectorRightTargetY, selectorRight.y, Math.exp(-elapsed * OptionsConfig.SELECTOR_LERP_SPEED));
	}

	function changeSelection(change:Int = 0)
	{
		curSelected = FlxMath.wrap(curSelected + change, 0, options.length - 1);

		for (i in 0...grpOptions.length)
		{
			var item = grpOptions.members[i];
			item.y = startY + i * itemSpacing;
			item.alpha = (i == curSelected) ? 1 : 0.6;
		}

		updateDescriptionText();
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}

	// 更新描述文本
	private function updateDescriptionText():Void
	{
		descriptionText.text = optionDescriptions[curSelected];
		
		// 取消之前的tween
		if (descriptionTween != null) {
			descriptionTween.cancel();
			//descriptionTween.destroy();
		}
		
		// 重置位置并创建新的tween
		descriptionText.y = FlxG.height + OptionsConfig.DESC_Y_START;
		descriptionTween = FlxTween.tween(descriptionText,
			{y: FlxG.height + OptionsConfig.DESC_Y_END},
			OptionsConfig.TWEEN_DURATION,
			{
				ease: FlxEase.quadOut,
				onComplete: function(twn:FlxTween) {
					if (descriptionTween == twn)
						descriptionTween = null;
				}
			}
		);
	}

	public function refreshTexts()
	{
		// 更新选项文本
		for (i in 0...options.length)
		{
			var optionText = grpOptions.members[i];
			optionText.text = LanguageBasic.getPhrase('options_${options[i]}', options[i]);
		}

		// 更新描述文本
		if(curSelected >= 0 && curSelected < optionDescriptions.length) {
			descriptionText.text = optionDescriptions[curSelected];
		}

		// 重新计算选择器位置
		var selectedOption = grpOptions.members[curSelected];
		if (selectedOption != null)
		{
			selectorLeftTargetX = selectedOption.x - 63;
			selectorLeftTargetY = selectedOption.y;
			selectorRightTargetX = selectedOption.x + selectedOption.width + 15;
			selectorRightTargetY = selectedOption.y;
		}
	}

	override function destroy()
	{
		if (descriptionTween != null)
		{
			descriptionTween.cancel();
			descriptionTween.destroy();
		}
		ClientPrefs.loadPrefs();
		super.destroy();
	}
}