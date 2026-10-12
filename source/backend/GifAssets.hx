package backend;

import com.yagp.Gif;
import com.yagp.GifDecoder;
import flixel.util.FlxTimer;
import openfl.utils.Assets;
import openfl.utils.ByteArray;
#if sys
import Sys;
#end

/**
 * GIF 解码结果的全局缓存 + 后台线程异步解码。
 *
 * 背景：FlxGifSprite.loadGif 会在主线程同步解码全部帧（如 minispeaki.gif 73 帧约 500 万像素，
 * 解码数据约 19MB），低端机上进入设置界面会卡顿数秒。这里把解码放到后台线程（cpp/neko 支持），
 * 完成后通过 EnterFrame 在主线程回调；解码结果全局缓存，避免重复解码。
 *
 * 注意：解码出的 Gif 数据会被永久缓存（受保护，不随状态销毁），请只在确有高频复用价值的
 * 资源上使用（如设置界面反复进入的装饰 GIF）。
 */
class GifAssets
{
	static var cache:Map<String, Gif> = [];
	static var loading:Map<String, Bool> = [];
	static var pending:Map<String, Array<Gif->Void>> = [];
	static var errorHandlers:Map<String, Array<Void->Void>> = [];

	public static function getCached(key:String):Null<Gif>
	{
		return cache.get(key);
	}

	/**
	 * 异步加载并解码 GIF。
	 * @param key 资源路径，如 'assets/shared/images/gifs/minispeaki.gif'（与 FlxGifSprite.loadGif 一致）
	 * @param onComplete 解码成功回调（主线程），参数为已解码的 Gif
	 * @param onError 解码失败回调（主线程），可选
	 */
	public static function load(key:String, onComplete:Gif->Void, ?onError:Void->Void):Void
	{
		var cached:Gif = cache.get(key);
		if (cached != null)
		{
			#if sys
			trace('[GifAssets] cache hit (async): $key');
			#end
			// 强制异步回调：避免缓存对象被旧 GifPlayer 改坏内部帧状态时，
			// 同步 new GifPlayer(gif) 在构造函数中间崩溃（二次进入子设置界面）
			new FlxTimer().start(0, function(_:FlxTimer) { onComplete(cached); });
			return;
		}

		// 同一资源解码中：排队等待，解码完成后统一回调
		if (loading.get(key) == true)
		{
			#if sys
			trace('[GifAssets] already loading, queued: $key');
			#end
			var cbs:Array<Gif->Void> = pending.get(key);
			if (cbs == null)
			{
				cbs = [];
				pending.set(key, cbs);
			}
			cbs.push(onComplete);
			if (onError != null)
			{
				var errs:Array<Void->Void> = errorHandlers.get(key);
				if (errs == null)
				{
					errs = [];
					errorHandlers.set(key, errs);
				}
				errs.push(onError);
			}
			return;
		}

		loading.set(key, true);
		pending.set(key, [onComplete]);
		if (onError != null)
			errorHandlers.set(key, [onError]);

		#if (neko || cpp)
		#if sys
		var tRead:Float = Sys.cpuTime();
		#end
		var bytes:ByteArray = Assets.getBytes(key);
		#if sys
		trace('[GifAssets] getBytes took ${Std.int((Sys.cpuTime() - tRead) * 1000)}ms, bytes=${bytes == null ? "null" : Std.string(bytes.length)}');
		var tDec:Float = Sys.cpuTime();
		#end
		if (bytes != null && GifDecoder.parseByteArrayAsync(bytes, function(gif:Gif) {
			#if sys
			trace('[GifAssets] async decode took ${Std.int((Sys.cpuTime() - tDec) * 1000)}ms');
			#end
			// 主线程回调（parseBytesAsync 通过 stage EnterFrame 在主线程派发）
			finishLoad(key, gif);
		}, function(err:Dynamic) {
			finishLoad(key, null);
		}))
		{
			return;
		}
		// 异步启动失败（非 cpp/neko，或 getBytes 失败），回退为同步解码
		var gif:Gif = null;
		if (bytes != null)
		{
			try { gif = GifDecoder.parseByteArray(bytes); } catch (e:Dynamic) {}
		}
		finishLoad(key, gif);
		#else
		var gif:Gif = null;
		try { gif = GifDecoder.parseByteArray(Assets.getBytes(key)); } catch (e:Dynamic) {}
		finishLoad(key, gif);
		#end
	}

	// 解码完成/失败：分发结果（主线程调用）
	static function finishLoad(key:String, gif:Null<Gif>):Void
	{
		loading.set(key, false);
		var cbs:Array<Gif->Void> = pending.get(key);
		var errs:Array<Void->Void> = errorHandlers.get(key);
		pending.remove(key);
		errorHandlers.remove(key);

		if (gif != null)
			cache.set(key, gif);

		if (cbs != null)
		{
			for (cb in cbs)
			{
				if (gif != null)
					cb(gif);
			}
		}
		if (gif == null && errs != null)
		{
			for (e in errs)
				e();
		}
	}
}
