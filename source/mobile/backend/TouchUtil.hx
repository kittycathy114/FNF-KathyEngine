/*
 * Copyright (C) 2025 Mobile Porting Team
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

package mobile.backend;

import flixel.FlxObject;
import flixel.input.touch.FlxTouch;

/**
 * ...
 * @author: Karim Akra
 */
class TouchUtil
{
	public static var pressed(get, never):Bool;
	public static var justPressed(get, never):Bool;
	public static var justReleased(get, never):Bool;
	public static var released(get, never):Bool;
	public static var touch(get, never):FlxTouch;

	// 性能优化：触摸点缓存
	private static var _cachedTouchPositions:Array<FlxPoint> = [];
	private static var _lastCacheTime:Float = -1;
	private static inline var CACHE_EXPIRE_TIME:Float = 0.016; // 60fps，约16ms

	/**
	 * 性能优化：获取缓存的触摸点位置
	 */
	public static function getCachedTouchPositions(forceRefresh:Bool = false):Array<FlxPoint>
	{
		var currentTime = FlxG.game.ticks / 1000;

		// 如果缓存过期或强制刷新，重新计算
		if (forceRefresh || _lastCacheTime < 0 || currentTime - _lastCacheTime > CACHE_EXPIRE_TIME)
		{
			updateTouchCache();
			_lastCacheTime = currentTime;
		}

		return _cachedTouchPositions;
	}

	/**
	 * 更新触摸点缓存
	 */
	private static function updateTouchCache():Void
	{
		// 清空旧缓存
		while (_cachedTouchPositions.length > 0)
		{
			var point = _cachedTouchPositions.pop();
			point.put();
		}

		// 添加新的触摸点位置
		for (touch in FlxG.touches.list)
		{
			var point = FlxPoint.get(touch.x, touch.y);
			_cachedTouchPositions.push(point);
		}
	}

	public static function overlaps(object:FlxObject, ?camera:FlxCamera):Bool
	{
		for (touch in FlxG.touches.list)
			if (touch.overlaps(object, camera ?? object.camera))
				return true;

		return false;
	}

	public static function overlapsComplex(object:FlxObject, ?camera:FlxCamera):Bool
	{
		if (camera == null)
			for (camera in object.cameras)
				for (touch in FlxG.touches.list)
					@:privateAccess
					if (object.overlapsPoint(touch.getWorldPosition(camera, object._point), true, camera))
						return true;
		else
			@:privateAccess
			if (object.overlapsPoint(touch.getWorldPosition(camera, object._point), true, camera))
				return true;

		return false;
	}

	@:noCompletion
	private static function get_pressed():Bool
	{
		for (touch in FlxG.touches.list)
			if (touch.pressed)
				return true;

		return false;
	}

	@:noCompletion
	private static function get_justPressed():Bool
	{
		for (touch in FlxG.touches.list)
			if (touch.justPressed)
				return true;

		return false;
	}

	@:noCompletion
	private static function get_justReleased():Bool
	{
		for (touch in FlxG.touches.list)
			if (touch.justReleased)
				return true;

		return false;
	}

	@:noCompletion
	private static function get_released():Bool
	{
		for (touch in FlxG.touches.list)
			if (touch.released)
				return true;

		return false;
	}

	@:noCompletion
	private static function get_touch():FlxTouch
	{
		for (touch in FlxG.touches.list)
			if (touch != null)
				return touch;

		return FlxG.touches.getFirst();
	}
}