package ui;

import openfl.display.Sprite;
import openfl.display.Shape;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.events.TouchEvent;
import openfl.Lib;
import openfl.filters.GlowFilter;
import openfl.geom.Matrix;
import flixel.FlxG;
import haxe.ds.IntMap;

/**
 * 鼠标拖尾效果类
 * 在 OpenFL 层创建鼠标移动时的拖尾效果
 */
class MouseTrail extends Sprite
{
	// 拖尾粒子数组
	private var particles:Array<TrailParticle> = [];
	private var clickEffects:Array<ClickEffect> = [];
	private var rippleEffects:Array<RippleEffect> = [];

	// 拖尾配置
	public var trailLength:Int = 10;        // 拖尾粒子数量（降低以提升性能）
	public var trailSize:Float = 28;        // 粒子初始大小
	public var trailDecay:Float = 0.96;     // 粒子衰减系数 - 稍微加快衰减以减少活跃粒子
	public var trailColor:Int = 0x00BFFF;   // 拖尾颜色（深天蓝色）
	public var trailAlpha:Float = 0.8;      // 初始透明度

	// 点击效果配置
	public var clickEffectEnabled:Bool = true;    // 是否启用点击效果
	public var mobileOnlyClickEffect:Bool = false; // 只在手机端显示点击效果（默认false，所有平台都显示）
	public var clickEffectSize:Float = 40;  // 点击效果初始大小
	public var clickEffectAlpha:Float = 1.0; // 点击效果初始透明度
	#if mobile
	public var clickEffectDecay:Float = 0.85; // 点击效果衰减速度（手机端更快消失）
	#else
	public var clickEffectDecay:Float = 0.96; // 点击效果衰减速度（桌面端较慢）
	#end
	public var clickEffectColor:Int = 0x00BFFF; // 点击效果颜色（与拖尾一致）

	// 光圈效果配置
	public var rippleEnabled:Bool = true;    // 是否启用光圈效果
	public var rippleMaxSize:Float = 100;   // 光圈最大扩散半径
	#if mobile
	public var rippleSpeed:Float = 2.0;     // 光圈扩散速度（手机端更慢）
	public var rippleAlphaDecay:Float = 0.08; // 光圈透明度衰减速度（手机端更快）
	#else
	public var rippleSpeed:Float = 3.0;     // 光圈扩散速度
	public var rippleAlphaDecay:Float = 0.04; // 光圈透明度衰减速度
	#end
	public var rippleThickness:Float = 3.0;   // 光圈线条粗细
	public var rippleColor:Int = 0x00BFFF;  // 光圈颜色

	// 发光效果配置
	public var glowEnabled:Bool = true;    // 是否启用发光效果
	public var glowColor:Int = 0x00BFFF;  // 发光颜色
	public var glowAlpha:Float = 0.8;     // 发光透明度（降低以减少渲染开销）
	public var glowBlur:Float = 30.0;     // 发光模糊度（降低以提升性能）
	public var glowStrength:Float = 5;   // 发光强度（降低以提升性能）

	// 全局开关
	public var enabled:Bool = true;         // 是否完全启用拖尾效果（由设置控制）

	// 性能优化：缓存的发光滤镜
	private var cachedGlowFilter:GlowFilter = null;

	// 位图渲染优化
	private var trailBitmap:Bitmap;
	private var trailBitmapData:BitmapData;
	private var clickBitmap:Bitmap;
	private var clickBitmapData:BitmapData;
	private var rippleBitmap:Bitmap;
	private var rippleBitmapData:BitmapData;
	private var renderMatrix:Matrix = new Matrix();

	// 鼠标位置追踪
	private var trailMouseX:Float = 0;
	private var trailMouseY:Float = 0;
	private var lastMouseX:Float = -1;
	private var lastMouseY:Float = -1;
	private var isMoving:Bool = false;
	private var initialized:Bool = false;
	private var dpiScale:Float = 1.0;
	private var screenScale:Float = 1.0; // 基于屏幕尺寸的缩放因子
	private var userScale:Float = 1.0; // 用户设置的大小比例（来自ClientPrefs）

