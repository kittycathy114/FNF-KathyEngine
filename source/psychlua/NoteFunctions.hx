package psychlua;

import flixel.FlxG;
import flixel.FlxObject;
import flixel.group.FlxGroup;
import objects.Note;
import states.PlayState;

/**
 * C 类：音符便捷函数
 * 封装 getPropertyFromGroup/setPropertyFromGroup，让脚本不用反射也能操作音符
 */
class NoteFunctions
{
	public static function implement(funk:FunkinLua)
	{
		var lua:State = funk.lua;

		// getNoteCount() — 存活音符数量
		Lua_helper.add_callback(lua, "getNoteCount", function():Int {
			var game:PlayState = PlayState.instance;
			if (game == null || game.notes == null) return 0;
			var aliveCount:Int = 0;
			for (n in game.notes.members)
				if (n != null && Std.is(n, Note) && cast(n, Note).exists) aliveCount++;
			return aliveCount;
		});

		// getTotalNoteCount() — 预加载的全部音符数（不管存活/销毁）
		Lua_helper.add_callback(lua, "getTotalNoteCount", function():Int {
			var game:PlayState = PlayState.instance;
			if (game == null || game.notes == null) return 0;
			return game.notes.members.length;
		});

		// getNoteProperty(index, property) — 读取指定音符的某个属性
		Lua_helper.add_callback(lua, "getNoteProperty", function(index:Int, property:String):Dynamic {
			var game:PlayState = PlayState.instance;
			if (game == null || game.notes == null || index < 0 || index >= game.notes.members.length) return null;
			var note:Note = cast game.notes.members[index];
			if (note == null) return null;
			switch (property)
			{
				case 'noteData': return note.noteData;
				case 'strumTime': return note.strumTime;
				case 'noteType': return note.noteType;
				case 'isSustainNote': return note.isSustainNote;
				case 'missed': return note.missed;
				case 'wasGoodHit': return note.wasGoodHit;
				case 'canBeHit': return note.canBeHit;
				case 'tooLate': return note.tooLate;
				case 'ignoreNote': return note.ignoreNote;
				case 'mustPress': return note.mustPress;
				case 'gfNote': return note.gfNote;
				case 'x': return note.x;
				case 'y': return note.y;
				case 'alpha': return note.alpha;
				case 'angle': return note.angle;
				case 'velocityX': return note.velocity != null ? note.velocity.x : 0;
				case 'velocityY': return note.velocity != null ? note.velocity.y : 0;
				case 'hitHealth': return note.hitHealth;
				case 'missHealth': return note.missHealth;
				case 'exists': return note.exists;
				default:
					// fallback：反射读取任意属性
					return Reflect.getProperty(note, property);
			}
		});

		// setNoteProperty(index, property, value) — 设置指定音符的某个属性
		Lua_helper.add_callback(lua, "setNoteProperty", function(index:Int, property:String, value:Dynamic):Bool {
			var game:PlayState = PlayState.instance;
			if (game == null || game.notes == null || index < 0 || index >= game.notes.members.length) return false;
			var note:Note = cast game.notes.members[index];
			if (note == null) return false;
			Reflect.setProperty(note, property, value);
			return true;
		});

		// getNoteData(index) — 返回包含常用属性的完整对象
		Lua_helper.add_callback(lua, "getNoteData", function(index:Int):Dynamic {
			var game:PlayState = PlayState.instance;
			if (game == null || game.notes == null || index < 0 || index >= game.notes.members.length) return null;
			var note:Note = cast game.notes.members[index];
			if (note == null) return null;
			return {
				noteData: note.noteData,
				strumTime: note.strumTime,
				noteType: note.noteType,
				isSustainNote: note.isSustainNote,
				mustPress: note.mustPress,
				gfNote: note.gfNote,
				missed: note.missed,
				wasGoodHit: note.wasGoodHit,
				canBeHit: note.canBeHit,
				tooLate: note.tooLate,
				x: note.x,
				y: note.y,
				alpha: note.alpha,
				angle: note.angle,
				velocityX: note.velocity != null ? note.velocity.x : 0,
				velocityY: note.velocity != null ? note.velocity.y : 0,
				hitHealth: note.hitHealth,
				missHealth: note.missHealth
			};
		});

		// destroyNote(index) — 销毁指定音符（kill 或 remove）
		Lua_helper.add_callback(lua, "destroyNote", function(index:Int):Bool {
			var game:PlayState = PlayState.instance;
			if (game == null || game.notes == null || index < 0 || index >= game.notes.members.length) return false;
			var note:Note = cast game.notes.members[index];
			if (note == null) return false;
			note.kill();
			return true;
		});

		// getNoteRating(index) — 获取当前音符的评级（需要先判定才有效）
		Lua_helper.add_callback(lua, "getNoteRating", function(index:Int):String {
			var game:PlayState = PlayState.instance;
			if (game == null || game.notes == null || index < 0 || index >= game.notes.members.length) return '';
			var note:Note = cast game.notes.members[index];
			if (note == null) return '';
			// Note 类有 rating 字段
			return Reflect.getProperty(note, 'rating');
		});

		// getAliveNotes — 返回存活音符的 index 数组
		Lua_helper.add_callback(lua, "getAliveNotes", function():Array<Int> {
			var game:PlayState = PlayState.instance;
			var result:Array<Int> = [];
			if (game == null || game.notes == null) return result;
			for (i in 0...game.notes.members.length)
			{
				var n:Note = cast game.notes.members[i];
				if (n != null && n.exists) result.push(i);
			}
			return result;
		});
	}
}
