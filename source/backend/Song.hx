package backend;

import haxe.Json;
import lime.utils.Assets;
import sys.io.File;
import sys.io.FileOutput;

import objects.Note;
import states.editors.content.VSlice;

typedef SwagSong =
{
	var song:String;
	var notes:Array<SwagSection>;
	var events:Array<Dynamic>;
	var bpm:Float;
	var needsVoices:Bool;
	var speed:Float;
	var offset:Float;

	var player1:String;
	var player2:String;
	var gfVersion:String;
	var stage:String;
	var format:String;

	// 谱面由哪个编辑器/引擎生成，仅作元信息展示，不参与任何玩法逻辑
	@:optional var generatedBy:String;

	// Extra Keys：键数档位（0=1键 ... 17=18键）。缺省 = 3（标准 4 键）。
	// 对应 extrakeys.json 里 keys 数组的下标。
	@:optional var mania:Int;

	// 兼容其他多键引擎的字段名（如 Matt/MattV3 的 "keyCount": 6 表示 6 键）。
	// onLoadJson 里会把 keyCount 映射成 mania = keyCount - 1。
	@:optional var keyCount:Int;

	@:optional var gameOverChar:String;
	@:optional var gameOverSound:String;
	@:optional var gameOverLoop:String;
	@:optional var gameOverEnd:String;
	
	@:optional var disableNoteRGB:Bool;

	@:optional var arrowSkin:String;
	@:optional var splashSkin:String;
	@:optional var holdCoverSkin:String;
	@:optional var specialInst:String;
    @:optional var specialVocal:String;
    @:optional var specialEvents:String;
}

typedef SwagSection =
{
	var sectionNotes:Array<Dynamic>;
	var sectionBeats:Float;
	var mustHitSection:Bool;
	@:optional var altAnim:Bool;
	@:optional var gfSection:Bool;
	@:optional var bpm:Float;
	@:optional var changeBPM:Bool;
	@:optional var bpmRamp:Float; // 线性 BPM 过渡持续的步数（0/缺省 = 瞬时跳变，保持旧行为）
}

class Song
{
	public var song:String;
	public var notes:Array<SwagSection>;
	public var events:Array<Dynamic>;
	public var bpm:Float;
	public var needsVoices:Bool = true;
	public var arrowSkin:String;
	public var splashSkin:String;
	public var holdCoverSkin:String;
	public var gameOverChar:String;
	public var gameOverSound:String;
	public var gameOverLoop:String;
	public var gameOverEnd:String;
	public var disableNoteRGB:Bool = false;
	public var speed:Float = 1;
	public var stage:String;
	public var player1:String = 'bf';
	public var player2:String = 'dad';
	public var gfVersion:String = 'gf';
	public var format:String = 'psych_v1';
	public var generatedBy:String;
	public var specialInst:String;
	public var specialVocal:String;
	public var specialEvents:String;