	// 多触控支持：触摸点跟踪
	#if mobile
	private var activeTouches:IntMap<TouchPoint> = new IntMap<TouchPoint>(); // 跟踪所有活动触摸点
	#end

	// 性能优化：更新计数器
	private var updateFrameCount:Int = 0;
	#if mobile
	private var updateInterval:Int = 2; // 手机端每2帧更新一次
	private var maxClickEffects:Int = 12; // 最多同时12个点击效果
	private var maxRippleEffects:Int = 12; // 最多同时12个光圈效果（与点击效果一致）
	#else
	private var updateInterval:Int = 1; // 桌面端每帧更新
	private var maxClickEffects:Int = 4; // 桌面端最多4个点击效果
	private var maxRippleEffects:Int = 4; // 桌面端最多4个光圈效果（与点击效果一致）
	#end

	public function new()
	{
		super();
		this.mouseEnabled = false;
		this.mouseChildren = false;

		// 计算 DPI 缩放比例和屏幕尺寸缩放
		calculateDPIScale();

		// 监听屏幕尺寸变化（重新计算缩放）
		Lib.current.stage.addEventListener(Event.RESIZE, onStageResize);

		#if mobile
		// 手机端：使用多触控事件
		Lib.current.stage.addEventListener(TouchEvent.TOUCH_BEGIN, onTouchBegin);
		Lib.current.stage.addEventListener(TouchEvent.TOUCH_MOVE, onTouchMove);
		Lib.current.stage.addEventListener(TouchEvent.TOUCH_END, onTouchEnd);
		Lib.current.stage.addEventListener(TouchEvent.TOUCH_OUT, onTouchEnd);
		#else
		// 桌面端：使用鼠标事件
		Lib.current.stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
		Lib.current.stage.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
		#end

		// 监听每帧更新
		Lib.current.stage.addEventListener(Event.ENTER_FRAME, update);

		// 初始化位图渲染
		initBitmaps();
	}

	/**
	 * 初始化位图用于高效渲染
	 */
	private function initBitmaps():Void
	{
		var stageWidth:Int = Std.int(Lib.current.stage.stageWidth);
		var stageHeight:Int = Std.int(Lib.current.stage.stageHeight);

		// 拖尾位图
		trailBitmapData = new BitmapData(stageWidth, stageHeight, true, 0x00000000);
		trailBitmap = new Bitmap(trailBitmapData);
		addChild(trailBitmap);

		// 点击效果位图
		clickBitmapData = new BitmapData(stageWidth, stageHeight, true, 0x00000000);
		clickBitmap = new Bitmap(clickBitmapData);
		addChild(clickBitmap);

		// 光圈效果位图
		rippleBitmapData = new BitmapData(stageWidth, stageHeight, true, 0x00000000);
		rippleBitmap = new Bitmap(rippleBitmapData);
		addChild(rippleBitmap);
	}

	/**
	 * 舞台尺寸变化时重新计算缩放
	 */
	private function onStageResize(e:Event):Void
	{
		calculateScreenScale();

		// 重新创建位图以适应新尺寸
		if (trailBitmapData != null)
			trailBitmapData.dispose();
		if (clickBitmapData != null)
			clickBitmapData.dispose();
		if (rippleBitmapData != null)
			rippleBitmapData.dispose();

		initBitmaps();
	}

	/**
	 * 计算 DPI 缩放比例和屏幕尺寸缩放
	 */
	private function calculateDPIScale():Void
	{
		if (Lib.current.stage != null)
		{
			// 获取舞台缩放比例（考虑 DPI）
			dpiScale = Lib.current.stage.contentsScaleFactor;

			// 如果无法获取，尝试从窗口属性获取
			if (dpiScale <= 0 || dpiScale == 1)
			{
				#if desktop
				// 桌面平台尝试从系统 DPI 计算
				dpiScale = 1.0;
				if (Lib.current.stage.window != null)
				{
					// 默认假设 96 DPI，根据实际系统 DPI 调整
					// 大多数系统 DPI 约为 96-192
					dpiScale = Lib.current.stage.window.scale;
				}
				#end
			}

			// 确保 DPI 缩放在合理范围内
			if (dpiScale < 1.0)
				dpiScale = 1.0;
			else if (dpiScale > 3.0)
				dpiScale = 3.0;

			// 计算基于屏幕尺寸的缩放因子
			// 使用基准分辨率 1280x720 进行缩放
			calculateScreenScale();
		}
	}

