package backend;

import openfl.utils.Assets;
import lime.utils.Assets as LimeAssets;
import flixel.addons.display.FlxGridOverlay;
import flixel.graphics.FlxGraphic;
import flixel.FlxG;

#if cpp
@:cppFileCode('#include <thread>')
#end
class CoolUtil
{
	private static var cachedTips:String = null;
	private static var _coolTextFileCache:Map<String, Array<String>> = null;
	private static var _gridCache:Map<String, FlxGraphic> = null;
	private static var _updateCheckDone:Bool = false;
	private static var _updateCheckPending:Bool = false;

	public static function checkForUpdates(?onComplete:(latestVersion:String, isOutdated:Bool)->Void, url:String = null):Void {
		var version:String = states.MainMenuState.kathyEngineVersion;
		if(!ClientPrefs.data.checkForUpdates) {
			if(onComplete != null) onComplete(version, false);
			return;
		}
		if(_updateCheckDone) {
			if(onComplete != null) onComplete(version, false);
			return;
		}
		if(_updateCheckPending) return;
		_updateCheckPending = true;
		if (url == null || url.length == 0)
			url = "https://raw.githubusercontent.com/kittycathy114/FNF-KathyEngine/main/gitVersion.txt";
		final fallbackUrl:String = "https://cdn.jsdelivr.net/gh/kittycathy114/FNF-KathyEngine@main/gitVersion.txt";

		trace('checking for updates... ($url)');
		Network.httpGet(url,
			function (data:String) {
				_updateCheckDone = true;
				var newVersion:String = data.split('\n')[0].trim();
				trace('version online: $newVersion, your version: $version');
				if(versionCompare(newVersion, version) > 0) {
					trace('a new version is available!');
					if(onComplete != null) onComplete(newVersion, true);
				} else {
					trace('you are on the latest version');
					if(onComplete != null) onComplete(version, false);
				}
			},
			function (error) {
				// 官方 GitHub 不可用时，回退到 jsDelivr CDN
				if (url != fallbackUrl) {
					trace('failed to check (official github): $error, fallback to jsdelivr');
					checkForUpdates(onComplete, fallbackUrl);
				} else {
					_updateCheckDone = true;
					trace('failed to check for updates: $error');
					if(onComplete != null) onComplete(version, false);
				}
			});
	}

	/**
	 * 语义化版本比较。会自动忽略 " dev" 之类的附加后缀，只比较主.次.修订号。
	 * @return >0 表示 a 比 b 新，<0 表示 a 比 b 旧，0 表示相等
	 */
	public static function versionCompare(a:String, b:String):Int
	{
		var va:String = a.split(' ')[0].trim();
		var vb:String = b.split(' ')[0].trim();
		var pa:Array<String> = va.split('.');
		var pb:Array<String> = vb.split('.');
		var len:Int = Std.int(Math.max(pa.length, pb.length));
		for (i in 0...len)
		{
			var na:Int = (i < pa.length) ? Std.parseInt(pa[i]) : 0;
			var nb:Int = (i < pb.length) ? Std.parseInt(pb[i]) : 0;
			if (na > nb) return 1;
			if (na < nb) return -1;
		}
		return 0;
	}

	public static function tipsShow(?onComplete:String->Void, url:String = null, forceReload:Bool = false):Void {
		if (!forceReload && cachedTips != null) {
			if (onComplete != null) onComplete(cachedTips);
			return;
		}

		if (url == null || url.length == 0)
			url = "https://raw.githubusercontent.com/kittycathy332/FNF-Kathy-Things/main/engine/menu/tips/" + ClientPrefs.data.language + ".txt";

		trace('searching for tips... ($url)');
		Network.httpGet(url,
			function (data:String)
			{
				cachedTips = data.trim(); // 缓存结果
				if (onComplete != null) onComplete(cachedTips);
			},
			function (error) {
				// 语言专属文件不存在时，回退到简体中文
				if (url.indexOf("zh_cn.txt") == -1) {
					trace('tip file for current language unavailable, fallback to zh_cn: $error');
					tipsShow(onComplete, "https://raw.githubusercontent.com/kittycathy332/FNF-Kathy-Things/main/engine/menu/tips/zh_cn.txt", forceReload);
				} else {
					trace('error: $error');
					if (onComplete != null) onComplete('');
				}
			});
	}

