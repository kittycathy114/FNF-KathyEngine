package options;

import objects.AttachedFlxText;
import objects.CheckboxThingie;
import flixel.text.FlxText;

import backend.Language.OptionsLanguage;
import options.Option.OptionType;

class GameplayChangersSubstate extends MusicBeatSubstate
{
	private var curSelected:Int = 0;
	private var optionsArray:Array<Dynamic> = [];
	private var antiMashOption:GameplayOption; // Leather 血量模型专属，其他模型下禁用

	private var grpOptions:FlxTypedGroup<FlxText>;
	private var checkboxGroup:FlxTypedGroup<CheckboxThingie>;
	private var grpTexts:FlxTypedGroup<AttachedFlxText>;

	private var listCenterY:Float = 360;
	private var itemSpacing:Float = 56;
	private var listBaseX:Float = 150;

	private var curOption(get, never):GameplayOption;
	function get_curOption() return optionsArray[curSelected]; //shorter lol

	function getOptions()
	{
		var goption:GameplayOption = new GameplayOption('Scroll Type', 'scrolltype', STRING, 'multiplicative', ["multiplicative", "constant"]);
		optionsArray.push(goption);

		var option:GameplayOption = new GameplayOption('Scroll Speed', 'scrollspeed', FLOAT, 1);
		option.scrollSpeed = 2.0;
		option.minValue = 0.35;
		option.changeValue = 0.05;
		option.decimals = 2;
		if (goption.getValue() != "constant")
		{
			option.displayFormat = '%vX';
			option.maxValue = 3;
		}
		else
		{
			option.displayFormat = "%v";
			option.maxValue = 6;
		}
		optionsArray.push(option);

		#if FLX_PITCH
		var option:GameplayOption = new GameplayOption('Playback Rate', 'songspeed', FLOAT, 1);
		option.scrollSpeed = 1;
		option.minValue = 0.5;
		option.maxValue = 3.0;
		option.changeValue = 0.05;
		option.displayFormat = '%vX';
		option.decimals = 2;
		optionsArray.push(option);
		#end

		var option:GameplayOption = new GameplayOption('Health Gain Multiplier', 'healthgain', FLOAT, 1);
		option.scrollSpeed = 2.5;
		option.minValue = 0;
		option.maxValue = 5;
		option.changeValue = 0.1;
		option.displayFormat = '%vX';
		optionsArray.push(option);

		var option:GameplayOption = new GameplayOption('Health Loss Multiplier', 'healthloss', FLOAT, 1);
		option.scrollSpeed = 2.5;
		option.minValue = 0.5;
		option.maxValue = 5;
		option.changeValue = 0.1;
		option.displayFormat = '%vX';
		optionsArray.push(option);

		optionsArray.push(new GameplayOption('Instakill on Miss', 'instakill', BOOL, false));
		optionsArray.push(new GameplayOption('Practice Mode', 'practice', BOOL, false));
		optionsArray.push(new GameplayOption('Botplay', 'botplay', BOOL, false));
		optionsArray.push(new GameplayOption('Play Opponent', 'playOpponent', BOOL, false));
		optionsArray.push(new GameplayOption('Health Model', 'healthmodel', STRING, 'default', ['default', 'kade', 'leather', 'forever']));
		antiMashOption = new GameplayOption('Anti Mash', 'antiMash', BOOL, false);
		optionsArray.push(antiMashOption);
		updateAntiMashState();
	}

	public function getOptionByVar(variable:String)
	{
		for(i in optionsArray)
		{
			var opt:GameplayOption = i;
			if (opt.variable == variable)
				return opt;
		}
		return null;
	}

	// antiMash 仅当血量模型为 Leather 时可用，其余情况禁用（灰显、不可修改，并强制关掉该值）
	function updateAntiMashState()
	{
		if (antiMashOption == null) return;
		var healthModelOpt:GameplayOption = getOptionByVar('healthmodel');
		var isLeather:Bool = (healthModelOpt != null && healthModelOpt.getValue() == 'leather');
		antiMashOption.disabled = !isLeather;
		if (!isLeather && antiMashOption.getValue() == true)
		{
			antiMashOption.setValue(false); // 非 Leather 时强制关掉，避免显示 Enabled 却已失效
			updateTextFrom(antiMashOption);
		}
	}