	/**
	 * 计算基于屏幕尺寸的缩放因子
	 */
	private function calculateScreenScale():Void
	{
		if (Lib.current.stage != null)
		{
			var stageWidth:Float = Lib.current.stage.stageWidth;
			var stageHeight:Float = Lib.current.stage.stageHeight;

			// 使用基准分辨率 1280x720 计算缩放
			// 选择较小的缩放比例，确保效果不会超出屏幕
			var widthScale:Float = stageWidth / 1280.0;
			var heightScale:Float = stageHeight / 720.0;

			// 使用较小的缩放比例，并考虑设备类型
			screenScale = Math.min(widthScale, heightScale);

			#if mobile
			// 手机端使用更大的基础缩放，因为触摸区域需要更大
			screenScale = Math.max(screenScale, 1.0);
			#else
			// 桌面端可能需要稍小的缩放
			screenScale = Math.max(screenScale, 0.8);
			#end

			// 确保缩放在合理范围内
			screenScale = Math.max(0.6, Math.min(2.5, screenScale));
		}
	}

	/**
	 * 鼠标移动事件处理 - 获取准确的屏幕坐标
	 */
	private function onMouseMove(e:MouseEvent):Void
	{
		// 检查拖尾效果是否启用
		if (!enabled)
		{
			// 即使禁用，也要更新鼠标位置以备后用
			trailMouseX = e.stageX;
			trailMouseY = e.stageY;
			return;
		}

		// 更新鼠标位置
		trailMouseX = e.stageX;
		trailMouseY = e.stageY;

		if (!initialized)
		{
			// 初始化鼠标位置
			lastMouseX = trailMouseX;
			lastMouseY = trailMouseY;
			initialized = true;
		}
	}

	/**
	 * 鼠标点击事件处理
	 */
	private function onMouseDown(e:MouseEvent):Void
	{
		// 检查拖尾效果是否启用
		if (!enabled)
			return;

		// 检查是否应该显示点击效果
		var shouldShowClickEffect:Bool = clickEffectEnabled;

		// 如果启用了"只在手机端显示"，则检查平台
		if (mobileOnlyClickEffect)
		{
			#if mobile
			shouldShowClickEffect = true;
			#else
			shouldShowClickEffect = false;
			#end
		}

		// 只处理左键点击
		// OpenFL 的 MouseEvent 使用 altKey、ctrlKey、shiftKey 和 buttonDown
		// buttonDown 为 true 表示主要鼠标按钮（通常是左键）
		if (shouldShowClickEffect)
		{
			addClickEffect(e.stageX, e.stageY);

			// 添加光圈扩张效果
			if (rippleEnabled)
			{
				addRippleEffect(e.stageX, e.stageY);
			}
		}
	}

	#if mobile
	/**
	 * 触摸开始事件处理（多触控支持）
	 */
	private function onTouchBegin(e:TouchEvent):Void
	{
		// 检查拖尾效果是否启用
		if (!enabled)
			return;

		if (!clickEffectEnabled)
			return;

		var touchId:Int = e.touchPointID;

		// 为新触摸点创建跟踪
		var touchPoint:TouchPoint = new TouchPoint(touchId);
		touchPoint.x = e.stageX;
		touchPoint.y = e.stageY;
		touchPoint.lastX = e.stageX;
		touchPoint.lastY = e.stageY;
		activeTouches.set(touchId, touchPoint);

		// 添加点击效果
		addClickEffect(e.stageX, e.stageY);

		// 添加光圈扩张效果
		if (rippleEnabled)
		{
			addRippleEffect(e.stageX, e.stageY);
		}
	}

