package states;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.math.FlxMath;
import flixel.graphics.FlxGraphic;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;

import backend.MusicBeatState;
import backend.ui.PsychUIButton;
import backend.ClientPrefs;

import states.editors.MasterEditorMenu;
import states.editors.content.FileDialogHandler;

import states.StoryData;
import states.StorySpineTools;

import mobile.backend.StorageUtil;

import spine.flixel.NoCullSkeletonSprite;

import haxe.Json;

#if desktop
import lime.app.Application;
#end

/**
 * 剧情播放器（Story Player）
 *
 * 参考 DialogueEditorState 的「读取 / 加载 / 逐字播放」逻辑，以及
 * SpineViewerState 的 Spine 角色加载方式，做一个类似《蔚蓝档案》的 ADV 剧情演出。
 *
 * UI 完全从零绘制，不依赖 FNF 自带贴图：
 *   - 屏幕底部到中间：#4682B4 -> 透明 的竖直渐变
 *   - 屏幕垂直中间往下约 1/5 处：较粗横线（#87CEFA）
 *   - 横线上方约 20px、左对齐：角色名（白色）；其右 50px：所属（#6495ED，字偏小）
 *   - 横线下方：逐字打字机文本（unifont，支持中文）
 *
 * 剧情用一个 JSON 描述（见 StoryData.StoryFile），通过顶部 Load 按钮或拖拽 .json
 * 载入；也可点 Demo 直接体验示例。编辑器（StoryEditorState）负责创作并保存。
 */
class StoryPlayerState extends MusicBeatState
{
	static final UI_FONT:String = 'unifont-18.0.01.otf';
	static final TOP_BAR_H:Int = 36;
	static final MARGIN:Int = 64;
	static final LINE_COLOR:Int = 0x87CEFA;
	static final GRADIENT_BOTTOM:Int = 0x4682B4;
	static final AFF_COLOR:Int = 0x6495ED;

	// 编辑器通过此静态入口直接把内存中的剧情交给播放器
	public static var pendingStory:StoryFile = null;
	public static var pendingJsonDir:String = '';

	var bgSprite:FlxSprite;
	var charGroup:FlxGroup;
	var chars:Array<StorySpineChar> = [];
	var charMap:Map<String, StorySpineChar> = new Map<String, StorySpineChar>();

	var gradient:FlxSprite;
	var divider:FlxSprite;
	var nameText:FlxText;
	var affText:FlxText;
	var daText:FlxText;
	var advanceHint:FlxText;

	var topBar:FlxSprite;
	var loadBtn:PsychUIButton;
	var demoBtn:PsychUIButton;
	var backBtn:PsychUIButton;
	var hintText:FlxText;

	var fileHandler:FileDialogHandler;

	var story:StoryFile = null;
	var loaded:Bool = false;
	var curLine:Int = 0;
	var currentJsonDir:String = '';

	var typeText:String = '';
	var typeChars:Int = 0;
	var typeTimer:Float = 0;
	var typeDelay:Float = 0.05;
	var typeSound:String = 'dialogue';
	var typeFinished:Bool = false;
	var maxChars:Int = 40;
	var advanceHintTimer:Float = 0;

	var inputLockFrames:Int = 0;

	#if desktop
	var dropHandler:(String)->Void = null;
	#end