	public function new()
	{
		controls.isInSubstate = true;

		super();
		
		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = 0.6;
		add(bg);

		// avoids lagspikes while scrolling through menus!
		grpOptions = new FlxTypedGroup<FlxText>();
		add(grpOptions);

		grpTexts = new FlxTypedGroup<AttachedFlxText>();
		add(grpTexts);

		checkboxGroup = new FlxTypedGroup<CheckboxThingie>();
		add(checkboxGroup);

		getOptions();

		for (i in 0...optionsArray.length)
		{
			var optionText:FlxText = new FlxText(150, listCenterY + i * itemSpacing, 0, optionsArray[i].name, OptionsConfig.SUBMENU_ITEM_SIZE);
			optionText.setFormat(Paths.font(Language.get('game_font')), OptionsConfig.SUBMENU_ITEM_SIZE, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			optionText.borderSize = 2;
			optionText.antialiasing = ClientPrefs.data.antialiasing;
			optionText.ID = i;
			optionText.scrollFactor.set();
			grpOptions.add(optionText);

			if(optionsArray[i].type == BOOL)
			{
				var on:Bool = (optionsArray[i].getValue() == true);
				var valueText:AttachedFlxText = new AttachedFlxText(optionText.x, optionText.y, 0, on ? Language.get('enabled') : Language.get('disabled'), OptionsConfig.SUBMENU_VALUE_SIZE);
				valueText.setFormat(Paths.font(Language.get('game_font')), OptionsConfig.SUBMENU_VALUE_SIZE, on ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				valueText.borderSize = 2;
				valueText.antialiasing = ClientPrefs.data.antialiasing;
				valueText.sprTracker = optionText;
				valueText.offsetX = optionText.width + 60;
				valueText.copyAlpha = true;
				valueText.ID = i;
				valueText.scrollFactor.set();
				grpTexts.add(valueText);
				optionsArray[i].setChild(valueText);
			}
			else
			{
				var valueText:AttachedFlxText = new AttachedFlxText(optionText.x, optionText.y, 0, Std.string(optionsArray[i].getValue()), OptionsConfig.SUBMENU_VALUE_SIZE);
				valueText.setFormat(Paths.font(Language.get('game_font')), OptionsConfig.SUBMENU_VALUE_SIZE, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				valueText.borderSize = 2;
				valueText.antialiasing = ClientPrefs.data.antialiasing;
				valueText.sprTracker = optionText;
				valueText.offsetX = optionText.width + 40;
				valueText.copyAlpha = true;
				valueText.ID = i;
				valueText.scrollFactor.set();
				grpTexts.add(valueText);
				optionsArray[i].setChild(valueText);
			}
			updateTextFrom(optionsArray[i]);
		}

		addTouchPad('LEFT_FULL', 'A_B_C');
		addTouchPadCamera();

		changeSelection();
		reloadCheckboxes();
	}

	var nextAccept:Int = 5;
	var holdTime:Float = 0;
	var holdValue:Float = 0;
	override function update(elapsed:Float)
	{
		if (controls.UI_UP_P)
			changeSelection(-1);

		if (controls.UI_DOWN_P)
			changeSelection(1);

		if (controls.BACK)
		{
			close();
			ClientPrefs.saveSettings();
			controls.isInSubstate = false;
			FlxG.sound.play(Paths.sound('cancelMenu'));
		}

		if(nextAccept <= 0)
		{
			var usesCheckbox:Bool = (curOption.type == BOOL);
			if(usesCheckbox)
			{
				if(!curOption.disabled && controls.ACCEPT)
				{
					FlxG.sound.play(Paths.sound('scrollMenu'));
					curOption.setValue((curOption.getValue() == true) ? false : true);
					curOption.change();
					reloadCheckboxes();
				}
			}
			else
			{
				if(!curOption.disabled && (controls.UI_LEFT || controls.UI_RIGHT))
				{
					var pressed = (controls.UI_LEFT_P || controls.UI_RIGHT_P);
					if(holdTime > 0.5 || pressed)
					{
						if(pressed)
						{
							var add:Dynamic = null;
							if(curOption.type != STRING)
								add = controls.UI_LEFT ? -curOption.changeValue : curOption.changeValue;

							switch(curOption.type)
							{
								case INT, FLOAT, PERCENT:
									holdValue = curOption.getValue() + add;
									if(holdValue < curOption.minValue) holdValue = curOption.minValue;
									else if (holdValue > curOption.maxValue) holdValue = curOption.maxValue;

									switch(curOption.type)
									{
										case INT:
											holdValue = Math.round(holdValue);
											curOption.setValue(holdValue);

										case FLOAT, PERCENT:
											holdValue = FlxMath.roundDecimal(holdValue, curOption.decimals);
											curOption.setValue(holdValue);

										default:
									}

								case STRING:
									var num:Int = curOption.curOption; //lol
									if(controls.UI_LEFT_P) --num;
									else num++;

									if(num < 0)
										num = curOption.options.length - 1;
									else if(num >= curOption.options.length)
										num = 0;

									curOption.curOption = num;
									curOption.setValue(curOption.options[num]); //lol
									
									if (curOption.variable == 'scrolltype')
									{
										var oOption:GameplayOption = getOptionByVar("scrollspeed");
										if (oOption != null)
										{
											if (curOption.getValue() == "constant")
											{
												oOption.displayFormat = "%v";
												oOption.maxValue = 6;
											}
											else
											{
												oOption.displayFormat = "%vX";
												oOption.maxValue = 3;
												if(oOption.getValue() > 3) oOption.setValue(3);
											}
											updateTextFrom(oOption);
										}
									}
									else if (curOption.variable == 'healthmodel')
										updateAntiMashState();
									//trace(curOption.options[num]);

								default:
							}
							updateTextFrom(curOption);
							curOption.change();
							FlxG.sound.play(Paths.sound('scrollMenu'));
						}
						else if(curOption.type != STRING)
						{
							holdValue = Math.max(curOption.minValue, Math.min(curOption.maxValue, holdValue + curOption.scrollSpeed * elapsed * (controls.UI_LEFT ? -1 : 1)));

							switch(curOption.type)
							{
								case INT:
									curOption.setValue(Math.round(holdValue));
								
								case FLOAT, PERCENT:
									var blah:Float = Math.max(curOption.minValue, Math.min(curOption.maxValue, holdValue + curOption.changeValue - (holdValue % curOption.changeValue)));
									curOption.setValue(FlxMath.roundDecimal(blah, curOption.decimals));

								default:
							}
							updateTextFrom(curOption);
							curOption.change();
						}
					}

					if(curOption.type != STRING)
						holdTime += elapsed;
				}
				else if(controls.UI_LEFT_R || controls.UI_RIGHT_R)
					clearHold();
			}

			if(controls.RESET || touchPad.buttonC.justPressed)
			{
				for (i in 0...optionsArray.length)
				{
					var leOption:GameplayOption = optionsArray[i];
					leOption.setValue(leOption.defaultValue);
					if(leOption.type != BOOL)
					{
						if(leOption.type == STRING)
							leOption.curOption = leOption.options.indexOf(leOption.getValue());

						updateTextFrom(leOption);
					}

					if(leOption.variable == 'scrollspeed')
					{
						leOption.displayFormat = "%vX";
						leOption.maxValue = 3;
						if(leOption.getValue() > 3)
							leOption.setValue(3);

						updateTextFrom(leOption);
					}
					leOption.change();
				}
				FlxG.sound.play(Paths.sound('cancelMenu'));
				updateAntiMashState(); // 重置后血量模型可能回到非 Leather，需同步禁用状态
				reloadCheckboxes();
			}
		}

		if(nextAccept > 0) {
			nextAccept -= 1;
		}

		if (touchPad == null) { //sometimes it dosent add the tpad, hopefully this fixes it
			addTouchPad('LEFT_FULL', 'A_B_C');
			addTouchPadCamera();
		}
		updateGCItemLayout(elapsed);
		super.update(elapsed);
	}

	private function updateGCItemLayout(elapsed:Float):Void
	{
		var lerp:Float = Math.exp(-elapsed * OptionsConfig.SUBMENU_LAYOUT_LERP);
		for (num => item in grpOptions.members)
		{
			var offset:Int = num - curSelected;
			var targetY:Float = listCenterY + offset * itemSpacing;
			item.y = FlxMath.lerp(targetY, item.y, lerp);

			// Freeplay 式连续水平投影：选中行最右，距离做幂次曲线呈弧形（与 BaseOptionsMenu 一致）
			var shaped:Float = Math.pow(Math.abs(offset), OptionsConfig.SUBMENU_X_DRIFT_CURVE);
			var targetX:Float = listBaseX + OptionsConfig.SUBMENU_SELECTED_OFFSET_X
				+ OptionsConfig.SUBMENU_SELECTED_EXTRA_OFFSET_X
				- shaped * OptionsConfig.SUBMENU_X_DRIFT_PER_ITEM;
			item.x = FlxMath.lerp(targetX, item.x, lerp);

			var targetAlpha:Float = (offset == 0) ? OptionsConfig.SUBMENU_SELECTED_ALPHA : OptionsConfig.SUBMENU_UNSELECTED_ALPHA;
			if (optionsArray[item.ID] != null && optionsArray[item.ID].disabled) targetAlpha *= OptionsConfig.SUBMENU_DISABLED_ALPHA_MULT;
			item.alpha = FlxMath.lerp(targetAlpha, item.alpha, lerp);

			var targetScale:Float = (offset == 0) ? OptionsConfig.SUBMENU_SELECTED_SCALE : OptionsConfig.SUBMENU_NORMAL_SCALE;
			item.scale.x = FlxMath.lerp(targetScale, item.scale.x, lerp);
			item.scale.y = item.scale.x;
		}

		// 右侧数值/Enabled 文本跟随选中项一起缩放，保持视觉一致
		for (text in grpTexts) {
			var isSelected:Bool = (text.ID == curSelected);
			var targetScale:Float = isSelected ? OptionsConfig.SUBMENU_SELECTED_SCALE : OptionsConfig.SUBMENU_NORMAL_SCALE;
			text.scale.x = FlxMath.lerp(targetScale, text.scale.x, lerp);
			text.scale.y = text.scale.x;
		}
	}

	function updateTextFrom(option:GameplayOption) {
		if(option.type == BOOL) {
			var on:Bool = (option.getValue() == true);
			if (option.child != null) {
				option.child.text = on ? Language.get('enabled') : Language.get('disabled');
				option.child.color = on ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			}
			return;
		}
		if(option.type == STRING) {
			var val:Dynamic = option.getValue();
			option.text = '${OptionsConfig.SUBMENU_STRING_ARROW.charAt(0)}$val${OptionsConfig.SUBMENU_STRING_ARROW.charAt(2)}';
			if (option.child != null) option.child.color = OptionsConfig.SUBMENU_STRING_COLOR;
			return;
		}
		var text:String = option.displayFormat;
		var val:Dynamic = option.getValue();
		if(option.type == PERCENT) val *= 100;
		var def:Dynamic = option.defaultValue;
		option.text = text.replace('%v', val).replace('%d', def);
	}

	function clearHold()
	{
		if(holdTime > 0.5)
			FlxG.sound.play(Paths.sound('scrollMenu'));

		holdTime = 0;
	}
	
	function changeSelection(change:Int = 0)
	{
		curSelected = FlxMath.wrap(curSelected + change, 0, optionsArray.length - 1);
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}

	function reloadCheckboxes() {
		for (checkbox in checkboxGroup) {
			checkbox.daValue = (optionsArray[checkbox.ID].getValue() == true);
		}
		// BOOL 选项已改为右侧 "Enabled/Disabled" 文本，随状态刷新颜色
		for (text in grpTexts) {
			var opt = optionsArray[text.ID];
			if (opt != null && opt.type == BOOL) {
				var on:Bool = (opt.getValue() == true);
				text.text = on ? Language.get('enabled') : Language.get('disabled');
				text.color = on ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			}
		}
	}
}

class GameplayOption
{
	public var child:FlxText;
	public var disabled:Bool = false; // 是否禁用（禁用时不可修改并灰显）
	public var text(get, set):String;
	public var onChange:Void->Void = null; //Pressed enter (on Bool type options) or pressed/held left/right (on other types)
	public var type:OptionType = BOOL;

	public var showBoyfriend:Bool = false;
	public var scrollSpeed:Float = 50; //Only works on int/float, defines how fast it scrolls per second while holding left/right

	public var variable:String = null; //Variable from ClientPrefs.hx's gameplaySettings
	public var defaultValue:Dynamic = null;

	public var curOption:Int = 0; //Don't change this
	public var options:Array<String> = null; //Only used in string type
	public var changeValue:Dynamic = 1; //Only used in int/float/percent type, how much is changed when you PRESS
	public var minValue:Dynamic = null; //Only used in int/float/percent type
	public var maxValue:Dynamic = null; //Only used in int/float/percent type
	public var decimals:Int = 1; //Only used in float/percent type

	public var displayFormat:String = '%v'; //How String/Float/Percent/Int values are shown, %v = Current value, %d = Default value
	public var name:String = 'Unknown';

	private static var LANG_KEYS:Map<String, String> = [
		'Scroll Type' => 'scrolltype',
		'Scroll Speed' => 'scrollspeed',
		'Playback Rate' => 'playbackrate',
		'Health Gain Multiplier' => 'healthgain',
		'Health Loss Multiplier' => 'healthloss',
		'Instakill on Miss' => 'instakill',
		'Practice Mode' => 'practice',
		'Botplay' => 'botplay',
		'Play Opponent' => 'playopponent'
	];

	public var langKey:String;

	public function new(name:String, variable:String, type:OptionType, defaultValue:Dynamic = 'null variable value', ?options:Array<String> = null)
	{
		_name = name;
		langKey = LANG_KEYS.exists(name) ? LANG_KEYS.get(name) : name.toLowerCase().replace(' ', '');
		this.name = OptionsLanguage.get(langKey, name);
		this.variable = variable;
		this.type = type;
		this.defaultValue = defaultValue;
		this.options = options;

		if(defaultValue == 'null variable value')
		{
			switch(type)
			{
				case BOOL:
					defaultValue = false;
				case INT, FLOAT:
					defaultValue = 0;
				case PERCENT:
					defaultValue = 1;
				case STRING:
					defaultValue = '';
					if(options.length > 0)
						defaultValue = options[0];

				default:
			}
		}

		if(getValue() == null)
			setValue(defaultValue);

		switch(type)
		{
			case STRING:
				var num:Int = options.indexOf(getValue());
				if(num > -1)
					curOption = num;

			case PERCENT:
				displayFormat = '%v%';
				changeValue = 0.01;
				minValue = 0;
				maxValue = 1;
				scrollSpeed = 0.5;
				decimals = 2;

			default:
		}
	}

	public function change()
	{
		//nothing lol
		if(onChange != null)
			onChange();
	}

	public function getValue():Dynamic
		return ClientPrefs.data.gameplaySettings.get(variable);

	public function setValue(value:Dynamic)
		ClientPrefs.data.gameplaySettings.set(variable, value);

	public function setChild(child:FlxText)
		this.child = child;

	var _name:String = null;
	var _text:String = null;
	private function get_text()
		return _text;

	private function set_text(newValue:String = '')
	{
		if(child != null)
		{
			_text = newValue;
			var arrowL:String = OptionsConfig.SUBMENU_STRING_ARROW.charAt(0);
			var arrowR:String = OptionsConfig.SUBMENU_STRING_ARROW.charAt(2);
			var wrapped:Bool = (newValue.charAt(0) == arrowL) && (newValue.charAt(newValue.length - 1) == arrowR);
			var raw:String = wrapped ? newValue.substring(1, newValue.length - 1) : newValue;
			var translated:String = OptionsLanguage.get('${langKey}_${raw.toLowerCase().replace(' ', '')}', raw);
			child.text = wrapped ? '${arrowL}${translated}${arrowR}' : translated;
			return _text;
		}
		return null;
	}
}