package backend;

/** 导出配置 */
class ExportConfig
{
	public function new() {}
	public var includePrefs:Bool = true;
	public var includeKeyboard:Bool = true;
	public var includeGamepad:Bool = true;
	public var includeMobile:Bool = true;
	public var includeGameplay:Bool = true;
	public var format:String = 'json'; // 'json' | 'base64' | 'zlib'
}