	/**
	 * 触摸移动事件处理（多触控支持）
	 */
	private function onTouchMove(e:TouchEvent):Void
	{
		var touchId:Int = e.touchPointID;
		var touchPoint:TouchPoint = activeTouches.get(touchId);

		if (touchPoint != null)
		{
			touchPoint.lastX = touchPoint.x;
			touchPoint.lastY = touchPoint.y;
			touchPoint.x = e.stageX;
			touchPoint.y = e.stageY;

			// 检测是否移动了足够距离
			var moved:Bool = (Math.abs(touchPoint.x - touchPoint.lastX) > 0.5 ||
			                Math.abs(touchPoint.y - touchPoint.lastY) > 0.5);

			if (moved)
			{
				// 添加拖尾粒子（手机端也支持拖尾）
				addParticle(touchPoint.x, touchPoint.y);
			}
		}
	}

	/**
	 * 触摸结束事件处理（多触控支持）
	 */
	private function onTouchEnd(e:TouchEvent):Void
	{
		var touchId:Int = e.touchPointID;
		activeTouches.remove(touchId);
	}
	#end

	/**
	 * 更新拖尾效果（性能优化：降低更新频率）
	 */
	private function update(e:Event):Void
	{
		// 性能优化：如果没有任何效果，直接返回
		if (particles.length == 0 && clickEffects.length == 0 && rippleEffects.length == 0)
			return;

		// 性能优化：降低更新频率
		updateFrameCount++;
		if (updateFrameCount < updateInterval)
		{
			return;
		}
		updateFrameCount = 0;

		#if mobile
		// 手机端：触摸拖尾粒子在 onTouchMove 中处理，这里只更新现有效果
		#else
		// 桌面端：检测鼠标移动
		if (!initialized)
			return;

		// 检测鼠标是否移动
		var moved:Bool = (Math.abs(trailMouseX - lastMouseX) > 0.5 || Math.abs(trailMouseY - lastMouseY) > 0.5);

		if (moved)
		{
			// 创建新粒子
			addParticle(trailMouseX, trailMouseY);
			isMoving = true;
		}
		else if (isMoving)
		{
			// 鼠标停止移动时，减少生成粒子
			isMoving = false;
		}

		// 更新最后位置
		lastMouseX = trailMouseX;
		lastMouseY = trailMouseY;
		#end

		// 更新所有粒子
		if (particles.length > 0)
			updateParticles();

		// 更新点击效果
		if (clickEffects.length > 0)
			updateClickEffects();

		// 更新光圈效果
		if (rippleEffects.length > 0)
			updateRippleEffects();

		// 渲染到位图
		renderToBitmaps();
	}

	/**
	 * 渲染所有效果到位图（性能优化）
	 */
	private function renderToBitmaps():Void
	{
		// 清除位图
		trailBitmapData.fillRect(trailBitmapData.rect, 0x00000000);
		clickBitmapData.fillRect(clickBitmapData.rect, 0x00000000);
		rippleBitmapData.fillRect(rippleBitmapData.rect, 0x00000000);

		// 渲染拖尾粒子
		for (particle in particles)
		{
			if (particle.alpha >= 0.05 && particle.size >= 1)
			{
				renderMatrix.identity();
				renderMatrix.translate(particle.x - particle.size / 2, particle.y - particle.size / 2);
				trailBitmapData.draw(createParticleShape(particle), renderMatrix);
			}
		}

		// 渲染点击效果
		for (effect in clickEffects)
		{
			if (effect.alpha >= 0.05 && effect.size >= 1)
			{
				renderMatrix.identity();
				renderMatrix.translate(effect.x - effect.size / 2, effect.y - effect.size / 2);
				clickBitmapData.draw(createClickShape(effect), renderMatrix);
			}
		}

		// 渲染光圈效果
		for (ripple in rippleEffects)
		{
			if (ripple.alpha >= 0.05 && ripple.radius >= 1)
			{
				renderMatrix.identity();
				renderMatrix.translate(ripple.x - ripple.radius, ripple.y - ripple.radius);
				rippleBitmapData.draw(createRippleShape(ripple), renderMatrix);
			}
		}

		// 应用滤镜
		var glow:GlowFilter = createGlowFilter();
		if (glow != null)
		{
			trailBitmap.filters = [glow];
			clickBitmap.filters = [glow];
			rippleBitmap.filters = [glow];
		}
		else
		{
			trailBitmap.filters = [];
			clickBitmap.filters = [];
			rippleBitmap.filters = [];
		}
	}

