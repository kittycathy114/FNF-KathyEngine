package options;

import flixel.input.keyboard.FlxKey;
import flixel.input.gamepad.FlxGamepadInputID;
import flixel.input.gamepad.FlxGamepad;
import flixel.FlxG;
import flixel.tweens.FlxTween;
import objects.Alphabet;
import objects.AttachedText;
import backend.InputFormatter;

/**
 * Handles keybinding UI logic and interactions
 * Manages the binding state, UI elements, and input detection
 */
class KeybindManager
{
	public var isBinding:Bool = false;
	
	private var bindingOverlay:FlxSprite;
	private var bindingTitle:Alphabet;
	private var bindingInstructions:Alphabet;
	private var curOption:Option;
	private var holdingEsc:Float = 0;
	private var onComplete:Void->Void;
	
	public function new() {}
	
	/**
	 * Start binding a key for the given option
	 */
	public function startBinding(option:Option, onComplete:Void->Void):Void
	{
		if (option.type != KEYBIND) return;
		
		this.curOption = option;
		this.onComplete = onComplete;
		this.isBinding = true;
		this.holdingEsc = 0;
		
		// Create overlay
		bindingOverlay = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		bindingOverlay.scale.set(FlxG.width, FlxG.height);
		bindingOverlay.updateHitbox();
		bindingOverlay.alpha = 0;
		FlxTween.tween(bindingOverlay, {alpha: 0.6}, 0.35, {ease: FlxEase.linear});
		
		// Create title
		bindingTitle = new Alphabet(
			FlxG.width / 2, 
			160, 
			LanguageBasic.getPhrase('controls_rebinding', 'Rebinding {1}', [option.name]), 
			false
		);
		bindingTitle.alignment = CENTERED;
		
		// Create instructions
		final escapeKey = Controls.instance.mobileC ? "B" : "ESC";
		final backspaceKey = Controls.instance.mobileC ? "C" : "Backspace";
		bindingInstructions = new Alphabet(
			FlxG.width / 2, 
			340, 
			LanguageBasic.getPhrase('controls_rebinding2', 'Hold {1} to Cancel\nHold {2} to Delete', [escapeKey, backspaceKey]), 
			true
		);
		bindingInstructions.alignment = CENTERED;
		
		ClientPrefs.toggleVolumeKeys(false);
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}
	
	/**
	 * Update binding state
	 * @param elapsed Time since last frame
	 * @return Whether binding was completed or cancelled
	 */
	public function update(elapsed:Float):Bool
	{
		if (!isBinding) return false;
		
		// Check for cancel/delete hold
		if (checkCancelDelete(elapsed)) {
			return true;
		}
		
		// Check for key input
		if (checkKeyInput()) {
			return true;
		}
		
		return false;
	}
	
	/**
	 * Check for cancel or delete button holds
	 */
	private function checkCancelDelete(elapsed:Float):Bool
	{
		// Cancel (ESC / B)
		if (FlxG.keys.pressed.ESCAPE || FlxG.gamepads.anyPressed(B))
		{
			holdingEsc += elapsed;
			if (holdingEsc > OptionsConfig.HOLD_THRESHOLD)
			{
				cancelBinding();
				return true;
			}
		}
		// Delete (Backspace / C)
		else if (FlxG.keys.pressed.BACKSPACE || FlxG.gamepads.anyPressed(BACK))
		{
			holdingEsc += elapsed;
			if (holdingEsc > OptionsConfig.HOLD_THRESHOLD)
			{
				deleteBinding();
				return true;
			}
		}
		else
		{
			holdingEsc = 0;
		}

		return false;
	}
	
	/**
	 * Check for new key input
	 */
	private function checkKeyInput():Bool
	{
		var changed = false;
		
		if (!Controls.instance.controllerMode)
		{
			changed = checkKeyboardInput();
		}
		else
		{
			changed = checkGamepadInput();
		}
		
		if (changed)
		{
			completeBinding();
			return true;
		}
		
		return false;
	}
	
	/**
	 * Check for keyboard input
	 */
	private function checkKeyboardInput():Bool
	{
		if (!FlxG.keys.justPressed.ANY && !FlxG.keys.justReleased.ANY) return false;

		var keyPressed:FlxKey = cast (FlxG.keys.firstJustPressed(), FlxKey);
		var keyReleased:FlxKey = cast (FlxG.keys.firstJustReleased(), FlxKey);

		if (keyPressed != FlxKey.NONE && keyPressed != FlxKey.ESCAPE && keyPressed != FlxKey.BACKSPACE)
		{
			curOption.keys.keyboard = keyPressed;
			return true;
		}
		else if (keyReleased != FlxKey.NONE && (keyReleased == FlxKey.ESCAPE || keyReleased == FlxKey.BACKSPACE))
		{
			curOption.keys.keyboard = keyReleased;
			return true;
		}

		return false;
	}
	
