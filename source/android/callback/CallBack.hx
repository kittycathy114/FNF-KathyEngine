package android.callback;

import lime._internal.backend.android.JNICache;
import lime.system.JNI;
import haxe.Json;
import lime.app.Event;

using StringTools;

/**
 * Utility class to manage callbacks from native code using JNI.
 * This class provides initialization methods and events for handling
 * activity results and permissions results from native code.
 */
#if android
#if !lime_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
class CallBack
{
	/**
	 * Event triggered when an activity result is received.
	 * Handlers should expect a dynamic argument.
	 */
	public static var onActivityResult:Event<Dynamic->Void>;

	/**
	 * Event triggered when a permissions result is received.
	 * Handlers should expect a dynamic argument.
	 */
	public static var onRequestPermissionsResult:Event<Dynamic->Void>;

	@:noCompletion
	private static var initialized:Bool = false;

	/**
	 * Initializes the callback handling mechanism.
	 * This method should be called once before using any callback events.
	 */
	public static function init():Void
	{
		if (initialized)
			return;

		onActivityResult = new Event<Dynamic->Void>();
		onRequestPermissionsResult = new Event<Dynamic->Void>();

		JNICache.createStaticMethod('org/haxe/extension/Tools', 'initCallBack', '(Lorg/haxe/lime/HaxeObject;)V')(new CallBackHandler());

		initialized = true;
	}
}

/**
 * Internal class to handle native callback events.
 */
@:keep
@:noCompletion
#if !lime_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
private class CallBackHandler implements JNISafety
{
	public function new():Void {}

	/**
	 * Handles the activity result callback from native code.
	 *
	 * @param content The JSON string containing the activity result data.
	 */
	@:runOnMainThread
	public function onActivityResult(content:String):Void
	{
		if (CallBack.onActivityResult != null)
		{
			CallBack.onActivityResult.dispatch(Json.parse(content.trim()));
		}
	}

	/**
	 * Handles the permissions result callback from native code.
	 *
	 * @param content The JSON string containing the permissions result data.
	 */
	@:runOnMainThread
	public function onRequestPermissionsResult(content:String):Void
	{
		if (CallBack.onRequestPermissionsResult != null)
		{
			CallBack.onRequestPermissionsResult.dispatch(Json.parse(content.trim()));
		}
	}
}
#end
