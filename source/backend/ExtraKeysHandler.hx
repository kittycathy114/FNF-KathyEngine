package backend;

/**
 * Extra Keys 配置加载器（从 Psych EK 移植并适配到 KathyEngine）。
 *
 * 数据文件：assets/shared/data/extrakeys.json
 *
 * 核心映射：
 *   keys[mania].notes[noteData] -> 全局样式索引（0..17）
 *   animations[globalIdx]        -> 该列箭头的贴图前缀 / sing 动画 / 像素帧号
 *   colors[globalIdx]            -> 高清箭头 RGB 配色
 *   pixelNoteColors[globalIdx]   -> 像素箭头 RGB 配色
 *   keybinds[mania]              -> 该档位的默认键盘按键（FlxKey keycode 数组）
 *
 * 用法：
 *   var ek = ExtraKeysHandler.instance.data;
 *   var globalIdx = ek.keys[mania].notes[noteData];
 *   var notePrefix = ek.animations[globalIdx].note;   // "purple"/"blue"/"rombus"/"circle" ...
 *   var singAnim   = 'sing' + ek.animations[globalIdx].sing;  // "singLEFT" ...
 */
class ExtraKeysHandler
{
    public static var instance:ExtraKeysHandler;

    public var data:ExtraKeysData;

    public function new()
    {
        reload();
    }

    public static function ensure():Void
    {
        if (instance == null) instance = new ExtraKeysHandler();
    }

    public function reload():Void
    {
        trace('[EK] Loading extrakeys.json ...');
        var path:String = 'data/extrakeys.json';
        var text:String;
        #if sys
        var fsPath:String = Paths.formatToSongPath(path);
        // 尝试 mod 目录优先
        #if MODS_ALLOWED
        var modPath:String = Paths.modsJson(path);
        if (FileSystem.exists(modPath)) {
            text = File.getContent(modPath);
        } else
        #end
        {
            // 打包资源
            try {
                text = Paths.getTextFromFile(path);
            } catch (e:Dynamic) {
                trace('[EK] FAILED to load $path, falling back to defaults. Error: $e');
                data = ExtraKeysData.defaults();
                return;
            }
        }
        #else
        text = Paths.getTextFromFile(path);
        #end

        if (text == null || text.length == 0) {
            trace('[EK] empty extrakeys.json, using defaults.');
            data = ExtraKeysData.defaults();
            return;
        }

        try {
            var raw:Dynamic = haxe.Json.parse(text);
            data = ExtraKeysData.fromJson(raw);
            trace('[EK] Loaded. maxKeys=' + data.maxKeys + ' minKeys=' + data.minKeys
                + ' modeCount=' + data.keys.length);
        } catch (e:Dynamic) {
            trace('[EK] parse error: $e');
            data = ExtraKeysData.defaults();
        }
    }

    /** 便捷方法：根据 mania 档位和谱面轨道号取全局样式索引。 */
    public function globalIndex(mania:Int, noteData:Int):Int
    {
        if (data == null || data.keys == null || data.keys.length == 0) return noteData;
        var m:Int = Std.int(Math.min(Math.max(mania, data.minKeys), data.maxKeys));
        var mode:EKManiaMode = data.keys[m];
        if (mode == null || mode.notes == null || mode.notes.length == 0) return noteData;
        var lane:Int = Std.int(noteData % mode.notes.length);
        return mode.notes[lane];
    }

    /** 便捷方法：取某列的贴图前缀（purple/blue/green/red/rombus/circle...）。 */
    public function notePrefix(mania:Int, noteData:Int):String
    {
        var g:Int = globalIndex(mania, noteData);
        if (data.animations == null || g < 0 || g >= data.animations.length) return 'purple';
        return data.animations[g].note;
    }

    /** 便捷方法：取某列的 sing 动画名（如 singLEFT）。 */
    public function singAnim(mania:Int, noteData:Int):String
    {
        var g:Int = globalIndex(mania, noteData);
        if (data.animations == null || g < 0 || g >= data.animations.length) return 'singLEFT';
        return 'sing' + data.animations[g].sing;
    }

    /** 便捷方法：取某列 strum 箭头前缀（LEFT/DOWN/UP/RIGHT/ROMBUS/CIRCLE）。 */
    public function strumName(mania:Int, noteData:Int):String
    {
        var g:Int = globalIndex(mania, noteData);
        if (data.animations == null || g < 0 || g >= data.animations.length) return 'LEFT';
        return data.animations[g].strum;
    }
}

class ExtraKeysData
{
    public var minKeys:Int = 0;
    public var maxKeys:Int = 17;
    public var keys:Array<EKManiaMode> = [];
    public var colors:Array<EKNoteColor> = [];
    public var pixelNoteColors:Array<EKNoteColor> = [];
    public var animations:Array<EKAnimation> = [];
    public var keybinds:Array<Array<Array<Int>>> = [];
    public var scales:Array<Float> = [];
    public var pixelScales:Array<Float> = [];

    public function new() {}

