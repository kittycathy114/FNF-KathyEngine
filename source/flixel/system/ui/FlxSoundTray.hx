package flixel.system.ui;

#if FLX_SOUND_SYSTEM
import flixel.FlxG;
import flixel.system.FlxAssets;
import flixel.util.FlxColor;
import openfl.Lib;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
#if flash
import openfl.text.AntiAliasType;
import openfl.text.GridFitType;
#end
import openfl.display.Graphics;
import openfl.geom.Matrix;

/**
 * The flixel sound tray, the little volume meter that pops down sometimes.
 * Accessed via `FlxG.game.soundTray` or `FlxG.sound.soundTray`.
 */
class FlxSoundTray extends Sprite
{
	/**
	 * Because reading any data from DisplayObject is insanely expensive in hxcpp, keep track of whether we need to update it or not.
	 */
	public var active:Bool;

	/**
	 * Helps us auto-hide the sound tray after a volume change.
	 */
	var _timer:Float;

	/**
	 * Helps display the volume bars on the sound tray.
	 */
	var _volumeBar:Sprite;

	/**
	 * Progress bar background.
	 */
	var _barBg:Sprite;

	/**
	 * Text field for displaying volume percentage.
	 */
	var _volumeText:TextField;

	/**
	 * Current display volume for animation.
	 */
	var _displayVolume:Float = 1.0;

	/**
	 * Target volume for animation.
	 */
	var _targetVolume:Float = 1.0;

	/**
	 * How wide the sound tray background is.
	 */
	var _width:Int = 160;

	/**
	 * How tall the sound tray background is.
	 */
	var _height:Int = 50;

	var _defaultScale:Float = 2.0;

	/**
	 * Background sprite for custom styling.
	 */
	var _background:Sprite;

	/**The sound used when increasing the volume.**/
	public var volumeUpSound:String = "flixel/sounds/beep";

	/**The sound used when decreasing the volume.**/
	public var volumeDownSound:String = 'flixel/sounds/beep';

	/**Whether or not changing the volume should make noise.**/
	public var silent:Bool = false;

	/**
	 * Sets up the "sound tray", the little volume meter that pops down sometimes.
	 */
	@:keep
	public function new()
	{
		super();

		visible = false;
		scaleX = _defaultScale;
		scaleY = _defaultScale;

		// Create simple background without gradient and border
		_background = new Sprite();
		drawBackground();
		screenCenter();
		addChild(_background);

		// Create volume text field
		_volumeText = new TextField();
		_volumeText.width = _width;
		_volumeText.height = 20;
		_volumeText.multiline = false;
		_volumeText.wordWrap = false;
		_volumeText.selectable = false;

		#if flash
		_volumeText.embedFonts = true;
		_volumeText.antiAliasType = AntiAliasType.NORMAL;
		_volumeText.gridFitType = GridFitType.PIXEL;
		#else
		#end
		var textFormat:TextFormat = new TextFormat(FlxAssets.FONT_DEFAULT, 14, 0xFFFFFF);
		textFormat.align = TextFormatAlign.CENTER;
		textFormat.bold = true;
		_volumeText.defaultTextFormat = textFormat;
		_volumeText.text = "VOLUME: 100%";
		_volumeText.y = 8;
		addChild(_volumeText);

	// Create progress bar background
	var _barBg:Sprite = new Sprite();
	var bgGraphics:Graphics = _barBg.graphics;
	bgGraphics.beginFill(0x2a2a2a, 0.8);
	bgGraphics.drawRoundRect(10, 30, _width - 20, 12, 6, 6);
	bgGraphics.endFill();
	addChild(_barBg);

	// Create volume progress bar
	_volumeBar = new Sprite();
	_volumeBar.x = 10;
	_volumeBar.y = 30;
	addChild(_volumeBar);

	// Initialize volume display with full volume
	_displayVolume = 1.0;
	_targetVolume = 1.0;
	updateVolumeBar(1.0);

	// Set initial position 50 pixels lower
	y = -height - 50;
	visible = false;
	}

