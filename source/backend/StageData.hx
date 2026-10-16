package backend;

import openfl.utils.Assets;
import haxe.Json;
import backend.Song;
import backend.Mods;
import psychlua.ModchartSprite;

typedef StageFile = {
	var directory:String;
	var defaultZoom:Float;
	@:optional var isPixelStage:Null<Bool>;
	var stageUI:String;

	var boyfriend:Array<Dynamic>;
	var girlfriend:Array<Dynamic>;
	var opponent:Array<Dynamic>;
	var hide_girlfriend:Bool;

	var camera_boyfriend:Array<Float>;
	var camera_opponent:Array<Float>;
	var camera_girlfriend:Array<Float>;
	var camera_speed:Null<Float>;

	@:optional var preload:Dynamic;
	@:optional var objects:Array<Dynamic>;
	@:optional var _editorMeta:Dynamic;
}

enum abstract LoadFilters(Int) from Int from UInt to Int to UInt
{
	var LOW_QUALITY:Int = (1 << 0);
	var HIGH_QUALITY:Int = (1 << 1);

	var STORY_MODE:Int = (1 << 2);
	var FREEPLAY:Int = (1 << 3);
}

class StageData {
	public static function dummy():StageFile
	{
		return {
			directory: "",
			defaultZoom: 0.9,
			stageUI: "normal",

			boyfriend: [770, 100],
			girlfriend: [400, 130],
			opponent: [100, 100],
			hide_girlfriend: false,

			camera_boyfriend: [0, 0],
			camera_opponent: [0, 0],
			camera_girlfriend: [0, 0],
			camera_speed: 1,

			_editorMeta: {
				gf: "gf",
				dad: "dad",
				boyfriend: "bf"
			}
		};
	}

	public static var forceNextDirectory:String = null;
	public static function loadDirectory(SONG:SwagSong) {
		var stage:String = '';
		if(SONG.stage != null)
			stage = SONG.stage;
		else if(Song.loadedSongName != null)
			stage = vanillaSongStage(Paths.formatToSongPath(Song.loadedSongName));
		else
			stage = 'stage';

		var stageFile:StageFile = getStageFile(stage);
		forceNextDirectory = (stageFile != null) ? stageFile.directory : ''; //preventing crashes
	}

	public static function getStageFile(stage:String):StageFile {
		try
		{
			var path:String = Paths.getPath('stages/' + stage + '.json', TEXT, null, true);
			#if MODS_ALLOWED
			if(FileSystem.exists(path))
				return cast tjson.TJSON.parse(File.getContent(path));
			#else
			if(Assets.exists(path))
				return cast tjson.TJSON.parse(Assets.getText(path));
			#end
		}
		// Leather 舞台 config 兜底：data/stage data/{stage}.json（默认走 Psych 逻辑，
		// 仅 Psych 舞台 json 缺失时才尝试 LE 布局，避免影响 Psych 谱面舞台）
		var lePath:String = findLeatherStageFile(stage);
		if (lePath != null)
		{
			try
			{
				var raw:Dynamic = tjson.TJSON.parse(File.getContent(lePath));
				if (raw != null) return convertLeatherStage(raw, stage);
			}
			catch(e:Dynamic)
			{
				trace('Error loading Leather stage file of "$stage": $e');
			}
		}
		return dummy();
	}

	/** 在启用 mod 的 data/stage data/{stage}.json 下查找 LE 舞台配置 */
	static function findLeatherStageFile(stage:String):String
	{
		#if MODS_ALLOWED
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
		{
			var p:String = Paths.mods(Mods.currentModDirectory + '/data/stage data/$stage.json');
			if (FileSystem.exists(p)) return p;
		}
		for (mod in Mods.getModDirectories())
		{
			var p:String = Paths.mods('$mod/data/stage data/$stage.json');
			if (FileSystem.exists(p)) return p;
		}
		#end
		return null;
	}