	/**
	 * 创建粒子形状用于绘制到位图
	 */
	private function createParticleShape(particle:TrailParticle):Shape
	{
		var shape:Shape = new Shape();
		shape.graphics.beginFill(particle.color, particle.alpha);
		shape.graphics.drawCircle(particle.size / 2, particle.size / 2, particle.size / 2);
		shape.graphics.endFill();
		return shape;
	}

	/**
	 * 创建点击效果形状
	 */
	private function createClickShape(effect:ClickEffect):Shape
	{
		var shape:Shape = new Shape();
		shape.graphics.beginFill(effect.color, effect.alpha);
		shape.graphics.drawCircle(effect.size / 2, effect.size / 2, effect.size / 2);
		shape.graphics.endFill();
		return shape;
	}

	/**
	 * 创建光圈效果形状
	 */
	private function createRippleShape(ripple:RippleEffect):Shape
	{
		var shape:Shape = new Shape();
		shape.graphics.lineStyle(rippleThickness, rippleColor, ripple.alpha);
		shape.graphics.drawCircle(ripple.radius, ripple.radius, ripple.radius);
		return shape;
	}
	private function createGlowFilter():GlowFilter
	{
		if (!glowEnabled)
			return null;

		// 如果缓存的滤镜参数与当前参数一致，则复用
		if (cachedGlowFilter != null)
		{
			return cachedGlowFilter;
		}

		// 创建并缓存新的滤镜
		cachedGlowFilter = new GlowFilter(glowColor, glowAlpha, glowBlur, glowBlur, glowStrength, 1, false, false);
		return cachedGlowFilter;
	}

	/**
	 * 重置缓存的滤镜（当参数改变时调用）
	 */
	private function invalidateGlowCache():Void
	{
		cachedGlowFilter = null;
	}

	/**
	 * 添加拖尾粒子（仅桌面端）
	 */
	private function addParticle(x:Float, y:Float):Void
	{
		// 只在桌面端显示拖尾效果
		#if mobile
		return;
		#end

		// 限制粒子数量
		while (particles.length >= trailLength)
		{
			particles.shift();
		}

		// 根据 DPI 缩放、屏幕尺寸和用户设置调整粒子大小
		var combinedScale:Float = dpiScale * screenScale * userScale;
		var scaledSize:Float = trailSize * combinedScale;

		// 创建新粒子
		var particle:TrailParticle = new TrailParticle();
		particle.x = x;
		particle.y = y;
		particle.size = scaledSize;
		particle.alpha = trailAlpha;
		particle.color = trailColor;

		particles.push(particle);
	}

	/**
	 * 更新所有粒子状态（性能优化：减少不必要的重绘）
	 */
	private function updateParticles():Void
	{
		var i:Int = particles.length - 1;
		while (i >= 0)
		{
			var particle:TrailParticle = particles[i];

			// 衰减大小和透明度
			particle.size *= trailDecay;
			particle.alpha *= trailDecay;

			// 移除过小的粒子
			if (particle.size < 1 || particle.alpha < 0.05)
			{
				particles.splice(i, 1);
			}

			i--;
		}
	}

	/**
	 * 添加点击效果（性能优化：限制数量）
	 */
	private function addClickEffect(x:Float, y:Float):Void
	{
		// 性能优化：限制同时存在的点击效果数量
		while (clickEffects.length >= maxClickEffects)
		{
			clickEffects.shift();
		}

		// 根据 DPI 缩放、屏幕尺寸和用户设置调整效果大小
		var combinedScale:Float = dpiScale * screenScale * userScale;
		var effect:ClickEffect = new ClickEffect();
		effect.x = x;
		effect.y = y;
		effect.size = clickEffectSize * combinedScale;
		effect.alpha = clickEffectAlpha;
		effect.color = clickEffectColor;

		clickEffects.push(effect);
	}

