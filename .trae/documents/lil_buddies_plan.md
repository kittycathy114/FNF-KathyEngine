# Lil' Buddies 制谱器迷你角色预览复刻计划

## 项目调研结论

### 资源状况
- ✅ **图片资源已存在**：`assets/shared/images/editors/` 目录下已有 `lilBf.png` (900×2304)、`lilOpp.png` (900×1280)、`lilStage.png` (256×256)
- 每帧尺寸 300×256，3列×9行（lilBf）和 3列×5行（lilOpp），与 FPS Plus 完全匹配

### 动画帧映射（与 FPS Plus 一致）
| 动画 | lilBf 帧 | lilOpp 帧 |
|------|---------|-----------|
| idle | [0, 1], loop | [0, 1], loop |
| singLEFT | [3, 4, 5] | [3, 4, 5] |
| singDOWN | [6, 7, 8] | [6, 7, 8] |
| singUP | [9, 10, 11] | [9, 10, 11] |
| singRIGHT | [12, 13, 14] | [12, 13, 14] |
| yeah(hey) | [17, 20, 23] | (无) |

### 现有 KathyEngine 架构要点
1. **ChartingState.hx** (9497行)：已有完整的基于时间窗口的音符动画触发机制
   - 第 2600 行：`noteStrumTime > lastStrumTime && noteStrumTime <= currentStrumTime` 判断音符刚到达判定点
   - 第 2602/2612 行：`note.mustPress` 直接判断玩家/对手，`noteData % 4` 得到方向
   - 第 2607/2614 行：调用 `playCharacterSing(boyfriend/dad, direction)`
   
2. **MetaNote.noteData 已归一化**：0-3=玩家, 4-7=对手，与 mustHitSection 无关
3. **ClientPrefs 无制谱器设置字段**，制谱器设置保存在 `FlxSave chartEditorSave` 里

### 与 FPS Plus 实现的关键差异
| 方面 | FPS Plus | KathyEngine |
|------|----------|-------------|
| 音符归属判断 | `editorBFNote` + mustHitSection 逻辑 | `note.mustPress`（已归一化） |
| 动画触发 | y 坐标越过 strumLine | 时间窗口（strumTime 跨越） |
| 防重复 | `playedEditorClick` 标记 | 时间窗口天然一次性 |
| 设置保存 | Config 类静态变量 | chartEditorSave (FlxSave) |

---

## 修改文件清单

| 文件 | 修改内容 |
|------|----------|
| `source/backend/ClientPrefs.hx` | 添加 `chartEditorShowLilBuddies:Bool = true` 设置字段 |
| `source/states/editors/ChartingState.hx` | 添加 lil 精灵变量、初始化、动画触发逻辑 |

---

## 实现步骤

### Step 1: ClientPrefs 添加设置字段
在制谱器相关设置区域（约 313-316 行附近）添加：
```haxe
public var chartEditorShowLilBuddies:Bool = true; // 制谱器是否显示Lil' Buddies迷你角色预览
```

### Step 2: ChartingState 添加变量声明（~行 380 附近）
```haxe
// Lil' Buddies 制谱器迷你角色预览
var lilStage:FlxSprite;
var lilBf:FlxSprite;
var lilOpp:FlxSprite;
```

### Step 3: create() 中初始化 lil 精灵
在 chartEditorSave 设置加载区域（~行 527 附近）添加设置加载：
```haxe
if(chartEditorSave.data.showLilBuddies == null) chartEditorSave.data.showLilBuddies = true;
```

在 vortexIndicator 创建之后（~行 614 附近）添加精灵初始化：
```haxe
// Lil' Buddies 迷你角色预览（固定在屏幕上，不随谱面滚动）
lilStage = new FlxSprite(0, FlxG.height - 256).loadGraphic(Paths.image('editors/lilStage'));
lilStage.scrollFactor.set(); // (0,0) 固定
lilStage.visible = chartEditorSave.data.showLilBuddies;
add(lilStage);

lilBf = new FlxSprite(FlxG.width - 600, FlxG.height - 560).loadGraphic(Paths.image('editors/lilBf'), true, 300, 256);
lilBf.animation.add('idle', [0, 1], 12, true);
lilBf.animation.add('0', [3, 4, 5], 12, false);
lilBf.animation.add('1', [6, 7, 8], 12, false);
lilBf.animation.add('2', [9, 10, 11], 12, false);
lilBf.animation.add('3', [12, 13, 14], 12, false);
lilBf.animation.play('idle');
lilBf.scrollFactor.set();
lilBf.visible = chartEditorSave.data.showLilBuddies;
add(lilBf);

lilOpp = new FlxSprite(FlxG.width - 300, FlxG.height - 560).loadGraphic(Paths.image('editors/lilOpp'), true, 300, 256);
lilOpp.animation.add('idle', [0, 1], 12, true);
lilOpp.animation.add('0', [3, 4, 5], 12, false);
lilOpp.animation.add('1', [6, 7, 8], 12, false);
lilOpp.animation.add('2', [9, 10, 11], 12, false);
lilOpp.animation.add('3', [12, 13, 14], 12, false);
lilOpp.animation.play('idle');
lilOpp.scrollFactor.set();
lilOpp.visible = chartEditorSave.data.showLilBuddies;
add(lilOpp);
```