	override function create()
	{
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Story Player", null);
		#end

		super.create();

		FlxG.camera.bgColor = 0xFF1a1a24;
		FlxG.mouse.visible = true;

		bgSprite = new FlxSprite(0, 0);
		bgSprite.scrollFactor.set();
		bgSprite.visible = false;
		add(bgSprite);

		charGroup = new FlxGroup();
		add(charGroup);

		// 下半屏渐变：中间透明 -> 底部 #4682B4
		var gh:Int = Std.int(FlxG.height / 2);
		gradient = new FlxSprite(0, gh);
		gradient.loadGraphic(makeGradientGraphic(FlxG.width, gh, GRADIENT_BOTTOM, GRADIENT_BOTTOM, 0.0, 1.0));
		gradient.scrollFactor.set();
		add(gradient);

		// 较粗横线（屏幕垂直中间往下约 1/5）
		var lineY:Int = Std.int(FlxG.height * 0.7);
		divider = new FlxSprite(0, lineY);
		divider.makeGraphic(FlxG.width, 4, LINE_COLOR);
		divider.scrollFactor.set();
		add(divider);

		// 角色名（横线上方约 20px，左对齐，白色）
		nameText = new FlxText(MARGIN, lineY - 44, FlxG.width - MARGIN, '', 24);
		nameText.setFormat(Paths.font(UI_FONT), 24, FlxColor.WHITE, LEFT);
		nameText.scrollFactor.set();
		nameText.visible = false;
		add(nameText);

		// 所属（角色名右 50px，字偏小，#6495ED）
		affText = new FlxText(MARGIN, lineY - 36, FlxG.width - MARGIN - 50, '', 16);
		affText.setFormat(Paths.font(UI_FONT), 16, AFF_COLOR, LEFT);
		affText.scrollFactor.set();
		affText.visible = false;
		add(affText);

		// 逐字文本（横线下方）
		daText = new FlxText(MARGIN, lineY + 14, FlxG.width - MARGIN * 2, '', 20);
		daText.setFormat(Paths.font(UI_FONT), 20, FlxColor.WHITE, LEFT);
		daText.wordWrap = true;
		daText.scrollFactor.set();
		daText.visible = false;
		add(daText);
		maxChars = Math.floor((FlxG.width - MARGIN * 2) / 20) - 1;

		advanceHint = new FlxText(FlxG.width - 50, FlxG.height - 40, 40, '▼', 22);
		advanceHint.setFormat(Paths.font(UI_FONT), 22, FlxColor.WHITE, RIGHT);
		advanceHint.scrollFactor.set();
		advanceHint.visible = false;
		add(advanceHint);

		topBar = new FlxSprite(0, 0);
		topBar.makeGraphic(FlxG.width, TOP_BAR_H, FlxColor.BLACK);
		topBar.alpha = 0.4;
		topBar.scrollFactor.set();
		add(topBar);

		loadBtn = makeButton(10, 4, 90, "Load", openStoryPicker);
		demoBtn = makeButton(110, 4, 90, "Demo", () -> beginStory(defaultStory()));
		backBtn = makeButton(FlxG.width - 80, 4, 70, "Back", onBack);

		hintText = new FlxText(10, TOP_BAR_H + 10, FlxG.width - 20,
			'剧情播放器：点击 Load 选择剧情 JSON，或点击 Demo 体验示例。\n'
			+ '播放时点击屏幕 / 空格 / 回车 推进对话；未打完时点击会立即显示整句。按 BACK / ESC 退出。', 18);
		hintText.setFormat(Paths.font(UI_FONT), 18, FlxColor.WHITE, LEFT);
		add(hintText);

		fileHandler = new FileDialogHandler();

		#if desktop
		dropHandler = function(path:String)
		{
			path = path.replace('\\', '/');
			if (path.toLowerCase().endsWith('.json'))
			{
				showHint("已通过拖拽载入剧情文件，正在播放……");
				currentJsonDir = StorySpineTools.dirname(path);
				loadStoryFromString(sys.io.File.getContent(path));
			}
			else
				showHint("拖入的文件不是 .json 剧情文件。");
		};
		Application.current.window.onDropFile.add(dropHandler);
		#end

		if (pendingStory != null)
		{
			var s = pendingStory;
			pendingStory = null;
			currentJsonDir = pendingJsonDir;
			pendingJsonDir = '';
			beginStory(s);
		}
	}

	override function destroy()
	{
		#if desktop
		if (dropHandler != null && Application.current != null && Application.current.window != null)
			Application.current.window.onDropFile.remove(dropHandler);
		dropHandler = null;
		#end

		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();

		if (fileHandler != null)
		{
			fileHandler.destroy();
			fileHandler = null;
		}
		super.destroy();
	}

