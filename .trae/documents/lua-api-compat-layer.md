# Lua API 三层兼容层（0.6.3 / 0.7.3 / 1.0.4）实施计划

## Context（背景与动机）

用户的一个模组（`mods/Developer Mode/custom_events/Distortion.lua`）在 KathyEngine 上报 `Invalid access to field 'remove'` 错误，堆栈指向 `Distortion.lua:29` 的 `setObjectCamera('staticD', 'camHUD')`。该模组大概率是为其他 PE 版本（0.6.3 或 0.7.3）编写的，与 KathyEngine（基于 PE 1.0.4）的 Lua API 行为存在差异。

经过对比三个主流 PE 版本的 Lua API 注册清单，确认存在多处**默认参数差异**和**实现差异**。用户希望：
1. 在 KathyEngine 中同时兼容 0.6.3 / 0.7.3 / 1.0.4 三层 Lua API；
2. 用户可在设置中自行选择使用哪一层兼容；
3. 全量 Lua API 对齐（不局限于 setObjectCamera）。

引擎内已有同模式的可借鉴设计：`source/states/editors/ChartingRouter.hx` 已实现"按 `ClientPrefs.data.chartingVersion` 切换制谱器版本"的版本路由机制，本计划完全套用该范式。

## 关键差异清单（兼容层需处理的点）

### A. 默认参数差异（最常见兼容性问题）

| 函数 | 0.6.3 | 0.7.3 | 1.0.4 / KathyEngine |
|------|-------|-------|----------------------|
| `setObjectCamera(obj, camera)` | `camera=''` | `camera=''` | `camera='game'` |
| `doTweenX/Y/Angle/Alpha/Zoom/Color` | `ease` 必填无默认 | `?ease` 可选无默认 | `?ease='linear'` |
| `noteTweenX/Y/Angle/Alpha/Direction` | `ease` 必填无默认 | `?ease` 可选无默认 | `?ease='linear'` |
| `setHealth(value)` | `value=0` | `value=1` | `value=1` |
| `mouseClicked/Pressed/Released(button)` | `button` 必填无默认 | `button` 必填无默认 | `?button='left'` |
| `makeAnimatedLuaSprite(tag, image, x, y, spriteType)` | `image`/`x`/`y` 必填、`spriteType='sparrow'` | 同 0.6.3 | 全可选、`spriteType='auto'` |
| `makeLuaSprite(tag, image, x, y, spriteType)` | 不含 `spriteType` 参数 | `image`/`x`/`y` 必填、`spriteType='auto'` | 全可选、`spriteType='auto'` |
| `keyJustPressed/Pressed/Released(name)` | `name` 必填无默认 | `name=''` | `name=''` |
| `precacheImage(name, allowGPU)` | 不含 `allowGPU` | 不含 `allowGPU` | `?allowGPU=true` |
| `getMouseX(camera)` / `getMouseY(camera)` | `camera` 必填无默认 | `camera` 必填无默认 | `?camera='game'` |
| `setObjectOrder(obj, pos, group)` / `getObjectOrder(obj, group)` | 不含 `group` | 不含 `group` | `?group=null` |

### B. 实现差异（行为不同）

| 函数 | 0.6.3 行为 | 1.0.4 / Kathy 行为 |
|------|-----------|-------------------|
| `makeAnimatedLuaSprite` 销毁旧对象 | `resetSpriteTag` → `pee.kill()` + `PlayState.instance.remove(pee, true)` + `pee.destroy()` + `modchartSprites.remove(tag)`，存储于 `PlayState.instance.modchartSprites` | `LuaUtils.destroyObject` → `getTargetInstance().remove(obj, true)` + `obj.destroy()` + `variables.remove(tag)`，存储于 `MusicBeatState.getVariables()` |
| `addLuaSprite` 取对象方式 | `modchartSprites.exists(tag)` + `wasAdded` 字段判断 | `MusicBeatState.getVariables().get(tag)` 直接取 |

→ **存储后端在 1.0.4/Kathy 中已是 `MusicBeatState.getVariables()`**，0.6.3/0.7.3 脚本只要不直接读写 `modchartSprites` 内部字段，就不受影响。**本计划不回退存储后端**，仅在文档中标注：脚本不应直接访问 `modchartSprites`（属于废弃内部 API）。