    public static function fromJson(raw:Dynamic):ExtraKeysData
    {
        var d = new ExtraKeysData();
        if (raw == null) return defaults();

        d.minKeys = (raw.minKeys == null) ? 0 : Std.int(raw.minKeys);
        d.maxKeys = (raw.maxKeys == null) ? 17 : Std.int(raw.maxKeys);

        var arrKeys:Array<Dynamic> = cast raw.keys;
        if (arrKeys != null) {
            for (k in arrKeys) {
                var mode = new EKManiaMode();
                var arrNotes:Array<Dynamic> = cast k.notes;
                mode.notes = [];
                if (arrNotes != null) for (n in arrNotes) mode.notes.push(Std.int(n));
                d.keys.push(mode);
            }
        }
        var arrColors:Array<Dynamic> = cast raw.colors;
        if (arrColors != null) {
            for (c in arrColors) {
                var nc = new EKNoteColor();
                nc.inner = c.inner; nc.border = c.border; nc.outline = c.outline;
                d.colors.push(nc);
            }
        }
        var arrPixelColors:Array<Dynamic> = cast raw.pixelNoteColors;
        if (arrPixelColors != null) {
            for (c in arrPixelColors) {
                var nc = new EKNoteColor();
                nc.inner = c.inner; nc.border = c.border; nc.outline = c.outline;
                d.pixelNoteColors.push(nc);
            }
        }
        var arrAnims:Array<Dynamic> = cast raw.animations;
        if (arrAnims != null) {
            for (a in arrAnims) {
                var na = new EKAnimation();
                na.strum = a.strum; na.anim = a.anim; na.note = a.note;
                na.sing = a.sing; na.pixel = (a.pixel == null) ? 0 : Std.int(a.pixel);
                d.animations.push(na);
            }
        }
        var arrKeybinds:Array<Dynamic> = cast raw.keybinds;
        if (arrKeybinds != null) {
            for (kb in arrKeybinds) {
                var row:Array<Array<Int>> = [];
                var lanes:Array<Dynamic> = cast kb;
                if (lanes != null) for (lane in lanes) {
                    var laneKeys:Array<Int> = [];
                    var kcs:Array<Dynamic> = cast lane;
                    if (kcs != null) for (k in kcs) laneKeys.push(Std.int(k));
                    row.push(laneKeys);
                }
                d.keybinds.push(row);
            }
        }
        var arrScales:Array<Dynamic> = cast raw.scales;
        if (arrScales != null) {
            for (s in arrScales) d.scales.push(Std.parseFloat(Std.string(s)));
        }
        var arrPixelScales:Array<Dynamic> = cast raw.pixelScales;
        if (arrPixelScales != null) {
            for (s in arrPixelScales) d.pixelScales.push(Std.parseFloat(Std.string(s)));
        }
        // Extra Keys：EK 原版 scales/pixelScales 默认为 null（需 ScaleSimulationState 生成）。
        // 这里兜底生成合理默认值（4 键=1.0，随键数线性缩到 18 键=0.45），避免脚本/取色读取时 NPE。
        var needScales:Int = d.maxKeys + 1;
        if (d.scales.length < needScales) {
            for (i in d.scales.length...needScales) {
                var s:Float = 1.0 - (0.55 * (i - 3) / 14.0);
                if (s > 1.0) s = 1.0;
                if (s < 0.4) s = 0.4;
                d.scales.push(s);
            }
        }
        if (d.pixelScales.length < needScales) {
            for (i in d.pixelScales.length...needScales) {
                var s:Float = 1.0 - (0.55 * (i - 3) / 14.0);
                if (s > 1.0) s = 1.0;
                if (s < 0.4) s = 0.4;
                d.pixelScales.push(s);
            }
        }
        return d;
    }

    /** 兜底：内置 4 键默认配置，避免 JSON 缺失时崩溃。 */
    public static function defaults():ExtraKeysData
    {
        var d = new ExtraKeysData();
        d.minKeys = 0;
        d.maxKeys = 3;
        // 单档：4 键
        var mode = new EKManiaMode();
        mode.notes = [0, 1, 2, 3];
        d.keys = [mode];

        // 4 个颜色
        function mkColor(inner:String, border:String, outline:String):EKNoteColor {
            var c = new EKNoteColor();
            c.inner = inner; c.border = border; c.outline = outline;
            return c;
        }
        d.colors = [
            mkColor('C24B99', 'FFFFFF', '3C1F56'),
            mkColor('00FFFF', 'FFFFFF', '1542B7'),
            mkColor('12FA05', 'FFFFFF', '0A4447'),
            mkColor('F9393F', 'FFFFFF', '651038')
        ];
        d.pixelNoteColors = d.colors;

        // 4 个动画
        function mkAnim(strum:String, anim:String, note:String, sing:String, pixel:Int):EKAnimation {
            var a = new EKAnimation();
            a.strum = strum; a.anim = anim; a.note = note; a.sing = sing; a.pixel = pixel;
            return a;
        }
        d.animations = [
            mkAnim('LEFT',  'left',  'purple', 'LEFT',  0),
            mkAnim('DOWN',  'down',  'blue',   'DOWN',  1),
            mkAnim('UP',    'up',    'green',  'UP',    2),
            mkAnim('RIGHT', 'right', 'red',    'RIGHT', 3)
        ];

        // 4 键默认键位：A S W D（FlxKey keycode: 65,83,87,68）
        d.keybinds = [[[65],[83],[87],[68]]];
        return d;
    }
}

class EKManiaMode
{
    public var notes:Array<Int> = [];
    public function new() {}
}

class EKNoteColor
{
    public var inner:String;
    public var border:String;
    public var outline:String;
    public function new() {}
}

class EKAnimation
{
    public var strum:String;
    public var anim:String;
    public var note:String;
    public var sing:String;
    public var pixel:Int = 0;
    public function new() {}
}
