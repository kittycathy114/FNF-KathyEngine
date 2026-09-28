package states.editors;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.math.FlxMath;

import backend.MusicBeatState;
import backend.ui.PsychUIBox;
import backend.ui.PsychUIButton;
import backend.ui.PsychUIInputText;
import backend.ui.PsychUINumericStepper;
import backend.ui.PsychUICheckBox;
import backend.ui.PsychUIDropDownMenu;
import backend.ui.PsychUIEventHandler;
import backend.ClientPrefs;

import states.StoryData;
import states.StoryPlayerState;
import states.StorySpineTools;
import states.editors.content.FileDialogHandler;
import states.editors.content.Prompt;

import mobile.backend.StorageUtil;

import spine.Physics;
import spine.flixel.NoCullSkeletonSprite;

import haxe.Json;
import flash.net.FileFilter;

#if sys
import sys.io.File;
#end

#if desktop
import lime.app.Application;
#end

/**
 * 剧情编辑器（Story Editor）
 *
 * 用来创作《蔚蓝档案》风格的 ADV 剧情：在 Characters 标签里读取并配置 Spine 角色，
 * 在 Lines 标签里编写台词。Save 会把角色定义写进 JSON，并把引用的 Spine 资源
 * （atlas / skeleton / 贴图）复制到 JSON 同级的 `<文件名>_assets/`，使剧情可随
 * 文件分发（"保存要附带"）。Test 直接把当前剧情交给 StoryPlayerState 预览。
 */
class StoryEditorState extends MusicBeatState implements PsychUIEventHandler.PsychUIEvent
{
	static final UI_FONT:String = 'unifont-18.0.01.otf';
	static final MARGIN:Int = 64;
	static final NARRATOR:String = '(旁白)';

	var previewBg:FlxSprite;
	var previewGroup:FlxGroup;
	var previewChars:Array<EditorChar> = [];

	var previewName:FlxText;
	var previewAff:FlxText;
	var previewText:FlxText;

	var UI_box:PsychUIBox;

	// Characters 标签
	var charSelectDropDown:PsychUIDropDownMenu;
	var idInput:PsychUIInputText;
	var nameInput:PsychUIInputText;
	var affInput:PsychUIInputText;
	var atlasInput:PsychUIInputText;
	var skelInput:PsychUIInputText;
	var xStepper:PsychUINumericStepper;
	var yStepper:PsychUINumericStepper;
	var scaleStepper:PsychUINumericStepper;
	var flipCheck:PsychUICheckBox;
	var skinInput:PsychUIInputText;
	var defaultAnimDropDown:PsychUIDropDownMenu;
	var loadCharBtn:PsychUIButton;
	var addCharBtn:PsychUIButton;
	var removeCharBtn:PsychUIButton;

	// Lines 标签
	var lineSelectDropDown:PsychUIDropDownMenu;
	var lineCharDropDown:PsychUIDropDownMenu;
	var lineExprDropDown:PsychUIDropDownMenu;
	var boxStateDropDown:PsychUIDropDownMenu;
	var speedStepper:PsychUINumericStepper;
	var soundInput:PsychUIInputText;
	var textInput:PsychUIInputText;
	var addLineBtn:PsychUIButton;
	var removeLineBtn:PsychUIButton;

	// 顶栏
	var saveBtn:PsychUIButton;
	var loadBtn:PsychUIButton;
	var testBtn:PsychUIButton;
	var backBtn:PsychUIButton;
	var hintText:FlxText;

	var fileHandler:FileDialogHandler;

	var story:StoryFile;
	var curChar:Int = 0;
	var curLine:Int = 0;
	var loadingFields:Bool = false;
	var unsavedProgress:Bool = false;
	var lastLoadedDir:String = '';

	#if desktop
	var dropHandler:(String)->Void = null;
	#end