	/**
	 * 把 Leather 舞台 json 转换为 Psych StageFile 结构：
	 *   character_Positions[0/1/2] → boyfriend / opponent / girlfriend
	 *   camera_Zoom → defaultZoom；camera_Offsets[0/1] → camera_boyfriend / camera_opponent
	 *   objects[] → Psych objects（is_Animated → animatedSprite，贴图路径 library='stages'，
	 *   由 addObjectsToState 通过 Paths.image/getAtlas(data.image, 'stages') 命中
	 *   mods/{mod}/stages/images/{stage}/{file_Name}.png）
	 */
	static function convertLeatherStage(raw:Dynamic, stage:String):StageFile
	{
		var positions:Array<Dynamic> = (raw.character_Positions != null) ? cast raw.character_Positions : null;
		var out:StageFile = {
			directory: '',
			defaultZoom: (raw.camera_Zoom != null) ? Std.parseFloat(Std.string(raw.camera_Zoom)) : 0.9,
			stageUI: 'normal',
			boyfriend: (positions != null && positions.length > 0) ? cast positions[0] : [770, 100],
			girlfriend: (positions != null && positions.length > 2) ? cast positions[2] : [400, 130],
			opponent: (positions != null && positions.length > 1) ? cast positions[1] : [100, 100],
			hide_girlfriend: false,
			camera_boyfriend: [0, 0],
			camera_opponent: [0, 0],
			camera_girlfriend: [0, 0],
			camera_speed: 1,
			objects: []
		};
		if (raw.camera_Offsets != null)
		{
			var camOff:Array<Dynamic> = cast raw.camera_Offsets;
			if (camOff.length > 0) out.camera_boyfriend = cast camOff[0];
			if (camOff.length > 1) out.camera_opponent = cast camOff[1];
		}
		if (raw.camera_speed != null) out.camera_speed = Std.parseFloat(Std.string(raw.camera_speed));

		var objects:Array<Dynamic> = [];
		if (raw.objects != null)
		{
			var i:Int = 0;
			for (o in (cast raw.objects:Array<Dynamic>))
			{
				var isAnim:Bool = (o.is_Animated == true);
				var obj:Dynamic = {
					name: (o.object_Name != null && Std.string(o.object_Name).length > 0) ? Std.string(o.object_Name) : 'obj$i',
					type: isAnim ? 'animatedSprite' : 'sprite',
					image: '$stage/' + Std.string(o.file_Name),
					library: 'stages',
					x: (o.position != null) ? Std.parseFloat(Std.string(o.position[0])) : 0,
					y: (o.position != null) ? Std.parseFloat(Std.string(o.position[1])) : 0,
					scroll: (o.scroll_Factor != null) ? cast o.scroll_Factor : [1, 1],
					scale: [1, 1],
					antialiasing: (o.antialiased != false),
					color: 'FFFFFF'
				};
				if (o.scale != null)
				{
					var sc:Float = Std.parseFloat(Std.string(o.scale));
					obj.scale = [sc, sc];
				}
				if (o.alpha != null) obj.alpha = Std.parseFloat(Std.string(o.alpha));
				if (isAnim && o.animations != null)
				{
					var anims:Array<Dynamic> = [];
					for (a in (cast o.animations:Array<Dynamic>))
					{
						anims.push({
							anim: Std.string(a.name),
							name: Std.string(a.animation_name),
							fps: (a.fps != null) ? Std.parseInt(Std.string(a.fps)) : 24,
							loop: (a.looped == true),
							indices: (a.indices != null) ? cast a.indices : [],
							offsets: [0, 0]
						});
					}
					obj.animations = anims;
					if (o.start_Animation != null && Std.string(o.start_Animation).length > 0 && Std.string(o.start_Animation) != 'null')
						obj.firstAnimation = Std.string(o.start_Animation);
				}
				objects.push(obj);
				i++;
			}
		}
		out.objects = objects;
		return out;
	}

	public static function vanillaSongStage(songName):String
	{
		switch (songName)
		{
			case 'spookeez' | 'south' | 'monster':
				return 'spooky';
			case 'pico' | 'blammed' | 'philly' | 'philly-nice':
				return 'philly';
			case 'milf' | 'satin-panties' | 'high':
				return 'limo';
			case 'cocoa' | 'eggnog':
				return 'mall';
			case 'winter-horrorland':
				return 'mallEvil';
			case 'senpai' | 'roses':
				return 'school';
			case 'thorns':
				return 'schoolEvil';
			case 'ugh' | 'guns' | 'stress':
				return 'tank';
		}
		return 'stage';
	}

