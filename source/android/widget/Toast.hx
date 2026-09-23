package android.widget;

import lime._internal.backend.android.JNICache;

/**
 * Utility class for displaying toast messages on Android via JNI.
 */
#if android
#if !lime_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
class Toast
{
	/**
	 * Constant representing a short duration toast message.
	 */
	public static final LENGTH_SHORT:Int = 0;

	/**
	 * Constant representing a long duration toast message.
	 */
	public static final LENGTH_LONG:Int = 1;

	/**
	 * Creates and displays a toast message.
	 *
	 * @param text The text message to display in the toast.
	 * @param duration The duration of the toast message. Use `LENGTH_SHORT` or `LENGTH_LONG`.
	 * @param gravity Optional. Gravity for the toast display. Default is -1.
	 * @param xOffset Optional. Horizontal offset from the gravity position. Default is 0.
	 * @param yOffset Optional. Vertical offset from the gravity position. Default is 0.
	 */
	public static inline function makeText(text:String, duration:Int, ?gravity:Int = -1, ?xOffset:Int = 0, ?yOffset:Int = 0):Void
		JNICache.createStaticMethod('org/haxe/extension/Tools', 'makeToastText', '(Ljava/lang/String;IIII)V')(text, duration, gravity, xOffset, yOffset);
}
#end