	override function create()
	{
		persistentUpdate = persistentDraw = true;
		FlxG.camera.bgColor = 0xFF101018;
		FlxG.mouse.visible = true;

		super.create();

		previewBg = new FlxSprite(0, 0);
		previewBg.makeGraphic(FlxG.width, FlxG.height, 0xFF1a1a24);
		previewBg.scrollFactor.set();
		add(previewBg);

		previewGroup = new FlxGroup();
		add(previewGroup);

		var lineY:Int = Std.int(FlxG.height * 0.7);
		previewName = new FlxText(MARGIN, lineY - 44, 600, '', 24);
		previewName.setFormat(Paths.font(UI_FONT), 24, FlxColor.WHITE, LEFT);
		add(previewName);

		previewAff = new FlxText(MARGIN, lineY - 36, 400, '', 16);
		previewAff.setFormat(Paths.font(UI_FONT), 16, 0x6495ED, LEFT);
		add(previewAff);

		previewText = new FlxText(MARGIN, lineY + 14, FlxG.width - MARGIN * 2, '', 20);
		previewText.setFormat(Paths.font(UI_FONT), 20, FlxColor.WHITE, LEFT);
		previewText.wordWrap = true;
		add(previewText);

		buildUIBox();

		saveBtn = makeButton(10, 4, 80, "Save", saveStory);
		loadBtn = makeButton(100, 4, 80, "Load", loadStoryFromFile);
		testBtn = makeButton(190, 4, 80, "Test", testPlay);
		backBtn = makeButton(FlxG.width - 80, 4, 70, "Back", onBack);

		hintText = new FlxText(10, 40, FlxG.width - 300, '', 16);
		hintText.setFormat(Paths.font(UI_FONT), 16, FlxColor.WHITE, LEFT);
		add(hintText);
		showHint("编辑器：Characters 添加/配置 Spine 角色，Lines 编写台词。Save 保存（附带角色资源），Test 预览。");

		fileHandler = new FileDialogHandler();

		#if desktop
		dropHandler = function(path:String)
		{
			path = path.replace('\\', '/');
			if (path.toLowerCase().endsWith('.json'))
				loadStoryFromPath(path);
		};
		Application.current.window.onDropFile.add(dropHandler);
		#end

		if (story == null)
			story = defaultStory();
		rebuildPreviewChars();
		refreshCharList();
		refreshLineList();
		curChar = 0;
		curLine = 0;
		loadCharIntoFields();
		loadLineIntoFields();
		refreshPreview();

		#if mobile
		addTouchPad('NONE', 'A_B_X_Y');
		#end
	}

	override function destroy()
	{
		#if desktop
		if (dropHandler != null && Application.current != null && Application.current.window != null)
			Application.current.window.onDropFile.remove(dropHandler);
		dropHandler = null;
		#end
		if (fileHandler != null)
		{
			fileHandler.destroy();
			fileHandler = null;
		}
		super.destroy();
	}

	// ------------------------------------------------------------------
	// 顶栏按钮
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

