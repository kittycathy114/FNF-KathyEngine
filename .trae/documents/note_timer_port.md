# Note Timer（箭头倒计时）移植文档

> 移植来源：Voiid Chronicles V2 模组的 Leather Engine `source/ui/NoteTimer.hx`
> 移植到：KathyEngine（基于 PsychEngine）
> 移植日期：2026-09-21

---

## 一、功能概述

当**两箭头之间**存在较长空白间隔（≥ 3 秒）时，在屏幕中央（判定线上方/下方 260px）显示一个**圆形进度圈** + **整数秒/Beat 数**倒计时，随着箭头即将到达逐渐收缩并消失。

核心用途：给玩家在长空白段落时一个"下一波箭头快来了"的预期提示。

---

## 二、新增/修改文件清单

| 文件 | 操作 | 说明 |
|------|:----:|------|
| `source/ui/NoteTimer.hx` | ✨ 新建 | 主逻辑 + CircleShader（FLSL） |
| `source/backend/ClientPrefs.hx` | ✏️ 修改 | 新增 4 个 `noteTimer*` 变量 |
| `source/states/PlayState.hx` | ✏️ 修改 | 条件创建 + legacyHUD/图层兼容 |
| `source/options/VisualsSettingsSubState.hx` | ✏️ 修改 | 注册 4 个设置项 |
| `assets/languages/options/zh_cn.json` | ✏️ 修改 | 中文 8 个 key |
| `assets/languages/options/en_us.json` | ✏️ 修改 | 英文 8 个 key |
| `assets/languages/options/zh_tw.json` | ✏️ 修改 | 繁中 8 个 key |
| `assets/shared/images/circleThing.png` | ✨ 新建 | 圆环贴图（来自 Leather Engine） |

### 不需要修改的文件

- `Project.xml` — 资源通过 `Paths.image("circleThing")` 动态加载，`assets/shared` 已注册
- 存档格式 — 新变量有默认值，老存档自动兼容
- PlayState 的 `update()` / `destroy()` — NoteTimer 未启用时为 null，无任何生命周期调用

---

## 三、ClientPrefs 新增变量

```haxe
// source/backend/ClientPrefs.hx

public var noteTimerEnabled:Bool    = true;          // 总开关
public var noteTimerLayer:String    = 'Above Notes'; // 'Above Notes' | 'Below Notes'
public var noteTimerDisplay:String  = 'Seconds';     // 'Seconds'     | 'Beats'
public var noteTimerStepped:Bool    = false;         // false=丝滑   true=跳剪脉冲
```

### 默认值选择理由

- **默认开**：移植自 Voiid 的特色功能，默认启用体验更好
- **默认 Above Notes**：倒计时圆本身就是 HUD 层视觉提示，压在箭头之上更醒目
- **默认 Seconds**：原版 Leather Engine 就是按秒显示，保持一致
- **默认 Stepped=false**：丝滑裁剪更通用；跳剪是高级效果，配 Beats 才有那味儿

---

## 四、PlayState 创建逻辑

### 位置
`source/states/PlayState.hx` 约 L1409-1430，在 `comboGroup.cameras` 设置之后、`startingSong = true` 之前。

### 关键设计

```
legacyHUD 分支处理：
├─ 非 legacyHUD（默认）：
│   Above Notes → add(noteTimer) 进 state → 排在 noteGroup 之后 → 箭头之上
│   Below Notes → uiGroup.add(noteTimer) → uiGroup 先于 noteGroup add → 箭头之下
│
└─ legacyHUD：
    Above Notes → add(noteTimer) → members 末尾 → 最顶层
    Below Notes → insert(members.indexOf(strumLineNotes), noteTimer) → strumLineNotes 之前
```

> **为什么这么麻烦？** legacyHUD 模式下 `uiGroup`/`comboGroup`/`noteGroup` **不被 add 进 state**（复刻 Psych 0.6.x 结构），所有 HUD 元素必须直接 add 进 state。KathyEngine 的 `addToHUD()` helper 签名是 `FlxSprite`，NoteTimer 是 `FlxSpriteGroup`，所以没法复用，手写分支。

### 禁用时的性能

`noteTimerEnabled = false` → 整个 if 块被跳过 → `noteTimer` 永远是 null → **0 CPU / 0 内存开销**（除一个 8 字节的 null 指针）。不存在"创建但隐藏"的半吊子做法。

---

## 五、NoteTimer.hx 核心逻辑

### 5.1 CircleShader

仅 fragment shader，vertex 交给 flixel 默认 `FlxShader`（通过 `#pragma header` 自动注入）。

```glsl
uniform float percent;  // 0.0 ~ 1.0

// 核心裁剪：以 12 点方向为起点，逆时针裁掉 (1-percent)*360° 的扇形
float percentAngle = (percent * 360.0) / (180.0 / PI);
if ((angle + PI) > percentAngle)
    spritecolor = vec4(0,0,0,0);  // 透明 → 被裁掉
```

### 5.2 玩家过滤

