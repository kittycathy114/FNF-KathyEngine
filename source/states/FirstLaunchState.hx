package states;

import flixel.FlxSubState;
import flixel.ui.FlxButton;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.effects.FlxFlicker;
import backend.Language;
import backend.ClientPrefs;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.FlxG;
import flixel.util.FlxTimer;
import openfl.display.BitmapData;
import openfl.display.Shape;

class FirstLaunchState extends MusicBeatState
{
    public static var leftState:Bool = false;

    var currentPage:Int = 0;
    var maxPages:Int = 2;
    var languageButtons:FlxTypedGroup<FlxButton>;
    var flashingButtons:FlxTypedGroup<FlxButton>;
    var bg:FlxSprite;
    var bgGradient:FlxSprite;
    var titleText:FlxText;
    var descText:FlxText;
    
    // 闪光效果精灵
    var flashSprite:FlxSprite;
    
    // 反馈文本
    var feedbackText:FlxText;
    var feedbackTween:FlxTween;
    
    // 可用语言列表
    var availableLanguages:Array<String> = ["en_us", "zh_cn", "zh_tw"];
    var languageNames:Map<String, String> = [
        "en_us" => "English",
        "zh_cn" => "简体中文",
        "zh_tw" => "繁體中文"
    ];
    var selectedLanguage:String = "en_us";

    var pageGroups:Array<FlxSpriteGroup>; // 存储每个页面的精灵组
    var inTransition:Bool = false; // 防止在动画期间进行交互
    
    // 页面指示器
    var pageIndicators:Array<FlxSprite>;
    
    // 装饰元素
    var decorations:Array<FlxSprite>;
    var decorationOrigins:Array<{x:Float, y:Float}>; // 存储装饰元素的原始位置
    var decorationAngles:Array<Float>; // 存储装饰元素的当前角度
    
    // 屏幕尺寸相关的缩放因子
    var screenScaleX:Float = 1.0;
    var screenScaleY:Float = 1.0;
    var baseWidth:Float = 1280; // 基准宽度
    var baseHeight:Float = 720; // 基准高度

    override function create()
    {
        super.create();
        FlxG.mouse.visible = true;
        
        // 计算屏幕尺寸缩放因子
        calculateScreenScale();
        
        pageGroups = [];
        decorations = [];
        pageIndicators = [];
        decorationOrigins = [];
        decorationAngles = [];
        
        // 创建渐变背景 - 使用OpenFL的Shape绘制
        createGradientBackground();
        
        // 创建装饰元素（光点效果）
        createDecorations();

        // 创建标题文本 - 基于屏幕尺寸
        var titleFontSize = Std.int(40 * screenScaleY);
        titleText = new FlxText(0, Std.int(80 * screenScaleY), FlxG.width, "", titleFontSize);
        titleText.setFormat(Language.get('game_font'), titleFontSize, FlxColor.WHITE, CENTER, OUTLINE, 0xFF000000);
        titleText.borderSize = Std.int(2 * screenScaleY);
        titleText.alpha = 0;
        add(titleText);

        // 创建描述文本
        var descFontSize = Std.int(20 * screenScaleY);
        descText = new FlxText(
            Std.int(50 * screenScaleX), 
            Std.int(140 * screenScaleY), 
            Std.int(FlxG.width - 100 * screenScaleX), 
            "", 
            descFontSize
        );
        descText.setFormat(Language.get('game_font'), descFontSize, 0xFFAAAAAA, CENTER, OUTLINE, 0xFF000000);
        descText.borderSize = Std.int(1.5 * screenScaleY);
        descText.alpha = 0;
        add(descText);

        // 创建反馈文本（初始隐藏）
        var feedbackFontSize = Std.int(28 * screenScaleY);
        feedbackText = new FlxText(0, 0, FlxG.width, "", feedbackFontSize);
        feedbackText.setFormat(Language.get('game_font'), feedbackFontSize, FlxColor.WHITE, CENTER, OUTLINE, 0xFF000000);
        feedbackText.borderSize = Std.int(2 * screenScaleY);
        feedbackText.alpha = 0;
        feedbackText.visible = false;
        add(feedbackText);

        // 为每个页面创建一个精灵组
        for (i in 0...maxPages) {
            var group = new FlxSpriteGroup();
            group.x = i * FlxG.width;
            pageGroups.push(group);
            add(group);
        }

        // 创建各个按钮组
        languageButtons = new FlxTypedGroup<FlxButton>();
        flashingButtons = new FlxTypedGroup<FlxButton>();
        
        // 初始化所有页面内容
        initializeAllPages();
        
        // 创建页面指示器
        createPageIndicators();
        
        // 创建闪光效果精灵（初始隐藏）
        flashSprite = new FlxSprite();
        flashSprite.makeGraphic(FlxG.width, FlxG.height, FlxColor.WHITE);
        flashSprite.alpha = 0;
        add(flashSprite);
        
        // 设置默认语言
        ClientPrefs.data.language = selectedLanguage;
        Language.load();
        
        updateText();
        
        // 入场动画
        startIntroAnimation();
    }
    
