package backend;

/** 导入结果 */
class ImportResult
{
	public function new() {}
	public var success:Bool = false;
	public var errorMsg:String = '';
	public var loadedSections:Array<String> = [];
	public var skippedSections:Array<String> = [];
	public var appliedFieldCount:Int = 0;
	public var typeMismatchCount:Int = 0; // 因类型不匹配而跳过的字段数
}
