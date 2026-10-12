package objects;

import com.yagp.Gif;
import com.yagp.GifPlayer;
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;

/**
 * 与 FlxGifSprite 功能一致的 GIF 精灵，但支持直接挂载已解码的 Gif（配合 GifAssets 后台解码/缓存），
 * 并允许在销毁时不释放共享的 Gif 解码数据。
 */
class GifSprite extends FlxSprite
{
	/**
	 * The Gif Player (warning: can be `null`).
	 */
	public var player(default, null):GifPlayer;

	/**
	 * 销毁时是否释放解码出的 Gif 数据。当 Gif 由 GifAssets 全局缓存共享时应为 false。
	 */
	public var disposeGifOnDestroy:Bool = true;

	/**
	 * 跳过 GIF 帧更新（冻结在当前帧，当作静态贴图使用）。
	 * 用于只需 GIF 第一帧做装饰、不想有帧播放开销的场景。
	 */
	public var skipPlayerUpdate:Bool = false;

	public function new(?x:Float = 0, ?y:Float = 0)
	{
		super(x, y);
	}

	/**
	 * 直接挂载一个已解码的 Gif（不再重复解码），并重置图形为第一帧。
	 * @param gif 已解码的 Gif（通常来自 GifAssets 缓存/后台线程解码结果）
	 * @return This `GifSprite` instance (nice for chaining stuff together).
	 */
	public function attachGif(gif:Gif):GifSprite
	{
		if (player != null)
		{
			player.dispose(false); // 不释放旧 Gif：可能被其他精灵共享
			player = null;
		}
		player = new GifPlayer(gif);
		loadGraphic(FlxGraphic.fromBitmapData(player.data, false, null, false));
		return this;
	}

	public override function update(elapsed:Float):Void
	{
		if (player != null && !skipPlayerUpdate)
			player.update(elapsed);

		super.update(elapsed);
	}

	public override function destroy():Void
	{
		super.destroy();

		if (player != null)
		{
			player.dispose(disposeGifOnDestroy);
			player = null;
		}
	}
}