```haxe
// KathyEngine 特有：完全兼容 playOpponent 模式
// PlayState.isPlayerNote() 内部已处理 mustPress 逻辑
if (daNote.exists && instance.isPlayerNote(daNote)) { ... }
```

| 模式 | `isPlayerNote()` 返回 |
|------|----------------------|
| 普通 | bf 侧（`mustPress=true`） |
| playOpponent | dad 侧（`mustPress=false`） |

这是**原版 Leather Engine 没有的特性**——原版硬编码 `characterPlayingAs == 0`，不支持对手游玩。

### 5.3 倒计时触发条件

```
timeTillNextNote > 3000ms  →  开始计时，记录 lastStartTime
timeTillNextNote → 负数    →  lastStartTime 不被更新 → percent 保持初始值 → 圆消失（原版设计，不加 >=0 检查）
percent <= 0               →  重置 lastStartTime = 1e10，等待下一次长空白
```

**故意不加 `timeDiff >= 0` 检查**：如果加了，当已判定的 note（timeDiff 负）被过滤掉后，notes 循环一条都不匹配，fallback 到 unspawnNotes 的**最远** note → lastStartTime 被记录为 gap 全长 → percent 永远 ≈ 1 → 圆常亮。原版靠"负数竞争最小 timeTillNextNote"来让圆自动消失。

### 5.4 圆环裁剪：丝滑 vs 跳剪

| 模式 | percent 公式 | 效果 |
|------|-------------|------|
| 丝滑（默认） | `timeTillNextNote / lastStartTime` | 每帧连续变化，圆平滑收缩 |
| 跳剪（stepped） | `numLeft / initialUnits` | 只在整数跳变时 percent 才跳一下 |

`initialUnits` 在**进入倒计时那一刻**记录，跟 `numLeft` 用完全相同的公式（beats 或 seconds），确保 percent 从 1.0 起、每次减 `1/initialUnits`。

### 5.5 数字显示：秒 vs Beat

```haxe
if (mode == 'Beats' && backend.Conductor.crochet > 0)
    numLeft = Math.ceil(timeTillNextNote / backend.Conductor.crochet);  // 按拍
else
    numLeft = Math.ceil(timeTillNextNote * 0.001);                      // 按秒
```

- **ceil 向上取整**：避免显示 0 然后瞬间跳到下一个数
- **crochet > 0 保护**：BPM 为 0 时除零异常

### 5.6 数字放大跳动

检测数字变化时瞬时放大 1.55 倍，每帧 lerp 回 1.0：

```haxe
if (curNum != prevShownNum) { prevShownNum = curNum; textScale = 1.55; }
textScale = FlxMath.lerp(textScale, 1.0, elapsed * 10);  // 约 0.2s 衰减
timerText.scale.set(textScale, textScale);
```

**不需要开关**——利用两种模式数字变化频率天然不同：

| 模式 | 变化频率 | 跳动观感 |
|------|---------|---------|
| Beats | 每拍（120 BPM → 2次/秒） | 密集，跟节拍同步 |
| Seconds | 每秒一次 | 稀疏，不抢戏 |

### 5.7 透明度淡入淡出

```
目标 alpha：
  timeTillNextNote > 1000ms → 1.0（完全显示）
  timeTillNextNote ≤ 1000ms → 0.0（淡出）
  
过渡：
  timerText.alpha = lerp(alpha, target, elapsed * 5)  // 约 0.4s 过渡
  timerCircle.alpha = timerText.alpha                  // 圆跟随数字
```

**原版设计**——圆和数字作为独立子元素分别 lerp（不用 group 级 alpha），有 shader 的 sprite 可能不遵循 group 级 alpha。

### 5.8 位置

屏幕居中 ± 260px，按 downScroll 决定方向：

```haxe
timerCircle.screenCenter();
timerText.screenCenter();
if (backend.ClientPrefs.data.downScroll) {
    timerCircle.y += 260; timerText.y += 260;  // downscroll → 判定线下方
} else {
    timerCircle.y -= 260; timerText.y -= 260;  // upscroll → 判定线上方
}
```

---

## 六、设置页（Visuals Settings）

### 完整面板

```
Note Timer                          ✓ 开关          (noteTimerEnabled)
Note Timer Layer                    ▼ Above Notes   (noteTimerLayer)
Countdown Display Mode              ▼ Seconds       (noteTimerDisplay)
Stepped Circle Animation            ✓ 开关          (noteTimerStepped)
```

### VisualsSettingsSubState 注册