### C. 函数缺失差异（0.6.3/0.7.3 独有但 KathyEngine 可能缺）

经 grep 确认 KathyEngine 已含：`addAnimation`、`getColorFromHex`、`musicFadeIn`、`musicFadeOut`、`addAnimationByIndicesLoop`、`objectPlayAnimation`、`characterPlayAnim`、`luaSpriteMakeGraphic`、`luaSpriteAddAnimationByPrefix`、`luaSpriteAddAnimationByIndices`、`luaSpritePlayAnimation`、`setLuaSpriteCamera`、`setLuaSpriteScrollFactor`、`scaleLuaSprite`、`getPropertyLuaSprite`、`setPropertyLuaSprite`、`updateHitboxFromGroup`、`makeFlxAnimateSprite`、`loadAnimateAtlas`、`addAnimationBySymbol`、`addAnimationBySymbolIndices`、`initLuaShader`、`setSpriteShader`、`removeSpriteShader`、`getShaderBool/Int/Float/Array`、`setShaderBool/Int/Float/Array`、`openCustomSubstate`、`closeCustomSubstate`、`insertToCustomSubstate`、`setVar`、`getVar`、`addHScript`、`removeHScript`、`loadMultipleFrames`、`callMethod`、`callMethodFromClass`、`createInstance`、`addInstance`、`instanceArg`、`initSaveData`、`flushSaveData`、`getDataFromSave`、`setDataFromSave`、`eraseSaveData`、`checkFileExists`、`saveFile`、`deleteFile`、`getTextFromFile`、`directoryFileList`、`stringStartsWith`、`stringEndsWith`、`stringSplit`、`stringTrim`、`getRandomInt/Float/Bool`。

→ KathyEngine 的 1.0.4 API + DeprecatedFunctions 已基本覆盖 0.6.3/0.7.3 的全部公开函数名，**无需新增缺失函数注册**。

## 实施方案

### 步骤 1：新增 `ClientPrefs` 字段

