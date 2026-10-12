package states.editors.old.content;

import backend.Song;
import backend.Song.SwagSong;

using StringTools;

/**
 * Translates charts between Psych 1.0's `psych_v1` layout and the legacy layout the 0.6.3 / 0.7.3
 * editors were written for.
 *
 * The only structural difference that matters for editing is how a section note stores its lane:
 *  - legacy (<= 0.7.x): the lane is *relative* to the section, `0-3` means "the side that owns this
 *    section" and `4-7` the other one, so flipping `mustHitSection` swaps every note.
 *  - psych_v1: the lane is *absolute*, `0-3` is always the player and `4-7` always the opponent.
 *
 * `Song.parseJSON` upgrades everything it loads to `psych_v1`, so the ported editors have to undo
 * that on entry (otherwise notes show up on the wrong side of the grid) and redo it before handing
 * the chart over to `PlayState`.
 */
class LegacyChartFormat
{
	public static inline var FORMAT_063:String = '0.6.3';
	public static inline var FORMAT_073:String = '0.7.3';

	public static function isPsychV1(song:SwagSong):Bool
		return song != null && song.format != null && song.format.startsWith('psych_v1');

	/** psych_v1 -> legacy. No-op when the chart is already in a legacy format. */
	public static function toLegacy(song:SwagSong, targetFormat:String):Void
	{
		if (song == null)
			return;

		if (isPsychV1(song))
		{
			flipToRelativeLanes(song);
			trace('LegacyChartFormat: downgraded "${song.song}" from ${song.format} to $targetFormat');
		}
		song.format = targetFormat;
	}

	/** legacy -> psych_v1, so `PlayState` reads the chart the same way it reads any 1.0 chart. */
	public static function toPsychV1(song:SwagSong):Void
	{
		if (song == null || isPsychV1(song))
			return;

		var from:String = song.format;
		Song.convert(song);
		song.format = 'psych_v1_convert';
		trace('LegacyChartFormat: upgraded "${song.song}" from $from to psych_v1');
	}

	static function flipToRelativeLanes(song:SwagSong):Void
	{
		if (song.notes == null)
			return;

		// Extra Keys：列数从 mania 推（legacy 无 mania 字段时兜底 4 键）。
		var sectCols:Int = (song.mania != null) ? song.mania + 1 : 4;

		for (section in song.notes)
		{
			if (section == null || section.sectionNotes == null)
				continue;

			for (note in section.sectionNotes)
			{
				var data:Int = note[1];
				if (data < 0)
					continue; // legacy inline event, has no lane

				// Inverse of Song.convert(): keep the column, re-encode the side relative to the section.
				var mustPress:Bool = (data < sectCols);
				note[1] = (data % sectCols) + ((mustPress == section.mustHitSection) ? 0 : sectCols);
			}
		}
	}
}
