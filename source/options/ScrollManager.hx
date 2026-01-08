package options;

import flixel.math.FlxMath;
import flixel.FlxG;

/**
 * Manages scrolling physics and calculations for option menus
 * Simple vertical scrolling without parallax effects
 */
class ScrollManager
{
	public var scrollOffset:Float = 0;

	private var optionCount:Int = 0;
	private var itemSpacing:Int;

	public function new(optionCount:Int, itemSpacing:Int)
	{
		this.optionCount = optionCount;
		this.itemSpacing = itemSpacing;
	}

	/**
	 * Update scrolling based on mouse/touch input
	 * @param mousePressed Whether mouse is pressed
	 * @param mouseY Current mouse Y position
	 * @param mouseOverOption Whether mouse is over an option
	 * @return Whether scroll changed this frame
	 */
	public function update(mousePressed:Bool, mouseY:Float, mouseOverOption:Bool):Bool
	{
		var changed = false;

		// Handle drag input (no inertia, direct 1:1 movement)
		if (mousePressed && !mouseOverOption)
		{
			var deltaY = mouseY - _lastMouseY;
			scrollOffset += deltaY;
			_lastMouseY = mouseY;
			changed = true;
		}
		else if (!mousePressed)
		{
			_lastMouseY = null;
		}

		// Clamp to bounds
		clampScroll();

		return changed;
	}

	/**
	 * Start a drag interaction
	 */
	public function startDrag(startY:Float):Void
	{
		_lastMouseY = startY;
	}

	/**
	 * Clamp scroll offset to valid range
	 */
	private function clampScroll():Void
	{
		var minScroll = -(itemSpacing * (optionCount - 1));
		var maxScroll = 0;
		scrollOffset = FlxMath.bound(scrollOffset, minScroll, maxScroll);
	}

	/**
	 * Calculate target Y position (no parallax)
	 * @param baseY The base Y position
	 * @return Target Y position with scroll applied
	 */
	public function getTargetY(baseY:Float):Float
	{
		return baseY + scrollOffset;
	}

	/**
	 * Reset scroll to default position
	 */
	public function reset():Void
	{
		scrollOffset = 0;
		_lastMouseY = null;
	}

	private var _lastMouseY:Null<Float> = null;
}