```haxe
// BOOL 型开关
new Option(Language.get('note_timer'), Language.get('note_timer_desc'), 'noteTimerEnabled', BOOL);
new Option(Language.get('note_timer_stepped'), Language.get('note_timer_stepped_desc'), 'noteTimerStepped', BOOL);

// STRING 型下拉 —— 需手动设置 valueLocalizations 让界面显示本地化文本
var opt = new Option(Language.get('note_timer_layer'), Language.get('note_timer_layer_desc'), 'noteTimerLayer', STRING, ['Above Notes', 'Below Notes']);
opt.valueLocalizations = ['Above Notes' => Language.get('note_timer_layer_above'), 'Below Notes' => Language.get('note_timer_layer_below')];

var opt = new Option(Language.get('note_timer_display'), Language.get('note_timer_display_desc'), 'noteTimerDisplay', STRING, ['Seconds', 'Beats']);
opt.valueLocalizations = ['Seconds' => Language.get('note_timer_display_seconds'), 'Beats' => Language.get('note_timer_display_beats')];
```

> valueLocalizations 的 key 必须跟 options 数组里的原始值**完全一致**（区分大小写），否则选项面板显示的是英文原始值而非本地化文本。

---

## 七、语言 Key 对照表

### zh_cn.json

| Key | 值 |
|-----|---|
| `note_timer` | 箭头倒计时 |
| `note_timer_desc` | 当两首两箭头之间有 ≥3秒 空白时... |
| `note_timer_layer` | 箭头倒计时图层 |
| `note_timer_layer_desc` | 设置箭头倒计时圆和秒数显示在箭头的上方还是下方... |
| `note_timer_layer_above` | 箭头之上（圆盖住箭头） |
| `note_timer_layer_below` | 箭头之下（箭头盖住圆） |
| `note_timer_display` | 倒计时数字显示 |
| `note_timer_display_desc` | 倒计时圆内的数字按什么显示... |
| `note_timer_display_seconds` | 秒 |
| `note_timer_display_beats` | Beat（拍） |
| `note_timer_stepped` | 圆环跳剪动效 |
| `note_timer_stepped_desc` | 启用后圆环裁剪不再丝滑连续... |

### en_us.json / zh_tw.json

同理，`note_timer_*` 前缀下共 12 个 key（每个语言文件）。

---

## 八、Shader 踩坑记录

| 问题 | 根因 | 解决方案 |
|------|------|---------|
| 编译报错 `unknown uniform "hasTransform"` | 自定义 vertex shader 覆盖了 flixel 默认 vertex，默认 fragment 里的 `hasTransform` / `hasColorTransform` 没人初始化 | **删掉自定义 vertex**，只保留 `#pragma header`，让 flixel 注入默认的 vertex + uniform |
| 圆环始终可见 | 我画蛇添足加了 `timeDiff >= 0` 过滤条件 | 原版故意不加，靠负数竞争让 timeTillNextNote 变成负数 → 自动消失 |
| alpha 不生效 | 用了 `group.alpha` 但 shader sprite 不继承 group alpha | 原版写法：子元素分别 lerp，不设 group 级 alpha |
| 位置飞了 | 我画蛇添足加了 `playerSideStrums()` 贴判定线 | 原版就是 `screenCenter() ± 260px`，别改 |

---

## 九、资源文件

| 文件 | 来源 | 说明 |
|------|------|------|
| `circleThing.png` | Leather Engine 内置（`objects/circleThing.png`） | 圆形贴图，Shader 用 GLSL atan 裁剪为扇形 |
| `vcr.ttf` | KathyEngine 已有（PsychEngine 继承） | 像素风 24px 字体 |

**circleThing.png 路径必须是 `assets/shared/images/circleThing.png`**——`Project.xml` 注册的 shared 目录只有这个，放错到 `base_game` 不会被 OpenFL 打包。

---

## 十、性能分析

| noteTimerEnabled | CPU 开销 | 内存 |
|:---:|:---:|:---:|
| true | notes + unspawnNotes 各遍历 1 次（线性 O(n)，n 为当前已生成音符数） + 每帧一次 GLSL uniform 写入 | ~数 KB（FlxSpriteGroup + 2个子元素 + shader） |
| **false** | **0** | **8 字节（null 指针）** |

- GC 分配：每帧 notes/unspawnNotes 遍历里的 `timeDiff` 是局部栈变量，不触发 GC
- Shader uniform 更新：`this.percent.value = [0.5]` 每帧写一个 Float32 array，非常便宜
- circleThing.png 复用引擎纹理缓存，不会重复加载

---

## 十一、移植 vs 原版差异

| 方面 | Leather Engine 原版 | KathyEngine 移植 |
|------|---------------------|-----------------|
| 玩家过滤 | 硬编码 `characterPlayingAs == 0` | `PlayState.isPlayerNote()` — 兼容 playOpponent |
| 创建时机 | PlayState.create() | 同（但用 if (enabled) 包起来） |
| 图层控制 | 无（固定贴判定线） | 有——Above/Below Notes 可选 |
| 数字单位 | 固定秒 | 秒/Beat 可选 |
| 圆环动效 | 固定丝滑连续 | 丝滑/跳剪 可选 |
| 数字动画 | 无 | 变化时弹性放大跳动 |
| legacyHUD 兼容 | 无（0.7+ 结构） | 有——双分支处理 |
| 语言本地化 | 无（硬编码英文） | 三语（zh_cn / en_us / zh_tw） |