	function makeBoxButton(x:Float, y:Float, w:Int, label:String, onClick:Void->Void, g:flixel.group.FlxSpriteGroup):PsychUIButton
	{
		var btn:PsychUIButton = new PsychUIButton(x, y, label, onClick, w, 22);
		g.add(btn);
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

	// ------------------------------------------------------------------
	// UI 盒子（标签）
	// ------------------------------------------------------------------
	function buildUIBox():Void
	{
		UI_box = new PsychUIBox(FlxG.width - 275, 44, 265, FlxG.height - 120, ['Characters', 'Lines']);
		UI_box.scrollFactor.set();
		addCharsUI();
		addLinesUI();
		add(UI_box);
	}

	function mkLabel(x:Float, y:Float, t:String):FlxText
	{
		var l:FlxText = new FlxText(x, y, 245, t, 8);
		l.setFormat(Paths.font(UI_FONT), 14, FlxColor.WHITE, LEFT);
		return l;
	}

	function addCharsUI():Void
	{
		var g = UI_box.getTab('Characters').menu;
		var x0:Int = 10;

		g.add(mkLabel(x0, 8, 'Character:'));
		charSelectDropDown = new PsychUIDropDownMenu(x0, 26, [''], function(i, s) {}, 200);
		g.add(charSelectDropDown);

		g.add(mkLabel(x0, 56, 'ID:'));
		idInput = new PsychUIInputText(x0, 74, 200, '', 8); g.add(idInput);
		g.add(mkLabel(x0, 104, 'Name:'));
		nameInput = new PsychUIInputText(x0, 122, 200, '', 8); g.add(nameInput);
		g.add(mkLabel(x0, 152, 'Affiliation (所属):'));
		affInput = new PsychUIInputText(x0, 170, 200, '', 8); g.add(affInput);

		g.add(mkLabel(x0, 200, 'Atlas path:'));
		atlasInput = new PsychUIInputText(x0, 218, 150, '', 8); g.add(atlasInput);
		makeBoxButton(x0 + 155, 218, 40, '...', browseAtlas, g);

		g.add(mkLabel(x0, 248, 'Skeleton path:'));
		skelInput = new PsychUIInputText(x0, 266, 150, '', 8); g.add(skelInput);
		makeBoxButton(x0 + 155, 266, 40, '...', browseSkel, g);

		g.add(mkLabel(x0, 296, 'X / Y (0..1):'));
		xStepper = new PsychUINumericStepper(x0, 314, 0.05, 0.5, 0, 1, 2); g.add(xStepper);
		yStepper = new PsychUINumericStepper(x0 + 90, 314, 0.05, 0.85, 0, 1, 2); g.add(yStepper);

		g.add(mkLabel(x0, 344, 'Scale / Flip:'));
		scaleStepper = new PsychUINumericStepper(x0, 362, 0.1, 1.0, 0.1, 3, 2); g.add(scaleStepper);
		flipCheck = new PsychUICheckBox(x0 + 90, 362, 'Flip X', 100); g.add(flipCheck);

		g.add(mkLabel(x0, 392, 'Skin:'));
		skinInput = new PsychUIInputText(x0, 410, 200, '', 8); g.add(skinInput);

		g.add(mkLabel(x0, 440, 'Default Anim:'));
		defaultAnimDropDown = new PsychUIDropDownMenu(x0, 458, [''], function(i, s) {}, 200); g.add(defaultAnimDropDown);

		loadCharBtn = makeBoxButton(x0, 492, 95, 'Load Spine', loadCurrentCharSpine, g);
		addCharBtn = makeBoxButton(x0 + 100, 492, 70, 'Add', addChar, g);
		removeCharBtn = makeBoxButton(x0, 524, 95, 'Remove', removeChar, g);
		makeBoxButton(x0 + 100, 524, 150, 'Import Spine Preset', importSpinePreset, g);
	}

	function addLinesUI():Void
	{
		var g = UI_box.getTab('Lines').menu;
		var x0:Int = 10;

		g.add(mkLabel(x0, 8, 'Line:'));
		lineSelectDropDown = new PsychUIDropDownMenu(x0, 26, [''], function(i, s) {}, 200); g.add(lineSelectDropDown);

		g.add(mkLabel(x0, 56, 'Character:'));
		lineCharDropDown = new PsychUIDropDownMenu(x0, 74, [NARRATOR], function(i, s) {}, 200); g.add(lineCharDropDown);

		g.add(mkLabel(x0, 104, 'Expression:'));
		lineExprDropDown = new PsychUIDropDownMenu(x0, 122, [''], function(i, s) {}, 200); g.add(lineExprDropDown);

		g.add(mkLabel(x0, 152, 'Box State:'));
		boxStateDropDown = new PsychUIDropDownMenu(x0, 170, ['normal', 'angry'], function(i, s) {}, 200); g.add(boxStateDropDown);

		g.add(mkLabel(x0, 200, 'Speed:'));
		speedStepper = new PsychUINumericStepper(x0, 218, 0.005, 0.05, 0, 1, 3); g.add(speedStepper);

		g.add(mkLabel(x0, 248, 'Sound:'));
		soundInput = new PsychUIInputText(x0, 266, 200, '', 8); g.add(soundInput);

		g.add(mkLabel(x0, 296, 'Text:'));
		textInput = new PsychUIInputText(x0, 314, 240, '', 8); g.add(textInput);

		addLineBtn = makeBoxButton(x0, 360, 95, 'Add', addLine, g);
		removeLineBtn = makeBoxButton(x0 + 100, 360, 95, 'Remove', removeLine, g);
	}

	// ------------------------------------------------------------------
	// 事件联动
	// ------------------------------------------------------------------
	public function UIEvent(id:String, sender:Dynamic):Void
	{
		if (loadingFields)
			return;

		if (id == PsychUIInputText.CHANGE_EVENT && (sender is PsychUIInputText))
		{
			unsavedProgress = true;
			if (sender == idInput)
			{
				curDef().id = idInput.text;
				refreshCharList();
			}
			else if (sender == nameInput)
			{
				curDef().name = nameInput.text;
				refreshPreview();
			}
			else if (sender == affInput)
			{
				curDef().affiliation = affInput.text;
				refreshPreview();
			}
			else if (sender == atlasInput)
			{
				curDef().atlasPath = atlasInput.text;
			}
			else if (sender == skelInput)
			{
				curDef().skeletonPath = skelInput.text;
			}
			else if (sender == skinInput)
			{
				curDef().skin = skinInput.text;
				applySkin(curChar);
			}
			else if (sender == speedStepper)
			{
				curLineDef().speed = speedStepper.value;
			}
			else if (sender == soundInput)
			{
				curLineDef().sound = soundInput.text;
			}
			else if (sender == textInput)
			{
				curLineDef().text = textInput.text;
				refreshPreview();
			}
		}
		else if (id == PsychUIDropDownMenu.CLICK_EVENT && (sender is PsychUIDropDownMenu))
		{
			unsavedProgress = true;
			if (sender == charSelectDropDown)
			{
				curChar = charSelectDropDown.selectedIndex;
				loadCharIntoFields();
				refreshPreview();
			}
			else if (sender == defaultAnimDropDown)
			{
				curDef().defaultAnim = defaultAnimDropDown.selectedLabel;
				var pc = previewChars[curChar];
				if (pc != null && pc.sprite != null)
					pc.setAnim(defaultAnimDropDown.selectedLabel, true);
			}
			else if (sender == lineSelectDropDown)
			{
				curLine = lineSelectDropDown.selectedIndex;
				loadLineIntoFields();
				refreshPreview();
			}
			else if (sender == lineCharDropDown)
			{
				var lbl:String = lineCharDropDown.selectedLabel;
				curLineDef().character = (lbl == NARRATOR) ? null : lbl;
				refreshExprDropdown();
				refreshPreview();
			}
			else if (sender == lineExprDropDown)
			{
				curLineDef().expression = lineExprDropDown.selectedLabel;
				refreshPreview();
			}
			else if (sender == boxStateDropDown)
			{
				curLineDef().boxState = boxStateDropDown.selectedLabel;
			}
		}
		else if (id == PsychUICheckBox.CLICK_EVENT && sender == flipCheck)
		{
			unsavedProgress = true;
			curDef().flipX = flipCheck.checked;
			applyCharTransform(previewChars[curChar]);
		}
	}

	function curDef():StoryCharDef
	{
		if (curChar < 0) curChar = 0;
		if (curChar >= story.characters.length) curChar = story.characters.length - 1;
		return story.characters[curChar];
	}

	function curLineDef():StoryLine
	{
		if (curLine < 0) curLine = 0;
		if (curLine >= story.lines.length) curLine = story.lines.length - 1;
		return story.lines[curLine];
	}

	// ------------------------------------------------------------------
	// 字段 <-> 控件
	// ------------------------------------------------------------------
	function loadCharIntoFields():Void
	{
		loadingFields = true;
		if (curChar < story.characters.length)
		{
			var d:StoryCharDef = story.characters[curChar];
			idInput.text = d.id;
			nameInput.text = (d.name != null) ? d.name : '';
			affInput.text = (d.affiliation != null) ? d.affiliation : '';
			atlasInput.text = (d.atlasPath != null) ? d.atlasPath : '';
			skelInput.text = (d.skeletonPath != null) ? d.skeletonPath : '';
			xStepper.value = (d.x != null) ? d.x : 0.5;
			yStepper.value = (d.y != null) ? d.y : 0.85;
			scaleStepper.value = (d.scale != null) ? d.scale : 1.0;
			flipCheck.checked = (d.flipX == true);
			skinInput.text = (d.skin != null) ? d.skin : '';
			var pc:EditorChar = findPreviewChar(d.id);
			var anims:Array<String> = (pc != null) ? pc.anims : [];
			defaultAnimDropDown.list = anims.length > 0 ? anims : [''];
			defaultAnimDropDown.selectedLabel = (d.defaultAnim != null) ? d.defaultAnim : (anims.length > 0 ? anims[0] : null);
		}
		loadingFields = false;
	}

	function loadLineIntoFields():Void
	{
		loadingFields = true;
		if (curLine < story.lines.length)
		{
			var l:StoryLine = story.lines[curLine];
			var cl:String = (l.character != null) ? l.character : null;
			lineCharDropDown.selectedLabel = (cl == null) ? NARRATOR : cl;
			var anims:Array<String> = (cl != null) ? getCharAnims(cl) : [];
			lineExprDropDown.list = anims.length > 0 ? anims : [''];
			lineExprDropDown.selectedLabel = (l.expression != null) ? l.expression : null;
			boxStateDropDown.selectedLabel = (l.boxState != null) ? l.boxState : 'normal';
			speedStepper.value = (l.speed != null && !Math.isNaN(l.speed)) ? l.speed : 0.05;
			soundInput.text = (l.sound != null) ? l.sound : '';
			textInput.text = (l.text != null) ? l.text : '';
		}
		loadingFields = false;
	}

	function refreshCharList():Void
	{
		loadingFields = true;
		var labels:Array<String> = [for (c in story.characters) c.id];
		charSelectDropDown.list = labels.length > 0 ? labels : [''];
		if (curChar >= story.characters.length) curChar = story.characters.length - 1;
		if (curChar < 0) curChar = 0;
		charSelectDropDown.selectedIndex = curChar;

		lineCharDropDown.list = [NARRATOR].concat(labels);
		var cl:String = curLineDef().character;
		lineCharDropDown.selectedLabel = (cl == null) ? NARRATOR : cl;
		loadingFields = false;
	}

	function refreshLineList():Void
	{
		loadingFields = true;
		var labels:Array<String> = [for (i in 0...story.lines.length) 'Line ' + (i + 1)];
		lineSelectDropDown.list = labels.length > 0 ? labels : [''];
		if (curLine >= story.lines.length) curLine = story.lines.length - 1;
		if (curLine < 0) curLine = 0;
		lineSelectDropDown.selectedIndex = curLine;
		loadingFields = false;
	}

	function refreshExprDropdown():Void
	{
		loadingFields = true;
		var cl:String = curLineDef().character;
		var anims:Array<String> = (cl != null) ? getCharAnims(cl) : [];
		lineExprDropDown.list = anims.length > 0 ? anims : [''];
		lineExprDropDown.selectedLabel = curLineDef().expression;
		loadingFields = false;
	}

	// ------------------------------------------------------------------
	// 增删角色 / 台词
	// ------------------------------------------------------------------
	function addChar():Void
	{
		var id:String = 'char' + (story.characters.length + 1);
		story.characters.push({
			id: id, name: id, affiliation: '', atlasPath: '', skeletonPath: '',
			x: 0.5, y: 0.85, scale: 1.0, flipX: false, skin: '', defaultAnim: ''
		});
		curChar = story.characters.length - 1;
		rebuildPreviewChars();
		refreshCharList();
		loadCharIntoFields();
		unsavedProgress = true;
		showHint("已添加角色: " + id);
	}

	function removeChar():Void
	{
		if (story.characters.length == 0)
			return;
		var id:String = story.characters[curChar].id;
		story.characters.splice(curChar, 1);
		for (l in story.lines)
			if (l.character == id)
				l.character = null;
		if (curChar >= story.characters.length) curChar = story.characters.length - 1;
		if (curChar < 0) curChar = 0;
		rebuildPreviewChars();
		refreshCharList();
		refreshLineList();
		loadCharIntoFields();
		refreshPreview();
		unsavedProgress = true;
		showHint("已删除角色: " + id);
	}

	function addLine():Void
	{
		story.lines.insert(curLine + 1, copyDefaultLine());
		curLine++;
		refreshLineList();
		loadLineIntoFields();
		refreshPreview();
		unsavedProgress = true;
	}

	function removeLine():Void
	{
		story.lines.remove(story.lines[curLine]);
		if (story.lines.length == 0)
			story.lines = [copyDefaultLine()];
		if (curLine >= story.lines.length) curLine = story.lines.length - 1;
		if (curLine < 0) curLine = 0;
		refreshLineList();
		loadLineIntoFields();
		refreshPreview();
		unsavedProgress = true;
	}

	function copyDefaultLine():StoryLine
	{
		return {character: null, name: null, affiliation: null, expression: null, text: '新台词', boxState: 'normal', speed: 0.05, sound: ''};
	}

	// ------------------------------------------------------------------
	// 读取 / 加载 Spine 角色
	// ------------------------------------------------------------------
	function browseAtlas():Void
	{
		if (fileHandler == null || !fileHandler.completed)
			fileHandler.completed = true;
		fileHandler.open(null, null, [new FileFilter('Atlas', 'atlas')], function()
		{
			atlasInput.text = fileHandler.path;
			if (skelInput.text != null && skelInput.text != '')
				loadCurrentCharSpine();
		}, null, null);
	}

	function browseSkel():Void
	{
		if (fileHandler == null || !fileHandler.completed)
			fileHandler.completed = true;
		fileHandler.open(null, null, [new FileFilter('Skeleton', 'skel,json')], function()
		{
			skelInput.text = fileHandler.path;
			if (atlasInput.text != null && atlasInput.text != '')
				loadCurrentCharSpine();
		}, null, null);
	}

	function loadCurrentCharSpine():Void
	{
		if (curChar < 0 || curChar >= story.characters.length)
			return;
		var def:StoryCharDef = story.characters[curChar];
		if (def.atlasPath == null || def.atlasPath == '' || def.skeletonPath == null || def.skeletonPath == '')
		{
			showHint("请先设置 atlas / skeleton 路径（或用 ... 选择）。");
			return;
		}
		try
		{
			var loaded = StorySpineTools.loadSpine(def.atlasPath, def.skeletonPath, def.skin);
			var old:EditorChar = previewChars[curChar];
			if (old != null && old.sprite != null)
			{
				previewGroup.remove(old.sprite);
				old.sprite.destroy();
			}
			var pc:EditorChar = new EditorChar();
			pc.def = def;
			pc.sprite = loaded.sprite;
			pc.anims = loaded.anims;
			pc.defaultAnim = (def.defaultAnim != null) ? def.defaultAnim : (loaded.anims.length > 0 ? loaded.anims[0] : '');
			if (def.defaultAnim == null || def.defaultAnim == '')
				def.defaultAnim = pc.defaultAnim;
			previewChars[curChar] = pc;
			applyCharTransform(pc);
			previewGroup.add(loaded.sprite);

			loadingFields = true;
			defaultAnimDropDown.list = loaded.anims.length > 0 ? loaded.anims : [''];
			defaultAnimDropDown.selectedLabel = pc.defaultAnim;
			loadingFields = false;

			refreshExprDropdown();
			refreshPreview();
			showHint("已加载角色: " + def.id + "（" + loaded.anims.length + " 个动画）");
		}
		catch (e:Dynamic)
		{
			showHint("角色加载失败 (" + def.id + "): " + Std.string(e));
		}
	}

	// 从 Spine Viewer 导出的角色预设导入。Spine Viewer 的预设是像素坐标、
	// scaleX/scaleY、flipX/Y，这里转换成剧情角色定义（归一化坐标、单缩放、
	// 单 flip）。皮肤在预设里只存索引，导入后留空，可在 Load Spine 后手选。
	function importSpinePreset():Void
	{
		if (fileHandler == null || !fileHandler.completed)
			fileHandler.completed = true;
		fileHandler.open(null, null, [new FileFilter('Spine Preset', 'json')], function()
		{
			var path:String = fileHandler.path.replace('\\', '/');
			if (path == null || !path.toLowerCase().endsWith('.json'))
			{
				showHint("请选择 .json 预设文件。");
				return;
			}
			var str:String = fileHandler.data;
			#if sys
			if ((str == null || str.length == 0) && sys.FileSystem.exists(path))
				str = sys.io.File.getContent(path);
			#end
			importPresetFromJson(str);
		}, null, null);
	}

	function importPresetFromJson(str:String):Void
	{
		if (str == null || str.length == 0)
		{
			showHint("预设内容为空。");
			return;
		}
		var parsed:Dynamic;
		try
		{
			parsed = haxe.Json.parse(str);
		}
		catch (e:Dynamic)
		{
			showHint("预设解析失败: " + e);
			return;
		}
		if (parsed == null)
		{
			showHint("预设格式不正确。");
			return;
		}

		var defs:Array<Dynamic> = [];
		if (Reflect.hasField(parsed, "characters") && parsed.characters != null)
		{
			for (c in cast(parsed.characters, Array<Dynamic>))
				if (c != null)
					defs.push(c);
		}
		else if (Reflect.hasField(parsed, "atlasPath") && Reflect.hasField(parsed, "skeletonPath"))
		{
			defs.push(parsed);
		}
		else
		{
			showHint("预设格式不正确（缺少角色信息）。");
			return;
		}

		if (defs.length == 0)
		{
			showHint("预设中没有任何可加载的角色。");
			return;
		}

		var startIdx:Int = story.characters.length;
		for (c in defs)
		{
			var atlasPath:String = Reflect.hasField(c, "atlasPath") ? Std.string(c.atlasPath) : '';
			var skeletonPath:String = Reflect.hasField(c, "skeletonPath") ? Std.string(c.skeletonPath) : '';
			if (atlasPath == '' || skeletonPath == '')
				continue;
			var name:String = Reflect.hasField(c, "name") ? Std.string(c.name) : '';
			var px:Float = Reflect.hasField(c, "x") ? c.x : FlxG.width / 2;
			var py:Float = Reflect.hasField(c, "y") ? c.y : FlxG.height * 0.55;
			var sx:Float = Reflect.hasField(c, "scaleX") ? Math.abs(c.scaleX) : 1.0;
			var sy:Float = Reflect.hasField(c, "scaleY") ? Math.abs(c.scaleY) : 1.0;
			var scaleV:Float = (sx + sy) / 2;
			var flipX:Bool = Reflect.hasField(c, "flipX") ? c.flipX : false;
			var currentAnim:String = Reflect.hasField(c, "currentAnim") ? Std.string(c.currentAnim) : '';
			var id:String = genUniqueCharId((name != null && name != '') ? name : ('preset' + (story.characters.length + 1)));
			story.characters.push({
				id: id,
				name: (name != null) ? name : id,
				affiliation: '',
				atlasPath: atlasPath,
				skeletonPath: skeletonPath,
				x: px / FlxG.width,
				y: py / FlxG.height,
				scale: scaleV,
				flipX: flipX,
				skin: '',
				defaultAnim: (currentAnim != null) ? currentAnim : ''
			});
		}

		if (story.characters.length == startIdx)
		{
			showHint("没有可导入的角色（预设缺少 atlas / skeleton 路径）。");
			return;
		}
		rebuildPreviewChars();
		refreshCharList();
		curChar = story.characters.length - 1;
		loadCharIntoFields();
		refreshPreview();
		unsavedProgress = true;
		showHint("已从 Spine Viewer 预设导入 " + (story.characters.length - startIdx) + " 个角色。");
	}

	function genUniqueCharId(base:String):String
	{
		var id:String = base;
		var n:Int = 1;
		while (charIdExists(id))
		{
			id = base + '_' + n;
			n++;
		}
		return id;
	}

	function charIdExists(id:String):Bool
	{
		for (c in story.characters)
			if (c.id == id)
				return true;
		return false;
	}

	function applyCharTransform(pc:EditorChar):Void
	{
		if (pc == null || pc.sprite == null)
			return;
		var d:StoryCharDef = pc.def;
		var sx:Float = (d.x != null) ? d.x * FlxG.width : FlxG.width / 2;
		var sy:Float = (d.y != null) ? d.y * FlxG.height : FlxG.height * 0.85;
		var sc:Float = (d.scale != null) ? d.scale : 1.0;
		pc.sprite.x = sx;
		pc.sprite.y = sy;
		pc.sprite.scaleX = (d.flipX == true) ? -sc : sc;
		pc.sprite.scaleY = sc;
		pc.sprite.antialiasing = ClientPrefs.data.antialiasing;
	}

	function applySkin(idx:Int):Void
	{
		var pc:EditorChar = previewChars[idx];
		if (pc == null || pc.sprite == null)
			return;
		var skin:String = story.characters[idx].skin;
		if (skin != null && skin != '' && pc.sprite.skeleton.data.findSkin(skin) != null)
		{
			pc.sprite.skeleton.skinName = skin;
			pc.sprite.skeleton.setSlotsToSetupPose();
			pc.sprite.skeleton.updateWorldTransform(Physics.update);
		}
	}

	function rebuildPreviewChars():Void
	{
		for (pc in previewChars)
		{
			if (pc != null && pc.sprite != null)
			{
				previewGroup.remove(pc.sprite);
				pc.sprite.destroy();
			}
		}
		previewChars = [];
		for (d in story.characters)
		{
			var pc:EditorChar = new EditorChar();
			pc.def = d;
			pc.defaultAnim = (d.defaultAnim != null) ? d.defaultAnim : '';
			try
			{
				var loaded = StorySpineTools.loadSpine(d.atlasPath, d.skeletonPath, d.skin);
				pc.sprite = loaded.sprite;
				pc.anims = loaded.anims;
				if (pc.defaultAnim == null || pc.defaultAnim == '')
					pc.defaultAnim = (pc.anims.length > 0) ? pc.anims[0] : '';
				applyCharTransform(pc);
				previewGroup.add(loaded.sprite);
			}
			catch (e:Dynamic)
			{
				pc.sprite = null;
				trace("StoryEditor preview char load failed: " + d.id + " -> " + Std.string(e));
			}
			previewChars.push(pc);
		}
	}

	function findPreviewChar(id:String):EditorChar
	{
		for (pc in previewChars)
			if (pc != null && pc.def != null && pc.def.id == id)
				return pc;
		return null;
	}

	function getCharAnims(id:String):Array<String>
	{
		var pc:EditorChar = findPreviewChar(id);
		return (pc != null) ? pc.anims : [];
	}

	function refreshPreview():Void
	{
		var onChars:Bool = (UI_box != null && UI_box.selectedName == 'Characters');
		var line:StoryLine = (curLine < story.lines.length) ? story.lines[curLine] : null;
		var speakerId:String = (line != null) ? line.character : null;

		for (pc in previewChars)
		{
			if (pc == null || pc.sprite == null)
				continue;
			// 角色标签下全部不透明，方便查看导入的角色；台词标签下按发言者淡化
			var isSp:Bool = (speakerId != null && pc.def.id == speakerId);
			pc.sprite.alpha = (onChars || isSp) ? 1 : 0.4;
		}

		var sp:EditorChar = (speakerId != null) ? findPreviewChar(speakerId) : null;
		if (sp != null && sp.sprite != null)
		{
			var expr:String = (line.expression != null && line.expression != '') ? line.expression : sp.defaultAnim;
			sp.setAnim(expr, true);
		}

		if (sp != null)
		{
			var nm:String = (line.name != null && line.name.trim() != '') ? line.name : sp.def.name;
			previewName.text = (nm != null) ? nm : '';
			var aff:String = (line.affiliation != null && line.affiliation.trim() != '') ? line.affiliation : sp.def.affiliation;
			if (aff != null && aff.trim() != '')
			{
				previewAff.text = aff;
				previewAff.x = previewName.x + previewName.width + 50;
				previewAff.visible = true;
			}
			else
				previewAff.visible = false;
		}
		else
		{
			previewName.text = '';
			previewAff.visible = false;
		}
		previewText.text = (line != null && line.text != null) ? line.text : '';
	}

	// ------------------------------------------------------------------
	// 保存 / 载入 / 预览
	// ------------------------------------------------------------------
	function saveStory():Void
	{
		var json:String = haxe.Json.stringify(story, "\t");
		#if sys
		if (fileHandler == null || !fileHandler.completed)
			fileHandler.completed = true;
		fileHandler.save('story.json', json, onSaveComplete, onSaveCancel, onSaveError);
		#else
		StorageUtil.saveContent('story.json', json);
		unsavedProgress = false;
		showHint("已保存 story.json");
		#end
	}

	#if sys
	function onSaveComplete():Void
	{
		showHint("已保存: " + fileHandler.path);
		try
		{
			// 把引用的 Spine 资源复制到 JSON 同级目录，使剧情可随文件分发（"保存要附带"）
			var copy:StoryFile = cast haxe.Json.parse(haxe.Json.stringify(story));
			var outDir:String = StorySpineTools.dirname(fileHandler.path);
			var base:String = StorySpineTools.baseNoExt(fileHandler.path);
			var assetsDir:String = outDir + '/' + base + '_assets';
			for (c in copy.characters)
			{
				if (c.atlasPath == null || c.skeletonPath == null)
					continue;
				var ext:String = StorySpineTools.extOf(c.skeletonPath);
				var aDst:String = assetsDir + '/' + c.id + '.atlas';
				var sDst:String = assetsDir + '/' + c.id + ext;
				StorySpineTools.copyFile(c.atlasPath, aDst);
				StorySpineTools.copyFile(c.skeletonPath, sDst);
				var imgs:Array<String> = StorySpineTools.collectAtlasImages(c.atlasPath);
				for (img in imgs)
					StorySpineTools.copyFile(StorySpineTools.dirname(c.atlasPath) + '/' + img, assetsDir + '/' + img);
				c.atlasPath = base + '_assets/' + c.id + '.atlas';
				c.skeletonPath = base + '_assets/' + c.id + ext;
			}
			File.saveContent(fileHandler.path, haxe.Json.stringify(copy, "\t"));
			showHint("已保存并附带角色资源: " + fileHandler.path);
		}
		catch (e:Dynamic)
		{
			trace("StoryEditor bundle failed: " + e);
		}
		unsavedProgress = false;
	}

	function onSaveCancel():Void
	{
		showHint("已取消保存。");
	}

	function onSaveError():Void
	{
		showHint("保存失败。");
	}
	#end

	function loadStoryFromFile():Void
	{
		if (fileHandler == null || !fileHandler.completed)
			fileHandler.completed = true;
		fileHandler.open(null, null, [new FileFilter('JSON', 'json')], function()
		{
			loadStoryFromPath(fileHandler.path);
		}, null, null);
	}

	function loadStoryFromPath(path:String):Void
	{
		var str:String = null;
		#if sys
		if (sys.FileSystem.exists(path))
			str = sys.io.File.getContent(path);
		#end
		if (str == null || str.length == 0)
			str = fileHandler.data;
		if (str == null)
			return;
		try
		{
			var sf:StoryFile = cast haxe.Json.parse(str);
			if (sf == null || sf.lines == null)
			{
				showHint("剧情格式不正确（缺少 lines 数组）。");
				return;
			}
			story = sf;
			if (story.characters == null)
				story.characters = [];
			lastLoadedDir = StorySpineTools.dirname(path);
			curChar = 0;
			curLine = 0;
			rebuildPreviewChars();
			refreshCharList();
			refreshLineList();
			loadCharIntoFields();
			loadLineIntoFields();
			refreshPreview();
			unsavedProgress = false;
			showHint("已载入: " + path);
		}
		catch (e:Dynamic)
		{
			showHint("载入失败: " + Std.string(e));
		}
	}

	function testPlay():Void
	{
		var copy:StoryFile = cast haxe.Json.parse(haxe.Json.stringify(story));
		StoryPlayerState.pendingJsonDir = lastLoadedDir;
		StoryPlayerState.pendingStory = copy;
		MusicBeatState.switchState(new StoryPlayerState());
	}

	function onBack():Void
	{
		if (!unsavedProgress)
		{
			MusicBeatState.switchState(new MasterEditorMenu());
			return;
		}
		openSubState(new ExitConfirmationPrompt(function()
		{
			MusicBeatState.switchState(new MasterEditorMenu());
		}));
	}

	// ------------------------------------------------------------------
	// 默认内容
	// ------------------------------------------------------------------
	function defaultStory():StoryFile
	{
		return {
			background: '#1a1a24',
			music: '',
			characters: [],
			lines: [
				{text: '欢迎使用剧情编辑器。点击右侧 Characters 添加 Spine 角色，Lines 编写台词，Save 保存（会附带角色资源），Test 预览。'}
			]
		};
	}

	// ------------------------------------------------------------------
	// 主循环
	// ------------------------------------------------------------------
	override function update(elapsed:Float)
	{
		if (PsychUIInputText.focusOn == null)
		{
			if (FlxG.keys.justPressed.ESCAPE)
			{
				onBack();
				return;
			}
			if (FlxG.keys.justPressed.LEFT)
				changeLine(-1);
			else if (FlxG.keys.justPressed.RIGHT)
				changeLine(1);
		}
		super.update(elapsed);
	}

	function changeLine(d:Int):Void
	{
		curLine = FlxMath.wrap(curLine + d, 0, story.lines.length - 1);
		refreshLineList();
		loadLineIntoFields();
		refreshPreview();
	}
}

/**
 * 编辑器里的一个 Spine 角色预览实例。
 */
private class EditorChar
{
	public var def:StoryCharDef;
	public var sprite:NoCullSkeletonSprite;
	public var anims:Array<String> = [];
	public var defaultAnim:String = '';

	public function new() {}

	public function setAnim(name:String, loop:Bool):Void
	{
		if (name == null || name == '' || sprite == null)
			return;
		var anim = sprite.skeleton.data.findAnimation(name);
		if (anim == null)
			return;
		sprite.state.setAnimation(0, anim, loop);
	}
}