### Step 4: 添加 lil 动画播放辅助方法
```haxe
private function playLilSing(isBf:Bool, direction:Int):Void
{
    if(chartEditorSave == null || !chartEditorSave.data.showLilBuddies) return;
    var target:FlxSprite = isBf ? lilBf : lilOpp;
    if(target == null) return;
    target.animation.play("" + Std.int(Math.abs(direction)), true);
}
```

### Step 5: 在音符动画触发处（~行 2607/2614）调用 lil 动画
```haxe
// 玩家音符处（~行 2607）：
playCharacterSing(boyfriend, direction);
playLilSing(true, direction);  // 新增

// 对手音符处（~行 2614）：
playCharacterSing(dad, direction);
playLilSing(false, direction);  // 新增
```

### Step 6: 添加 lil 回到 idle 的逻辑
在长条持续判断和 idle 处理之后（~行 2656 附近），添加 lil 角色的 idle 恢复：
```haxe
// Lil' Buddies 动画恢复 idle
if(chartEditorSave != null && chartEditorSave.data.showLilBuddies)
{
    if(lilBf != null && !boyfriendInSustain)
    {
        var bfAnim:String = lilBf.animation.curAnim != null ? lilBf.animation.curAnim.name : '';
        if(bfAnim != 'idle' && bfAnim != '' && lilBf.animation.finished)
            lilBf.animation.play('idle', true);
    }
    if(lilOpp != null && !dadInSustain)
    {
        var oppAnim:String = lilOpp.animation.curAnim != null ? lilOpp.animation.curAnim.name : '';
        if(oppAnim != 'idle' && oppAnim != '' && lilOpp.animation.finished)
            lilOpp.animation.play('idle', true);
    }
}
```

### Step 7: 在制谱器设置 UI 中添加开关（可选后续）
在 ChartingState 的设置面板里添加复选框，修改 `chartEditorSave.data.showLilBuddies` 并实时更新可见性。

### Step 8: 其他需要处理的场景
- **歌曲暂停/恢复时**：确保 lil 角色回到 idle（在 pause 回调处添加）
- **section 切换时**：重置 lil 动画到 idle
- **destroy() 清理**：FlxSprite 会被 Flixel 自动回收

---

## 依赖与注意事项

1. **资源路径**：KathyEngine 已把图片放在 `editors/` 目录，Paths.image('editors/lilBf') 可以正确解析
2. **动画帧尺寸**：必须用 `loadGraphic(path, true, 300, 256)` 加载，每帧 300×256
3. **scrollFactor.set()**：设为 (0,0) 让 lil 角色固定在屏幕上，这是 FPS Plus 的设计意图——制谱时始终可见
4. **位置坐标**：使用 `FlxG.width - 600` 等基于屏幕尺寸的定位，兼容不同分辨率
5. **设置字段名**：在 chartEditorSave 中用 `showLilBuddies` 保存

---

## 验证方案

1. 进入制谱器 → 左下角应显示 lilStage + lilBf + lilOpp 三个精灵
2. 播放歌曲 → 音符到达判定线时，对应的 lil 角色应播放对应方向的 sing 动画
3. 动画播放完毕 → 自动回到 idle
4. 长条音符 → 动画保持 sing 不回 idle
5. 设置开关关闭 → 三个精灵全部隐藏

---

## 风险与应对

| 风险 | 应对 |
|------|------|
| lil 精灵被其他 UI 元素遮挡 | 在 vortexIndicator 之前 add，确保在底层 |
| animation.finished 在循环动画时不准确 | lil sing 动画都是 loop(false)，所以 finished 可靠 |
| 旧的 chartEditorSave 没有 showLilBuddies 字段 | 默认值 true，首次启动自动创建 |
| KathyEngine 与 FPS Plus 图片尺寸不同 | 已验证尺寸完全一致（900×2304 / 900×1280） |