	/**
	 * 更新点击效果（性能优化：减少不必要的重绘）
	 */
	private function updateClickEffects():Void
	{
		var i:Int = clickEffects.length - 1;
		while (i >= 0)
		{
			var effect:ClickEffect = clickEffects[i];

			// 衰减大小和透明度
			effect.size *= clickEffectDecay;
			effect.alpha *= clickEffectDecay;

			// 移除过小的效果
			if (effect.size < 1 || effect.alpha < 0.05)
			{
				clickEffects.splice(i, 1);
			}

			i--;
		}
	}

	/**
	 * 添加光圈效果（性能优化：限制数量）
	 */
	private function addRippleEffect(x:Float, y:Float):Void
	{
		// 性能优化：限制同时存在的光圈效果数量
		while (rippleEffects.length >= maxRippleEffects)
		{
			rippleEffects.shift();
		}

		// 根据 DPI 缩放、屏幕尺寸和用户设置调整效果大小
		var combinedScale:Float = dpiScale * screenScale * userScale;
		var ripple:RippleEffect = new RippleEffect();
		ripple.x = x;
		ripple.y = y;
		ripple.radius = 10 * combinedScale;
		ripple.alpha = 1.0;

		rippleEffects.push(ripple);
	}

	/**
	 * 更新光圈效果（性能优化：减少不必要的重绘）
	 */
	private function updateRippleEffects():Void
	{
		var combinedScale:Float = dpiScale * screenScale * userScale;
		var i:Int = rippleEffects.length - 1;
		while (i >= 0)
		{
			var ripple:RippleEffect = rippleEffects[i];

			// 扩散光圈
			ripple.radius += rippleSpeed * combinedScale;

			// 衰减透明度
			ripple.alpha -= rippleAlphaDecay;

			// 移除完全消失的光圈
			if (ripple.radius >= rippleMaxSize * combinedScale || ripple.alpha <= 0)
			{
				rippleEffects.splice(i, 1);
			}

			i--;
		}
	}

	/**
	 * 清除所有拖尾粒子
	 */
	public function clearTrail():Void
	{
		particles = [];
	}

	/**
	 * 清除所有点击效果
	 */
	public function clearClickEffects():Void
	{
		clickEffects = [];
	}

	/**
	 * 清除所有光圈效果
	 */
	public function clearRippleEffects():Void
	{
		rippleEffects = [];
	}

	/**
	 * 设置初始鼠标位置（用于初始化）
	 * @param x 鼠标X坐标
	 * @param y 鼠标Y坐标
	 */
	public function setInitPosition(x:Float, y:Float):Void
	{
		trailMouseX = x;
		trailMouseY = y;
		lastMouseX = x;
		lastMouseY = y;
		initialized = true;
	}

	/**
	 * 设置拖尾颜色
	 */
	public function setTrailColor(color:Int):Void
	{
		trailColor = color;
	}

	/**
	 * 设置是否启用点击效果
	 */
	public function setClickEffectEnabled(enabled:Bool):Void
	{
		clickEffectEnabled = enabled;
	}

	/**
	 * 设置是否只在手机端显示点击效果
	 */
	public function setMobileOnlyClickEffect(enabled:Bool):Void
	{
		mobileOnlyClickEffect = enabled;
	}

	/**
	 * 设置点击效果颜色
	 */
	public function setClickEffectColor(color:Int):Void
	{
		clickEffectColor = color;
	}

	/**
	 * 设置是否启用光圈效果
	 */
	public function setRippleEnabled(enabled:Bool):Void
	{
		rippleEnabled = enabled;
	}

	/**
	 * 设置光圈最大扩散半径
	 */
	public function setRippleMaxSize(size:Float):Void
	{
		rippleMaxSize = size;
	}

	/**
	 * 设置光圈扩散速度
	 */
	public function setRippleSpeed(speed:Float):Void
	{
		rippleSpeed = speed;
	}

	/**
	 * 设置光圈颜色
	 */
	public function setRippleColor(color:Int):Void
	{
		rippleColor = color;
	}

