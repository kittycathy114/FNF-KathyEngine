package states.editors;

import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.FlxG;
import flixel.group.FlxGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.util.FlxColor;

import backend.ui.PsychUIInputText;
import backend.ui.PsychUIButton;
import backend.ui.PsychUICheckBox;
import backend.ui.PsychUISlider;
import states.editors.content.FileDialogHandler;
import spineflixel.SpineViewerTextureLoader;
import mobile.backend.StorageUtil;

import spine.SkeletonData;
import spine.Physics;
import spine.SkeletonJson;
import spine.SkeletonBinary;
import spine.atlas.TextureAtlas;
import spine.attachments.AtlasAttachmentLoader;
import spine.animation.AnimationStateData;
import spine.flixel.NoCullSkeletonSprite;
import spine.attachments.RegionAttachment;
import spine.attachments.MeshAttachment;
import spine.atlas.TextureAtlasRegion;
import flixel.graphics.FlxGraphic;

#if desktop
import lime.app.Application;
#end

#if cpp
import cpp.vm.Gc;
#end

/**
 * Spine Viewer — a toolbox editor that displays one or more Spine characters
 * loaded directly from disk, with free controls (pan / zoom) and buttons to
 * pick the `.atlas`, `.skel` and `.json` files.
 *
 * Multi-character mode (each character is independently controlled):
 *   - "Add" loads another character (it is appended and becomes the active one).
 *   - Click a character on the canvas to select it (the right panel then shows
 *     THAT character's animations / skins).
 *   - Drag a character to move it; drag empty space to pan all characters.
 *   - Mouse wheel (or [ ] / +/- / on-screen buttons) zooms the character under
 *     the cursor, or the active one if none is under the cursor.
 *   - Right panel: play an animation / cycle skin / toggle loop for the active
 *     character. "◀ Char" / "Char ▶" switch the active character; "Del Char"
 *     removes it.
 *
 * Note: the flixel camera always stays at zoom = 1. Pan/zoom is done by moving
 * and scaling each skeleton itself, because spine-haxe does not apply the
 * camera zoom to the mesh vertices.
 */
class SpineViewerState extends MusicBeatState
{
	// Layout constants
	static final TOP_BAR_H:Int = 40;
	static final PANEL_W:Int = 240;
	static final INPUT_W:Int = 175;
	// Y where the animation list begins inside the right panel
	static final LIST_TOP:Int = TOP_BAR_H + 122;

	// UI font: use the project's unifont so CJK glyphs and symbols render
	// correctly in the editor chrome (buttons, labels, lists, etc.).
	static final UI_FONT:String = 'unifont-18.0.01.otf';


	var uiCam:FlxCamera;

	var charGroup:FlxGroup;

	var characters:Array<SpineCharacter> = [];
	var activeChar:SpineCharacter;
	var dragTarget:SpineCharacter;

	var atlasInput:PsychUIInputText;
	var skeletonInput:PsychUIInputText; // accepts either .skel or .json

	var fileHandler:FileDialogHandler;
	var pendingPicker:String = null; // 'atlas' | 'skeleton'

	#if desktop
	var dropHandler:(String)->Void = null;
	#end

	var animTexts:Array<FlxText> = [];
	var animScroll:Float = 0;
	var animPanel:FlxSprite;
	var animScrollBar:FlxSprite;
	var animTitle:FlxText;
	var rSlider:PsychUISlider;
	var gSlider:PsychUISlider;
	var bSlider:PsychUISlider;
	var animListTop:Float = LIST_TOP;
	var topBar:FlxSprite;
	// Set true right after a native file dialog closes; we then wait for the
	// (stray) mouse press that "passes through" to be released before allowing a
	// new canvas drag, so it doesn't grab a character or overwrite the inputs.
	var awaitingMouseRelease:Bool = false;

	var skinBtn:PsychUIButton;
	var loopBtn:PsychUICheckBox;
	// Background-music toggle. When checked (default) the viewer loops
	// romantic-smile.ogg with a fade-in as it enters; unchecking stops it.
	var musicBtn:PsychUICheckBox;
	// Smooth-zoom responsiveness. Higher = snappier glide. Used via
	// 1 - exp(-rate * dt) so the feel is frame-rate independent.
	var zoomSmoothRate:Float = 14;
	var infoText:FlxText;
	var hintText:FlxText;
	// Bottom-left memory readout (shown in place of the hidden FPS counter).
	var memText:FlxText;
	var memPeak:Float = 0;
	// Shows the currently selected animation layer (Spine track index).
	var trackLabel:FlxText;

	var dragging:Bool = false;
	var dragStartMouseX:Float = 0;
	var dragStartMouseY:Float = 0;
	// Frames during which canvas click/drag is ignored, so a click that
	// "passes through" when a native file dialog closes doesn't grab/drag a
	// character or overwrite the path inputs via selectChar().
	var inputLockFrames:Int = 0;

	override function create()
	{
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Spine Viewer", null);
		#end

		// super.create() initializes the psych camera and RESETS FlxG.cameras,
		// which would destroy any camera added before it. So initialize first.
		super.create();

		// 进入本 state 时临时隐藏全局 FPS 计数器（不受 showFPS 设置影响），
		// 退出时还原；左下角改用自建内存信息文本显示内存占用。
		Main.forceHideFPS = true;
		if (Main.fpsVar != null)
			Main.fpsVar.visible = false;

		FlxG.camera.bgColor = 0xFF1a1a24;

		// Reset main camera (used for the Spine characters only)
		FlxG.camera.zoom = 1;
		FlxG.camera.scroll.set(0, 0);

		// Single shared camera. Layering is controlled by FlxGroup order, not by
		// camera stacking (a separately-added camera ended up rendered *behind*
		// the default camera, putting characters on top of the UI).
		uiCam = FlxG.camera;

		// Group that holds every Spine character. Added before the UI so all
		// characters always render behind the UI.
		charGroup = new FlxGroup();
		add(charGroup);

		FlxG.mouse.visible = true;

		buildUI();

		// Enter the viewer with looping background music and a fade-in.
		startMusic();


		fileHandler = new FileDialogHandler();

		addTouchPad('LEFT_FULL', 'A_B_E');
		addTouchPadCamera();

		#if desktop
		// Drag & drop a .atlas / .skel / .json file onto the window as a
		// reliable alternative to the native file dialog.
		dropHandler = function(path:String)
		{
			path = path.replace('\\', '/');
			var lower:String = path.toLowerCase();
					if (lower.endsWith('.atlas'))
						atlasInput.text = path;
					else if (lower.endsWith('.skel') || lower.endsWith('.json'))
						skeletonInput.text = path;
			else
			{
				showHint("拖入的文件类型不支持，请拖入 .atlas / .skel / .json 文件。");
				return;
			}
			showHint("已通过拖拽填入路径，点击 Add 加载。");
		};
		Application.current.window.onDropFile.add(dropHandler);
		#end
	}

	override function destroy()
	{
		#if desktop
		if (dropHandler != null && Application.current != null && Application.current.window != null)
			Application.current.window.onDropFile.remove(dropHandler);
		dropHandler = null;
		#end

		// Stop the looping background music when leaving the viewer so it does
		// not bleed into the next state.
		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();

		if (fileHandler != null)
		{
			fileHandler.destroy();
			fileHandler = null;
		}
		// 还原 FPS 计数器的可见性（恢复为 showFPS 设置）。
		Main.forceHideFPS = false;
		Main.updateFPSCounterVisibility();
		characters = [];
		activeChar = null;
		super.destroy();
	}