	public static var reservedNames:Array<String> = ['gf', 'gfGroup', 'dad', 'dadGroup', 'boyfriend', 'boyfriendGroup']; //blocks these names from being used on stage editor's name input text
	public static function addObjectsToState(objectList:Array<Dynamic>, gf:FlxSprite, dad:FlxSprite, boyfriend:FlxSprite, ?group:Dynamic = null, ?ignoreFilters:Bool = false)
	{
		var addedObjects:Map<String, FlxSprite> = [];
		for (num => data in objectList)
		{
			if (addedObjects.exists(data)) continue;

			switch(data.type)
			{
				case 'gf', 'gfGroup':
					if(gf != null)
					{
						gf.ID = num; 
						if (group != null) group.add(gf);
						addedObjects.set('gf', gf);
					}
				case 'dad', 'dadGroup':
					if(dad != null)
					{
						dad.ID = num;
						if (group != null) group.add(dad);
						addedObjects.set('dad', dad);
					}
				case 'boyfriend', 'boyfriendGroup':
					if(boyfriend != null)
					{
						boyfriend.ID = num;
						if (group != null) group.add(boyfriend);
						addedObjects.set('boyfriend', boyfriend);
					}

				case 'square', 'sprite', 'animatedSprite':
					if(!ignoreFilters && !validateVisibility(data.filters)) continue;

				var spr:ModchartSprite = new ModchartSprite(data.x, data.y);
				spr.ID = num;
				if(data.type != 'square')
				{
					// Leather 舞台贴图位于 mods/{mod}/stages/images/{stage}/（library='stages'），
					// 经 Paths.image/getAtlas(data.image, library) 携带 parentFolder 前缀查找；
					// 普通 Psych 舞台 object 无 library 字段，走原逻辑。
					var libStr:String = '';
					var libVal:Dynamic = Reflect.getProperty(data, 'library');
					if (libVal != null) libStr = Std.string(libVal);

					if(data.type == 'sprite')
						spr.loadGraphic((libStr.length > 0) ? Paths.image(data.image, libStr) : Paths.image(data.image));
					else
						spr.frames = (libStr.length > 0) ? Paths.getAtlas(data.image, libStr) : Paths.getAtlas(data.image);
						
						if(data.type == 'animatedSprite' && data.animations != null)
						{
							var anims:Array<objects.Character.AnimArray> = cast data.animations;
							for (key => anim in anims)
							{
								if(anim.indices == null || anim.indices.length < 1)
									spr.animation.addByPrefix(anim.anim, anim.name, anim.fps, anim.loop);
								else
									spr.animation.addByIndices(anim.anim, anim.name, anim.indices, '', anim.fps, anim.loop);
	
								if(anim.offsets != null)
									spr.addOffset(anim.anim, anim.offsets[0], anim.offsets[1]);
	
								if(spr.animation.curAnim == null || data.firstAnimation == anim.anim)
									spr.playAnim(anim.anim, true);
							}
						}
						for (varName in ['antialiasing', 'flipX', 'flipY'])
						{
							var dat:Dynamic = Reflect.getProperty(data, varName);
							if(dat != null) Reflect.setProperty(spr, varName, dat);
						}
						if(!ClientPrefs.data.antialiasing) spr.antialiasing = false;
					}
					else
					{
						spr.makeGraphic(1, 1, FlxColor.WHITE);
						spr.antialiasing = false;
					}

					if(data.scale != null && (data.scale[0] != 1.0 || data.scale[1] != 1.0))
					{
						spr.scale.set(data.scale[0], data.scale[1]);
						spr.updateHitbox();
					}
					spr.scrollFactor.set(data.scroll[0], data.scroll[1]);
					spr.color = CoolUtil.colorFromString(data.color);
					
					for (varName in ['alpha', 'angle'])
					{
						var dat:Dynamic = Reflect.getProperty(data, varName);
						if(dat != null) Reflect.setProperty(spr, varName, dat);
					}

					if (group != null) group.add(spr);
					addedObjects.set(data.name, spr);

				default:
					var err = '[Stage .JSON file] Unknown sprite type detected: ${data.type}';
					trace(err);
					FlxG.log.error(err);
			}
		}
		return addedObjects;
	}

	public static function validateVisibility(filters:LoadFilters)
	{
		if((filters & STORY_MODE) == STORY_MODE)
			if(!PlayState.isStoryMode) return false;
		else if((filters & FREEPLAY) == FREEPLAY)
			if(PlayState.isStoryMode) return false;

		return ((ClientPrefs.data.lowQuality && (filters & LOW_QUALITY) == LOW_QUALITY) ||
			(!ClientPrefs.data.lowQuality && (filters & HIGH_QUALITY) == HIGH_QUALITY));
	}
}
