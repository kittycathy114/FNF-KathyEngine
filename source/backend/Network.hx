package backend;

import flixel.FlxG;

/**
 * 联网行为集中拦截层。
 *
 * 所有运行时联网入口（HTTP 请求、打开浏览器、Discord RPC 等）都应经过本类，
 * 以便通过 `ClientPrefs.data.disableNetworking` 这一个开关统一禁用 / hook 掉
 * 全部联网行为。
 */
class Network
{
	/**
	 * 当前是否处于"禁用联网"状态。
	 * 在 `ClientPrefs.data` 尚未初始化时（极早期）安全返回 false。
	 */
	public static function isNetworkingDisabled():Bool
	{
		return (ClientPrefs.data != null && ClientPrefs.data.disableNetworking);
	}

	/**
	 * 统一的 HTTP GET 封装（异步，不阻塞主线程）。
	 *
	 * 使用 `lime.net.HTTPRequest` 而非 `haxe.Http`：后者在 native(cpp) 平台
	 * 上的 `request()` 是同步阻塞的，会导致每次进主界面时主线程卡住等待网络响应。
	 * `HTTPRequest.load()` 在 native 上由后台线程 + 事件循环驱动，不会阻塞 UI。
	 *
	 * 当联网被禁用时不会发起任何请求，并会调用一次 `onError('networking disabled')`（若提供）。
	 *
	 * @param url       请求地址
	 * @param onData    成功回调（被拦截时不会触发，参数为响应文本）
	 * @param onError   失败回调（被拦截时会以原因字符串调用一次）
	 * @param userAgent 可选 User-Agent（GitHub API 要求请求必须携带 UA，否则返回 403）
	 * @return 实际发起的 `lime.net.HTTPRequest`，被拦截时返回 null
	 */
	public static function httpGet(url:String, ?onData:String->Void, ?onError:Dynamic->Void, ?userAgent:String):lime.net.HTTPRequest<Dynamic>
	{
		if (isNetworkingDisabled())
		{
			trace('[Network] networking disabled, skipping HTTP request to: $url');
			if (onError != null) onError('networking disabled');
			return null;
		}

		final req = new lime.net.HTTPRequest<Dynamic>();
		if (userAgent != null && userAgent.length > 0)
			req.userAgent = userAgent;
		req.load(url).onComplete(function(data:Dynamic) {
			if (onData != null) onData(Std.string(data));
		}).onError(function(error:Dynamic) {
			if (onError != null) onError(error);
		});
		return req;
	}

	/**
	 * 封装"打开外部浏览器/链接"。
	 * 当联网被禁用时静默跳过，不会唤起任何外部程序。
	 */
	public static function openURL(site:String):Void
	{
		if (isNetworkingDisabled())
		{
			trace('[Network] networking disabled, skipping openURL: $site');
			return;
		}

		#if linux
		Sys.command('/usr/bin/xdg-open', [site]);
		#else
		FlxG.openURL(site);
		#end
	}
}