    // 计算屏幕尺寸缩放因子
    function calculateScreenScale() {
        screenScaleX = FlxG.width / baseWidth;
        screenScaleY = FlxG.height / baseHeight;
        
        // 限制缩放范围，避免太小或太大
        screenScaleX = Math.max(0.7, Math.min(1.5, screenScaleX));
        screenScaleY = Math.max(0.7, Math.min(1.5, screenScaleY));
    }
    
    // 创建渐变背景 - 使用OpenFL的Shape
    function createGradientBackground()
    {
        var shape = new Shape();
        var matrix = new openfl.geom.Matrix();
        matrix.createGradientBox(FlxG.width, FlxG.height, Math.PI / 2, 0, 0);
        
        var colors = [0xFF0A0A2E, 0xFF1A1A4A, 0xFF0A0A1A];
        var alphas = [1.0, 1.0, 1.0];
        var ratios = [0, 128, 255]; // 渐变停止点（0-255之间的整数）
        
        shape.graphics.beginGradientFill(
            openfl.display.GradientType.LINEAR,
            colors,
            alphas,
            ratios,
            matrix
        );
        shape.graphics.drawRect(0, 0, FlxG.width, FlxG.height);
        shape.graphics.endFill();
        
        var bitmapData = new BitmapData(FlxG.width, FlxG.height, true, 0x00000000);
        bitmapData.draw(shape);
        
        bgGradient = new FlxSprite();
        bgGradient.pixels = bitmapData;
        add(bgGradient);
        
        bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0x00000000);
        bg.alpha = 0.3;
        add(bg);
    }
    
    // 创建装饰元素
    function createDecorations()
    {
        var numDecorations = 8;
        for (i in 0...numDecorations) {
            var decoration = new FlxSprite();
            var decorSize = Std.int(20 * Math.min(screenScaleX, screenScaleY));
            decoration.makeGraphic(decorSize, decorSize, 0xFFFFFFFF);
            decoration.alpha = 0;
            var x = Math.random() * FlxG.width;
            var y = Math.random() * FlxG.height;
            decoration.x = x;
            decoration.y = y;
            decoration.color = [0xFF33FFFF, 0xFF33CCFF, 0xFF9999FF, 0xFF6666FF][Std.random(4)];
            decorations.push(decoration);
            decorationOrigins.push({x: x, y: y});
            decorationAngles.push(Math.random() * Math.PI * 2);
            add(decoration);
        }
    }
    
    // 创建页面指示器
    function createPageIndicators()
    {
        var indicatorSize = Std.int(16 * Math.min(screenScaleX, screenScaleY));
        var spacing = Std.int(40 * screenScaleX);
        var startX = FlxG.width / 2 - (maxPages - 1) * spacing / 2;
        
        for (i in 0...maxPages) {
            var indicator = new FlxSprite(startX + i * spacing, FlxG.height - Std.int(60 * screenScaleY));
            indicator.makeGraphic(indicatorSize, indicatorSize, 0xFFFFFFFF);
            indicator.alpha = 0.3;
            pageIndicators.push(indicator);
            add(indicator);
        }
        updatePageIndicators();
    }
    
    // 更新页面指示器
    function updatePageIndicators()
    {
        for (i in 0...pageIndicators.length) {
            if (i == currentPage) {
                pageIndicators[i].alpha = 1;
                pageIndicators[i].scale.set(1.2, 1.2);
            } else {
                pageIndicators[i].alpha = 0.3;
                pageIndicators[i].scale.set(1, 1);
            }
            pageIndicators[i].updateHitbox();
        }
    }
    
    // 入场动画
    function startIntroAnimation()
    {
        // 标题淡入
        FlxTween.tween(titleText, {alpha: 1}, 0.8, {ease: FlxEase.circOut});
        FlxTween.tween(descText, {alpha: 1}, 0.8, {ease: FlxEase.circOut, startDelay: 0.2});
        
        // 装饰元素淡入
        for (i in 0...decorations.length) {
            var delay = i * 0.1;
            FlxTween.tween(decorations[i], {alpha: 0.3}, 1.5, {
                ease: FlxEase.circOut,
                startDelay: delay
            });
        }
    }
    
    override function update(elapsed:Float)
    {
        super.update(elapsed);
        
        // 更新装饰元素的漂浮动画
        if (!inTransition) {
            var radius = 25 * Math.min(screenScaleX, screenScaleY);
            for (i in 0...decorations.length) {
                decorationAngles[i] += elapsed * 0.5;
                var origin = decorationOrigins[i];
                decorations[i].x = origin.x + Math.cos(decorationAngles[i]) * radius;
                decorations[i].y = origin.y + Math.sin(decorationAngles[i]) * radius;
            }
        }
    }

    // 获取按钮缩放比例
    private function getButtonScale():Float {
        #if mobile
        return Math.min(screenScaleX, screenScaleY) * 2.0;
        #else
        return Math.min(screenScaleX, screenScaleY);
        #end
    }

    // 统一设置按钮大小 - 修复后的版本
    private function setButtonDefaults(button:FlxButton, baseWidth:Int, baseHeight:Int) {
        var scale = getButtonScale();
        var finalWidth = Std.int(baseWidth * scale);
        var finalHeight = Std.int(baseHeight * scale);
        
        // 创建自定义按钮图形
        var shape = new Shape();
        var radius = finalHeight * 0.2; // 圆角半径
        
        // 绘制圆角矩形背景
        shape.graphics.beginFill(0xFFFFFFFF);
        shape.graphics.drawRoundRect(0, 0, finalWidth, finalHeight, radius, radius);
        shape.graphics.endFill();
        
        // 创建按钮的图形数据
        var bitmapData = new BitmapData(finalWidth, finalHeight, true, 0xFFFFFFFF);
        bitmapData.draw(shape);
        
        // 设置按钮的图形
        button.loadGraphic(bitmapData);
        button.scale.set(1, 1);
        button.updateHitbox();
        
        // 设置按钮颜色和透明度
        button.color = 0xFF1A1A3E;
        button.alpha = 0.9;
        
        formatButtonText(button);
    }
    
    function initializeAllPages() 
    {
        // 初始化语言选择页面
        var baseButtonWidth = 320;
        var baseButtonHeight = 50;
        var scale = getButtonScale();
        var yPos = Std.int(220 * screenScaleY);
        var spacing = Std.int(70 * screenScaleY);

        for (lang in availableLanguages) {
            var button = new FlxButton(0, yPos, languageNames[lang], function() {
                if (inTransition) return;
                
                selectedLanguage = lang;
                
                // 立即保存并加载语言设置
                ClientPrefs.data.language = selectedLanguage;
                Language.load();
                
                // 更新按钮状态和文本内容
                updateLanguageButtons();
                updateText();
                
                // 播放按钮点击音效
                FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
                
                // 显示语言设置成功的反馈
                showLanguageFeedback();
            });
            setButtonDefaults(button, baseButtonWidth, baseButtonHeight);
            button.x = (FlxG.width - button.width) / 2;
            button.alpha = 0.85;
            languageButtons.add(button);
            pageGroups[0].add(button);
            yPos = yPos + spacing;
        }
        updateLanguageButtons();

        // 初始化闪光设置页面
        var baseButtonWidth = 280;
        var baseButtonHeight = 55;
        var scale = getButtonScale();
        var spacingFromCenter = Std.int(50 * screenScaleX); // 按钮距离中心的间距
        var buttonY = FlxG.height / 2 + Std.int(80 * screenScaleY); // 按钮在下方
        
        // 计算按钮实际宽度
        var actualButtonWidth = Std.int(baseButtonWidth * scale);
        
        var yesButton = new FlxButton(
            FlxG.width / 2 - actualButtonWidth - spacingFromCenter, // 左侧按钮
            buttonY,
            Language.get("firstlaunch_yes"),
            function() {
                if (inTransition) return;
                
                ClientPrefs.data.flashing = true;
                FlxG.sound.play(Paths.sound('confirmMenu'), 0.5);
                
                // 屏幕闪光效果（使用quadOut缓动渐隐）
                flashSprite.alpha = 1;
                FlxTween.tween(flashSprite, {alpha: 0}, 0.3, {ease: FlxEase.quadOut});
                
                saveAndExit();
            }
        );
        setButtonDefaults(yesButton, baseButtonWidth, baseButtonHeight);
        yesButton.color = 0xFF2ECC71; // 绿色
        yesButton.alpha = 0.9;
        
        var noButton = new FlxButton(
            FlxG.width / 2 + spacingFromCenter, // 右侧按钮
            buttonY,
            Language.get("firstlaunch_no"),
            function() {
                if (inTransition) return;
                
                ClientPrefs.data.flashing = false;
                FlxG.sound.play(Paths.sound('confirmMenu'), 0.5);
                saveAndExit();
            }
        );
        setButtonDefaults(noButton, baseButtonWidth, baseButtonHeight);
        noButton.color = 0xFFE74C3C; // 红色
        noButton.alpha = 0.9;
        
        flashingButtons.add(yesButton);
        flashingButtons.add(noButton);
        pageGroups[1].add(yesButton);
        pageGroups[1].add(noButton);
    }

    // 显示语言设置成功的反馈动画
    function showLanguageFeedback()
    {
        inTransition = true;
        
        // 禁用所有按钮
        for (button in languageButtons) {
            button.active = false;
            button.alpha = 0.4;
        }
        
        // 设置反馈文本
        var feedbackMsg = "✓ " + languageNames[selectedLanguage];
        feedbackText.text = feedbackMsg;
        feedbackText.font = Paths.font(Language.get('game_font'));
        var feedbackFontSize = Std.int(32 * screenScaleY);
        feedbackText.size = feedbackFontSize;
        feedbackText.color = 0xFF2ECC71;
        feedbackText.updateHitbox();
        
        // 初始位置和状态
        feedbackText.x = 0;
        feedbackText.y = FlxG.height / 2 - feedbackText.height / 2;
        feedbackText.alpha = 0;
        feedbackText.scale.set(0.5, 0.5);
        feedbackText.visible = true;
        
        // 播放成功音效
        FlxG.sound.play(Paths.sound('confirmMenu'), 0.5);
        
        // 缩放+渐显动画
        FlxTween.tween(feedbackText.scale, {x: 1, y: 1}, 0.4, {ease: FlxEase.backOut});
        FlxTween.tween(feedbackText, {alpha: 1}, 0.4, {
            ease: FlxEase.quadOut,
            onComplete: function(twn:FlxTween) {
                // 停留0.8秒
                new FlxTimer().start(0.8, function(tmr:FlxTimer) {
                    // 缩小+渐隐
                    FlxTween.tween(feedbackText.scale, {x: 0.8, y: 0.8}, 0.3, {ease: FlxEase.backIn});
                    feedbackTween = FlxTween.tween(feedbackText, {
                        y: feedbackText.y - 80 * screenScaleY,
                        alpha: 0
                    }, 0.3, {
                        ease: FlxEase.quadIn,
                        onComplete: function(twn:FlxTween) {
                            feedbackText.visible = false;
                            feedbackText.scale.set(1, 1);
                            goToNextPage();
                        }
                    });
                });
            }
        });
    }

    // 统一设置按钮文本格式
    function formatButtonText(button:FlxButton) {
        var scale = getButtonScale();
        var fontSize = Std.int(26 * scale);
        
        button.label.setFormat(
            Paths.font(Language.get('game_font')),
            fontSize,
            FlxColor.WHITE,
            CENTER,
            OUTLINE,
            0xFF000000
        );
        button.label.borderSize = Std.int(2 * scale);
        button.label.fieldWidth = Std.int(button.width);
        button.label.alignment = CENTER;
        centerButtonText(button);
    }

    // 居中按钮文本
    function centerButtonText(button:FlxButton) {
        button.label.fieldWidth = Std.int(button.width);
        button.label.x = 0;
        button.label.y = (button.height - button.label.height) / 2;
    }

    function goToNextPage()
    {
        if (currentPage < maxPages - 1) {
            currentPage++;
            inTransition = true;
            
            // 更新页面指示器
            updatePageIndicators();
            
            // 页面切换动画
            for (i in 0...pageGroups.length) {
                var group = pageGroups[i];
                FlxTween.tween(group, {
                    x: (i - currentPage) * FlxG.width
                }, 0.8, {
                    ease: FlxEase.circInOut,
                    onComplete: function(twn:FlxTween) {
                        inTransition = false;
                    }
                });
            }
            
            // 标题和描述文本的淡入淡出
            FlxTween.tween(titleText, {alpha: 0}, 0.2, {
                onComplete: function(twn:FlxTween) {
                    updateText();
                    FlxTween.tween(titleText, {alpha: 1}, 0.4, {ease: FlxEase.circOut});
                    FlxTween.tween(descText, {alpha: 1}, 0.4, {ease: FlxEase.circOut});
                }
            });
            FlxTween.tween(descText, {alpha: 0}, 0.2);
        }
    }

    function updateLanguageButtons()
    {
        for (button in languageButtons) {
            // 重置所有按钮样式
            button.color = 0xFF1A1A3E;
            button.alpha = 0.85;
            button.label.color = FlxColor.WHITE;
            button.label.borderColor = 0xFF000000;
            
            // 高亮显示选中按钮
            if (button.text == languageNames[selectedLanguage]) {
                // 选中的按钮更明亮
                button.color = 0xFF3498DB; // 亮蓝色
                button.alpha = 1;
                
                // 添加发光效果
                button.label.color = FlxColor.WHITE;
                var scale = getButtonScale();
                button.label.borderSize = Std.int(3 * scale);
                
                // 缩放动画
                FlxTween.tween(button.scale, {x: 1.05, y: 1.05}, 0.2, {ease: FlxEase.backOut});
                button.updateHitbox();
            } else {
                var scale = getButtonScale();
                button.label.borderSize = Std.int(2 * scale);
                button.scale.set(1, 1);
                button.updateHitbox();
            }
        }
    }

    function saveAndExit()
    {
        inTransition = true;
        
        // 保存语言设置
        ClientPrefs.data.language = selectedLanguage;
        
        // 保存所有设置
        ClientPrefs.saveSettings();
        
        leftState = true;
        FlxTransitionableState.skipNextTransIn = true;
        FlxTransitionableState.skipNextTransOut = true;
        
        // 加载语言
        Language.load();
        
        // 淡出所有元素（慢速渐隐）
        var fadeDuration = 1.5;
        FlxTween.tween(bg, {alpha: 0}, fadeDuration, {ease: FlxEase.quadIn});
        FlxTween.tween(bgGradient, {alpha: 0}, fadeDuration, {ease: FlxEase.quadIn});
        FlxTween.tween(titleText, {alpha: 0}, fadeDuration * 0.6, {ease: FlxEase.quadIn});
        FlxTween.tween(descText, {alpha: 0}, fadeDuration * 0.6, {ease: FlxEase.quadIn});
        
        for (group in pageGroups) {
            FlxTween.tween(group, {alpha: 0}, fadeDuration * 0.8, {ease: FlxEase.quadIn});
        }
        
        for (indicator in pageIndicators) {
            FlxTween.tween(indicator, {alpha: 0}, fadeDuration * 0.5, {ease: FlxEase.quadIn});
        }
        
        for (decor in decorations) {
            FlxTween.tween(decor, {alpha: 0}, fadeDuration, {ease: FlxEase.quadIn});
        }
        
        // 渐隐闪光效果精灵
        FlxTween.tween(flashSprite, {alpha: 0}, fadeDuration * 0.5, {ease: FlxEase.quadIn});
        
        // 切换到标题界面
        new FlxTimer().start(fadeDuration, function(tmr:FlxTimer) {
            MusicBeatState.switchState(new TitleState());
        });
    }

    function updateText() {
        switch (currentPage) {
            case 0:
                titleText.text = Language.get("firstlaunch_select");
                descText.text = "请选择您的首选语言\nPlease select your preferred language";
            case 1:
                titleText.text = "⚠️ 闪光效果警告";
                descText.text = Language.get("firstlaunch_warning") + "\n\n" + 
                               Language.get("flashing_warning_text");
            default:
                titleText.text = "";
                descText.text = "";
        }

        titleText.font = Paths.font(Language.get('game_font'));
        descText.font = Paths.font(Language.get('game_font'));
        titleText.updateHitbox();
        descText.updateHitbox();
        titleText.screenCenter(X);
        descText.screenCenter(X);

        // 更新闪光设置按钮
        if (currentPage == 1) {
            var buttons = flashingButtons.members;
            if(buttons.length >= 2) {
                buttons[0].label.text = Language.get("firstlaunch_yes");
                buttons[1].label.text = Language.get("firstlaunch_no");
                
                for(button in buttons) {
                    formatButtonText(button);
                }
            }
        }
    }
}
