package objects;

class HealthIcon extends FlxSprite
{
	public var sprTracker:FlxSprite;
	private var isPlayer:Bool = false;
	private var char:String = '';
	public var startSize:Float = 1;
	public var framesCount:Int = 1; // 当前图标实际包含的状态帧数量

	// 资源保护的上下文标签。由 FreeplayState 在构建图标批量创建前设为 'freeplay'，
	// 构建完清回 null。其他状态（PlayState、编辑器等）默认 null，
	// HealthIcon 不会自动调 excludeAsset，图标纹理随该状态 destroy 时一起被清。
	public static var _excludeContext:Null<String> = null;


	public function new(char:String = 'face', isPlayer:Bool = false, ?allowGPU:Bool = true)
	{
		super();
		this.isPlayer = isPlayer;
		changeIcon(char, allowGPU);
		scrollFactor.set();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (sprTracker != null)
			setPosition(sprTracker.x + sprTracker.width + 12, sprTracker.y - 30);
	}

	private var iconOffsets:Array<Float> = [0, 0];
	public function changeIcon(char:String, ?allowGPU:Bool = true) {
		if(this.char != char) {
			var name:String = 'icons/' + char;

			// Leather 图标模式：当 loadLeatherIcons='leather' 时优先查找 leather/<角色名>-icons 格式，
			// Paths.fileExists / Paths.image 会自动按 Mods → currentLevel → shared 顺序解析，
			// 因此 Mods 中的 Leather 图标会被自动优先使用。
			if (ClientPrefs.data.loadLeatherIcons == 'leather') {
				var leatherName:String = 'icons/leather/' + char + '-icons';
				if (Paths.fileExists('images/' + leatherName + '.png', IMAGE))
					name = leatherName;
			}
			// OS 图标模式：当 loadLeatherIcons='os' 时使用 OS 风格图标（icons/os/icon-<角色名>.png）
			else if (ClientPrefs.data.loadLeatherIcons == 'os') {
				var osName:String = 'icons/os/icon-' + char;
				if (Paths.fileExists('images/' + osName + '.png', IMAGE))
					name = osName;
			}

			if(!Paths.fileExists('images/' + name + '.png', IMAGE)) name = 'icons/icon-' + char; //Older versions of psych engine's support
			if(!Paths.fileExists('images/' + name + '.png', IMAGE)) name = 'icons/icon-face'; //Prevents crash from missing icon

			var graphic = Paths.image(name, allowGPU);

			// 资源保护由调用方通过 HealthIcon._excludeContext 设置上下文标签。
			// FreeplayState 在构建批量图标前会设为 'freeplay'，退出时调
			// Paths.clearExcludedByTag('freeplay') → clearStoredMemory → 真正释放纹理。
			// PlayState / 编辑器等其他状态的 _excludeContext 默认 null，
			// 图标纹理不被保护，随该状态 destroy 时一起被清，无累积泄漏。
			if (graphic != null && graphic.key != null && graphic.key.length > 0)
				Paths.excludeAsset(graphic.key, _excludeContext);

			// 自适应切分：按 宽/高 推算图标数量，每个图标视为正方形。
			// 这样 2:1（双态）、3:1（三态）等任意数量的图标条都能正确切分，避免把 2:1 误切成三份。
			var iSize:Int = Math.round(graphic.width / graphic.height);
			var frameW:Int = Math.floor(graphic.width / iSize);
			var frameH:Int = Math.floor(graphic.height);

			loadGraphic(graphic, true, frameW, frameH);
			// 在 150x150 参考框内居中，兼容宽矩形与方形图标
			iconOffsets[0] = (width - 150) / 2;
			iconOffsets[1] = (height - 150) / 2;
			startSize = scale.x;
			updateHitbox();

			animation.add(char, [for(i in 0...frames.frames.length) i], 0, false, isPlayer);
			animation.play(char);
			this.char = char;
			framesCount = frames.frames.length;

			if(char.endsWith('-pixel'))
				antialiasing = false;
			else
				antialiasing = ClientPrefs.data.antialiasing;
		}
	}

	/**
	 * 设置图标状态：'normal'（正常）、'lose'（输）、'win'（赢）
	 * 帧索引：0 = 正常，1 = 输，2 = 赢（仅当图标实际包含对应帧时生效，否则自动回退，保证兼容）
	 */
	public function setIconState(state:String)
	{
		if (animation.curAnim == null || framesCount <= 0) return;
		var f:Int = 0;
		switch (state)
		{
			case 'lose': f = (framesCount > 1) ? 1 : 0;
			case 'win':  f = (framesCount > 2) ? 2 : 0; // 无独立赢帧时回退到正常帧(0)，而不是输帧(1)
			default:     f = 0;
		}
		if (f > framesCount - 1) f = framesCount - 1;
		if (f < 0) f = 0;
		animation.curAnim.curFrame = f;
	}


	public var autoAdjustOffset:Bool = true;
	override function updateHitbox()
	{
		super.updateHitbox();
		if(autoAdjustOffset)
		{
			offset.x = iconOffsets[0];
			offset.y = iconOffsets[1];
		}
	}

	public function getCharacter():String {
		return char;
	}
}
