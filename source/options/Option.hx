package options;

import flixel.text.FlxText;

typedef Keybind = {
	keyboard:String,
	gamepad:String
}

enum OptionType {
	// Bool will use checkboxes
	// Everything else will use a text
	BOOL;
	INT;
	FLOAT;
	PERCENT;
	STRING;
	KEYBIND;
	BUTTON;
}

class Option
{
	public var child:FlxText;
	public var text(get, set):String;
	public var onChange:Void->Void = null;
	public var type:OptionType = BOOL;

	public var scrollSpeed:Float = 50;
	public var variable(default, null):String = null;
	public var defaultValue:Dynamic = null;

	public var curOption:Int = 0;
	public var options:Array<String> = null;
	public var changeValue:Dynamic = 1;
	public var minValue:Null<Dynamic> = null;
	public var maxValue:Null<Dynamic> = null;
	public var decimals:Int = 1;

	public var displayFormat:String = '%v';
	// STRING 选项可选值的本地化显示映射（key = 存储值, value = 显示文案）。
	// 存储值保持不变，仅影响列表/下拉中的显示。
	public var valueLocalizations:Map<String, String> = null;
	public var description:String = '';
	public var name:String = 'Unknown';
	// 选项被禁用时的前提条件说明（如"需要 Kathy 评价下落风格"），选中禁用项时显示在描述框
	public var requirement:String = null;
	// 自定义显示文案，覆盖 name + requirement 的默认拼接（用于替代带前缀的 requirement 显示）
	public var altText:String = null;
	// 禁用原因说明（不带前缀），选中禁用项时显示在描述框；为 null 时回退到 requirement 逻辑
	public var disabledReason:String = null;

	public var defaultKeys:Keybind = null;
	public var keys:Keybind = null;
	public var disabled:Bool = false;

	public function new(name:String, description:String = '', variable:String, type:OptionType = BOOL, ?options:Array<String> = null, ?translation:String = null)
	{
		_name = name;
		_translationKey = translation != null ? translation : _name;
		this.name = LanguageBasic.getPhrase('setting_$_translationKey', name);
		this.description = LanguageBasic.getPhrase('description_$_translationKey', description);
		this.variable = variable;
		this.type = type;
		this.options = options;

		if(this.type != KEYBIND && this.type != BUTTON) this.defaultValue = Reflect.getProperty(ClientPrefs.defaultData, variable);
		switch(type)
		{
			case BOOL:
				if(defaultValue == null) defaultValue = false;
			case INT, FLOAT:
				if(defaultValue == null) defaultValue = 0;
			case PERCENT:
				if(defaultValue == null) defaultValue = 1;
				displayFormat = '%v%';
				changeValue = 0.01;
				minValue = 0;
				maxValue = 1;
				scrollSpeed = 0.5;
				decimals = 2;
			case STRING:
				if(options.length > 0)
					defaultValue = options[0];
				if(defaultValue == null)
					defaultValue = '';

			case KEYBIND:
				defaultValue = '';
				defaultKeys = {gamepad: 'NONE', keyboard: 'NONE'};
				keys = {gamepad: 'NONE', keyboard: 'NONE'};
			case BUTTON:
				// No need for default value or variable
		}

		try
		{
			if(this.type != BUTTON && getValue() == null)
				setValue(defaultValue);

			switch(type)
			{
				case STRING:
					var num:Int = options.indexOf(getValue());
					if(num > -1) curOption = num;

				default:
			}
		}
		catch(e) {}
	}

	public function change()
	{
		//nothing lol
		if(onChange != null)
			onChange();
	}

	dynamic public function getValue():Dynamic
	{
		if (type == BUTTON) return null;
		var value = Reflect.getProperty(ClientPrefs.data, variable);
		if(type == KEYBIND) return !Controls.instance.controllerMode ? value.keyboard : value.gamepad;
		return value;
	}

	dynamic public function setValue(value:Dynamic)
	{
		if (type == BUTTON) return null;
		if(type == KEYBIND)
		{
			var keys = Reflect.getProperty(ClientPrefs.data, variable);
			if(!Controls.instance.controllerMode) keys.keyboard = value;
			else keys.gamepad = value;
			return value;
		}
		return Reflect.setProperty(ClientPrefs.data, variable, value);
	}

	var _name:String = null;
	var _text:String = null;
	var _translationKey:String = null;
	public var translationKey(get, never):String;
	private function get_translationKey():String return _translationKey;
	private function get_text()
		return _text;

	private function set_text(newValue:String = '')
	{
		if(child != null)
		{
			_text = newValue;
			child.text = LanguageBasic.getPhrase('setting_$_translationKey-${getValue()}', _text);
			return _text;
		}
		return null;
	}
}