	// ------------------------------------------------------------------
	// 渐变生成（从零绘制，不用 FNF 贴图）
	// ------------------------------------------------------------------
	function makeGradientGraphic(w:Int, h:Int, topColor:Int, bottomColor:Int, topAlpha:Float, bottomAlpha:Float):FlxGraphic
	{
		var bd:BitmapData = new BitmapData(w, h, true, 0x00000000);
		for (i in 0...h)
		{
			var t:Float = (h <= 1) ? 0 : i / (h - 1);
			var r:Int = Std.int(lerp(((topColor >> 16) & 0xFF), ((bottomColor >> 16) & 0xFF), t));
			var g:Int = Std.int(lerp(((topColor >> 8) & 0xFF), ((bottomColor >> 8) & 0xFF), t));
			var b:Int = Std.int(lerp((topColor & 0xFF), (bottomColor & 0xFF), t));
			var a:Int = Std.int(lerp(topAlpha * 255, bottomAlpha * 255, t));
			var col:Int = (a << 24) | (r << 16) | (g << 8) | b;
			bd.fillRect(new Rectangle(0, i, w, 1), col);
		}
		return FlxGraphic.fromBitmapData(bd);
	}

	function lerp(a:Float, b:Float, t:Float):Float
	{
		return a + (b - a) * t;
	}

	// ------------------------------------------------------------------
	// UI 辅助
	// ------------------------------------------------------------------
	function makeButton(x:Float, y:Float, w:Int, label:String, onClick:Void->Void):PsychUIButton
	{
		var btn:PsychUIButton = new PsychUIButton(x, y, label, onClick, w, 28);
		btn.cameras = [FlxG.camera];
		btn.bg.cameras = [FlxG.camera];
		btn.text.cameras = [FlxG.camera];
		add(btn);
		return btn;
	}

	function showHint(msg:String):Void
	{
		if (hintText != null)
		{
			hintText.text = msg;
			hintText.visible = true;
		}
	}

	function isOverUI(px:Float, py:Float):Bool
	{
		return topBar != null && FlxG.mouse.overlaps(topBar);
	}

	// ------------------------------------------------------------------
	// 载入剧情
	// ------------------------------------------------------------------
	function openStoryPicker():Void
	{
		if (fileHandler == null)
			return;
		if (!fileHandler.completed)
			fileHandler.completed = true;

		#if (desktop || (js && html5))
		try
		{
			fileHandler.open(null, null, [new flash.net.FileFilter('JSON', 'json')], onStoryLoaded, null, onStoryLoadError);
		}
		catch (e:Dynamic)
		{
			fileHandler.completed = true;
			showHint("无法打开文件选择窗口: " + e);
		}
		#else
		#if sys
		var p:String = StorageUtil.getExternalStorageDirectory() + 'saves/story.json';
		if (!sys.FileSystem.exists(p))
		{
			showHint("未找到移动端剧情文件:\n" + p);
			return;
		}
		currentJsonDir = StorySpineTools.dirname(p);
		loadStoryFromString(sys.io.File.getContent(p));
		#else
		showHint("当前平台不支持文件选择，请使用桌面端载入剧情。");
		#end
		#end
	}

	function onStoryLoaded():Void
	{
		inputLockFrames = 12;
		if (fileHandler == null || fileHandler.path == null)
			return;
		var path:String = fileHandler.path.replace('\\', '/');
		if (!path.toLowerCase().endsWith('.json'))
		{
			showHint("请选择 .json 剧情文件。");
			return;
		}
		currentJsonDir = StorySpineTools.dirname(path);
		var str:String = fileHandler.data;
		#if sys
		if ((str == null || str.length == 0) && sys.FileSystem.exists(path))
			str = sys.io.File.getContent(path);
		#end
		loadStoryFromString(str);
	}

	function onStoryLoadError():Void
	{
		inputLockFrames = 12;
	}

	function loadStoryFromString(str:String):Void
	{
		if (str == null || str.length == 0)
		{
			showHint("剧情内容为空，无法载入。");
			return;
		}
		var sf:StoryFile = null;
		try
		{
			sf = cast haxe.Json.parse(str);
		}
		catch (e:Dynamic)
		{
			showHint("剧情解析失败: " + e);
			return;
		}
		if (sf == null || sf.lines == null)
		{
			showHint("剧情格式不正确（缺少 lines 数组）。");
			return;
		}
		beginStory(sf);
	}