	function buildUI():Void
	{
		var gameFont:String = Paths.font(UI_FONT);


		// Top bar background. We hit-test against this sprite with
		// FlxG.mouse.overlaps(topBar, uiCam) (mirroring the right-panel check)
		// so clicks/drags on the top bar are never treated as canvas input.
		topBar = new FlxSprite(0, 0);
		topBar.makeGraphic(FlxG.width, TOP_BAR_H, FlxColor.BLACK);
		topBar.alpha = 0.4;
		topBar.cameras = [uiCam];
		add(topBar);

		var y:Float = 6.0;

		// --- Atlas row ---
		var atlasBtn:PsychUIButton = makeButton(10, y, 70, "Atlas", () -> openPicker("atlas"));
		atlasInput = makeInput(85, y, INPUT_W, "path/to/char.atlas");

		// --- Skeleton row (selective: .skel OR .json, user picks either) ---
		var skelJsonBtn:PsychUIButton = makeButton(265, y, 80, "Skel/JSON", () -> openPicker("skeleton"));
		skeletonInput = makeInput(350, y, INPUT_W, "path/to/char.skel or .json");

		// --- Action buttons ---
		var loadBtn:PsychUIButton = makeButton(545, y, 80, "Add", addCharacter);
		var loadPresetBtn:PsychUIButton = makeButton(640, y, 95, "Load", openPresetPicker);
		var savePresetBtn:PsychUIButton = makeButton(735, y, 95, "Save", savePreset);
		var delBtn:PsychUIButton = makeButton(845, y, 90, "Del Char", deleteActiveChar);
		var resetBtn:PsychUIButton = makeButton(940, y, 80, "Reset", resetCamera);
		var zoomOutBtn:PsychUIButton = makeButton(1025, y, 60, "Zoom-", () -> zoomActive(0.9));
		var zoomInBtn:PsychUIButton = makeButton(1090, y, 60, "Zoom+", () -> zoomActive(1.1));
		var backBtn:PsychUIButton = makeButton(FlxG.width - 80, y, 70, "Back", onBack);

		// --- Right panel: animation list ---
		var panelX:Float = FlxG.width - PANEL_W;
		// Y where the animation list begins. It sits below the RGB sliders,
		// the layer stepper and the active-character navigation row.
		animListTop = TOP_BAR_H + 308;

		// Semi-transparent panel background. The Spine characters live on the
		// main camera (which renders first), so they always stay behind this
		// uiCam panel.
		animPanel = new FlxSprite(panelX, TOP_BAR_H);
		animPanel.makeGraphic(PANEL_W, Math.floor(FlxG.height - TOP_BAR_H), FlxColor.BLACK);
		animPanel.alpha = 0.45;
		animPanel.cameras = [uiCam];
		add(animPanel);

		// Scrollbar for the animation list (hidden when the list fits).
		animScrollBar = new FlxSprite(panelX + PANEL_W - 4, animListTop);
		animScrollBar.makeGraphic(4, 20, FlxColor.GRAY);
		animScrollBar.alpha = 0.8;
		animScrollBar.cameras = [uiCam];
		animScrollBar.visible = false;
		add(animScrollBar);

		animTitle = new FlxText(panelX + 8, TOP_BAR_H + 8, PANEL_W - 16, "No Character", 16);
		animTitle.setFormat(gameFont, 16, FlxColor.YELLOW, LEFT, OUTLINE, FlxColor.BLACK);
		animTitle.cameras = [uiCam];
		add(animTitle);

		skinBtn = makeButton(panelX + 8, TOP_BAR_H + 34, PANEL_W - 16, "Skin: —", cycleSkin);
		loopBtn = new PsychUICheckBox(panelX + 8, TOP_BAR_H + 64, "Loop", 60);
		loopBtn.onClick = toggleLoop;
		loopBtn.checked = true;
		loopBtn.text.font = gameFont;
		loopBtn.text.size = 16;
		// FlxSpriteGroup bakes the group's world x/y into each child ONCE at
		// add() time (preAdd), so children live in WORLD coordinates. To
		// re-center the label after swapping the (taller) unifont we must
		// offset from the group's world position — not from 0, or the text
		// jumps to the top of the screen. The re-assignment below forces a
		// height re-measure so the centering uses the new glyph metrics.
		loopBtn.text.text = loopBtn.text.text;
		loopBtn.text.x = loopBtn.x + loopBtn.box.width + 6;
		loopBtn.text.y = loopBtn.y + (loopBtn.box.height - loopBtn.text.height) / 2;
		loopBtn.cameras = [uiCam];
		loopBtn.box.cameras = [uiCam];
		loopBtn.text.cameras = [uiCam];
		add(loopBtn);

		// Background music toggle, sits to the right of the Loop checkbox on
		// the same row. Checked by default: the viewer plays romantic-smile.ogg
		// on loop (with a fade-in) when it opens; unchecking fades it out.
		musicBtn = new PsychUICheckBox(panelX + 8 + 100, TOP_BAR_H + 64, "Music", 80);
		musicBtn.onClick = toggleMusic;
		musicBtn.checked = true;
		musicBtn.text.font = gameFont;
		musicBtn.text.size = 16;
		musicBtn.text.text = musicBtn.text.text;
		musicBtn.text.x = musicBtn.x + musicBtn.box.width + 6;
		musicBtn.text.y = musicBtn.y + (musicBtn.box.height - musicBtn.text.height) / 2;
		musicBtn.cameras = [uiCam];
		musicBtn.box.cameras = [uiCam];
		musicBtn.text.cameras = [uiCam];
		add(musicBtn);



		// Per-character RGB tint (0..1). Sliders live on the right panel, so
		// overlaps(topBar/animPanel) keeps them from grabbing the canvas.
		var rgbLabel:FlxText = new FlxText(panelX + 8, TOP_BAR_H + 94, PANEL_W - 16, "RGB Tint (active char)", 16);
		rgbLabel.setFormat(gameFont, 16, FlxColor.CYAN, LEFT, OUTLINE, FlxColor.BLACK);
		rgbLabel.cameras = [uiCam];
		add(rgbLabel);

		rSlider = new PsychUISlider(panelX + 8, TOP_BAR_H + 112, (_) -> applyActiveRGB(), 1, 0, 1, PANEL_W - 16, FlxColor.RED);
		gSlider = new PsychUISlider(panelX + 8, TOP_BAR_H + 162, (_) -> applyActiveRGB(), 1, 0, 1, PANEL_W - 16, FlxColor.LIME);
		bSlider = new PsychUISlider(panelX + 8, TOP_BAR_H + 212, (_) -> applyActiveRGB(), 1, 0, 1, PANEL_W - 16, FlxColor.BLUE);
		rSlider.label = "R";
		gSlider.label = "G";
		bSlider.label = "B";
		for (s in [rSlider, gSlider, bSlider])
		{
			// The PsychUISlider picks its own font internally; switch it to the
			// project unifont for consistency with the rest of the editor.
			s.labelText.font = gameFont;
			s.minText.font = gameFont;
			s.maxText.font = gameFont;
			s.valueText.font = gameFont;
			s.cameras = [uiCam];
			s.labelText.cameras = [uiCam];
			s.minText.cameras = [uiCam];
			s.maxText.cameras = [uiCam];
			s.valueText.cameras = [uiCam];
			add(s);
		}


		// Layered animation (Spine tracks / "layers"): one character can play
		// several animations at once by stacking them on separate tracks. The
		// stepper picks which layer the next clicked animation goes onto;
		// "Clr" clears that layer, "All" stops every layer.
		var trackRowY:Float = TOP_BAR_H + 244;
		makeButton(panelX + 8, trackRowY, 30, "-", decTrack);
		makeButton(panelX + 8 + 34, trackRowY, 30, "+", incTrack);
		trackLabel = new FlxText(panelX + 8 + 68, trackRowY + 5, 70, "Layer 0", 16);
		trackLabel.setFormat(gameFont, 16, FlxColor.LIME, LEFT, OUTLINE, FlxColor.BLACK);
		trackLabel.cameras = [uiCam];
		add(trackLabel);
		makeButton(panelX + 8 + 142, trackRowY, 44, "Clr", clearTrack);
		makeButton(panelX + 8 + 190, trackRowY, 42, "All", clearAllTracks);

		// Active character navigation
		var navY:Float = TOP_BAR_H + 276;
		var halfW:Int = Std.int((PANEL_W - 24) / 2);
		makeButton(panelX + 8, navY, halfW, "◀ Char", () -> cycleActiveChar(-1));
		makeButton(panelX + 8 + halfW + 8, navY, halfW, "Char ▶", () -> cycleActiveChar(1));

		animTexts = [];

		// --- Bottom info / hint ---
		infoText = new FlxText(10, FlxG.height - 58, FlxG.width - PANEL_W - 20, "", 16);
		infoText.setFormat(gameFont, 16, FlxColor.LIME, LEFT, OUTLINE, FlxColor.BLACK);
		infoText.cameras = [uiCam];
		add(infoText);

		// Bottom-left memory readout (the global FPS counter is hidden here,
		// so surface RAM usage + peak ourselves). Sits just above infoText.
		memText = new FlxText(10, FlxG.height - 76, FlxG.width - PANEL_W - 20, "", 16);
		memText.setFormat(gameFont, 16, FlxColor.CYAN, LEFT, OUTLINE, FlxColor.BLACK);
		memText.cameras = [uiCam];
		memText.y = FlxG.height - memText.height - 8;
		add(memText);

		hintText = new FlxText(10, TOP_BAR_H + 8, FlxG.width - PANEL_W - 20,
			"选择 Atlas 与骨架文件（Skel/JSON 二选一，也可直接填写路径），点击 Add 加载角色。\n"
			+ "可加载多个角色，点击角色选中它，右侧面板独立控制其动画/皮肤。\n"
			+ "拖拽角色移动；拖空白处平移全部；滚轮 / [ ] 缩放光标下角色；方向键 / WASD 移动当前角色，R 重置。\n"
			+ "Save 导出当前选中角色的预设（文件名默认用角色名）；Load 把预设里的单个角色追加进来。", 16);
		hintText.setFormat(gameFont, 16, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
		hintText.cameras = [uiCam];
		add(hintText);

		updateInfo();
	}

	function makeButton(x:Float, y:Float, w:Int, label:String, onClick:Void->Void):PsychUIButton
	{
		var btn:PsychUIButton = new PsychUIButton(x, y, label, onClick, w, 28);
		// PsychUIButton defaults to the engine UI font; swap it for the project
		// unifont so CJK glyphs render correctly. Use a dark-theme style to
		// match the rest of the editor chrome.
		btn.text.setFormat(Paths.font(UI_FONT), 16, FlxColor.WHITE, CENTER);
		btn.normalStyle = {bgColor: 0xFF3a3a4a, textColor: FlxColor.WHITE, bgAlpha: 0.8};
		btn.hoverStyle = {bgColor: 0xFF5a5a6e, textColor: FlxColor.WHITE, bgAlpha: 0.95};
		btn.clickStyle = {bgColor: 0xFF20202c, textColor: FlxColor.WHITE, bgAlpha: 1};
		btn.cameras = [uiCam];
		btn.bg.cameras = [uiCam];
		btn.text.cameras = [uiCam];
		add(btn);
		return btn;
	}



	function makeInput(x:Float, y:Float, w:Int, placeholder:String):PsychUIInputText
	{
		var input:PsychUIInputText = new PsychUIInputText(x, y, w, "", 16);
		// Use the project unifont for the editable text / placeholder.
		input.textObj.font = Paths.font(UI_FONT);
		input.cameras = [uiCam];
		input.bg.cameras = [uiCam];
		input.behindText.cameras = [uiCam];
		input.textObj.cameras = [uiCam];
		input.text = placeholder;
		add(input);
		return input;
	}


	// ------------------------------------------------------------------
	// File picking
	// ------------------------------------------------------------------
	function openPicker(type:String):Void
	{
		if (fileHandler == null)
			return;

		if (!fileHandler.completed)
		{
			// A previous dialog may have failed to open; let the user try again.
			fileHandler.completed = true;
		}

		pendingPicker = type;

		#if (desktop || (js && html5))
		try
		{
			// IMPORTANT: pass null title and an empty filter (=> show all files).
			// The engine's FileDialogHandler passes these straight into lime's
			// native dialog, and a non-null title / custom filter was causing a
			// hard crash here. We validate the chosen file's extension ourselves
			// in onPickerComplete() instead.
			fileHandler.open(null, null, [], onPickerComplete, null, onPickerError);
		}
		catch (e:Dynamic)
		{
			fileHandler.completed = true;
			showHint("无法打开文件选择窗口: " + e + "\n你也可以直接把文件拖拽到窗口，或手动填写路径。");
		}
		#else
		// On targets without a system file dialog (e.g. Android), the user
		// must type the absolute path directly into the input field.
		pendingPicker = null;
		showHint("当前平台不支持系统文件选择，请直接在输入框填写完整路径后点击 Add，或把文件放到可访问目录。");
		#end
	}

	function onPickerComplete():Void
	{
		// The native dialog is closing; block the click that will "pass through"
		// to the game window for a few frames so it doesn't grab a character.
		inputLockFrames = 12;
		if (fileHandler == null || fileHandler.path == null)
		{
			pendingPicker = null;
			return;
		}
		var path:String = fileHandler.path.replace('\\', '/');
		var lower:String = path.toLowerCase();
		switch (pendingPicker)
		{
			case "atlas":
				if (!lower.endsWith(".atlas"))
					showHint("请选择 .atlas 文件。");
				else
					atlasInput.text = path;
			case "skeleton":
				if (lower.endsWith(".skel"))
					skeletonInput.text = path;
				else if (lower.endsWith(".json"))
					skeletonInput.text = path;
				else
					showHint("请选择 .skel 或 .json 骨架文件。");
		}
		pendingPicker = null;
	}

	function onPickerError():Void
	{
		// The native dialog is closing (error or cancel): block the pass-through
		// click just like a successful pick.
		inputLockFrames = 12;
		pendingPicker = null;
	}

	// ------------------------------------------------------------------
	// Preset import / export
	//
	// A preset is a JSON snapshot of the whole scene: every character's
	// atlas/skeleton paths, on-screen position, scale, RGB tint, current
	// skin, loop flag and playing animation. "Save" exports it; "Load"
	// clears the current scene and restores exactly what was saved.
	// ------------------------------------------------------------------
	function openPresetPicker():Void
	{
		if (fileHandler == null)
			return;
		if (!fileHandler.completed)
			fileHandler.completed = true;

		#if (desktop || (js && html5))
		try
		{
			// Mirror openPicker: pass null title + empty filter (a custom
			// filter was crashing the native dialog), and validate the
			// extension ourselves in onPresetLoaded().
			fileHandler.open(null, null, [], onPresetLoaded, null, onPresetLoadError);
		}
		catch (e:Dynamic)
		{
			fileHandler.completed = true;
			showHint("无法打开文件选择窗口: " + e + "\n你也可以把预设文件放到可访问目录后手动加载。");
		}
		#else
		// On mobile there is no system file dialog; load the fixed preset file
		// from the external storage directory instead.
		#if sys
		var p:String = StorageUtil.getExternalStorageDirectory() + 'saves/spine_preset.json';
		if (!sys.FileSystem.exists(p))
		{
			showHint("未找到移动端预设文件:\n" + p);
			return;
		}
		loadPresetFromJson(sys.io.File.getContent(p));
		#else
		showHint("当前平台不支持预设导入，请使用桌面端。");
		#end
		#end
	}

	function onPresetLoaded():Void
	{
		// Block the click that "passes through" when the native dialog closes.
		inputLockFrames = 12;
		if (fileHandler == null || fileHandler.path == null)
			return;
		var path:String = fileHandler.path.replace('\\', '/');
		if (!path.toLowerCase().endsWith(".json"))
		{
			showHint("请选择 .json 预设文件。");
			return;
		}
		var str:String = fileHandler.data;
		#if sys
		if ((str == null || str.length == 0) && sys.FileSystem.exists(path))
			str = sys.io.File.getContent(path);
		#end
		loadPresetFromJson(str);
	}

	function onPresetLoadError():Void
	{
		inputLockFrames = 12;
	}

	function savePreset():Void
	{
		if (activeChar == null)
		{
			showHint("请先选中一个角色（点击画布中的角色，或用 ◀/▶ 切换）后再导出预设。");
			return;
		}
		var c = activeChar;
		// A preset is a single character (its paths, transform, color, skin and
		// playing animation). The default file name follows the character's
		// resource name so it is easy to tell presets apart.
		// Serialize every active layer (track index + animation name), sorted
		// by track so the order is stable across saves.
		var layerList:Array<SpineLayerPreset> = [];
		for (t in c.trackAnims.keys())
			layerList.push({track: t, anim: c.trackAnims.get(t), loop: trackLooping(c, t)});
		layerList.sort((a, b) -> a.track - b.track);
		var def:SpineCharPreset = {
			version: 1,
			name: c.name,
			atlasPath: c.atlasPath,
			skeletonPath: c.skeletonPath,
			x: c.sprite.x,
			y: c.sprite.y,
			// Store the scale as a magnitude and the flip as a separate flag.
			// In spine-haxe the flip is implemented by negating skeleton.scaleY,
			// so we must NOT save the raw (possibly negative) scaleY AND a flip
			// flag at the same time — that double-applies the flip on import and
			// produces a spurious vertical flip. The flag re-applies the negation
			// on load, so the magnitude is what we persist.
			scaleX: Math.abs(c.sprite.scaleX),
			scaleY: Math.abs(c.sprite.scaleY),
			flipX: c.sprite.flipX,
			flipY: c.sprite.flipY,
			r: c.r, g: c.g, b: c.b,
			curSkin: c.curSkin,
			looping: c.looping,
			currentAnim: c.currentAnim,
			// Persist every active layer (track index + animation name).
			layers: layerList
		};
		var json:String = haxe.Json.stringify(def, '\t');
		var defaultName:String = c.name + '.json';

		#if (desktop || (js && html5))
		try
		{
			if (fileHandler == null)
				return;
			if (!fileHandler.completed)
				fileHandler.completed = true;
			fileHandler.save(defaultName, json, onPresetSaved, onPresetSaveCancel, onPresetSaveError);
		}
		catch (e:Dynamic)
		{
			fileHandler.completed = true;
			showHint("无法打开保存窗口: " + e);
		}
		#else
		// Mobile: write to the external storage directory.
		#if sys
		try
		{
			StorageUtil.saveContent(defaultName, json, false);
			showHint("预设已导出到移动存储的 saves/" + defaultName + "。");
		}
		catch (e:Dynamic)
		{
			showHint("保存失败: " + Std.string(e));
		}
		#else
		showHint("当前平台不支持预设导出，请使用桌面端。");
		#end
		#end
	}

	function onPresetSaved():Void
	{
		inputLockFrames = 12;
		showHint("角色预设已导出：" + (activeChar != null ? activeChar.name : "") + "。");
	}

	function onPresetSaveCancel():Void
	{
		inputLockFrames = 12;
	}

	function onPresetSaveError():Void
	{
		inputLockFrames = 12;
	}

	// Parse a single character definition (a Dynamic from JSON) into a typed
	// SpineCharPreset, filling in defaults for any missing fields.
	function readCharDef(cdef:Dynamic):SpineCharPreset
	{
		return {
			version: Reflect.hasField(cdef, "version") ? Std.int(cdef.version) : 1,
			name: Reflect.hasField(cdef, "name") ? cdef.name : "",
			atlasPath: cdef.atlasPath,
			skeletonPath: cdef.skeletonPath,
			x: Reflect.hasField(cdef, "x") ? cdef.x : FlxG.width / 2,
			y: Reflect.hasField(cdef, "y") ? cdef.y : FlxG.height * 0.55,
			// Use the magnitude of scaleY/scaleX (a buggy older export may have
			// stored a negative scaleY); the flip is re-applied via flipX/flipY.
			scaleX: Reflect.hasField(cdef, "scaleX") ? Math.abs(cdef.scaleX) : 1,
			scaleY: Reflect.hasField(cdef, "scaleY") ? Math.abs(cdef.scaleY) : 1,
			flipX: Reflect.hasField(cdef, "flipX") ? cdef.flipX : false,
			flipY: Reflect.hasField(cdef, "flipY") ? cdef.flipY : false,
			r: Reflect.hasField(cdef, "r") ? cdef.r : 1,
			g: Reflect.hasField(cdef, "g") ? cdef.g : 1,
			b: Reflect.hasField(cdef, "b") ? cdef.b : 1,
			curSkin: Reflect.hasField(cdef, "curSkin") ? Std.int(cdef.curSkin) : 0,
			looping: Reflect.hasField(cdef, "looping") ? cdef.looping : true,
			currentAnim: Reflect.hasField(cdef, "currentAnim") ? cdef.currentAnim : "",
			layers: (Reflect.hasField(cdef, "layers") && cdef.layers != null)
				? [
					for (l in cast(cdef.layers, Array<Dynamic>))
						{
							track: Std.int(l.track),
							anim: Std.string(l.anim),
							loop: Reflect.hasField(l, "loop") ? l.loop : true
						}
				]
				: []
		};
	}

	// Parse a preset JSON string and ADD the character(s) it describes to the
	// current scene (it appends — it never clears existing characters). The
	// modern format is one SpineCharPreset object; the older whole-scene format
	// wrapped them in a `characters` array and is still accepted.
	function loadPresetFromJson(str:String):Void
	{
		if (str == null || str.length == 0)
		{
			showHint("预设内容为空，无法导入。");
			return;
		}
		var parsed:Dynamic;
		try
		{
			parsed = haxe.Json.parse(str);
		}
		catch (e:Dynamic)
		{
			showHint("预设文件解析失败: " + e);
			return;
		}
		if (parsed == null)
		{
			showHint("预设文件格式不正确。");
			return;
		}

		var defs:Array<SpineCharPreset> = [];
		if (Reflect.hasField(parsed, "characters"))
		{
			// Old whole-scene format: import each character it lists.
			var arr:Array<Dynamic> = parsed.characters;
			if (arr != null)
				for (cdef in arr)
					if (cdef != null)
						defs.push(readCharDef(cdef));
		}
		else if (Reflect.hasField(parsed, "atlasPath") && Reflect.hasField(parsed, "skeletonPath"))
		{
			// Single-character format (current).
			defs.push(readCharDef(parsed));
		}
		else
		{
			showHint("预设文件格式不正确（缺少角色信息）。");
			return;
		}

		if (defs.length == 0)
		{
			showHint("预设中没有任何可加载的角色。");
			return;
		}

		var loaded:Array<SpineCharacter> = [];
		for (def in defs)
		{
			if (def.atlasPath == null || def.skeletonPath == null)
				continue;
			var ch:SpineCharacter = buildCharacter(def.atlasPath, def.skeletonPath, def);
			if (ch != null)
				loaded.push(ch);
		}

		if (loaded.length == 0)
		{
			showHint("预设中的角色都加载失败，请检查文件路径是否正确。");
			updateInfo();
			return;
		}

		// Select (and play the animation of) the last character we just added,
		// so the user immediately sees what was imported.
		var last:SpineCharacter = loaded[loaded.length - 1];
		selectChar(last);
		if (last.currentAnim.length > 0)
			playAnimation(last.currentAnim);
		updateInfo();
		showHint("已导入预设，成功加载 " + loaded.length + " 个角色（已追加到当前场景）。");
	}

	// ------------------------------------------------------------------
	// Loading a Spine character (appends to the list)
	// ------------------------------------------------------------------
	function addCharacter():Void
	{
		var atlasPath:String = atlasInput.text.trim();
		var skeletonPath:String = skeletonInput.text.trim();

		if (atlasPath.length == 0 || atlasPath == "path/to/char.atlas")
		{
			showHint("请先选择或填写 Atlas 文件路径。");
			return;
		}
		if (skeletonPath.length == 0 || skeletonPath == "path/to/char.skel or .json")
		{
			showHint("请选择或填写 Skel (.skel) 或 JSON (.json) 骨架文件路径。");
			return;
		}

		// The same atlas+skeleton may be loaded more than once, so several
		// copies of one character can be shown at once. We therefore no longer
		// de-duplicate here: every "Add" appends a fresh, independent instance
		// (offset on screen so the copies don't fully overlap).

		var ch:SpineCharacter = buildCharacter(atlasPath, skeletonPath, null);
		if (ch == null)
			return;
		hintText.visible = false;
		selectChar(ch);
		if (ch.animList.length > 0)
			playAnimation(ch.animList[0]);
		updateInfo();
	}

	// Returns true if a character with the given display name already exists in
	// the list. Used to disambiguate duplicate loads of the same resource so
	// each copy reads uniquely in the title / preset list.
	function nameTaken(nm:String):Bool
	{
		for (c in characters)
			if (c.name == nm)
				return true;
		return false;
	}

	/**
	 * Loads a Spine character from disk and adds it to the scene. When `def` is
	 * provided (preset import) it also restores the saved transform, color, skin
	 * and animation. Returns the created SpineCharacter, or null on failure.
	 */
	function buildCharacter(atlasPath:String, skeletonPath:String, def:SpineCharPreset):SpineCharacter
	{
		var lower:String = skeletonPath.toLowerCase();
		var isBinary:Bool = lower.endsWith(".skel");

		try
		{
			#if sys
			if (!sys.FileSystem.exists(atlasPath))
			{
				showHint("Atlas 文件不存在: " + atlasPath);
				return null;
			}
			if (!sys.FileSystem.exists(skeletonPath))
			{
				showHint("骨架文件不存在: " + skeletonPath);
				return null;
			}
			#end

			var baseDir:String = dirname(atlasPath);
			var atlasContent:String = readText(atlasPath);
			var loader = new spineflixel.SpineViewerTextureLoader(baseDir);
			var atlas:TextureAtlas = new TextureAtlas(atlasContent, loader);
			var attachmentLoader:AtlasAttachmentLoader = new AtlasAttachmentLoader(atlas);

			var skeletonData:SkeletonData;
			if (isBinary)
			{
				var bytes:haxe.io.Bytes = readBytes(skeletonPath);
				var bin:SkeletonBinary = new SkeletonBinary(attachmentLoader);
				bin.scale = 1;
				skeletonData = bin.readSkeletonData(bytes);
			}
			else
			{
				var json:String = readText(skeletonPath);
				var sj:SkeletonJson = new SkeletonJson(attachmentLoader);
				sj.scale = 1;
				skeletonData = sj.readSkeletonData(json);
			}

			var stateData:AnimationStateData = new AnimationStateData(skeletonData);
			var sprite:NoCullSkeletonSprite = new NoCullSkeletonSprite(skeletonData, stateData);
			if (def != null)
			{
				sprite.x = def.x;
				sprite.y = def.y;
				sprite.scaleX = def.scaleX;
				sprite.scaleY = def.scaleY;
				// Restore the flip AFTER the scale, so its negation stays
				// consistent with what was on screen when the preset was saved.
				sprite.flipX = def.flipX;
				sprite.flipY = def.flipY;
			}
			else
			{
				// Place the new character offset from the center so several of
				// them don't fully overlap; the user can drag them apart.
				sprite.x = FlxG.width / 2 + characters.length * 180;
				sprite.y = FlxG.height * 0.55;
				sprite.scaleX = 1;
				sprite.scaleY = 1;
			}
			sprite.antialiasing = ClientPrefs.data.antialiasing;
			sprite.active = true;
			sprite.cameras = [FlxG.camera];
			charGroup.add(sprite);

			// Derive a display name from the skeleton file name (unless the
			// preset supplied one).
			var nm:String = skeletonPath;
			var slash:Int = nm.lastIndexOf("/");
			var back:Int = nm.lastIndexOf("\\");
			var d:Int = slash > back ? slash : back;
			if (d >= 0)
				nm = nm.substring(d + 1);
			var dot:Int = nm.lastIndexOf(".");
			if (dot > 0)
				nm = nm.substring(0, dot);
			if (def != null && def.name != null && def.name.length > 0)
				nm = def.name;
			// Disambiguate duplicate display names (e.g. loading the same
			// resource again) by appending " (2)", " (3)", ... so each copy
			// reads uniquely in the title / preset list. IMPORTANT: test the
			// *candidate* name `nm`, not the original `base` — `base` stays in
			// the list forever, so checking it would loop infinitely and freeze
			// the game on any name collision.
			var base:String = nm;
			var copyN:Int = 2;
			while (nameTaken(nm))
			{
				nm = base + " (" + copyN + ")";
				copyN++;
			}

			var ch:SpineCharacter = new SpineCharacter(sprite, nm, atlasPath, skeletonPath);
			for (anim in skeletonData.animations)
				ch.animList.push(anim.name);
			for (skin in skeletonData.skins)
				ch.skinNames.push(skin.name);
			ch.curSkin = 0;
			ch.looping = true;
			ch.currentAnim = '';

			// Restore the saved state from a preset, if any.
			if (def != null)
			{
				ch.r = def.r;
				ch.g = def.g;
				ch.b = def.b;
				var col = sprite.skeleton.color;
				col.r = def.r;
				col.g = def.g;
				col.b = def.b;
				if (def.curSkin >= 0 && def.curSkin < ch.skinNames.length)
				{
					ch.curSkin = def.curSkin;
					sprite.skeleton.skinName = ch.skinNames[ch.curSkin];
					sprite.skeleton.setSlotsToSetupPose();
				}
				ch.looping = def.looping;
				// Restore layered animations. Prefer the explicit layers array
				// (newer presets); fall back to the legacy single currentAnim.
				var restored:Bool = false;
				if (def.layers != null && def.layers.length > 0)
				{
					for (layer in def.layers)
					{
						var anim = sprite.skeleton.data.findAnimation(layer.anim);
						if (anim != null)
						{
							// Per-layer loop: use the saved value, defaulting to
							// the character's base flag for older presets.
							var lp:Bool = layer.loop != null ? layer.loop : ch.looping;
							ch.trackAnims.set(layer.track, layer.anim);
							ch.trackLoops.set(layer.track, lp);
							sprite.state.setAnimation(layer.track, anim, lp);
							if (layer.track == 0)
								ch.currentAnim = layer.anim;
							restored = true;
						}
					}
				}
				if (!restored && def.currentAnim != null && def.currentAnim.length > 0)
				{
					var anim = sprite.skeleton.data.findAnimation(def.currentAnim);
					if (anim != null)
					{
						ch.currentAnim = def.currentAnim;
						ch.trackAnims.set(0, def.currentAnim);
						ch.trackLoops.set(0, ch.looping);
						sprite.state.setAnimation(0, anim, ch.looping);
					}
				}
			}

		// Recompute the world transform once so the very first rendered
		// frame already matches the saved pose (avoids a one-frame vertical
		// flip that would otherwise only correct itself on the next zoom).
		sprite.skeleton.updateWorldTransform(Physics.update);

		// Seed the smooth-zoom targets with the actual transform so the first
		// update() lerp has nothing to animate (no surprise snap on load).
		ch.vMagX = Math.abs(sprite.scaleX);
		ch.vMagY = Math.abs(sprite.scaleY);
		ch.vX = sprite.x;
		ch.vY = sprite.y;

		characters.push(ch);
			return ch;
		}
		catch (e:Dynamic)
		{
			showHint("加载失败: " + Std.string(e));
			trace("SpineViewerState.buildCharacter error: " + Std.string(e));
			return null;
		}
	}

	function applyActiveRGB():Void
	{
		if (activeChar == null)
			return;
		var r:Float = rSlider.value;
		var g:Float = gSlider.value;
		var b:Float = bSlider.value;
		activeChar.r = r;
		activeChar.g = g;
		activeChar.b = b;
		var col = activeChar.sprite.skeleton.color;
		col.r = r;
		col.g = g;
		col.b = b;
	}

	function selectChar(c:SpineCharacter):Void
	{
		activeChar = c;
		atlasInput.text = c.atlasPath;
		skeletonInput.text = c.skeletonPath;
		// Reflect this character's stored RGB on the sliders, then apply it.
		if (rSlider != null) rSlider.value = c.r;
		if (gSlider != null) gSlider.value = c.g;
		if (bSlider != null) bSlider.value = c.b;
		applyActiveRGB();
		buildAnimList();
		if (skinBtn != null)
			skinBtn.label = c.skinNames.length > 0 ? "Skin: " + c.skinNames[c.curSkin] : "Skin: —";
		refreshAnimHighlights();
		updateTrackLabel();
		updateLoopCheckbox();
		updateInfo();
	}

	function cycleActiveChar(dir:Int):Void
	{
		if (characters.length == 0)
			return;
		var idx:Int = characters.indexOf(activeChar);
		if (idx < 0)
			idx = 0;
		idx = (idx + dir + characters.length) % characters.length;
		selectChar(characters[idx]);
	}

	function deleteActiveChar():Void
	{
		if (activeChar == null)
			return;
		var idx:Int = characters.indexOf(activeChar);
		charGroup.remove(activeChar.sprite);
		activeChar.sprite.destroy();
		characters.remove(activeChar);
		if (characters.length > 0)
			selectChar(characters[Std.int(Math.max(0, idx - 1))]);
		else
		{
			activeChar = null;
			buildAnimList();
			updateInfo();
		}
	}

	function buildAnimList():Void
	{
		// Remove and destroy the previous entries
		for (txt in animTexts)
		{
			remove(txt);
			txt.destroy();
		}
		animTexts = [];
		animScroll = 0;

		if (animTitle != null)
		{
			if (activeChar != null)
			{
				var idx:Int = characters.indexOf(activeChar);
				animTitle.text = '${activeChar.name}  (${idx + 1}/${characters.length})';
			}
			else
				animTitle.text = "No Character";
		}

		if (activeChar == null)
		{
			layoutAnimList();
			return;
		}

		var gameFont:String = Paths.font(UI_FONT);
		var panelX:Float = FlxG.width - PANEL_W + 8;
		for (i in 0...activeChar.animList.length)
		{
			var name:String = activeChar.animList[i];
			var txt:FlxText = new FlxText(panelX, animListTop + i * 22, PANEL_W - 16, name, 16);
			txt.setFormat(gameFont, 16, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
			txt.cameras = [uiCam];
			add(txt);
			animTexts.push(txt);
		}

		layoutAnimList();
	}

	// Position the animation entries inside the right panel and clip any that
	// fall outside it, so a long list scrolls instead of overflowing.
	function layoutAnimList():Void
	{
		var panelTop:Float = animListTop;
		var panelBottom:Float = FlxG.height - 10;
		var visibleHeight:Float = panelBottom - panelTop;
		var totalHeight:Float = animTexts.length * 22;
		var maxScroll:Float = Math.max(0, totalHeight - visibleHeight);
		animScroll = FlxMath.bound(animScroll, 0, maxScroll);

		for (i in 0...animTexts.length)
		{
			var txt:FlxText = animTexts[i];
			var y:Float = panelTop + i * 22 - animScroll;
			txt.y = y;
			txt.visible = (y + 22 > panelTop) && (y < panelBottom);
		}

		// Scrollbar reflecting the current scroll position
		if (animScrollBar != null)
		{
			var barH:Float = maxScroll > 0 ? Math.max(20, visibleHeight * (visibleHeight / totalHeight)) : 20;
			var barY:Float = panelTop + (maxScroll > 0 ? (animScroll / maxScroll) * (visibleHeight - barH) : 0);
			animScrollBar.scale.y = barH / 20;
			animScrollBar.setPosition(FlxG.width - PANEL_W + PANEL_W - 4, barY);
			animScrollBar.visible = (maxScroll > 0);
		}
	}

	// Scroll the animation list with the mouse wheel (clamped + relaid out).
	function scrollAnimList(wheel:Int):Void
	{
		animScroll += wheel * 22;
		layoutAnimList();
	}

	function playAnimation(name:String):Void
	{
		if (activeChar == null)
			return;
		var anim = activeChar.sprite.skeleton.data.findAnimation(name);
		if (anim == null)
			return;
		// Assign the animation to the currently selected layer (Spine track).
		// Higher tracks blend on top of lower ones, so a character can play
		// e.g. a walk cycle on layer 0 and a wave on layer 1 at the same time.
		var track:Int = activeChar.currentTrack;
		activeChar.trackAnims.set(track, name);
		if (track == 0)
			activeChar.currentAnim = name;
		// Loop is per-layer: use whatever the Loop checkbox shows for the
		// current layer (it mirrors this layer's stored flag), and remember it.
		var loop:Bool = loopBtn != null ? loopBtn.checked : trackLooping(activeChar, track);
		activeChar.trackLoops.set(track, loop);
		activeChar.sprite.state.setAnimation(track, anim, loop);
		refreshAnimHighlights();
		updateTrackLabel();
		updateInfo();
	}

	// The loop flag for a given layer, defaulting to the character's base
	// `looping` value when that layer has no explicit setting yet.
	function trackLooping(c:SpineCharacter, track:Int):Bool
	{
		if (c.trackLoops.exists(track))
			return c.trackLoops.get(track);
		return c.looping;
	}

	// Sync the Loop checkbox with the currently selected layer's loop flag.
	function updateLoopCheckbox():Void
	{
		if (loopBtn == null || activeChar == null)
			return;
		loopBtn.checked = trackLooping(activeChar, activeChar.currentTrack);
	}

	function cycleSkin():Void
	{
		if (activeChar == null || activeChar.skinNames.length == 0)
			return;
		activeChar.curSkin = (activeChar.curSkin + 1) % activeChar.skinNames.length;
		var name:String = activeChar.skinNames[activeChar.curSkin];
		activeChar.sprite.skeleton.skinName = name;
		activeChar.sprite.skeleton.setSlotsToSetupPose();
		skinBtn.label = "Skin: " + name;
	}

	function toggleLoop():Void
	{
		if (activeChar == null)
			return;
		// PsychUICheckBox already toggled `checked` before invoking onClick, so
		// just read back the new state instead of flipping it ourselves.
		// Loop is per-layer: only affect the currently selected layer.
		var track:Int = activeChar.currentTrack;
		activeChar.trackLoops.set(track, loopBtn.checked);
		// Keep the base value in sync with layer 0 so it acts as the default
		// for any layer that hasn't been touched yet.
		if (track == 0)
			activeChar.looping = loopBtn.checked;
		// Apply live to the animation currently on that layer, if any, without
		// restarting it.
		var entry = activeChar.sprite.state.getCurrent(track);
		if (entry != null)
			entry.loop = loopBtn.checked;
	}

	// --- Background music ------------------------------------------------

	// Start (or restart) the looping background track with a fade-in. Used both
	// on state entry and when the Music checkbox is (re)checked.
	function startMusic():Void
	{
		if (musicBtn == null || !musicBtn.checked)
			return;
		// Stop anything already on the music channel to avoid stacking.
		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();
		// romantic-smile.ogg lives at assets/shared/music/. Volume starts at 0
		// and ramps to full over ~2s for the requested fade-in.
		FlxG.sound.playMusic(Paths.music('romantic-smile'), 0, true);
		FlxG.sound.music.fadeIn(2, 0, 0.4);
	}

	// Fade the music out and stop it (Music checkbox unchecked).
	function stopMusic():Void
	{
		if (FlxG.sound.music != null)
		{
			var m:flixel.sound.FlxSound = FlxG.sound.music;
			m.fadeOut(0.5, 0, (_) -> m.stop());
		}
	}

	// Music checkbox toggle: play (with fade-in) or stop (with fade-out).
	function toggleMusic():Void
	{
		if (musicBtn == null)
			return;
		if (musicBtn.checked)
			startMusic();
		else
			stopMusic();
	}

	// --- Layered animation (Spine tracks) ---------------------------------

	// Pick a lower layer (track index). Layer 0 is the base pose; higher
	// layers overlay it. Never goes negative.
	function decTrack():Void
	{
		if (activeChar == null)
			return;
		if (activeChar.currentTrack > 0)
			activeChar.currentTrack--;
		updateTrackLabel();
		updateLoopCheckbox();
	}

	function incTrack():Void
	{
		if (activeChar == null)
			return;
		if (activeChar.currentTrack < 15)
			activeChar.currentTrack++;
		updateTrackLabel();
		updateLoopCheckbox();
	}

	// Stop and remove the currently selected layer.
	function clearTrack():Void
	{
		if (activeChar == null)
			return;
		activeChar.sprite.state.clearTrack(activeChar.currentTrack);
		activeChar.trackAnims.remove(activeChar.currentTrack);
		activeChar.trackLoops.remove(activeChar.currentTrack);
		if (activeChar.currentTrack == 0)
			activeChar.currentAnim = "";
		refreshAnimHighlights();
		updateTrackLabel();
		updateLoopCheckbox();
		updateInfo();
	}

	// Stop every layer on the active character.
	function clearAllTracks():Void
	{
		if (activeChar == null)
			return;
		activeChar.sprite.state.clearTracks();
		activeChar.trackAnims.clear();
		activeChar.trackLoops.clear();
		activeChar.currentAnim = "";
		refreshAnimHighlights();
		updateTrackLabel();
		updateLoopCheckbox();
		updateInfo();
	}

	// Reflect the active character's selected layer in the right-panel label.
	function updateTrackLabel():Void
	{
		if (trackLabel == null || activeChar == null)
			return;
		trackLabel.text = "Layer " + activeChar.currentTrack;
	}

	// Re-tint the animation list so every animation that is currently playing
	// on some layer is highlighted.
	function refreshAnimHighlights():Void
	{
		var active:Map<String, Bool> = new Map();
		if (activeChar != null)
		{
			for (a in activeChar.trackAnims)
				active.set(a, true);
		}
		for (txt in animTexts)
		{
			var on:Bool = active.exists(txt.text);
			txt.color = on ? FlxColor.YELLOW : FlxColor.WHITE;
			txt.borderColor = on ? FlxColor.RED : FlxColor.BLACK;
		}
	}

	// ------------------------------------------------------------------
	// Camera / transform controls (per character)
	// ------------------------------------------------------------------
	function resetCamera():Void
	{
		// The Spine character is panned/zoomed via its OWN transform (not the
		// camera), because spine-haxe does not apply camera zoom to the mesh
		// vertices. Keep the camera at identity and reset the active skeleton.
		FlxG.camera.zoom = 1;
		FlxG.camera.scroll.set(0, 0);
		if (activeChar != null)
		{
			// Reset the scale magnitude to 1, keeping the flip (the sign is
			// taken from the flipX/flipY booleans and re-applied every frame in
			// update()). This also fixes the old "Reset wipes the flip" quirk.
			activeChar.sprite.scaleX = activeChar.sprite.flipX ? -1 : 1;
			activeChar.sprite.scaleY = activeChar.sprite.flipY ? -1 : 1;
			activeChar.sprite.x = FlxG.width / 2;
			activeChar.sprite.y = FlxG.height * 0.55;
			// Retarget the smooth-zoom goals too, so the sprite doesn't glide
			// back to its pre-reset pose.
			activeChar.vMagX = 1;
			activeChar.vMagY = 1;
			activeChar.vX = activeChar.sprite.x;
			activeChar.vY = activeChar.sprite.y;
			// Reset per-character RGB tint to white, and sync the sliders.
			activeChar.r = activeChar.g = activeChar.b = 1;
			var col = activeChar.sprite.skeleton.color;
			col.r = col.g = col.b = 1;
			if (rSlider != null) rSlider.value = 1;
			if (gSlider != null) gSlider.value = 1;
			if (bSlider != null) bSlider.value = 1;
		}
		updateInfo();
	}

	// Zoom a specific skeleton around the screen point (sx, sy) so the world
	// point under the cursor stays under the cursor after zooming. (Camera
	// stays at zoom = 1; scaling is done on the skeleton.)
	function zoomChar(c:SpineCharacter, factor:Float, sx:Float, sy:Float):Void
	{
		if (c == null)
			return;
		var s = c.sprite;
		// Work in magnitudes only. The flip is kept as the SIGN of the
		// flipX/flipY booleans and applied separately in update() (see the
		// smooth-zoom loop), so the lerp never passes through scale = 0
		// (which would squash the character to a line / make it glitch).
		var magX0:Float = c.vMagX;
		var magY0:Float = c.vMagY;
		var magX1:Float = FlxMath.bound(magX0 * factor, 0.05, 20);
		var magY1:Float = FlxMath.bound(magY0 * factor, 0.05, 20);
		var f:Float = magY1 / magY0;

		// Anchor the zoom on the screen point (sx, sy) using the *target*
		// position, so successive wheel ticks / button clicks accumulate
		// correctly while the sprite glides toward the target instead of
		// snapping. update() lerps the sprite to (vX, vY, vMagX, vMagY).
		var ox:Float = s.offsetX;
		var oy:Float = s.offsetY;
		c.vX = sx - ox - f * (sx - c.vX - ox);
		c.vY = sy - oy - f * (sy - c.vY - oy);

		// Store the (positive) target magnitudes; the flip sign is supplied by
		// the flipX/flipY booleans when the sprite is actually scaled.
		c.vMagX = magX1;
		c.vMagY = magY1;
	}

	// Zoom the active character IN PLACE: anchor the zoom on the character's
	// own position instead of the screen center, so it scales around itself
	// rather than jumping to keep the screen center fixed. (The mouse wheel
	// zooms around the cursor — which feels stable because the point under the
	// cursor stays put — whereas anchoring at the screen center drags any
	// off-center character toward the middle on every click, looking like a
	// teleport.)
	function zoomActive(factor:Float):Void
	{
		if (activeChar == null)
			return;
		var s = activeChar.sprite;
		zoomChar(activeChar, factor, s.x + s.offsetX, s.y + s.offsetY);
	}

	// Topmost character whose *opaque* (alpha != 0) pixel is under the mouse.
	// The bounding box (FlxG.mouse.overlaps) includes transparent margins, so we
	// test the actual drawn triangles and sample the atlas alpha — clicking the
	// transparent edge no longer selects/drags the character.
	function charUnderMouse():SpineCharacter
	{
		var mx:Float = FlxG.mouse.x;
		var my:Float = FlxG.mouse.y;
		var i:Int = characters.length - 1;
		while (i >= 0)
		{
			if (pixelHitTest(characters[i], mx, my))
				return characters[i];
			i--;
		}
		return null;
	}

	// Pixel-perfect hit test for one character. Returns true only if (mx,my)
	// lands inside a visible triangle whose sampled atlas texel is opaque.
	function pixelHitTest(c:SpineCharacter, mx:Float, my:Float):Bool
	{
		var s = c.sprite;
		var verts:Array<Float> = [];
		var drawOrder:Array<spine.Slot> = s.skeleton.drawOrder;
		var i:Int = drawOrder.length - 1;
		while (i >= 0)
		{
			var slot:spine.Slot = drawOrder[i];
			i--;
			var att = slot.attachment;
			var worldX:Array<Float> = null;
			var uvs:Array<Float> = null;
			var tris:Array<Int> = null;
			var tex:Dynamic = null;
			if (Std.isOfType(att, RegionAttachment))
			{
				var region:RegionAttachment = cast att;
				verts.resize(8);
				region.computeWorldVertices(slot, verts, 0, 2);
				worldX = toScreen(s, verts, 4);
				uvs = region.uvs;
				tris = [0, 1, 2, 2, 3, 0];
				tex = cast(region.region, TextureAtlasRegion).page.texture;
			}
			else if (Std.isOfType(att, MeshAttachment))
			{
				var mesh:MeshAttachment = cast att;
				verts.resize(mesh.worldVerticesLength);
				mesh.computeWorldVertices(slot, 0, mesh.worldVerticesLength, verts, 0, 2);
				worldX = toScreen(s, verts, mesh.worldVerticesLength >> 1);
				uvs = mesh.uvs;
				tris = mesh.triangles;
				tex = cast(mesh.region, TextureAtlasRegion).page.texture;
			}
			else
				continue;

			if (pointInTrisScreen(mx, my, worldX, uvs, tris, tex))
				return true;
		}
		return false;
	}

	// Map skeleton-local vertices to screen coordinates, reusing the sprite's
	// own transform (handles scale / angle / offset / position like render()).
	function toScreen(s:NoCullSkeletonSprite, verts:Array<Float>, vcount:Int):Array<Float>
	{
		var out:Array<Float> = [];
		out.resize(vcount * 2);
		var k:Int = 0;
		while (k < vcount)
		{
			var p:Array<Float> = [verts[k * 2], verts[k * 2 + 1]];
			s.skeletonToHaxeWorldCoordinates(p);
			out[k * 2] = p[0];
			out[k * 2 + 1] = p[1];
			k++;
		}
		return out;
	}

	// Barycentric point-in-triangle on screen-space verts. If the point is
	// inside, sample the atlas page at the interpolated UV; return true only
	// when that texel is opaque (alpha >= threshold). tex null -> treat the
	// geometry itself as opaque (safe fallback so a char is never ungrabbable).
	function pointInTrisScreen(px:Float, py:Float, verts:Array<Float>, uvs:Array<Float>,
		tris:Array<Int>, tex:Dynamic):Bool
	{
		var bmp = (tex != null) ? cast(tex, FlxGraphic).bitmap : null;
		var W:Int = (bmp != null) ? bmp.width : 0;
		var Hh:Int = (bmp != null) ? bmp.height : 0;
		var t:Int = 0;
		while (t < tris.length)
		{
			var ia:Int = tris[t], ib:Int = tris[t + 1], ic:Int = tris[t + 2];
			t += 3;
			var ax:Float = verts[ia * 2], ay:Float = verts[ia * 2 + 1];
			var bx:Float = verts[ib * 2], by:Float = verts[ib * 2 + 1];
			var cx:Float = verts[ic * 2], cy:Float = verts[ic * 2 + 1];
			var v0x:Float = bx - ax, v0y:Float = by - ay;
			var v1x:Float = cx - ax, v1y:Float = cy - ay;
			var v2x:Float = px - ax, v2y:Float = py - ay;
			var denom:Float = v0x * v1y - v1x * v0y;
			if (denom == 0)
				continue;
			var w1:Float = (v2x * v1y - v1x * v2y) / denom;
			var w2:Float = (v0x * v2y - v2x * v0y) / denom;
			var w0:Float = 1 - w1 - w2;
			if (w0 >= 0 && w1 >= 0 && w2 >= 0)
			{
				if (bmp == null)
					return true;
				var u:Float = w0 * uvs[ia * 2] + w1 * uvs[ib * 2] + w2 * uvs[ic * 2];
				var v:Float = w0 * uvs[ia * 2 + 1] + w1 * uvs[ib * 2 + 1] + w2 * uvs[ic * 2 + 1];
				var tx:Int = Std.int(u * W);
				var ty:Int = Std.int(v * Hh);
				if (tx >= 0 && tx < W && ty >= 0 && ty < Hh)
				{
					var a:Int = (bmp.getPixel32(tx, ty) >> 24) & 0xFF;
					if (a >= 8)
						return true;
				}
			}
		}
		return false;
	}

	function isOverUI(px:Float, py:Float):Bool
	{
		// Mirror the right-panel wheel check: hit-test against the actual UI
		// sprites so the top bar and right panel are never treated as canvas
		// (no accidental character grab / input overwrite while using the UI).
		if (topBar != null && FlxG.mouse.overlaps(topBar, uiCam))
			return true;
		if (animPanel != null && FlxG.mouse.overlaps(animPanel, uiCam))
			return true;
		return false;
	}

	// The animation list only occupies the right panel BELOW the active-
	// character navigation row (the ◀ Char / Char ▶ buttons, which sit just
	// above animListTop). Clicks above that line — on the skin/loop/RGB area
	// or the nav buttons themselves — must never be treated as an animation
	// pick.
	function isOverAnimList(px:Float, py:Float):Bool
	{
		if (animPanel == null)
			return false;
		var px0:Float = animPanel.x;
		if (px < px0 || px > px0 + PANEL_W)
			return false;
		return (py >= animListTop && py <= FlxG.height);
	}

	function updateCamera(elapsed:Float):Void
	{
		// Keyboard pan (skip while typing in an input field) — moves the active char
		var typing:Bool = (PsychUIInputText.focusOn != null);
		var panSpeed:Float = 600 * elapsed; // screen pixels; camera stays at zoom 1
		if (!typing && activeChar != null)
		{
			var s = activeChar.sprite;
			if (controls.UI_LEFT || FlxG.keys.pressed.A) s.x -= panSpeed;
			if (controls.UI_RIGHT || FlxG.keys.pressed.D) s.x += panSpeed;
			if (controls.UI_UP || FlxG.keys.pressed.W) s.y -= panSpeed;
			if (controls.UI_DOWN || FlxG.keys.pressed.S) s.y += panSpeed;

			if (FlxG.keys.justPressed.MINUS || FlxG.keys.justPressed.LBRACKET)
				zoomActive(0.9);
			if (FlxG.keys.justPressed.PLUS || FlxG.keys.justPressed.RBRACKET)
				zoomActive(1.1);
			if (FlxG.keys.justPressed.R)
				resetCamera();
		}

		// TouchPad pan (mobile) — moves the active char
		if (touchPad != null && activeChar != null)
		{
			var s = activeChar.sprite;
			if (touchPad.buttonLeft.pressed) s.x -= panSpeed;
			if (touchPad.buttonRight.pressed) s.x += panSpeed;
			if (touchPad.buttonUp.pressed) s.y -= panSpeed;
			if (touchPad.buttonDown.pressed) s.y += panSpeed;
		if (touchPad.buttonA.justPressed) zoomActive(1.1);
		if (touchPad.buttonB.justPressed) zoomActive(0.9);
		}

		// Mouse wheel: scroll the animation list when over the right panel,
		// otherwise zoom the character under the cursor (or the active one).
		if (FlxG.mouse.wheel != 0)
		{
			if (FlxG.mouse.overlaps(animPanel, uiCam))
				scrollAnimList(FlxG.mouse.wheel);
			else
			{
				var c:SpineCharacter = charUnderMouse();
				if (c == null)
					c = activeChar;
				if (c != null)
					zoomChar(c, Math.pow(1.1, FlxG.mouse.wheel), FlxG.mouse.x, FlxG.mouse.y);
			}
		}

		// Drag to move: a specific character if one was grabbed, else pan all.
		var mx:Float = FlxG.mouse.x;
		var my:Float = FlxG.mouse.y;
		if (FlxG.mouse.pressed && !awaitingMouseRelease && !isOverUI(mx, my))
		{
			if (!dragging)
			{
				// Begin a drag only when an opaque pixel is grabbed. Clicking
				// the transparent gap starts nothing.
				var hit:SpineCharacter = charUnderMouse();
				if (hit != null)
				{
					dragging = true;
					dragStartMouseX = mx;
					dragStartMouseY = my;
					dragTarget = hit;
					hit.dragStartX = hit.sprite.x;
					hit.dragStartY = hit.sprite.y;
				}
			}
			else if (dragTarget != null)
			{
				var dx:Float = mx - dragStartMouseX;
				var dy:Float = my - dragStartMouseY;
				// Follow the mouse (character moves the same direction as the drag).
			dragTarget.sprite.x = dragTarget.dragStartX + dx;
			dragTarget.sprite.y = dragTarget.dragStartY + dy;
			// Keep the smooth-zoom target in lock-step with the drag so the
			// next update() lerp doesn't yank the character back.
			dragTarget.vX = dragTarget.sprite.x;
			dragTarget.vY = dragTarget.sprite.y;
		}
	}
	else
		dragging = false;
}

	override function update(elapsed:Float)
	{
		// A click that "passes through" when a native file dialog closes can
		// instantly grab/drag a character and overwrite the path inputs. Ignore
		// the stray press for a few frames, and only re-arm once the button is
		// actually released.
		if (inputLockFrames > 0)
		{
			inputLockFrames--;
			dragging = false;
			if (FlxG.mouse.pressed)
				awaitingMouseRelease = true;
		}
		else if (awaitingMouseRelease && !FlxG.mouse.pressed)
		{
			awaitingMouseRelease = false;
		}

		if (FlxG.mouse.justPressed && !awaitingMouseRelease)
		{
			var mx:Float = FlxG.mouse.x;
			var my:Float = FlxG.mouse.y;
			if (!isOverUI(mx, my))
			{
				// Only an opaque-pixel hit selects and starts a drag. Clicking
				// the transparent gap does nothing (no drag, no pan).
				var c:SpineCharacter = charUnderMouse();
				if (c != null)
				{
					selectChar(c);
					dragging = true;
					dragStartMouseX = mx;
					dragStartMouseY = my;
					dragTarget = c;
					c.dragStartX = c.sprite.x;
					c.dragStartY = c.sprite.y;
				}
			}
			else if (activeChar != null)
			{
				// Only pick an animation when the click lands inside the list
				// band (below the ◀ Char / Char ▶ buttons). This keeps clicks
				// on the skin/loop/RGB/nav controls from selecting an animation,
				// and we also skip entries that are scrolled off (visible=false)
				// so hidden items can no longer be triggered by a stray overlap.
				if (isOverAnimList(mx, my))
				{
					for (txt in animTexts)
					{
						if (txt.visible && FlxG.mouse.overlaps(txt, uiCam))
						{
							playAnimation(txt.text);
							break;
						}
					}
				}
			}
		}

		// Back / blur input
		if (controls.BACK)
		{
			if (PsychUIInputText.focusOn != null)
				PsychUIInputText.focusOn = null;
			else
			{
				onBack();
				return;
			}
		}
		if (touchPad != null && touchPad.buttonE.justPressed)
		{
			onBack();
			return;
		}

		updateCamera(elapsed);

		// Smooth zoom: glide every character's scale/position toward its target
		// (set by zoomChar) instead of snapping. The exponential factor is
		// frame-rate independent, so the glide feels the same at any FPS.
		var zoomK:Float = 1 - Math.exp(-zoomSmoothRate * elapsed);
		for (c in characters)
		{
			var s = c.sprite;
			// Lerp the magnitude (always positive) and re-apply the flip sign
			// from the booleans, so the scale can never cross zero and the
			// character never gets squashed.
			var magX:Float = FlxMath.lerp(Math.abs(s.scaleX), c.vMagX, zoomK);
			var magY:Float = FlxMath.lerp(Math.abs(s.scaleY), c.vMagY, zoomK);
			s.x = FlxMath.lerp(s.x, c.vX, zoomK);
			s.y = FlxMath.lerp(s.y, c.vY, zoomK);
			s.scaleX = magX * (s.flipX ? -1 : 1);
			s.scaleY = magY * (s.flipY ? -1 : 1);
		}

		updateMemText();
		updateInfo();
		super.update(elapsed);
	}

	function onBack():Void
	{
		MusicBeatState.switchState(new MasterEditorMenu());
	}

	// ------------------------------------------------------------------
	// Helpers
	// ------------------------------------------------------------------
	function updateInfo():Void
	{
		if (infoText == null)
			return;
		var n:Int = characters.length;
		var idx:Int = activeChar != null ? characters.indexOf(activeChar) : -1;
		var charInfo:String = activeChar != null ? 'Char: ${activeChar.name} (${idx + 1}/${n})  ' : 'Char: —  ';
		var zoomPct:Int = activeChar != null ? Math.round(Math.abs(activeChar.sprite.scaleX) * 100) : 100;
		var skin:String = (activeChar != null && activeChar.skinNames.length > 0) ? activeChar.skinNames[activeChar.curSkin] : "—";
		// Show every active layer as "L<track>:<anim>" (track 0 first), so the
		// stacked animations are visible at a glance.
		var animStr:String = "—";
		if (activeChar != null)
		{
			var keys:Array<Int> = [];
			for (k in activeChar.trackAnims.keys())
				keys.push(k);
			if (keys.length > 0)
			{
				keys.sort((a, b) -> a - b);
				var parts:Array<String> = [];
				for (k in keys)
					parts.push("L" + k + ":" + activeChar.trackAnims.get(k));
				animStr = parts.join("  ");
			}
		}
		infoText.text = charInfo + 'Zoom: ${zoomPct}%   Anim: ${animStr}   Skin: ${skin}';
	}

	function showHint(msg:String):Void
	{
		if (hintText != null)
		{
			hintText.text = msg;
			hintText.visible = true;
		}
	}

	// Refresh the bottom-left memory readout: current RAM usage plus the peak
	// seen since entering this state (mirrors the FPS counter's mempeak line).
	function updateMemText():Void
	{
		if (memText == null)
			return;
		var bytes:Float = getMemBytes();
		if (bytes > memPeak)
			memPeak = bytes;
		memText.text = 'RAM: ' + flixel.util.FlxStringUtil.formatBytes(bytes)
			+ '   Peak: ' + flixel.util.FlxStringUtil.formatBytes(memPeak);
	}

	// Current memory usage in bytes (cpp targets read the GC stats; other
	// targets fall back to 0 since the runtime doesn't expose it the same way).
	function getMemBytes():Float
	{
		#if cpp
		try
		{
			var v:Dynamic = Gc.memInfo64(Gc.MEM_INFO_USAGE);
			if (Std.is(v, Float) || Std.is(v, Int))
			{
				var m:Float = cast v;
				if (Math.isFinite(m) && m >= 0)
					return m;
			}
		}
		catch (e:Dynamic) {}
		try
		{
			var v:Dynamic = Gc.memInfo(Gc.MEM_INFO_USAGE);
			if (Std.is(v, Float) || Std.is(v, Int))
			{
				var m:Float = cast v;
				if (Math.isFinite(m) && m >= 0)
					return m;
			}
		}
		catch (e:Dynamic) {}
		#end
		return 0;
	}

	function dirname(p:String):String
	{
		var idx:Int = -1;
		var i:Int = p.lastIndexOf("/"); if (i > idx) idx = i;
		var j:Int = p.lastIndexOf("\\"); if (j > idx) idx = j;
		return idx > -1 ? p.substring(0, idx) : "";
	}

	function readText(path:String):String
	{
		#if sys
		if (sys.FileSystem.exists(path))
			return sys.io.File.getContent(path);
		#end
		return openfl.utils.Assets.getText(path);
	}

	function readBytes(path:String):haxe.io.Bytes
	{
		#if sys
		if (sys.FileSystem.exists(path))
			return sys.io.File.getBytes(path);
		#end
		var data = openfl.utils.Assets.getBytes(path);
		return haxe.io.Bytes.ofData(data);
	}
}

/**
 * A single character's saved state — this IS the preset file (one JSON object).
 * It is backwards-compatible with the older whole-scene format that wrapped this
 * in a `characters` array. `flipX`/`flipY` are captured alongside the scale so a
 * flipped character survives a round-trip (the skeleton's flip works by negating
 * `scaleY`, so saving only the scale would lose the flip).
 */
typedef SpineCharPreset =
{
	version:Int,
	name:String,
	atlasPath:String,
	skeletonPath:String,
	x:Float,
	y:Float,
	scaleX:Float,
	scaleY:Float,
	flipX:Bool,
	flipY:Bool,
	r:Float,
	g:Float,
	b:Float,
	curSkin:Int,
	looping:Bool,
	currentAnim:String,
	// Per-layer animations (track index -> animation name). Empty for
	// pre-layering presets; restored onto separate Spine tracks on load.
	layers:Array<SpineLayerPreset>
}

/**
 * One stacked animation layer: a Spine AnimationState track index and the
 * animation name playing on it.
 */
typedef SpineLayerPreset =
{
	track:Int,
	anim:String,
	// Whether this layer's animation loops (per-layer, controlled by the Loop
	// checkbox). Optional for older presets.
	?loop:Bool
}

/**
 * A single Spine character instance and all of its independently-controlled
 * state (animation list, current skin, loop flag, loaded file paths).
 */
private class SpineCharacter
{
	public var sprite:NoCullSkeletonSprite;
	public var name:String;
	public var atlasPath:String;
	public var skeletonPath:String;
	public var animList:Array<String>;
	public var currentAnim:String;
	public var skinNames:Array<String>;
	public var curSkin:Int;
	public var looping:Bool;
	// Layered playback: a Spine character can stack several animations by
	// putting each on a separate AnimationState track ("layer"). trackAnims
	// maps a track index -> the animation name currently playing on that
	// layer; currentTrack is the layer the next clicked animation goes onto
	// (selected via the right-panel stepper).
	public var trackAnims:Map<Int, String> = new Map();
	public var currentTrack:Int = 0;
	// Per-layer loop flag (track index -> looping). The Loop checkbox controls
	// only the currently selected layer, so each stacked animation can loop
	// (or not) independently. Missing entries fall back to `looping`.
	public var trackLoops:Map<Int, Bool> = new Map();
	// Per-character RGB tint (0..1) applied to skeleton.color.
	public var r:Float = 1;
	public var g:Float = 1;
	public var b:Float = 1;
	// Transient: character position captured when a drag starts.
	public var dragStartX:Float;
	public var dragStartY:Float;
	// Smooth-zoom targets. Each frame update() lerps the sprite's scale and
	// position toward these so zooming glides instead of snapping. The scale's
	// Smooth-zoom targets. Each frame update() lerps the sprite's scale
	// magnitude and position toward these so zooming glides instead of
	// snapping. The scale is stored as a POSITIVE magnitude; the flip is kept
	// as the SIGN of the flipX/flipY booleans (applied in update()), which
	// avoids the lerp ever crossing scale = 0 and squashing the character.
	public var vMagX:Float = 1;
	public var vMagY:Float = 1;
	public var vX:Float = 0;
	public var vY:Float = 0;

	public function new(sprite:NoCullSkeletonSprite, name:String, atlasPath:String, skeletonPath:String)
	{
		this.sprite = sprite;
		this.name = name;
		this.atlasPath = atlasPath;
		this.skeletonPath = skeletonPath;
		this.animList = [];
		this.currentAnim = '';
		this.skinNames = [];
		this.curSkin = 0;
		this.looping = true;
		this.trackAnims = new Map<Int, String>();
		this.currentTrack = 0;
		this.trackLoops = new Map<Int, Bool>();
		this.dragStartX = 0;
		this.dragStartY = 0;
	}
}
