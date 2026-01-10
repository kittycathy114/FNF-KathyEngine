package ui;

import openfl.display.Sprite;
import openfl.display.Shape;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.Lib;
import openfl.filters.GlowFilter;
import flixel.FlxG;

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
	public var clickEffectSize:Float = 40;  // 点击效果初始大小
	public var clickEffectAlpha:Float = 1.0; // 点击效果初始透明度
	public var clickEffectDecay:Float = 0.96; // 点击效果衰减速度
	public var clickEffectColor:Int = 0x00BFFF; // 点击效果颜色（与拖尾一致）

	// 光圈效果配置
	public var rippleEnabled:Bool = true;    // 是否启用光圈效果
	public var rippleMaxSize:Float = 100;   // 光圈最大扩散半径
	public var rippleSpeed:Float = 3.0;     // 光圈扩散速度
	public var rippleAlphaDecay:Float = 0.04; // 光圈透明度衰减速度（稍快以快速清理）
	public var rippleThickness:Float = 3.0;   // 光圈线条粗细
	public var rippleColor:Int = 0x00BFFF;  // 光圈颜色

	// 发光效果配置
	public var glowEnabled:Bool = true;    // 是否启用发光效果
	public var glowColor:Int = 0x00BFFF;  // 发光颜色
	public var glowAlpha:Float = 0.8;     // 发光透明度（降低以减少渲染开销）
	public var glowBlur:Float = 30.0;     // 发光模糊度（降低以提升性能）
	public var glowStrength:Float = 5;   // 发光强度（降低以提升性能）

	// 性能优化：缓存的发光滤镜
	private var cachedGlowFilter:GlowFilter = null;

	// 鼠标位置追踪
	private var trailMouseX:Float = 0;
	private var trailMouseY:Float = 0;
	private var lastMouseX:Float = -1;
	private var lastMouseY:Float = -1;
	private var isMoving:Bool = false;
	private var initialized:Bool = false;
	private var dpiScale:Float = 1.0;

	public function new()
	{
		super();
		this.mouseEnabled = false;
		this.mouseChildren = false;

		// 计算 DPI 缩放比例
		calculateDPIScale();

		// 监听鼠标移动事件
		Lib.current.stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);

		// 监听鼠标点击事件
		Lib.current.stage.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);

		// 监听每帧更新
		Lib.current.stage.addEventListener(Event.ENTER_FRAME, update);
	}

	/**
	 * 计算 DPI 缩放比例
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
		}
	}

	/**
	 * 鼠标移动事件处理 - 获取准确的屏幕坐标
	 */
	private function onMouseMove(e:MouseEvent):Void
	{
		if (!initialized)
		{
			// 初始化鼠标位置
			trailMouseX = e.stageX;
			trailMouseY = e.stageY;
			lastMouseX = trailMouseX;
			lastMouseY = trailMouseY;
			initialized = true;
		}
		else
		{
			// 更新鼠标位置
			trailMouseX = e.stageX;
			trailMouseY = e.stageY;
		}
	}

	/**
	 * 鼠标点击事件处理
	 */
	private function onMouseDown(e:MouseEvent):Void
	{
		// 只处理左键点击
		// OpenFL 的 MouseEvent 使用 altKey、ctrlKey、shiftKey 和 buttonDown
		// buttonDown 为 true 表示主要鼠标按钮（通常是左键）
		addClickEffect(e.stageX, e.stageY);

		// 添加光圈扩张效果
		if (rippleEnabled)
		{
			addRippleEffect(e.stageX, e.stageY);
		}
	}

	/**
	 * 更新拖尾效果（性能优化：只在有元素时才更新）
	 */
	private function update(e:Event):Void
	{
		if (!initialized)
			return;

		// 性能优化：如果没有任何效果，直接返回
		if (particles.length == 0 && clickEffects.length == 0 && rippleEffects.length == 0)
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

		// 更新所有粒子
		if (particles.length > 0)
			updateParticles();

		// 更新点击效果
		if (clickEffects.length > 0)
			updateClickEffects();

		// 更新光圈效果
		if (rippleEffects.length > 0)
			updateRippleEffects();

		// 更新最后位置
		lastMouseX = trailMouseX;
		lastMouseY = trailMouseY;
	}

	/**
	 * 创建发光滤镜（性能优化：缓存滤镜对象）
	 */
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
	 * 添加拖尾粒子
	 */
	private function addParticle(x:Float, y:Float):Void
	{
		// 限制粒子数量
		while (particles.length >= trailLength)
		{
			var oldParticle:TrailParticle = particles.shift();
			if (oldParticle != null)
			{
				removeChild(oldParticle.shape);
			}
		}

		// 根据 DPI 缩放调整粒子大小
		var scaledSize:Float = trailSize * dpiScale;

		// 创建新粒子
		var particle:TrailParticle = new TrailParticle();
		particle.x = x;
		particle.y = y;
		particle.size = scaledSize;
		particle.alpha = trailAlpha;
		particle.color = trailColor;

		// 创建形状
		var shape:Shape = new Shape();
		shape.graphics.beginFill(trailColor, trailAlpha);
		shape.graphics.drawCircle(0, 0, scaledSize / 2);
		shape.graphics.endFill();
		// 直接设置位置，不使用局部坐标
		shape.x = x;
		shape.y = y;

		// 应用发光效果
		var glow:GlowFilter = createGlowFilter();
		if (glow != null)
		{
			shape.filters = [glow];
		}

		particle.shape = shape;
		addChild(particle.shape);
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

			// 性能优化：只在粒子可见时才更新图形
			if (particle.alpha >= 0.05 && particle.size >= 1 && particle.shape != null)
			{
				particle.shape.graphics.clear();
				particle.shape.graphics.beginFill(particle.color, particle.alpha);
				particle.shape.graphics.drawCircle(0, 0, particle.size / 2);
				particle.shape.graphics.endFill();
			}

			// 移除过小的粒子
			if (particle.size < 1 || particle.alpha < 0.05)
			{
				removeChild(particle.shape);
				particles.splice(i, 1);
			}

			i--;
		}
	}

	/**
	 * 添加点击效果
	 */
	private function addClickEffect(x:Float, y:Float):Void
	{
		var effect:ClickEffect = new ClickEffect();
		effect.x = x;
		effect.y = y;
		effect.size = clickEffectSize * dpiScale;
		effect.alpha = clickEffectAlpha;
		effect.color = clickEffectColor;

		// 创建形状
		var shape:Shape = new Shape();
		shape.graphics.beginFill(clickEffectColor, clickEffectAlpha);
		shape.graphics.drawCircle(0, 0, effect.size / 2);
		shape.graphics.endFill();
		shape.x = x;
		shape.y = y;

		// 应用发光效果
		var glow:GlowFilter = createGlowFilter();
		if (glow != null)
		{
			shape.filters = [glow];
		}

		effect.shape = shape;
		addChild(shape);
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

			// 性能优化：只在效果可见时才更新图形
			if (effect.alpha >= 0.05 && effect.size >= 1 && effect.shape != null)
			{
				effect.shape.graphics.clear();
				effect.shape.graphics.beginFill(clickEffectColor, effect.alpha);
				effect.shape.graphics.drawCircle(0, 0, effect.size / 2);
				effect.shape.graphics.endFill();
			}

			// 移除过小的效果
			if (effect.size < 1 || effect.alpha < 0.05)
			{
				removeChild(effect.shape);
				clickEffects.splice(i, 1);
			}

			i--;
		}
	}

	/**
	 * 添加光圈效果
	 */
	private function addRippleEffect(x:Float, y:Float):Void
	{
		var ripple:RippleEffect = new RippleEffect();
		ripple.x = x;
		ripple.y = y;
		ripple.radius = 10;
		ripple.alpha = 1.0;

		// 创建形状
		var shape:Shape = new Shape();
		shape.graphics.lineStyle(rippleThickness * dpiScale, rippleColor, 1.0);
		shape.graphics.drawCircle(0, 0, ripple.radius);
		shape.x = x;
		shape.y = y;

		// 应用发光效果
		var glow:GlowFilter = createGlowFilter();
		if (glow != null)
		{
			shape.filters = [glow];
		}

		ripple.shape = shape;
		addChild(shape);
		rippleEffects.push(ripple);
	}

	/**
	 * 更新光圈效果（性能优化：减少不必要的重绘）
	 */
	private function updateRippleEffects():Void
	{
		var i:Int = rippleEffects.length - 1;
		while (i >= 0)
		{
			var ripple:RippleEffect = rippleEffects[i];

			// 扩散光圈
			ripple.radius += rippleSpeed * dpiScale;

			// 衰减透明度
			ripple.alpha -= rippleAlphaDecay;

			// 性能优化：只在光圈可见时才更新图形
			if (ripple.alpha > 0 && ripple.radius < rippleMaxSize * dpiScale && ripple.shape != null)
			{
				ripple.shape.graphics.clear();
				ripple.shape.graphics.lineStyle(rippleThickness * dpiScale, rippleColor, ripple.alpha);
				ripple.shape.graphics.drawCircle(0, 0, ripple.radius);
			}

			// 移除完全消失的光圈
			if (ripple.radius >= rippleMaxSize * dpiScale || ripple.alpha <= 0)
			{
				removeChild(ripple.shape);
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
		for (particle in particles)
		{
			if (particle.shape != null)
			{
				removeChild(particle.shape);
			}
		}
		particles = [];
	}

	/**
	 * 清除所有点击效果
	 */
	public function clearClickEffects():Void
	{
		for (effect in clickEffects)
		{
			if (effect.shape != null)
			{
				removeChild(effect.shape);
			}
		}
		clickEffects = [];
	}

	/**
	 * 清除所有光圈效果
	 */
	public function clearRippleEffects():Void
	{
		for (ripple in rippleEffects)
		{
			if (ripple.shape != null)
			{
				removeChild(ripple.shape);
			}
		}
		rippleEffects = [];
	}

	/**
	 * 设置拖尾颜色
	 */
	public function setTrailColor(color:Int):Void
	{
		trailColor = color;
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
	 * 销毁拖尾效果
	 */
	public function destroy():Void
	{
		clearTrail();
		clearClickEffects();
		clearRippleEffects();
		Lib.current.stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
		Lib.current.stage.removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
		Lib.current.stage.removeEventListener(Event.ENTER_FRAME, update);
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
	public var shape:Shape;

	public function new()
	{
		this.x = 0;
		this.y = 0;
		this.size = 28;
		this.alpha = 1;
		this.color = 0x00BFFF;
		this.shape = null;
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
	public var shape:Shape;

	public function new()
	{
		this.x = 0;
		this.y = 0;
		this.size = 40;
		this.alpha = 1;
		this.color = 0x00BFFF;
		this.shape = null;
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
	public var shape:Shape;

	public function new()
	{
		this.x = 0;
		this.y = 0;
		this.radius = 10;
		this.alpha = 1.0;
		this.shape = null;
	}
}
