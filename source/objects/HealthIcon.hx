package objects;

class HealthIcon extends FlxSprite
{
	public var sprTracker:FlxSprite;
	private var isPlayer:Bool = false;
	private var char:String = '';
	public var startSize:Float = 1;
	public var framesCount:Int = 1; // 当前图标实际包含的状态帧数量


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

			// 保护图标纹理缓存：图标是 Freeplay 等场景反复使用的高频资源，
			// 登记到 dumpExclusions 使其在 clearStoredMemory/clearUnusedMemory 时不被清除，
			// 避免每次进入 Freeplay 都重复解码全部图标 PNG（低端设备进入慢的主要卡顿源）。
			if (graphic != null && graphic.key != null && graphic.key.length > 0)
				Paths.excludeAsset(graphic.key);

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