	inline public static function quantize(f:Float, snap:Float){
		// changed so this actually works lol
		var m:Float = Math.fround(f * snap);
		//trace(snap);
		return (m / snap);
	}

	public static function coolLerp(base:Float, target:Float, ratio:Float):Float
		return base + cameraLerp(ratio) * (target - base);

	public static function cameraLerp(lerp:Float):Float
		return lerp * (FlxG.elapsed / (1 / 60));

	inline public static function capitalize(text:String)
		return text.charAt(0).toUpperCase() + text.substr(1).toLowerCase();

	inline public static function coolTextFile(path:String):Array<String>
	{
		if (_coolTextFileCache == null) _coolTextFileCache = [];
		if (_coolTextFileCache.exists(path)) return _coolTextFileCache.get(path);

		var daList:String = null;
		#if (sys && MODS_ALLOWED)
		if(FileSystem.exists(path)) daList = File.getContent(path);
		#else
		if(Assets.exists(path)) daList = Assets.getText(path);
		#end
		var result:Array<String> = daList != null ? listFromString(daList) : [];
		_coolTextFileCache.set(path, result);
		return result;
	}

	public static function invalidateCoolTextFileCache(?path:String):Void
	{
		if (_coolTextFileCache == null) return;
		if (path == null)
			_coolTextFileCache = [];
		else if (_coolTextFileCache.exists(path))
			_coolTextFileCache.remove(path);
	}

	public static function getCachedGrid(columns:Int, rows:Int, pWidth:Int, pHeight:Int, useRect:Bool, color1:Int, color2:Int):FlxGraphic
	{
		if (_gridCache == null) _gridCache = [];
		var key:String = '$columns,$rows,$pWidth,$pHeight,$useRect,$color1,$color2';
		if (_gridCache.exists(key))
		{
			var cached:FlxGraphic = _gridCache.get(key);
			if (cached.bitmap != null && cached.bitmap.width > 0)
				return cached;
			_gridCache.remove(key);
		}
		var bmp = FlxGridOverlay.createGrid(columns, rows, pWidth, pHeight, useRect, color1, color2);
		var graphic:FlxGraphic = FlxG.bitmap.add(bmp, true, 'cached_grid_$key');
		graphic.persist = true;
		graphic.destroyOnNoUse = false;
		_gridCache.set(key, graphic);
		return graphic;
	}

	inline public static function colorFromString(color:String):FlxColor
	{
		var hideChars = ~/[\t\n\r]/;
		var color:String = hideChars.split(color).join('').trim();
		if(color.startsWith('0x')) color = color.substring(color.length - 6);

		var colorNum:Null<FlxColor> = FlxColor.fromString(color);
		if(colorNum == null) colorNum = FlxColor.fromString('#$color');
		return colorNum != null ? colorNum : FlxColor.WHITE;
	}

	inline public static function listFromString(string:String):Array<String>
	{
		var daList:Array<String> = [];
		daList = string.trim().split('\n');

		for (i in 0...daList.length)
			daList[i] = daList[i].trim();

		return daList;
	}

	public static function floorDecimal(value:Float, decimals:Int):Float
	{
		if(decimals < 1)
			return Math.floor(value);

		return Math.floor(value * Math.pow(10, decimals)) / Math.pow(10, decimals);
	}

	#if linux
	public static function sortAlphabetically(list:Array<String>):Array<String> {
		if (list == null) return [];

		list.sort((a, b) -> {
			var upperA = a.toUpperCase();
			var upperB = b.toUpperCase();
			
			return upperA < upperB ? -1 : upperA > upperB ? 1 : 0;
		});
		return list;
	}
	#end