	/**
	 * 设置是否启用发光效果
	 */
	public function setGlowEnabled(enabled:Bool):Void
	{
		glowEnabled = enabled;
		invalidateGlowCache();
	}

	/**
	 * 设置发光颜色
	 */
	public function setGlowColor(color:Int):Void
	{
		glowColor = color;
		invalidateGlowCache();
	}

	/**
	 * 设置发光透明度
	 */
	public function setGlowAlpha(alpha:Float):Void
	{
		glowAlpha = Math.max(0, Math.min(1, alpha));
		invalidateGlowCache();
	}

	/**
	 * 设置发光模糊度
	 */
	public function setGlowBlur(blur:Float):Void
	{
		glowBlur = Math.max(0, blur);
		invalidateGlowCache();
	}

	/**
	 * 设置发光强度
	 */
	public function setGlowStrength(strength:Float):Void
	{
		glowStrength = Math.max(0, strength);
		invalidateGlowCache();
	}

	/**
	 * 设置拖尾透明度
	 */
	public function setTrailAlpha(alpha:Float):Void
	{
		trailAlpha = Math.max(0, Math.min(1, alpha));
	}

	/**
	 * 设置拖尾长度
	 */
	public function setTrailLength(length:Int):Void
	{
		trailLength = Std.int(Math.max(1, length));
	}

	/**
	 * 设置拖尾大小
	 */
	public function setTrailSize(size:Float):Void
	{
		trailSize = Math.max(1, size);
	}

	/**
	 * 设置更新间隔（性能优化：降低更新频率）
	 * @param interval 更新间隔帧数 (1=每帧更新，2=每2帧更新一次，以此类推)
	 * 值越大，性能开销越小，但动画可能不够流畅
	 * 推荐：手机端使用2-3，桌面端使用1
	 */
	public function setUpdateInterval(interval:Int):Void
	{
		updateInterval = Std.int(Math.max(1, interval));
	}

	/**
	 * 设置最大点击效果数量（性能优化）
	 * @param count 最大同时存在的点击效果数量
	 * 值越小，快速点击时的性能开销越小
	 * 推荐：手机端12，桌面端4
	 */
	public function setMaxClickEffects(count:Int):Void
	{
		maxClickEffects = Std.int(Math.max(1, count));
	}

	/**
	 * 设置最大光圈效果数量（性能优化）
	 * @param count 最大同时存在的光圈效果数量
	 * 值越小，快速点击时的性能开销越小
	 * 推荐：手机端1-2，桌面端3-5
	 */
	public function setMaxRippleEffects(count:Int):Void
	{
		maxRippleEffects = Std.int(Math.max(1, count));
	}

	/**
	 * 设置拖尾效果大小比例（用户设置）
	 * @param scale 大小比例 (0.5 = 50%, 1.0 = 100%, 2.0 = 200%)
	 * 这个设置会乘到所有效果的大小上（拖尾、点击、光圈）
	 */
	public function setTrailSizeScale(scale:Float):Void
	{
		userScale = Math.max(0.5, Math.min(2.0, scale));
	}

	/**
	 * 获取当前拖尾效果大小比例
	 * @return 当前大小比例
	 */
	public function getTrailSizeScale():Float
	{
		return userScale;
	}

	/**
	 * 手动设置 DPI 缩放比例
	 * @param scale DPI 缩放比例 (1.0 = 100%, 1.5 = 150%, 2.0 = 200%)
	 */
	public function setDPIScale(scale:Float):Void
	{
		dpiScale = Math.max(1.0, Math.min(3.0, scale));
	}

	/**
	 * 获取当前 DPI 缩放比例
	 * @return 当前 DPI 缩放比例
	 */
	public function getDPIScale():Float
	{
		return dpiScale;
	}

	/**
	 * 获取当前屏幕尺寸缩放因子
	 * @return 当前屏幕尺寸缩放因子
	 */
	public function getScreenScale():Float
	{
		return screenScale;
	}