	// ------------------------------------------------------------------
	// 开始播放
	// ------------------------------------------------------------------
	function beginStory(sf:StoryFile):Void
	{
		story = sf;

		setupBackground(sf.background);

		if (sf.music != null && sf.music != '')
		{
			if (FlxG.sound.music != null)
				FlxG.sound.music.stop();
			FlxG.sound.playMusic(Paths.music(sf.music), 0, true);
			FlxG.sound.music.fadeIn(2, 0, 0.6);
		}

		for (c in chars)
		{
			charGroup.remove(c.sprite);
			c.sprite.destroy();
		}
		chars = [];
		charMap = new Map<String, StorySpineChar>();

		if (sf.characters != null)
		{
			for (def in sf.characters)
			{
				if (def == null || def.id == null)
					continue;
				var ch:StorySpineChar = loadSpineCharacter(def);
				if (ch != null)
				{
					chars.push(ch);
					charMap.set(def.id, ch);
					charGroup.add(ch.sprite);
				}
			}
		}

		loaded = true;
		if (hintText != null) hintText.visible = false;
		if (loadBtn != null) loadBtn.visible = false;
		if (demoBtn != null) demoBtn.visible = false;

		inputLockFrames = 12;
		curLine = 0;
		startLine(sf.lines[0]);
	}

	function startLine(line:StoryLine):Void
	{
		if (line == null)
		{
			endStory();
			return;
		}

		var text:String = (line.text != null) ? line.text : '';
		typeText = wrapText(text, maxChars);
		typeChars = 0;
		typeTimer = 0;
		typeFinished = false;
		typeDelay = (line.speed != null && !Math.isNaN(line.speed) && line.speed > 0) ? line.speed : 0.05;
		typeSound = (line.sound != null && line.sound.trim() != '') ? line.sound : 'dialogue';
		daText.text = '';

		var speaker:StorySpineChar = (line.character != null) ? charMap.get(line.character) : null;

		for (c in chars)
		{
			c.targetAlpha = (c == speaker) ? 1.0 : 0.4;
			if (c != speaker)
				c.setAnim(c.defaultAnim, true);
		}

		if (speaker != null)
		{
			var expr:String = (line.expression != null && line.expression != '') ? line.expression : speaker.defaultAnim;
			speaker.setAnim(expr, true);

			var nm:String = (line.name != null && line.name.trim() != '') ? line.name : speaker.name;
			nameText.text = (nm != null) ? nm : '';
			nameText.visible = true;

			var aff:String = (line.affiliation != null && line.affiliation.trim() != '') ? line.affiliation : speaker.affiliation;
			if (aff != null && aff.trim() != '')
			{
				affText.text = aff;
				affText.x = nameText.x + nameText.width + 50;
				affText.visible = true;
			}
			else
				affText.visible = false;
		}
		else
		{
			nameText.visible = false;
			affText.visible = false;
		}

		daText.visible = true;
		advanceHint.visible = false;
	}

	function endStory():Void
	{
		if (FlxG.sound.music != null)
			FlxG.sound.music.fadeOut(0.6, 0, (_) -> FlxG.sound.music.stop());
		MusicBeatState.switchState(new MasterEditorMenu());
	}

	function onBack():Void
	{
		endStory();
	}