	public static function convert(songJson:Dynamic) // Convert old charts to psych_v1 format
	{
		if(songJson.gfVersion == null)
		{
			songJson.gfVersion = songJson.player3;
			if(Reflect.hasField(songJson, 'player3')) Reflect.deleteField(songJson, 'player3');
		}

		// Extra Keys：在按列折叠之前先确定列数。
		// legacy 谱面无 mania 字段 → 兜底 3（4 键），行为与原版一致；
		// 多键谱面（keyCount:6 或 mania:5）→ sectCols=6，轨道号 0-5 玩家 / 6-11 敌人。
		var mania:Int = 3;
		if (songJson.keyCount != null) mania = Std.int(songJson.keyCount) - 1;
		else if (songJson.mania != null) mania = Std.int(songJson.mania);
		var sectCols:Int = mania + 1;

		if(songJson.events == null)
		{
			songJson.events = [];
			for (secNum in 0...songJson.notes.length)
			{
				var sec:SwagSection = songJson.notes[secNum];
				var notes:Array<Dynamic> = sec.sectionNotes;
				var newNotes:Array<Dynamic> = [];
				if(notes != null)
				{
					for(note in notes)
					{
						if(note[1] < 0)
						{
							songJson.events.push([note[0], [[note[2], note[3], note[4]]]]);
						}
						else
						{
							newNotes.push(note);
						}
					}
				}
				sec.sectionNotes = newNotes;
			}
		}

		var sectionsData:Array<SwagSection> = songJson.notes;
		if(sectionsData == null) return;

		for (section in sectionsData)
		{
			if (section.sectionNotes == null)
				section.sectionNotes = [];

			var beats:Null<Float> = cast section.sectionBeats;
			if (beats == null || Math.isNaN(beats))
			{
				section.sectionBeats = 4;
				if(Reflect.hasField(section, 'lengthInSteps')) Reflect.deleteField(section, 'lengthInSteps');
			}

			for (note in section.sectionNotes)
			{
				// 列数从硬编码 4 改成按 mania 档位动态计算。
				// legacy 相对车道：0..sectCols-1 = 当前小节归属方，sectCols..2*sectCols-1 = 另一方。
				// psych_v1 绝对车道：0..sectCols-1 永远是玩家，sectCols..2*sectCols-1 永远是对手。
				var gottaHitNote:Bool = (note[1] < sectCols) ? section.mustHitSection : !section.mustHitSection;
				note[1] = (note[1] % sectCols) + (gottaHitNote ? 0 : sectCols);

				if(!Std.isOfType(note[3], String))
					note[3] = Note.defaultNoteTypes[note[3]];
			}
		}
	}

	public static var chartPath:String;
	public static var loadedSongName:String;
	// 最近一次谱面加载失败时实际尝试过的路径（用于错误提示）
	public static var lastTriedChartPaths:Array<String> = [];
	public static function loadFromJson(jsonInput:String, ?folder:String):SwagSong
	{
		if(folder == null) folder = jsonInput;
		var newSong:SwagSong = getChart(jsonInput, folder);
		if(newSong == null)
		{
			trace('Failed to load chart: $jsonInput (tried: ${lastTriedChartPaths.join(', ')})');
			return null;
		}
		PlayState.SONG = newSong;
		
		loadedSongName = folder;
		chartPath = _lastPath;
		#if windows
		// prevent any saving errors by fixing the path on Windows (being the only OS to ever use backslashes instead of forward slashes for paths)
		chartPath = chartPath.replace('/', '\\');
		#end
		StageData.loadDirectory(PlayState.SONG);
		return PlayState.SONG;
	}

	/**
	 * 计算谱面 JSON 的路径，不读文件。开销极小，可以在主线程调用后把路径丢给后台线程去读。
	 * 内置 Normal 难度兼容：无后缀谱面缺失时，回退尝试 -normal / 忽略大小写 / 已知拼写错误变体。
	 */
	public static function getChartPath(jsonInput:String, ?folder:String):String
	{
		if(folder == null) folder = jsonInput;

		var formattedFolder:String = Paths.formatToSongPath(folder);
		var formattedSong:String = Paths.formatToSongPath(jsonInput);
		var basePath:String = Paths.json('${formattedFolder}/${formattedSong}');
		lastTriedChartPaths = [basePath];

		// Compat：Normal（无后缀）谱面缺失时，尝试 -normal 后缀 / 难度名（忽略大小写）及已知拼写错误变体
		if(isDefaultDifficultyChart(formattedSong) && !chartFileExists(basePath))
		{
			var fallbackPath:String = findNormalFallbackChart(formattedFolder, formattedSong);
			if(fallbackPath != null) return fallbackPath;
		}
		return basePath;
	}

	/**
	 * 判断是否为"无后缀"（即 Normal / 默认难度）谱面名。
	 * 只要不以当前难度列表里的某个非默认难度名结尾，就按无后缀谱面处理。
	 */
	static function isDefaultDifficultyChart(formattedSong:String):Bool
	{
		var defaultDiff:String = Paths.formatToSongPath(Difficulty.getDefault()); // 'normal'
		for(diff in Difficulty.list)
		{
			var lower:String = Paths.formatToSongPath(diff);
			if(lower.length == 0 || lower == defaultDiff) continue;
			if(formattedSong.endsWith('-' + lower)) return false;
		}
		return true;
	}