	/**
	 * 手动设置屏幕尺寸缩放因子
	 * @param scale 屏幕尺寸缩放因子 (0.6-2.5)
	 * 注意：设置此值将禁用自动屏幕尺寸缩放
	 * @usage mouseTrail.setScreenScale(1.5); // 设置为150%大小
	 */
	public function setScreenScale(scale:Float):Void
	{
		screenScale = Math.max(0.6, Math.min(2.5, scale));
	}

	/**
	 * 获取组合缩放因子（DPI × 屏幕尺寸 × 用户设置）
	 * @return 组合缩放因子
	 */
	public function getCombinedScale():Float
	{
		return dpiScale * screenScale * userScale;
	}

	/**
	 * 重新计算屏幕尺寸缩放（启用自动缩放后调用）
	 */
	public function recalculateScreenScale():Void
	{
		calculateScreenScale();
	}

	/**
	 * 销毁拖尾效果
	 */
	public function destroy():Void
	{
		clearTrail();
		clearClickEffects();
		clearRippleEffects();

		// 清理位图
		if (trailBitmap != null && trailBitmap.parent != null)
			trailBitmap.parent.removeChild(trailBitmap);
		if (clickBitmap != null && clickBitmap.parent != null)
			clickBitmap.parent.removeChild(clickBitmap);
		if (rippleBitmap != null && rippleBitmap.parent != null)
			rippleBitmap.parent.removeChild(rippleBitmap);

		if (trailBitmapData != null)
			trailBitmapData.dispose();
		if (clickBitmapData != null)
			clickBitmapData.dispose();
		if (rippleBitmapData != null)
			rippleBitmapData.dispose();

		trailBitmap = null;
		trailBitmapData = null;
		clickBitmap = null;
		clickBitmapData = null;
		rippleBitmap = null;
		rippleBitmapData = null;

		#if mobile
		// 手机端：移除触摸事件监听器
		Lib.current.stage.removeEventListener(TouchEvent.TOUCH_BEGIN, onTouchBegin);
		Lib.current.stage.removeEventListener(TouchEvent.TOUCH_MOVE, onTouchMove);
		Lib.current.stage.removeEventListener(TouchEvent.TOUCH_END, onTouchEnd);
		Lib.current.stage.removeEventListener(TouchEvent.TOUCH_OUT, onTouchEnd);
		#else
		// 桌面端：移除鼠标事件监听器
		Lib.current.stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
		Lib.current.stage.removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
		#end

		Lib.current.stage.removeEventListener(Event.ENTER_FRAME, update);
		Lib.current.stage.removeEventListener(Event.RESIZE, onStageResize);

		if (parent != null)
		{
			parent.removeChild(this);
		}
	}
}

/**
 * 拖尾粒子数据结构
 */
class TrailParticle
{
	public var x:Float;
	public var y:Float;
	public var size:Float;
	public var alpha:Float;
	public var color:Int;

	public function new()
	{
		this.x = 0;
		this.y = 0;
		this.size = 28;
		this.alpha = 1;
		this.color = 0x00BFFF;
	}
}

/**
 * 点击效果数据结构
 */
class ClickEffect
{
	public var x:Float;
	public var y:Float;
	public var size:Float;
	public var alpha:Float;
	public var color:Int;

	public function new()
	{
		this.x = 0;
		this.y = 0;
		this.size = 40;
		this.alpha = 1;
		this.color = 0x00BFFF;
	}
}

/**
 * 光圈效果数据结构
 */
class RippleEffect
{
	public var x:Float;
	public var y:Float;
	public var radius:Float;
	public var alpha:Float;

	public function new()
	{
		this.x = 0;
		this.y = 0;
		this.radius = 10;
		this.alpha = 1.0;
	}
}

/**
 * 多触控触摸点数据结构
 */
class TouchPoint
{
	public var touchId:Int;      // 触摸点 ID
	public var x:Float;         // X 坐标
	public var y:Float;         // Y 坐标
	public var lastX:Float;      // 上一次 X 坐标
	public var lastY:Float;      // 上一次 Y 坐标

	public function new(touchId:Int)
	{
		this.touchId = touchId;
		this.x = 0;
		this.y = 0;
		this.lastX = -1;
		this.lastY = -1;
	}
}