	// ------------------------------------------------------------------
	// 主循环
	// ------------------------------------------------------------------
	override function update(elapsed:Float)
	{
		if (inputLockFrames > 0)
		{
			inputLockFrames--;
		}
		else if (loaded)
		{
			var overUI:Bool = isOverUI(FlxG.mouse.x, FlxG.mouse.y);
			var pressed:Bool = FlxG.mouse.justPressed
				|| FlxG.keys.justPressed.SPACE
				|| FlxG.keys.justPressed.ENTER
				|| controls.ACCEPT;
			if (pressed && !overUI)
			{
				if (!typeFinished)
				{
					typeFinished = true;
					typeChars = typeText.length;
					daText.text = typeText;
					advanceHint.visible = true;
				}
				else
				{
					curLine++;
					if (curLine >= story.lines.length)
						endStory();
					else
						startLine(story.lines[curLine]);
				}
			}
		}

		if (loaded && !typeFinished)
		{
			if (typeDelay <= 0)
			{
				typeFinished = true;
				typeChars = typeText.length;
				daText.text = typeText;
				advanceHint.visible = true;
			}
			else
			{
				typeTimer += elapsed;
				while (typeTimer >= typeDelay && typeChars < typeText.length)
				{
					typeChars++;
					typeTimer = 0;
					daText.text = typeText.substr(0, typeChars);
					if (typeSound != '' && (typeDelay > 0.025 || typeChars % 2 == 0))
						FlxG.sound.play(Paths.sound(typeSound), 1);
					if (typeChars >= typeText.length)
					{
						typeFinished = true;
						daText.text = typeText;
						advanceHint.visible = true;
					}
				}
			}
		}

		for (c in chars)
		{
			if (c.sprite.alpha != c.targetAlpha)
				c.sprite.alpha = FlxMath.lerp(c.sprite.alpha, c.targetAlpha, 1 - Math.exp(-10 * elapsed));
		}

		if (advanceHint.visible)
		{
			advanceHintTimer += elapsed;
			advanceHint.alpha = 0.35 + 0.65 * (0.5 + 0.5 * Math.sin(advanceHintTimer * Math.PI * 3));
		}

		if (controls.BACK || FlxG.keys.justPressed.ESCAPE)
		{
			onBack();
			return;
		}

		super.update(elapsed);
	}

	// ------------------------------------------------------------------
	// 背景
	// ------------------------------------------------------------------
	function setupBackground(bg:String):Void
	{
		bgSprite.visible = false;
		var col:Null<Int> = parseColor(bg);
		if (col != null)
		{
			FlxG.camera.bgColor = col;
			return;
		}
		var g:FlxGraphic = loadImageGraphic(bg);
		if (g != null)
		{
			bgSprite.loadGraphic(g);
			bgSprite.setGraphicSize(FlxG.width, FlxG.height);
			bgSprite.updateHitbox();
			bgSprite.visible = true;
			return;
		}
		FlxG.camera.bgColor = 0xFF1a1a24;
	}

	function parseColor(s:String):Null<Int>
	{
		if (s == null)
			return null;
		s = s.trim();
		if (s.length == 0)
			return null;
		if (s.startsWith('0x') || s.startsWith('0X'))
			return Std.parseInt(s);
		if (s.startsWith('#'))
		{
			var hex:String = s.substring(1);
			if (hex.length == 6 || hex.length == 8)
				return Std.parseInt('0x' + hex);
		}
		var v:Int = Std.parseInt(s);
		return Math.isNaN(v) ? null : v;
	}

	function loadImageGraphic(path:String):FlxGraphic
	{
		if (path == null || path == '')
			return null;
		#if sys
		if (sys.FileSystem.exists(path))
		{
			var bd:BitmapData = BitmapData.fromFile(path);
			if (bd != null)
				return FlxGraphic.fromBitmapData(bd);
			// 文件存在但解码失败：不直接返回 null，改用 Paths.image 走“资源缺失提示”，
			// 使 AssetErrorOverlay 的占位标记能够生效，而不是退化为 flixel 默认图。
		}
		#end
		try
		{
			return Paths.image(path);
		}
		catch (e:Dynamic) {}
		return null;
	}

	// ------------------------------------------------------------------
	// Spine 角色加载
	// ------------------------------------------------------------------
	function resolvePath(p:String):String
	{
		if (p == null)
			return p;
		#if sys
		if (sys.FileSystem.exists(p))
			return p;
		if (currentJsonDir != null && currentJsonDir != '' && !haxe.io.Path.isAbsolute(p))
		{
			var rel:String = currentJsonDir + '/' + p;
			if (sys.FileSystem.exists(rel))
				return rel;
		}
		#end
		return p;
	}

