package ui;

import flixel.FlxSprite;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.group.FlxSpriteGroup;
import states.PlayState;
import backend.Conductor;

/**
 * 圆形倒计时 Shader —— 按 percent (0~1) 裁剪 circleThing 贴图为扇形进度环。
 * 逐字节移植自 Leather Engine：仅 fragment + #pragma header，无自定义 vertex。
 * vertex 交给 flixel 默认 FlxShader，它负责正确传递 alpha/colorTransform 等 attribute。
 */
class CircleShader extends flixel.system.FlxAssets.FlxShader
{
	@:glFragmentSource('
		#pragma header

		float PI = 3.14159265358;
		uniform float percent;

		vec2 rotate(vec2 v, float a) {
			float s = sin(a);
			float c = cos(a);
			mat2 m = mat2(c, -s, s, c);
			return m * v;
		}

		void main()
		{
			vec2 uv = openfl_TextureCoordv;
			vec4 spritecolor = flixel_texture2D(bitmap, openfl_TextureCoordv);

			uv -= vec2(0.5, 0.5);
			uv = rotate(uv, PI * 0.5);
			uv += vec2(0.5, 0.5);

			float percentAngle = (percent * 360.0) / (180.0 / PI);

			vec2 center = vec2(0.5, 0.5);
			float radius = 0.5;
			float angle = atan(uv.y - center.y, uv.x - center.x);
			float distance = length(uv - center);

			if ((angle + (PI)) > percentAngle)
			{
				spritecolor = vec4(0.0, 0.0, 0.0, 0.0);
			}

			gl_FragColor = spritecolor;
		}')

	public function new()
	{
		super();
		this.percent.value = [0.0];
	}
}

/**
 * 箭头倒计时：当两箭头间隔 ≥ 3秒 时，在屏幕中央偏上/偏下显示圆形进度圈 + 整数秒数字。
 *
 * 玩家过滤：只对"人类玩家控制侧"的箭头做倒计时。
 *   普通模式   → bf 侧（mustPress=true）
 *   playOpponent → dad 侧（mustPress=false）
 * 完全兼容 KathyEngine 的对手游玩特性，由 PlayState.isPlayerNote() 提供侧别判定。
 *
 * 逐行逻辑对齐 Leather Engine 原版 NoteTimer.hx，仅替换包名与玩家过滤函数。
 */
class NoteTimer extends FlxSpriteGroup
{
	private var instance:PlayState;
	private var timerText:FlxText;
	private var timerCircle:FlxSprite;
	private var circleShader:CircleShader = new CircleShader();

	public function new(instance:PlayState)
	{
		super();
		this.instance = instance;

		timerCircle = new FlxSprite().loadGraphic(backend.Paths.image("circleThing"));
		if (timerCircle != null && timerCircle.graphic != null)
		{
			timerCircle.antialiasing = true;
			timerCircle.shader = circleShader;
			timerCircle.scale *= 0.75;
			timerCircle.updateHitbox();
			add(timerCircle);
		}

		timerText = new FlxText(0, 0, 0, "");
		timerText.setFormat(backend.Paths.font("vcr.ttf"), 24, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(timerText);

		timerCircle.screenCenter();
		timerText.screenCenter();

		circleShader.percent.value = [0.0];
	}

	private var lastStartTime:Float = 1e10;

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		var timeTillNextNote:Float = 1e10;

		if (instance != null)
		{
			var show:Bool = false;
			if (Conductor.songPosition > 0)
			{
				for (daNote in instance.notes)
					if (daNote.exists && instance.isPlayerNote(daNote))
					{
						var timeDiff:Float = daNote.strumTime - Conductor.songPosition;
						if (timeDiff < timeTillNextNote)
							timeTillNextNote = timeDiff;
					}

				if (timeTillNextNote == 1e10)
					for (daNote in instance.unspawnNotes)
						if (instance.isPlayerNote(daNote))
						{
							var timeDiff:Float = daNote.strumTime - Conductor.songPosition;
							if (timeDiff < timeTillNextNote)
							{
								timeTillNextNote = timeDiff;
								break;
							}
						}

				show = timeTillNextNote != 1e10;
			}

			var targetAlpha:Float = 0.0;
			if (show)
			{
				if (lastStartTime == 1e10 && timeTillNextNote > 3000)
					lastStartTime = timeTillNextNote;

				if (lastStartTime != 1e10)
				{
					var secsLeft:Float = Math.ceil(timeTillNextNote * 0.001);
					var percent:Float = timeTillNextNote / lastStartTime;

					if (percent <= 0.0)
					{
						lastStartTime = 1e10;
						timerText.text = "";
						circleShader.percent.value = [0.0];
					}
					else
					{
						circleShader.percent.value = [percent];
						timerText.text = Std.int(secsLeft) + "";
					}
					updatePosition();
				}

				if (timeTillNextNote > 1000)
					targetAlpha = 1.0;
			}

			// 原版写法：分别 lerp text，再把 alpha 拷给 circle
			timerText.alpha = FlxMath.lerp(timerText.alpha, targetAlpha, elapsed * 5);
			timerCircle.alpha = timerText.alpha;
		}
	}

	private function updatePosition():Void
	{
		timerCircle.screenCenter();
		timerText.screenCenter();
		if (backend.ClientPrefs.data.downScroll)
		{
			timerCircle.y += 260;
			timerText.y += 260;
		}
		else
		{
			timerCircle.y -= 260;
			timerText.y -= 260;
		}
	}
}
