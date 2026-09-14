package backend;

import haxe.Timer;

/**
 * 帧率无关的亚帧连续音频时钟。
 *
 * 原理：
 * - 锚点：每次 PlayState.update 帧首调用 [tick]，把"当前 OpenAL 音频位置"
 *   锚定到 haxe.Timer.stamp()（秒级浮点，跨平台，android target 走
 *   CLOCK_MONOTONIC 等价物，精度 ~1μs）的某一时刻。
 * - 外推：[getPosition] 返回 anchorAudioTime + (now - anchorSysTime) * 1000 * rate，
 *   其中 now 是 Timer.stamp()（秒），rate 为 playbackRate。这样即使帧间隔
 *   8ms（120fps），任意亚帧时刻都能拿到 ~μs 精度的"虚拟连续音频时间"，
 *   完全不受帧率影响。
 *
 * 边界处理：
 * - pause：[pause] 冻结锚点，[getPosition] 返回冻结时刻的音频时间
 * - resume：[resume] 重新锚点，避免跨暂停外推累积误差
 * - 切歌 / pitch 突变：[reset] 清空锚点，下一次 tick 重新建立
 * - OpenAL 量化：只有锚点那一次采样受 OpenAL 精度限制（~ms 级），
 *   后续全部走系统单调时钟外推，量化误差被"稀释"到锚点间隔之内
 */
class AudioClock
{
	static var anchorSysTime:Float = 0;
	static var anchorAudioTime:Float = 0;
	static var rate:Float = 1.0;
	static var lastRate:Float = 1.0;
	static var paused:Bool = false;
	static var pausedAudioTime:Float = 0;
	static var hasAnchor:Bool = false;

	/**
	 * 每帧调用一次（在 PlayState.update 帧首、Conductor 推进之前）。
	 *
	 * 锚定策略（关键修复：消除桌面端"更卡"）：
	 * - 旧版本在稳态下每帧都重新锚定 OpenAL music.time。桌面 OpenAL 的
	 *   music.time 是 buffer 粒度的跳变值（每 10~30ms 跳一次，取决于驱动），
	 *   帧帧重锚会让 AnchorAudioTime 帧帧抖动，外推位置随之抖动，桌面端"更卡"。
	 * - 新版本：只在 rate 突变 / 锚点缺失时重锚；稳态下沿用上一帧锚点，
	 *   仅用 haxe.Timer.stamp()（系统单调时钟，~μs 精度）做外推。
	 *   OpenAL 自身的 ms 级漂移在两次重锚之间累积，由下次 rate 突变 /
	 *   暂停恢复 / 切歌（reset）时一次性纠正，不进入稳态帧，桌面端平滑。
	 *
	 * @param audioTime 当前 OpenAL 音频位置（FlxG.sound.music.time，单位 ms）
	 * @param playbackRate 当前倍速
	 */
	public static function tick(audioTime:Float, playbackRate:Float):Void
	{
		// audioTime 可能为 0（music 刚 seek 到 0）或异常负值（OpenAL 在 pause/resume 瞬间偶发回跳）
		// 统一当作"已知真实位置"刷新锚点，让 getPosition() 仍能外推
		if (audioTime != audioTime || audioTime < 0)
			audioTime = 0;

		if (playbackRate != lastRate || !hasAnchor)
		{
			// rate 突变或无锚点：重新锚点，吸收 OpenAL 当前真实位置
			anchorSysTime = Timer.stamp();
			anchorAudioTime = audioTime;
			rate = playbackRate;
			lastRate = playbackRate;
			hasAnchor = true;
			return;
		}

		// 稳态：沿用现有锚点，仅刷新 rate 引用（避免后续读 rate 时取到旧值）。
		// OpenAL 漂移在稳态下不吸收，由下次 rate 突变 / resume / reset 一次性纠正。
		rate = playbackRate;
	}

	/**
	 * 获取亚帧连续的音频时间（ms），与帧率无关。
	 * 在任意调用点（包括 Note.followStrumNote）直接调用。
	 */
	public static function getPosition():Float
	{
		if (paused)
			return pausedAudioTime;
		if (!hasAnchor)
			return 0;

		var now:Float = Timer.stamp();
		var deltaMs:Float = (now - anchorSysTime) * 1000;
		return anchorAudioTime + deltaMs * rate;
	}

	/** 暂停：冻结当前音频时间，[getPosition] 返回冻结值 */
	public static function pause():Void
	{
		if (!hasAnchor) return;
		pausedAudioTime = getPosition();
		paused = true;
	}

	/** 恢复：重新锚点（调用方需保证 audioTime 是当前真实位置） */
	public static function resume(audioTime:Float, playbackRate:Float):Void
	{
		paused = false;
		hasAnchor = true;
		anchorSysTime = Timer.stamp();
		anchorAudioTime = audioTime;
		rate = playbackRate;
		lastRate = playbackRate;
	}

	/** 切歌 / 重新加载音乐时调用，清空锚点 */
	public static function reset():Void
	{
		hasAnchor = false;
		paused = false;
		anchorSysTime = 0;
		anchorAudioTime = 0;
		rate = 1.0;
		lastRate = 1.0;
	}
}
