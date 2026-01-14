package options;

class GameplaySettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = LanguageBasic.getPhrase('gameplay_menu', 'Gameplay Settings');
		rpcTitle = 'Gameplay Settings Menu'; //for Discord Rich Presence

		//I'd suggest using "Downscroll" as an example for making your own option since it is the simplest here
		var option:Option = new Option(
			"Downscroll",
			Language.get("downscroll_desc"),
			'downScroll',
			BOOL);
		addOption(option);

		var option:Option = new Option(
			"Middlescroll",
			Language.get("middlescroll_desc"),
			'middleScroll',
			BOOL);
		addOption(option);

		var option:Option = new Option(
			"Opponent Notes",
			Language.get("opponentnotes_desc"),
			'opponentStrums',
			BOOL);
		addOption(option);

		var option:Option = new Option(
			"Ghost Tapping",
			Language.get("ghosttapping_desc"),
			'ghostTapping',
			BOOL);
		addOption(option);
		
		var option:Option = new Option(
			"Auto Pause",
			Language.get("autopause_desc"),
			'autoPause',
			BOOL);
		addOption(option);
		option.onChange = onChangeAutoPause;

		var option:Option = new Option(
			"Pop Up Score",
			Language.get("popupscore_desc"),
			'popUpRating',
			BOOL);
		addOption(option);

		var option:Option = new Option(
			"Disable Reset Button",
			Language.get("disablereset_desc"),
			'noReset',
			BOOL);
		addOption(option);

		#if mobile
		var option:Option = new Option(
			"Game Over Vibration",
			Language.get("gameovervibration_desc"),
			'gameOverVibration',
			BOOL);
		addOption(option);
		option.onChange = onChangeVibration;
		#end

		var option:Option = new Option(
			"Sustains as One Note",
			Language.get("sustainsasone_desc"),
			'guitarHeroSustains',
			BOOL);
		addOption(option);

		var option:Option = new Option(
			"Hitsound Volume",
			Language.get("hitsoundvolume_desc"),
			'hitsoundVolume',
			PERCENT);
		addOption(option);
		option.scrollSpeed = 1.6;
		option.minValue = 0.0;
		option.maxValue = 1;
		option.changeValue = 0.1;
		option.decimals = 1;
		option.onChange = onChangeHitsoundVolume;

		var option:Option = new Option(
			"Rating Offset",
			Language.get("ratingoffset_desc"),
			'ratingOffset',
			INT);
		option.displayFormat = '%vms';
		option.scrollSpeed = 20;
		option.minValue = -30;
		option.maxValue = 30;
		addOption(option);

		var option:Option = new Option(
			"Perfect!! Hit Window",
			Language.get("perfectwindow_desc"),
			'perfectWindow',
			FLOAT);
		option.displayFormat = '%vms';
		option.scrollSpeed = 15;
		option.minValue = 5;
		option.maxValue = 45.0;
		option.changeValue = 0.1;
		option.onChange = function() adjustHitWindow('perfectWindow', ClientPrefs.data.perfectWindow);
		addOption(option);

		var option:Option = new Option(
			"Sick! Hit Window",
			Language.get("sickwindow_desc"),
			'sickWindow',
			FLOAT);
		option.displayFormat = '%vms';
		option.scrollSpeed = 15;
		option.minValue = 15.0;
		option.maxValue = 45.0;
		option.changeValue = 0.1;
		option.onChange = function() adjustHitWindow('sickWindow', ClientPrefs.data.sickWindow);
		addOption(option);

		var option:Option = new Option(
			"Good Hit Window",
			Language.get("goodwindow_desc"),
			'goodWindow',
			FLOAT);
		option.displayFormat = '%vms';
		option.scrollSpeed = 30;
		option.minValue = 15.0;
		option.maxValue = 90.0;
		option.changeValue = 0.1;
		option.onChange = function() adjustHitWindow('goodWindow', ClientPrefs.data.goodWindow);
		addOption(option);

		var option:Option = new Option(
			"Bad Hit Window",
			Language.get("badwindow_desc"),
			'badWindow',
			FLOAT);
		option.displayFormat = '%vms';
		option.scrollSpeed = 60;
		option.minValue = 15.0;
		option.maxValue = 135.0;
		option.changeValue = 0.1;
		option.onChange = function() adjustHitWindow('badWindow', ClientPrefs.data.badWindow);
		addOption(option);

		var option:Option = new Option(
			"Safe Frames",
			Language.get("safeframes_desc"),
			'safeFrames',
			FLOAT);
		option.scrollSpeed = 5;
		option.minValue = 2;
		option.maxValue = 15;
		option.changeValue = 0.1;
		addOption(option);

		super();
	}

	function onChangeHitsoundVolume()
		FlxG.sound.play(Paths.sound('hitsound'), ClientPrefs.data.hitsoundVolume);

	function onChangeAutoPause()
		FlxG.autoPause = ClientPrefs.data.autoPause;

	function onChangeVibration()
	{
		if(ClientPrefs.data.gameOverVibration)
			lime.ui.Haptic.vibrate(0, 500);
	}

	// 添加联动逻辑
	function adjustHitWindow(optionKey:String, newValue:Float) {
		switch(optionKey) {
			case 'perfectWindow':
				ClientPrefs.data.perfectWindow = newValue;
				if (newValue >= ClientPrefs.data.sickWindow) {
					ClientPrefs.data.sickWindow = newValue;
				}
			case 'sickWindow':
				ClientPrefs.data.sickWindow = newValue;
				if (newValue <= ClientPrefs.data.perfectWindow) {
					ClientPrefs.data.perfectWindow = newValue;
				} else if (newValue >= ClientPrefs.data.goodWindow) {
					ClientPrefs.data.goodWindow = newValue;
				}
			case 'goodWindow':
				ClientPrefs.data.goodWindow = newValue;
				if (newValue <= ClientPrefs.data.sickWindow) {
					ClientPrefs.data.sickWindow = newValue;
				} else if (newValue >= ClientPrefs.data.badWindow) {
					ClientPrefs.data.badWindow = newValue;
				}
			case 'badWindow':
				ClientPrefs.data.badWindow = newValue;
				if (newValue <= ClientPrefs.data.goodWindow) {
					ClientPrefs.data.goodWindow = newValue;
				}
			default:
		}
	}
}