	/**
	 * 尝试寻找 Normal 难度兼容谱面文件：
	 * 1) -normal 后缀精确路径（Windows/macOS 等大小写不敏感文件系统可一步命中）
	 * 2) 谱面目录内忽略大小写的文件名匹配（覆盖大小写敏感文件系统）
	 * 返回实际存在的路径；找不到返回 null。
	 */
	static function findNormalFallbackChart(formattedFolder:String, formattedSong:String):String
	{
		// 候选难度后缀（小写）。'nuormal' 是部分旧模组常见的拼写错误，可继续追加
		var suffixes:Array<String> = ['normal', 'nuormal'];
		var want:Array<String> = [];
		for(s in suffixes)
			want.push(formattedSong + '-' + s);

		// 1) 精确路径尝试（mods 解析 + 打包资源）
		for(w in want)
		{
			var p:String = Paths.json('$formattedFolder/$w');
			lastTriedChartPaths.push(p);
			if(chartFileExists(p)) return p;
		}

		// 2) 大小写敏感文件系统：扫描当前 mod 的谱面目录，忽略大小写匹配
		#if (MODS_ALLOWED && sys)
		try
		{
			if(Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			{
				var dir:String = Paths.mods(Mods.currentModDirectory + '/data/' + formattedFolder);
				if(FileSystem.exists(dir) && FileSystem.isDirectory(dir))
				{
					for(f in FileSystem.readDirectory(dir))
					{
						var lower:String = f.toLowerCase();
						for(w in want)
						{
							if(lower == w + '.json')
							{
								var fp:String = dir + '/' + f;
								lastTriedChartPaths.push(fp);
								return fp;
							}
						}
					}
				}
			}
		}
		catch(e:Dynamic) { /* 目录不可读时忽略，按未找到处理 */ }
		#end
		return null;
	}

	static function chartFileExists(path:String):Bool
	{
		#if sys
		if(FileSystem.exists(path)) return true;
		#end
		return Assets.exists(path, lime.utils.AssetType.TEXT);
	}

	/**
	 * 把一份**已经解析好**的谱面应用成当前谱面。
	 * 用于缓存命中 / 后台线程预解析的结果，避免重复 Json.parse。
	 */
	public static function applyChart(songJson:SwagSong, folder:String, ?path:String):SwagSong
	{
		if(songJson == null) return null;

		PlayState.SONG = songJson;
		loadedSongName = folder;
		chartPath = (path != null ? path : _lastPath);
		#if windows
		if(chartPath != null) chartPath = chartPath.replace('/', '\\');
		#end
		// Freeplay 缓存命中路径：getChart 不会再次执行，这里恢复 _lastPath 并重跑 LE 音频后缀
		// 探测，否则 Song.leatherSongFolder 会残留上一首歌曲的值，导致 LE 谱面音频路径错误。
		if (path != null) _lastPath = path;
		applyLeatherAudioSuffix(songJson);
		StageData.loadDirectory(songJson);
		return songJson;
	}

	static var _lastPath:String;
	// 当前谱面所属 mod 是否为 Leather Engine 模组（getChart 里按 mod 根目录结构判定，
	// parseJSON 据此区分"经典包裹+无format"谱面是 LE（LEATHER）还是旧版 Psych（psych_v1_convert）。
	static var _lastIsLeatherMod:Bool = false;
	public static function getChart(jsonInput:String, ?folder:String):SwagSong
	{
		if(folder == null) folder = jsonInput;
		var rawData:String = null;

		// 路径解析（含 Normal 难度兼容回退）
		_lastPath = getChartPath(jsonInput, folder);

		try
		{
			#if MODS_ALLOWED
			if(FileSystem.exists(_lastPath))
				rawData = File.getContent(_lastPath);
			else
			#end
				rawData = Assets.getText(_lastPath);
		}
		catch(e:Dynamic)
		{
			trace('Error loading chart file: $e');
		}

		// ── Leather mod 路径回退：标准 data/songs/ 找不到时，试 data/song data/ ──
		if(rawData == null || rawData.trim() == '')
		{
			var leatherPath:String = findLeatherChartPath(folder);
			if(leatherPath != null)
			{
				_lastPath = leatherPath;
				try
				{
					rawData = File.getContent(leatherPath);
				}
				catch(e:Dynamic) { trace('Error loading Leather chart: $e'); }
			}
		}

		if(rawData == null) return null;

		// ── 判定当前 mod 是否为 Leather 模组 ──
		// LE 与旧版 Psych 的经典谱面结构相同（{"song":{...}} 包裹、子对象无 format），
		// 单看谱面无法区分，必须按 mod 根目录特征判定（LE 特有 data/song data 等目录 / 旧 polymod 元数据）。
		var leatherModDir:String = extractLeatherModDir(_lastPath);
		_lastIsLeatherMod = (leatherModDir != null) && isLeatherMod(leatherModDir);

		// ── 自动检测：VSlice / Leather LTS 新格式 ──
		// 顶层无 .song 包裹、notes 是对象（按难度分组）、有 scrollSpeed → VSlice chart
		var probe:Dynamic = Json.parse(rawData);
		var song:SwagSong = null;
		if(probe != null && probe.song == null && probe.notes != null
			&& Type.typeof(probe.notes) == TObject && probe.scrollSpeed != null)
		{
			song = loadVSliceChart(probe, folder);
		}
		else
		{
			song = parseJSON(rawData, jsonInput);
		}

		// LE 谱面：从实际加载路径解析 mod 目录与难度后缀，设置 specialInst/specialVocal。
		// Leather 命名：songs/{folder}/Inst-{Diff}.ogg、Voices-{Diff}.ogg（如 Inst-Erect.ogg）。
		// 仅在对应后缀音频确实存在时设置，避免破坏只有无后缀 Inst.ogg 的普通谱面。
		applyLeatherAudioSuffix(song);
		return song;
	}

	/**
	 * 判断某 mod 目录是否为 Leather Engine 模组。
	 * 判定信号（命中任一即判定为 LE）：
	 *  1. LE 特有目录结构（带空格，区别于 Psych 的 data/songs、data/characters、data/stages）：
	 *     data/song data、data/character data、data/stage data、data/modcharts
	 *  2. polymod 旧版元数据：根目录有 _polymod_meta.json 且没有 pack.json
	 *     （LE 0.4.x 用旧版 polymod 的 _polymod_meta.json；Psych 0.7+ 用 pack.json）
	 * 注意：Paths.mods() 返回值无尾斜杠，拼接子路径必须手动补 '/'。
	 */
	static function isLeatherMod(modDir:String):Bool
	{
		if(modDir == null || modDir.length == 0) return false;
		#if MODS_ALLOWED
		var base:String = Paths.mods(modDir);
		if(FileSystem.exists(base + '/data/song data')
			|| FileSystem.exists(base + '/data/character data')
			|| FileSystem.exists(base + '/data/stage data')
			|| FileSystem.exists(base + '/data/modcharts'))
			return true;
		if(FileSystem.exists(base + '/_polymod_meta.json') && !FileSystem.exists(base + '/pack.json'))
			return true;
		#end
		return false;
	}

	/**
	 * 检测谱面是否来自 Leather（LEATHER / LEATHER LTS），若来自 LE 且带难度后缀，
	 * 且该 mod 里存在对应后缀音频，则把后缀写入 specialInst/specialVocal，
	 * 供 PlayState 的音频探测/加载链使用（modHasSong 检查 Inst-{si}、tryVoices 追加 -{sv}）。
	 */
	static function applyLeatherAudioSuffix(song:SwagSong):Void
	{
		leatherDebugLog('applyLeatherAudioSuffix called: _lastPath=$_lastPath format=${(song != null) ? song.format : 'null'}');
		if(song == null || _lastPath == null || song.format == null) return;
		if(song.format != 'LEATHER' && song.format != 'LEATHER LTS') return;

		#if MODS_ALLOWED
		var mod:String = extractLeatherModDir(_lastPath);
		if(mod == null) return;

		// Leather 的歌曲音频目录名 = 谱面文件所在 data/song data/{Folder} 的目录名（原始名，
		// 可含空格与原始大小写，如 "Final Destination"），与 json 内 song 字段不一定一致
		// （zavodila 谱面 song 字段为 "Zavodila" 但音频目录为小写 zavodila）。
		var songFolder:String = extractLeatherSongFolder(_lastPath);
		if(songFolder == null) songFolder = Paths.formatToSongPath(song.song);
		leatherSongFolder = songFolder;

		var fileName:String = haxe.io.Path.withoutDirectory(_lastPath);
		// 后缀提取基于文件名与“谱面所在目录名”比对（Leather 惯例 {Folder}-{diff}.json）
		var suffix:String = extractLeatherDiffSuffix(fileName, songFolder);
		if(suffix == null) return;

		// 难度后缀大小写不统一（谱面文件小写 erect，音频常为 Erect），两个候选都试
		var candidates:Array<String> = [suffix, suffix.charAt(0).toUpperCase() + suffix.substr(1)];
		var foundInst:String = null;
		var foundVocal:String = null;
		for(c in candidates)
		{
			var instPath:String = Paths.mods(mod + '/songs/' + songFolder + '/Inst-' + c + '.ogg');
			var vocalPath:String = Paths.mods(mod + '/songs/' + songFolder + '/Voices-' + c + '.ogg');
			leatherDebugLog('  probe mod=$mod folder=$songFolder suffix=$suffix cand=$c instExists=${FileSystem.exists(instPath)} ($instPath) vocalExists=${FileSystem.exists(vocalPath)}');
			if(foundInst == null && FileSystem.exists(instPath))
				foundInst = c;
			if(foundVocal == null && FileSystem.exists(vocalPath))
				foundVocal = c;
		}
		if(foundInst != null) song.specialInst = foundInst;
		if(foundVocal != null) song.specialVocal = foundVocal;
		leatherDebugLog('  result: specialInst=${song.specialInst} specialVocal=${song.specialVocal} leatherSongFolder=$leatherSongFolder');
		#end
	}

	static function leatherDebugLog(msg:String):Void
	{
		#if MODS_ALLOWED
		try
		{
			var path:String = Sys.getCwd() + 'leather_audio_debug.txt';
			var f:FileOutput = File.append(path, false);
			f.writeString(Date.now().toString() + ' | ' + msg + '\n');
			f.close();
		}
		catch(e:Dynamic) {}
		#end
	}

/**
 * LE 谱面的歌曲音频目录名（原始名，含空格/原始大小写）。
 * 供 PlayState.generateSong 的音频探测/加载链直接使用（跳过 formatToSongPath）。
 * 仅 LE 谱面加载后被设置。
 */
public static var leatherSongFolder:String = null;

	/** 从 LE 谱面路径（.../mods/{mod}/data/song data/...）提取 mod 目录名（兼容 Windows 反斜杠路径） */
	static function extractLeatherModDir(path:String):String
	{
		path = path.replace('\\', '/');
		var marker:String = '/mods/';
		var idx:Int = path.indexOf(marker);
		if(idx < 0) { marker = 'mods/'; idx = path.indexOf(marker); }
		if(idx < 0) return null;
		var rest:String = path.substring(idx + marker.length);
		var slash:Int = rest.indexOf('/');
		if(slash > 0) rest = rest.substring(0, slash);
		return rest.length > 0 ? rest : null;
	}

	/**
	 * 从 LE 谱面路径提取歌曲音频目录名：data/song data/{Folder}/{file}.json 中的 {Folder}
	 * （Leather 官方/Old 布局，Folder 为原始目录名，可含空格与原始大小写）。
	 * 找不到（如 LTS 的 data/charts 布局）返回 null，由调用方回退 formatToSongPath。
	 */
	static function extractLeatherSongFolder(path:String):String
	{
		if(path == null) return null;
		path = path.replace('\\', '/');
		var marker:String = '/data/song data/';
		var idx:Int = path.indexOf(marker);
		if(idx < 0) return null;
		var rest:String = path.substring(idx + marker.length);
		var slash:Int = rest.indexOf('/');
		if(slash < 0) return null;
		rest = rest.substring(0, slash);
		return rest.length > 0 ? rest : null;
	}

	/**
	 * 从谱面文件名（{folder}.json / {folder}-{diff}.json / {folder}-chart-{diff}.json）提取难度后缀。
	 * 注意 Leather 命名松散：目录名 "Final Destination"（大写）与谱面文件名 "final destination-erect.json"
	 * （小写）可能大小写不一致，匹配一律忽略大小写（长度相同，偏移量不变）。
	 */
	static function extractLeatherDiffSuffix(fileName:String, fmtFolder:String):String
	{
		if(fileName == null || !fileName.endsWith('.json')) return null;
		var base:String = fileName.substring(0, fileName.length - 5);
		var baseLower:String = base.toLowerCase();
		var folderLower:String = fmtFolder.toLowerCase();
		if(baseLower == folderLower) return null;
		if(baseLower.startsWith(folderLower + '-chart-'))
			return base.substring(folderLower.length + 7);
		if(baseLower.startsWith(folderLower + '-'))
			return base.substring(folderLower.length + 1);
		return null;
	}

	/**
	 * 归一化曲目名/目录名用于比对：
	 * Leather 的 data/song data/{Folder}/ 目录名与谱面文件名命名松散
	 * （"Final Destination"、"super saiyan" 等可含空格/大写/连字符混用），
	 * 统一去掉空格、连字符并转小写后再比较。
	 */
	static function normalizeChartKey(s:String):String
	{
		if(s == null) return '';
		return s.toLowerCase().replace(' ', '').replace('-', '');
	}

	/**
	 * 在 Leather mod 的 data/song data/ 目录下查找谱面文件。
	 * 第一优先：常规拼法（{folder}.json / {folder}-chart.json / {folder}-{diff}.json，folder 经 formatToSongPath）
	 *  —— 覆盖目录名为纯小写无空格的情况（如 zavodila）。
	 * 第二优先：扫描 data/song data/ 下所有子目录，目录名与谱面文件名均做归一化匹配
	 *  —— 覆盖目录名带空格/大写（REC 的 "Final Destination"、"super saiyan" 等）。
	 */
	static function findLeatherChartPath(folder:String):String
	{
		var fmtFolder:String = Paths.formatToSongPath(folder);
		var candidates:Array<String> = [
			'data/song data/' + fmtFolder + '/' + fmtFolder + '.json',
			'data/song data/' + fmtFolder + '/' + fmtFolder + '-chart.json'
		];
		// 难度变体（erect 等）
		for(diff in Difficulty.list)
		{
			var d:String = Paths.formatToSongPath(diff);
			if(d.length > 0)
			{
				candidates.push('data/song data/' + fmtFolder + '/' + fmtFolder + '-chart-' + d + '.json');
				candidates.push('data/song data/' + fmtFolder + '/' + fmtFolder + '-' + d + '.json'); // 旧版 Leather
			}
		}
		for(c in candidates)
		{
#if MODS_ALLOWED
			var p:String = Paths.modFolders(c);
			if(FileSystem.exists(p)) return p;
#end
		}

#if MODS_ALLOWED
		// ── 兜底：扫描 data/song data/ 全部子目录，归一化匹配 ──
		var normFolder:String = normalizeChartKey(folder);
		if(normFolder.length == 0) return null;
		var modDirs:Array<String> = [Mods.currentModDirectory];
		for(g in Mods.getGlobalMods())
			if(g != null && g.length > 0 && !modDirs.contains(g))
				modDirs.push(g);
		var curDiff:String = Paths.formatToSongPath(Difficulty.getString(false));
		for(mod in modDirs)
		{
			var baseDir:String = Paths.mods(mod + '/data/song data');
			if(!FileSystem.exists(baseDir) || !FileSystem.isDirectory(baseDir)) continue;
			try
			{
				for(sub in FileSystem.readDirectory(baseDir))
				{
					var fullDir:String = baseDir + '/' + sub;
					if(!FileSystem.isDirectory(fullDir)) continue;
					if(normalizeChartKey(sub) != normFolder) continue;

					var matchedCur:String = null;  // 当前难度变体（如 -erect）
					var matchedBase:String = null;  // 无难度后缀（如 {folder}.json）
					var matchedOther:String = null; // 其他难度变体
					for(f in FileSystem.readDirectory(fullDir))
					{
						var lower:String = f.toLowerCase();
						if(!lower.endsWith('.json') || lower.indexOf('-metadata') >= 0) continue;
						var base:String = f.substring(0, f.length - 5);
						var normBase:String = normalizeChartKey(base);
						if(normBase == normFolder) { if(matchedBase == null) matchedBase = fullDir + '/' + f; continue; }
						for(diff in Difficulty.list)
						{
							var dNorm:String = Paths.formatToSongPath(diff);
							if(dNorm.length == 0) continue;
							if(normBase == normalizeChartKey(folder + '-' + dNorm) || normBase == normalizeChartKey(folder + '-chart-' + dNorm))
							{
								if(dNorm == curDiff) { if(matchedCur == null) matchedCur = fullDir + '/' + f; }
								else if(matchedOther == null) matchedOther = fullDir + '/' + f;
								break;
							}
						}
					}
					if(matchedCur != null) return matchedCur;
					if(matchedBase != null) return matchedBase;
					if(matchedOther != null) return matchedOther;
				}
			}
			catch(e:Dynamic) { /* 目录不可读时忽略 */ }
		}
#end
		return null;
	}

	/**
	 * VSlice / Leather LTS 谱面自动加载：
	 * chart 文件（全难度）+ 同目录 metadata 文件 → 转换为当前难度的 psych_v1 SwagSong。
	 * metadata 路径跟随 Leather 命名：data/{folder}/{folder}-metadata.json。
	 */
	static function loadVSliceChart(chart:VSliceChart, folder:String):SwagSong
	{
		var fmtFolder:String = Paths.formatToSongPath(folder);
		var metaData:String = null;
		var metaPath:String = null;

		// 先试标准路径，再试 Leather mod 的 data/song data/ 路径
		var stdMeta:String = Paths.json('${fmtFolder}/${fmtFolder}-metadata');
		if(chartFileExists(stdMeta))
		{
			metaPath = stdMeta;
			metaData = Assets.getText(stdMeta);
		}
		else
		{
			// Leather LTS: data/song data/{folder}/{folder}-metadata.json
			var leatherCandidates:Array<String> = [
				'data/song data/' + fmtFolder + '/' + fmtFolder + '-metadata.json'
			];
			for(diff in Difficulty.list)
			{
				var d:String = Paths.formatToSongPath(diff);
				if(d.length > 0)
					leatherCandidates.push('data/song data/' + fmtFolder + '/' + fmtFolder + '-metadata-' + d + '.json');
			}
			for(c in leatherCandidates)
			{
#if MODS_ALLOWED
				var p:String = Paths.modFolders(c);
				if(FileSystem.exists(p))
				{
					metaPath = p;
					metaData = File.getContent(p);
					break;
				}
#end
			}
		}

		if(metaData == null || metaData.trim() == '')
		{
			trace('VSlice chart detected but metadata not found (folder=$fmtFolder)');
			return null;
		}

		var metadata:VSliceMetadata = cast Json.parse(metaData);
		var pack:PsychPackage = VSlice.convertToPsych(chart, metadata);
		if(pack == null || pack.difficulties == null)
		{
			trace('VSlice convert produced no difficulties');
			return null;
		}

		// 取当前难度，找不到回退第一个
		var wantDiff:String = Paths.formatToSongPath(Difficulty.getDefault());
		var song:SwagSong = null;
		if(pack.difficulties.exists(wantDiff))
			song = pack.difficulties.get(wantDiff);
		else
		{
			for(d in pack.difficulties.keys())
			{
				song = pack.difficulties.get(d);
				break;
			}
		}

		if(song != null)
		{
			song.format = 'LEATHER LTS';
			if(song.events == null) song.events = [];
			if(song.notes == null) song.notes = [];
			if(song.mania == null) song.mania = 3;
		}
		return song;
	}

	public static function parseJSON(rawData:String, ?nameForError:String = null, ?convertTo:String = 'psych_v1'):SwagSong
	{
		var root:Dynamic = Json.parse(rawData);

		// ── 自动检测：是否为经典包裹格式（{"song": {...}}）──
		// psych_v1 原生谱面顶层就是 SwagSong 本身（不包裹）；
		// Leather Official / 旧 Psych 谱面顶层是 {"song": {...}} 包裹。
		var hadLegacyWrapper:Bool = false;
		var songJson:SwagSong = cast root;
		if(Reflect.hasField(root, 'song'))
		{
			var subSong:Dynamic = Reflect.field(root, 'song');
			if(subSong != null && Type.typeof(subSong) == TObject)
			{
				songJson = cast subSong;
				hadLegacyWrapper = true;
			}
		}

		if(convertTo != null && convertTo.length > 0)
		{
			var fmt:String = songJson.format;
			// 记录子对象【原本】是否自带 format 字段：必须在写入 'unknown' 兜底值之前检查，
			// 否则 Reflect.hasField 永远为 true，Leather 谱面的 LEATHER 检测会失效。
			var hadFormatField:Bool = Reflect.hasField(songJson, 'format');
			if(fmt == null) fmt = songJson.format = 'unknown';

			switch(convertTo)
			{
				case 'psych_v1':
					if(!fmt.startsWith('psych_v1')) //Convert to Psych 1.0 format
					{
						trace('converting chart $nameForError with format $fmt to psych_v1 format...');
						// 经典包裹格式且子对象自身没写 psych_v1 format：
						//  -> 若当前 mod 是 Leather 模组，判为 LEATHER（LE 谱面）
						//  -> 否则是旧版 Psych 谱面（psych_v1_convert，结构与 LE 相同但引擎不同）
						// 注意：必须用 hadFormatField（写入 'unknown' 之前记录的原始状态），
						// 否则 Reflect.hasField 永远为 true，LEATHER 检测会失效。
						if(hadLegacyWrapper && !hadFormatField && _lastIsLeatherMod)
							songJson.format = 'LEATHER';
						else
							songJson.format = 'psych_v1_convert';
						convert(songJson);
					}
			}
		}

		// 防御：谱面可能完全没有 events 字段（常见于已是 psych_v1 的自定义/旧谱），
		// 不补默认空数组会导致 PlayState 遍历 songData.events 时 Null Object Reference 崩溃。
		if (songJson.events == null)
			songJson.events = [];

		// 防御：谱面可能完全没有 notes 字段，避免 PlayState 遍历 SONG.notes 时 Null Object Reference 崩溃。
		if (songJson.notes == null)
			songJson.notes = [];

		// Extra Keys：mania 字段兜底为 3（标准 4 键），与 Psych EK 行为一致。
		// 兼容 "keyCount" 字段（其他多键引擎风格）：keyCount=6 → mania=5。
		if (songJson.keyCount != null && songJson.mania == null)
			songJson.mania = Std.int(songJson.keyCount) - 1;
		if (songJson.mania == null)
			songJson.mania = 3;

		return songJson;
	}
}