	/**
	 * This function updates the soundtray object.
	 */
	public function update(MS:Float):Void
	{
		// Animate volume bar changes
		if (Math.abs(_targetVolume - _displayVolume) > 0.01)
		{
			// Smooth ease-out animation
			_displayVolume += (_targetVolume - _displayVolume) * 0.15;
			updateVolumeBar(_displayVolume);
		}
		else
		{
			_displayVolume = _targetVolume;
		}

		// Animate sound tray thing
		if (_timer > 0)
		{
			_timer -= (MS / 1000);
		}
		else if (y > -height - 50)
		{
			// Slide up animation
			y -= (MS / 1000) * height * 0.5;

			if (y <= -height - 50)
			{
				visible = false;
				active = false;

				#if FLX_SAVE
				// Save sound preferences
				if (FlxG.save.isBound)
				{
					FlxG.save.data.mute = FlxG.sound.muted;
					FlxG.save.data.volume = FlxG.sound.volume;
					FlxG.save.flush();
				}
				#end
			}
		}
	}

	/**
	 * Makes the little volume tray slide out.
	 *
	 * @param	up Whether the volume is increasing.
	 */
	public function show(up:Bool = false):Void
	{
		if (!silent)
		{
			var sound = FlxAssets.getSoundAddExtension(up ? volumeUpSound : volumeDownSound);
			if (sound != null)
				FlxG.sound.load(sound).play();
		}

		_timer = 1;
		y = 50;
		visible = true;
		active = true;

		var currentVolume:Float = FlxG.sound.muted ? 0.0 : FlxG.sound.volume;

		// Update volume text
		var volumePercent:Int = Math.round(currentVolume * 100);
		_volumeText.text = FlxG.sound.muted ? "VOLUME: MUTE" : 'VOLUME: $volumePercent%';

		// Set target volume for animation
		_targetVolume = currentVolume;
	}

	public function screenCenter():Void
	{
		scaleX = _defaultScale;
		scaleY = _defaultScale;

		x = (0.5 * (Lib.current.stage.stageWidth - _width * _defaultScale));
	}

	/**
	 * Draws a simple solid background without gradient and border.
	 */
	function drawBackground():Void
	{
		var g:Graphics = _background.graphics;
		g.clear();

		// Simple solid fill background
		g.beginFill(0x1a1a1a, 0.95);
		g.drawRoundRect(0, 0, _width, _height, 8, 8);
		g.endFill();
	}

	/**
	 * Updates the volume progress bar based on current volume with smooth animation.
	 * @param	volume Current volume (0.0 to 1.0)
	 */
	function updateVolumeBar(volume:Float):Void
	{
		var g:Graphics = _volumeBar.graphics;
		g.clear();

		var barWidth:Float = (_width - 20) * volume;
		var barHeight:Float = 12;

		// Hide progress bar background when volume is 0
		if (_barBg != null)
		{
			_barBg.visible = volume > 0;
		}

		if (barWidth > 0)
		{
			// Create gradient for the volume bar
			var barColor:Int = getVolumeBarColor(volume);

			// Draw the progress bar with gradient
			var colors:Array<Int> = [barColor, getVolumeBarColor(volume * 0.7)];
			var alphas:Array<Float> = [1.0, 0.9];
			var ratios:Array<Int> = [0, 255];
			var matrix:Matrix = new Matrix();
			matrix.createGradientBox(barWidth, barHeight);

			g.beginGradientFill(
				openfl.display.GradientType.LINEAR,
				colors,
				alphas,
				ratios,
				matrix
			);

			g.drawRoundRect(0, 0, barWidth, barHeight, 6, 6);
			g.endFill();
		}
	}

	/**
	 * Gets the color for the volume bar based on volume level.
	 * Colors transition from green (low volume) to yellow to red (high volume).
	 */
	function getVolumeBarColor(volume:Float):Int
	{
		if (volume < 0.33)
		{
			// Green to yellow
			var ratio:Float = volume / 0.33;
			var r:Int = Math.floor(76 + (255 - 76) * ratio);
			var g:Int = Math.floor(175 + (235 - 175) * ratio);
			var b:Int = Math.floor(80 + (59 - 80) * ratio);
			return FlxColor.fromRGB(r, g, b);
		}
		else
		{
			// Yellow to red
			var ratio:Float = (volume - 0.33) / 0.67;
			var r:Int = 255;
			var g:Int = Math.floor(235 - (235 - 64) * ratio);
			var b:Int = Math.floor(59 + (129 - 59) * ratio);
			return FlxColor.fromRGB(r, g, b);
		}
	}

	/**
	 * Gets the color for a volume bar based on its index.
	 * Colors transition from green (low volume) to yellow to red (high volume).
	 */
	@:deprecated("Use getVolumeBarColor instead")
	function getBarColor(index:Int):Int
	{
		return getVolumeBarColor(index / 10.0);
	}
}
#end