文件：[source/backend/ClientPrefs.hx](file:///e:/EXTRA/FNF/For%20Android/KathyEngine/source/backend/ClientPrefs.hx)

在 `SaveVariables` 类内，紧邻 `chartingVersion` 字段下方新增：

```haxe
// Lua API 兼容版本：决定 setObjectCamera / doTween* / makeAnimatedLuaSprite 等 API 的默认参数与行为
// 'auto' = 自动识别（基于脚本路径/特征），'1.0.4' = KathyEngine 原生（默认），'0.7.3' / '0.6.3' = 旧版脚本兼容
public var luaCompatVersion:String = '1.0.4';
```

### 步骤 2：新增 `LuaCompatRouter.hx`（仿 ChartingRouter）

文件：`source/psychlua/LuaCompatRouter.hx`（新建）

```haxe
package psychlua;

import backend.ClientPrefs;

class LuaCompatRouter
{
    public static final VERSION_1_0_4:String = '1.0.4';
    public static final VERSION_0_7_3:String = '0.7.3';
    public static final VERSION_0_6_3:String = '0.6.3';
    public static final VERSION_AUTO:String = 'auto';

    public static final VERSIONS:Array<String> =
        [VERSION_1_0_4, VERSION_0_7_3, VERSION_0_6_3, VERSION_AUTO];

    public static function resolveVersion():String
    {
        var v:String = ClientPrefs.data.luaCompatVersion;
        if (v == null || VERSIONS.indexOf(v) < 0) return VERSION_1_0_4;
        return v;
    }

    /** setObjectCamera 默认 camera 字符串 */
    public static function defaultCamera():String {
        return switch(resolveVersion()) {
            case VERSION_0_6_3, VERSION_0_7_3: '';
            default: 'game';
        };
    }

    /** doTween* / noteTween* 默认 ease 字符串 */
    public static function defaultEase():String {
        return switch(resolveVersion()) {
            case VERSION_0_6_3, VERSION_0_7_3: null; // null = 不传，调用者按需处理
            default: 'linear';
        };
    }

    /** makeAnimatedLuaSprite / makeLuaSprite 默认 spriteType */
    public static function defaultSpriteType():String {
        return switch(resolveVersion()) {
            case VERSION_0_6_3, VERSION_0_7_3: 'sparrow';
            default: 'auto';
        };
    }

    /** setHealth 默认 value */
    public static function defaultHealth():Float {
        return resolveVersion() == VERSION_0_6_3 ? 0 : 1;
    }

    /** mouseClicked/Pressed/Released 默认 button */
    public static function defaultMouseButton():String {
        return switch(resolveVersion()) {
            case VERSION_0_6_3, VERSION_0_7_3: null; // 必填
            default: 'left';
        };
    }

    /** getMouseX/Y 默认 camera */
    public static function defaultMouseCamera():String {
        return switch(resolveVersion()) {
            case VERSION_0_6_3, VERSION_0_7_3: null;
            default: 'game';
        };
    }

    /** keyJustPressed/Pressed/Released 默认 name */
    public static function defaultKeyName():String {
        return switch(resolveVersion()) {
            case VERSION_0_6_3: null;
            default: '';
        };
    }

    /** precacheImage 是否支持 allowGPU 参数 */
    public static function supportsAllowGPU():Bool {
        return resolveVersion() == VERSION_1_0_4;
    }
}
```

### 步骤 3：修改 `FunkinLua.hx` 关键 API 的默认值填充

文件：[source/psychlua/FunkinLua.hx](file:///e:/EXTRA/FNF/For%20Android/KathyEngine/source/psychlua/FunkinLua.hx)

按以下模式修改约 12 处 API（只列改动要点，不逐行贴）：

| 行号附近 | 函数 | 改动 |
|---------|------|------|
| L1151 | `setObjectCamera` | `camera:String = 'game'` → `?camera:String = null`，函数首行 `if (camera == null) camera = LuaCompatRouter.defaultCamera();` |
| L582-593 | `doTweenX/Y/Angle/Alpha` | `?ease:String = 'linear'` → `?ease:String = null`，调 `oldTweenFunction` 前 `if (ease == null) ease = LuaCompatRouter.defaultEase() ?? 'linear';` |
| L610-625 | `doTweenZoom/Color` | 同上 |
| L633-646 | `noteTweenX/Y/Angle/Alpha/Direction` | 同上 |
| L648 | `mouseClicked` | `?button:String = 'left'` → `?button:String = null`，首行 `if (button == null) button = LuaCompatRouter.defaultMouseButton() ?? 'left';` |
| L725 | `setHealth` | `value:Float = 1` → `?value:Float = null`，首行 `if (value == null) value = LuaCompatRouter.defaultHealth();` |
| L894 | `getMouseX` / `getMouseY` | `?camera:String = 'game'` → `?camera:String = null`，首行 `if (camera == null) camera = LuaCompatRouter.defaultMouseCamera() ?? 'game';` |
| L971 | `makeLuaSprite` | `?spriteType:String = 'auto'` → `?spriteType:String = null`，首行 `if (spriteType == null) spriteType = LuaCompatRouter.defaultSpriteType();` |
| L982 | `makeAnimatedLuaSprite` | 同上 |
| (ExtraFunctions 中) | `keyJustPressed/Pressed/Released` | `name:String = ''` → `?name:String = null`，首行 `if (name == null) name = LuaCompatRouter.defaultKeyName() ?? '';` |
| `precacheImage` | `?allowGPU:Bool = true` → `?allowGPU:Bool = null`，首行 `if (allowGPU == null) allowGPU = LuaCompatRouter.supportsAllowGPU();` |

**注意**：0.6.3 的 `doTweenX` 等没有 `?ease` 默认值（必填），但**在 Haxe 端无法用类型系统强制**（Lua 不强制），所以兼容层无法真正还原"0.6.3 旧脚本不传 ease 就报错"的行为——这其实也不会有人故意触发，可以接受。`defaultEase()` 返回 null 的语义是"调用者按需处理"，最终落到 `oldTweenFunction` 时会自动用 'linear' 兜底。

### 步骤 4：新增运行时查询 API

文件：[source/psychlua/FunkinLua.hx](file:///e:/EXTRA/FNF/For%20Android/KathyEngine/source/psychlua/FunkinLua.hx)

在 `setVar`/`getVar` 附近新增：

```haxe
Lua_helper.add_callback(lua, "getLuaCompatVersion", function() {
    return LuaCompatRouter.resolveVersion();
});
```

让模组脚本可读取当前兼容版本以做分支处理（极少数高级脚本需要）。

### 步骤 5：添加 Options UI 选项

文件：[source/options/ExtraGameplaySettingSubState.hx](file:///e:/EXTRA/FNF/For%20Android/KathyEngine/source/options/ExtraGameplaySettingSubState.hx)

在 `chartingVersion` 选项（L201-206）之后立即添加：

```haxe
option = new Option(Language.get('lua_compat_version'),
    Language.get("lua_compat_version_desc"),
    'luaCompatVersion',
    STRING,
    psychlua.LuaCompatRouter.VERSIONS.copy());
addOption(option);
```

### 步骤 6：添加语言键

在语言文件中（路径见 `Language.get` 实现）添加：
- `lua_compat_version` → "Lua API 兼容版本"
- `lua_compat_version_desc` → "决定 setObjectCamera / doTween* / makeAnimatedLuaSprite 等 Lua API 的默认参数。0.6.3/0.7.3 旧模组脚本选对应版本可避免兼容性错误；'auto' 自动识别；'1.0.4' 为引擎原生（默认）"

具体语言文件路径需要在执行时通过 grep `Language.get(` 与 `lua_compat_version` 类似已有键（如 `charting_version`）的对照来定位。

### 步骤 7：同步 `_initialregistry` 或类似默认值表

如 SaveVariables 在某处有"默认值注册表"或 schema（执行时确认），同步添加 `luaCompatVersion` 的默认值。

## 验证步骤

1. **编译**：`haxe setup.hxml`（项目根目录的 hxml 文件）确认无错误。
2. **设置项可见性**：进入"Extra Options"菜单，确认 `Lua API 兼容版本` 下拉显示 4 个选项。
3. **0.6.3 兼容性测试**：将兼容版本切换到 `0.6.3`，运行一段使用 `doTweenX('t', 'obj', 100, 1, 'quadInOut')` 省略 ease 默认值的 0.6.3 风格脚本，确认行为符合 0.6.3。
4. **1.0.4 默认行为不变**：保持兼容版本为 `1.0.4`（默认），运行 KathyEngine 现有 1.0.4 风格脚本，确认行为与改动前一致（不引入回归）。
5. **Distortion.lua 验证**：原报错模组放到 `mods/Developer Mode/` 下运行，确认不再触发 `Invalid access to field 'remove'` 错误（如果该错误原本是因为 setObjectCamera 默认值差异引发）。
6. **跨版本切换无崩溃**：在游戏中切换 `luaCompatVersion` 设置后立刻进入歌曲，确认无 Null Pointer / 类型错误。

## 关键修改文件清单

- `source/backend/ClientPrefs.hx` — 新增 `luaCompatVersion` 字段
- `source/psychlua/LuaCompatRouter.hx` — **新建**，版本路由 + 默认值提供
- `source/psychlua/FunkinLua.hx` — 修改约 12 处 API 的默认参数填充
- `source/psychlua/ExtraFunctions.hx` — 修改 `keyJustPressed/Pressed/Released` 默认值（如在此文件中）
- `source/options/ExtraGameplaySettingSubState.hx` — 新增选项 UI
- 语言文件（执行时定位）— 新增 2 个翻译键

## 设计权衡与不做的事

- **不回退存储后端**：0.6.3 用 `modchartSprites`、1.0.4 用 `MusicBeatState.getVariables()`。脚本只要不直接访问 `modchartSprites` 内部字段，就完全兼容。强行回退会破坏 KathyEngine 大量已有扩展。
- **不引入"按脚本路径自动识别版本"**：`auto` 模式留作占位，本计划不实现自动识别逻辑（不可靠且增加复杂度）。`auto` 暂时映射为 `1.0.4` 默认行为，未来可扩展。
- **不强制 0.6.3 的"必填参数"语义**：Lua 不支持类型系统强制参数数量，0.6.3 的 `doTweenX(tag, vars, value, duration, ease)` 中 ease 在 1.0.4 是可选的，无法在兼容层强制其必填。但这不影响脚本运行（只是默认行为不同）。
- **不修改 ChartingState / PlayState 中的回调触发点**：onCreatePost / onUpdate / onStepHit 等回调的触发位置和参数在三个版本间无差异，无需改动。