	/**
	 * Check for gamepad input
	 */
	private function checkGamepadInput():Bool
	{
		if (!FlxG.gamepads.anyJustPressed(FlxGamepadInputID.ANY) &&
			!FlxG.gamepads.anyJustPressed(FlxGamepadInputID.LEFT_TRIGGER) &&
			!FlxG.gamepads.anyJustPressed(FlxGamepadInputID.RIGHT_TRIGGER) &&
			!FlxG.gamepads.anyJustReleased(FlxGamepadInputID.ANY))
		{
			return false;
		}

		var keyPressed:FlxGamepadInputID = FlxGamepadInputID.NONE;
		var keyReleased:FlxGamepadInputID = FlxGamepadInputID.NONE;

		// Handle triggers separately
		if (FlxG.gamepads.anyJustPressed(FlxGamepadInputID.LEFT_TRIGGER))
		{
			keyPressed = FlxGamepadInputID.LEFT_TRIGGER;
		}
		else if (FlxG.gamepads.anyJustPressed(FlxGamepadInputID.RIGHT_TRIGGER))
		{
			keyPressed = FlxGamepadInputID.RIGHT_TRIGGER;
		}
		else
		{
			for (i in 0...FlxG.gamepads.numActiveGamepads)
			{
				var gamepad:FlxGamepad = FlxG.gamepads.getByID(i);
				if (gamepad != null)
				{
					keyPressed = gamepad.firstJustPressedID();
					keyReleased = gamepad.firstJustReleasedID();
					if (keyPressed != FlxGamepadInputID.NONE || keyReleased != FlxGamepadInputID.NONE) break;
				}
			}
		}

		if (keyPressed != FlxGamepadInputID.NONE && keyPressed != FlxGamepadInputID.BACK && keyPressed != FlxGamepadInputID.B)
		{
			curOption.keys.gamepad = keyPressed;
			return true;
		}
		else if (keyReleased != FlxGamepadInputID.NONE && (keyReleased == FlxGamepadInputID.BACK || keyReleased == FlxGamepadInputID.B))
		{
			curOption.keys.gamepad = keyReleased;
			return true;
		}

		return false;
	}
	
	/**
	 * Cancel current binding
	 */
	private function cancelBinding():Void
	{
		FlxG.sound.play(Paths.sound('cancelMenu'));
		closeBindingUI();
	}
	
	/**
	 * Delete current binding
	 */
	private function deleteBinding():Void
	{
		var controllerMode = Controls.instance.controllerMode;
		if (!controllerMode)
			curOption.keys.keyboard = 'NONE';
		else
			curOption.keys.gamepad = 'NONE';

		FlxG.sound.play(Paths.sound('cancelMenu'));
		closeBindingUI();
	}
	
	/**
	 * Complete binding with current key
	 */
	private function completeBinding():Void
	{
		var key:String = null;

		var controllerMode = Controls.instance.controllerMode;
		if (!controllerMode)
		{
			if (curOption.keys.keyboard == null) curOption.keys.keyboard = 'NONE';
			curOption.setValue(curOption.keys.keyboard);
			key = InputFormatter.getKeyName(FlxKey.fromString(curOption.keys.keyboard));
		}
		else
		{
			if (curOption.keys.gamepad == null) curOption.keys.gamepad = 'NONE';
			curOption.setValue(curOption.keys.gamepad);
			key = InputFormatter.getGamepadName(FlxGamepadInputID.fromString(curOption.keys.gamepad));
		}
		
		updateBindDisplay(key);
		FlxG.sound.play(Paths.sound('confirmMenu'));
		closeBindingUI();
		
		if (onComplete != null) onComplete();
	}
	
	/**
	 * Update the displayed key text
	 * Note: This should be called from BaseOptionsMenu with access to grpTexts
	 */
	public function updateBindDisplay(?text:String = null, ?option:Option = null, ?grpTexts:FlxTypedGroup<AttachedText>):Void
	{
		if (option == null) option = curOption;
		if (text == null)
		{
			text = option.getValue();
			if (text == null) text = 'NONE';

			var controllerMode = Controls.instance.controllerMode;
			if (!controllerMode)
				text = InputFormatter.getKeyName(FlxKey.fromString(text));
			else
				text = InputFormatter.getGamepadName(FlxGamepadInputID.fromString(text));
		}

		if (grpTexts == null) return; // Cannot update without grpTexts reference

		var bind:AttachedText = cast option.child;
		var attach:AttachedText = new AttachedText(text, bind.offsetX);
		attach.sprTracker = bind.sprTracker;
		attach.copyAlpha = true;
		attach.ID = bind.ID;

		checkPlaystationModel(attach);
		attach.scaleX = Math.min(1, OptionsConfig.MAX_KEYBIND_WIDTH / attach.width);
		attach.x = bind.x;
		attach.y = bind.y;

		option.child = attach;
		grpTexts.insert(grpTexts.members.indexOf(bind), attach);
		grpTexts.remove(bind);
		bind.destroy();
	}
	
	/**
	 * Check if gamepad is PlayStation model and adjust icons
	 */
	private function checkPlaystationModel(alpha:Alphabet):Void
	{
		var controllerMode = Controls.instance.controllerMode;
		if (!controllerMode) return;

		var gamepad:FlxGamepad = FlxG.gamepads.firstActive;
		if (gamepad == null) return;

		// PlayStation icons are handled by InputFormatter, no need to check model here
		// Leaving placeholder for future customization
	}
	
	/**
	 * Close binding UI and cleanup
	 */
	private function closeBindingUI():Void
	{
		isBinding = false;
		
		if (bindingOverlay != null)
		{
			bindingOverlay.destroy();
			bindingOverlay = null;
		}
		
		if (bindingTitle != null)
		{
			bindingTitle.destroy();
			bindingTitle = null;
		}
		
		if (bindingInstructions != null)
		{
			bindingInstructions.destroy();
			bindingInstructions = null;
		}
		
		ClientPrefs.toggleVolumeKeys(true);
	}
	
	/**
	 * Get the binding overlay sprite for adding to display
	 */
	public function getOverlay():FlxSprite
	{
		return bindingOverlay;
	}
	
	/**
	 * Get the binding title for adding to display
	 */
	public function getTitle():Alphabet
	{
		return bindingTitle;
	}
	
	/**
	 * Get the binding instructions for adding to display
	 */
	public function getInstructions():Alphabet
	{
		return bindingInstructions;
	}
	
	/**
	 * Clean up resources
	 */
	public function destroy():Void
	{
		closeBindingUI();
		curOption = null;
		onComplete = null;
	}
}
