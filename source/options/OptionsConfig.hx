package options;

/**
 * Options configuration constants
 * Centralized configuration for menu layout and behavior
 */
class OptionsConfig
{
	// Layout spacing
	public static final ITEM_SPACING:Int = 72;
	public static final LEFT_MARGIN:Int = 120;

	// Animation speeds
	public static final SELECTOR_LERP_SPEED:Float = 12;
	public static final SCALE_LERP_SPEED:Float = 16;

	// Selection scaling
	public static final SELECTED_SCALE:Float = 1.08;
	public static final NORMAL_SCALE:Float = 1.0;

	// Interaction timings
	public static final DOUBLE_CLICK_THRESHOLD:Float = 0.25;
	public static final INPUT_COOLDOWN:Float = 0.5;
	public static final TWEEN_DURATION:Float = 0.3;

	// Description box
	public static final DESC_Y_START:Float = -250;
	public static final DESC_Y_END:Float = -200;

	// Keybind settings
	public static final HOLD_THRESHOLD:Float = 0.5;
	public static final MAX_KEYBIND_WIDTH:Int = 320;
}