	function loadSpineCharacter(def:StoryCharDef):StorySpineChar
	{
		var atlasPath:String = resolvePath(def.atlasPath);
		var skeletonPath:String = resolvePath(def.skeletonPath);
		if (atlasPath == null || skeletonPath == null)
		{
			showHint("角色 " + def.id + " 缺少 atlasPath / skeletonPath。");
			return null;
		}

		try
		{
			var loaded = StorySpineTools.loadSpine(atlasPath, skeletonPath, def.skin);
			var sx:Float = (def.x != null) ? def.x * FlxG.width : FlxG.width / 2;
			var sy:Float = (def.y != null) ? def.y * FlxG.height : FlxG.height * 0.85;
			var sc:Float = (def.scale != null) ? def.scale : 1.0;
			loaded.sprite.x = sx;
			loaded.sprite.y = sy;
			loaded.sprite.scaleX = (def.flipX == true) ? -sc : sc;
			loaded.sprite.scaleY = sc;
			loaded.sprite.antialiasing = ClientPrefs.data.antialiasing;
			loaded.sprite.active = true;

			var ch:StorySpineChar = new StorySpineChar(loaded.sprite, def);
			ch.anims = loaded.anims;
			if (ch.defaultAnim == null || ch.defaultAnim == '')
				ch.defaultAnim = (ch.anims.length > 0) ? ch.anims[0] : '';
			if (ch.defaultAnim != '')
				ch.setAnim(ch.defaultAnim, true);

			return ch;
		}
		catch (e:Dynamic)
		{
			showHint("Spine 角色加载失败 (" + def.id + "): " + Std.string(e));
			trace("StoryPlayerState.loadSpineCharacter error: " + Std.string(e));
			return null;
		}
	}

	// ------------------------------------------------------------------
	// 文本换行（按字符数，兼容中文）
	// ------------------------------------------------------------------
	function wrapText(str:String, maxChars:Int):String
	{
		if (maxChars <= 0 || str == null)
			return str == null ? '' : str;
		var out:String = '';
		var lines:Array<String> = str.split('\n');
		for (li in 0...lines.length)
		{
			var line:String = lines[li];
			var i:Int = 0;
			while (i < line.length)
			{
				var take:Int = maxChars;
				var chunk:String = line.substr(i, take);
				if (i + take < line.length)
				{
					var sp:Int = chunk.lastIndexOf(' ');
					if (sp > 0)
					{
						take = sp + 1;
						chunk = line.substr(i, take);
					}
				}
				out += chunk;
				i += take;
				if (i < line.length)
					out += '\n';
			}
			if (li < lines.length - 1)
				out += '\n';
		}
		return out;
	}

	// ------------------------------------------------------------------
	// 示例剧情（无需 Spine 资源，点击 Demo 即可测试打字逻辑）
	// ------------------------------------------------------------------
	function defaultStory():StoryFile
	{
		return {
			background: '#1a1a24',
			music: '',
			characters: [],
			lines: [
				{text: '【示例剧情】这是一个用 Spine 角色演出、逐字打字的剧情播放器。'},
				{text: '点击屏幕 / 空格 / 回车 可推进对话；未打完时点一下会立即显示整句。'},
				{text: '在顶部点击 Load 载入你的剧情 JSON，即可让 Spine 角色登场演出。'},
				{text: '—— 就像《Blue Archive》那样。'}
			]
		};
	}
}

/**
 * 剧情里的一个 Spine 角色实例。
 */
private class StorySpineChar
{
	public var sprite:NoCullSkeletonSprite;
	public var def:StoryCharDef;
	public var id:String;
	public var name:String;
	public var affiliation:String;
	public var anims:Array<String> = [];
	public var defaultAnim:String;
	public var currentAnim:String = '';
	public var targetAlpha:Float = 1;

	public function new(sprite:NoCullSkeletonSprite, def:StoryCharDef)
	{
		this.sprite = sprite;
		this.def = def;
		this.id = def.id;
		this.name = (def.name != null) ? def.name : def.id;
		this.affiliation = (def.affiliation != null) ? def.affiliation : '';
		this.defaultAnim = (def.defaultAnim != null) ? def.defaultAnim : '';
	}

	public function setAnim(name:String, loop:Bool):Void
	{
		if (name == null || name == '' || sprite == null)
			return;
		var anim = sprite.skeleton.data.findAnimation(name);
		if (anim == null)
			return;
		sprite.state.setAnimation(0, anim, loop);
		currentAnim = name;
	}
}