	inline public static function dominantColor(sprite:flixel.FlxSprite):Int
	{
		var countByColor:Map<Int, Int> = [];
		for(col in 0...sprite.frameWidth)
		{
			for(row in 0...sprite.frameHeight)
			{
				var colorOfThisPixel:FlxColor = sprite.pixels.getPixel32(col, row);
				if(colorOfThisPixel.alphaFloat > 0.05)
				{
					colorOfThisPixel = FlxColor.fromRGB(colorOfThisPixel.red, colorOfThisPixel.green, colorOfThisPixel.blue, 255);
					var count:Int = countByColor.exists(colorOfThisPixel) ? countByColor[colorOfThisPixel] : 0;
					countByColor[colorOfThisPixel] = count + 1;
				}
			}
		}

		var maxCount = 0;
		var maxKey:Int = 0; //after the loop this will store the max color
		countByColor[FlxColor.BLACK] = 0;
		for(key => count in countByColor)
		{
			if(count >= maxCount)
			{
				maxCount = count;
				maxKey = key;
			}
		}
		countByColor = [];
		return maxKey;
	}

	inline public static function numberArray(max:Int, ?min = 0):Array<Int>
	{
		var dumbArray:Array<Int> = [];
		for (i in min...max) dumbArray.push(i);

		return dumbArray;
	}

	inline public static function browserLoad(site:String) {
		Network.openURL(site);
	}

	inline public static function openFolder(folder:String, absolute:Bool = false) {
		#if sys
			if(!absolute) folder =  Sys.getCwd() + '$folder';

			folder = folder.replace('/', '\\');
			if(folder.endsWith('/')) folder.substr(0, folder.length - 1);

			#if linux
			var command:String = '/usr/bin/xdg-open';
			#else
			var command:String = 'explorer.exe';
			#end
			Sys.command(command, [folder]);
			trace('$command $folder');
		#else
			FlxG.error("Platform is not supported for CoolUtil.openFolder");
		#end
	}

	/**
		Helper Function to Fix Save Files for Flixel 5

		-- EDIT: [November 29, 2023] --

		this function is used to get the save path, period.
		since newer flixel versions are being enforced anyways.
		@crowplexus
	**/
	@:access(flixel.util.FlxSave.validate)
	inline public static function getSavePath():String {
		final company:String = FlxG.stage.application.meta.get('company');
		// #if (flixel < "5.0.0") return company; #else
		return '${company}/${flixel.util.FlxSave.validate(FlxG.stage.application.meta.get('file'))}';
		// #end
	}

	public static function setTextBorderFromString(text:FlxText, border:String)
	{
		switch(border.toLowerCase().trim())
		{
			case 'shadow':
				text.borderStyle = SHADOW;
			case 'outline':
				text.borderStyle = OUTLINE;
			case 'outline_fast', 'outlinefast':
				text.borderStyle = OUTLINE_FAST;
			default:
				text.borderStyle = NONE;
		}
	}

	public static function showPopUp(message:String, title:String, ?onOk:()->Void):Void
	{
		#if android
		AndroidTools.showAlertDialog(title, message, {name: "OK", func: onOk != null ? onOk : null}, null);
		#else
		FlxG.stage.window.alert(message, title);
		if (onOk != null) onOk();
		#end
	}

	#if mobile
	public static function showConfirmDialog(message:String, title:String, onConfirm:()->Void, ?onCancel:()->Void):Void
	{
		#if android
		AndroidTools.showAlertDialog(title, message,
			{name: Language.get("confirm_button"), func: onConfirm},
			{name: Language.get("cancel_button"), func: onCancel != null ? onCancel : function() {}}
		);
		#else
		FlxG.stage.window.alert(message, title);
		if (onCancel != null) onCancel();
		#end
	}
	#end

	#if cpp
    @:functionCode('
        return std::thread::hardware_concurrency();
    ')
	#end
    public static function getCPUThreadsCount():Int
    {
        return 1;
    }
}
