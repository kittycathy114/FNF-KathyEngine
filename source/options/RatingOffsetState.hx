package options;

import objects.Character;
import flixel.addons.display.shapes.FlxShapeCircle;
import flixel.input.touch.FlxTouch;

import states.stages.StageWeek1 as BackgroundStage;

class RatingOffsetState extends MusicBeatState
{
	static final UI_FONT:String = 'unifont-18.0.01.otf';

	var stageDirectory:String = 'week1';
	var boyfriend:Character;
	var gf:Character;

	public var camHUD:FlxCamera;
	public var camGame:FlxCamera;
	public var camOther:FlxCamera;

	var controllerPointer:FlxSprite;
	var _lastControllerMode:Bool = false;

	var beatText:FlxText;
	var beatTween:FlxTween;
	var zoomTween:FlxTween;
	var pulseRing:FlxShapeCircle;

	var titleText:FlxText;
	var currentText:FlxText;
	var feedbackText:FlxText;
	var statsText:FlxText;
	var statusText:FlxText;
	var hintText:FlxText;

	var bars:Array<FlxSprite> = [];
	var barStartX:Float = 0;
	var barBaselineY:Float = 470;
	var barMaxH:Float = 180;
	var barMaxMs:Float = 150;

	var samples:Array<Float> = [];
	var warmupBeats:Int = 4;

	var _colorEarly:FlxColor;
	var _colorLate:FlxColor;
	var _colorApply:FlxColor;
	var _colorAccent:FlxColor;

	override public function create()
	{
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Rating Offset Calibration", null);
		#end

		// Cameras
		camGame = initPsychCamera();

		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		FlxG.cameras.add(camHUD, false);

		camOther = new FlxCamera();
		camOther.bgColor.alpha = 0;
		FlxG.cameras.add(camOther, false);

		FlxG.camera.scroll.set(120, 130);

		persistentUpdate = true;
		FlxG.sound.pause();

		// Stage
		Paths.setCurrentLevel(stageDirectory);
		new BackgroundStage();

		// Characters
		gf = new Character(400, 130, 'gf');
		gf.x += gf.positionArray[0];
		gf.y += gf.positionArray[1];
		gf.scrollFactor.set(0.95, 0.95);
		boyfriend = new Character(770, 100, 'bf', true);
		boyfriend.x += boyfriend.positionArray[0];
		boyfriend.y += boyfriend.positionArray[1];
		add(gf);
		add(boyfriend);

		// Palette
		_colorEarly = FlxColor.fromRGB(52, 201, 235);   // cyan  - early
		_colorLate = FlxColor.fromRGB(229, 57, 53);      // red   - late
		_colorApply = FlxColor.fromRGB(124, 252, 0);     // green - applied
		_colorAccent = FlxColor.fromRGB(194, 75, 153);   // brand pink

		// Header background
		var headerBg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, 80, FlxColor.BLACK);
		headerBg.scrollFactor.set();
		headerBg.alpha = 0.55;
		headerBg.cameras = [camHUD];
		add(headerBg);

		titleText = new FlxText(0, 8, FlxG.width, Language.get("ratingoffset_cal_title"), 28);
		titleText.setFormat(Paths.font(UI_FONT), 28, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.scrollFactor.set();
		titleText.borderSize = 2;
		titleText.cameras = [camHUD];
		add(titleText);

		currentText = new FlxText(0, 46, FlxG.width, '', 22);
		currentText.setFormat(Paths.font(UI_FONT), 22, _colorAccent, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		currentText.scrollFactor.set();
		currentText.borderSize = 2;
		currentText.cameras = [camHUD];
		add(currentText);
		refreshCurrentText();

		// Pulse ring (beat cue)
		pulseRing = new FlxShapeCircle(0, 0, 110, {thickness: 8, color: _colorAccent}, FlxColor.TRANSPARENT);
		pulseRing.screenCenter();
		pulseRing.alpha = 0;
		pulseRing.cameras = [camHUD];
		add(pulseRing);

		// Beat text
		beatText = new FlxText(0, 0, FlxG.width, Language.get("ratingoffset_beat"), 64);
		beatText.setFormat(Paths.font(UI_FONT), 64, _colorAccent, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		beatText.scale.set(0.6, 0.6);
		beatText.screenCenter(X);
		beatText.y = 320;
		beatText.alpha = 0;
		beatText.cameras = [camHUD];
		add(beatText);

		// Big feedback text
		feedbackText = new FlxText(0, 150, FlxG.width, Language.get("ratingoffset_cal_warmup"), 48);
		feedbackText.setFormat(Paths.font(UI_FONT), 48, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		feedbackText.scrollFactor.set();
		feedbackText.borderSize = 3;
		feedbackText.cameras = [camHUD];
		add(feedbackText);

		// Histogram bars
		var barCount:Int = 24;
		var barW:Float = 16;
		var gap:Float = 4;
		var totalW:Float = barCount * (barW + gap) - gap;
		barStartX = (FlxG.width - totalW) / 2;
		for (i in 0...barCount)
		{
			var bar:FlxSprite = new FlxSprite(barStartX + i * (barW + gap), barBaselineY).makeGraphic(Math.round(barW), 1, FlxColor.WHITE);
			bar.origin.set(0, 1);
			bar.scale.y = 1;
			bar.visible = false;
			bar.cameras = [camHUD];
			add(bar);
			bars.push(bar);
		}

		// Stats + status + hint
		statsText = new FlxText(0, 490, FlxG.width, '', 22);
		statsText.setFormat(Paths.font(UI_FONT), 22, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		statsText.scrollFactor.set();
		statsText.borderSize = 2;
		statsText.cameras = [camHUD];
		add(statsText);
		refreshStats();

		statusText = new FlxText(0, 524, FlxG.width, '', 22);
		statusText.setFormat(Paths.font(UI_FONT), 22, _colorApply, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		statusText.scrollFactor.set();
		statusText.borderSize = 2;
		statusText.cameras = [camHUD];
		add(statusText);

		hintText = new FlxText(0, FlxG.height - 40, FlxG.width, '', 20);
		hintText.setFormat(Paths.font(UI_FONT), 20, FlxColor.GRAY, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hintText.scrollFactor.set();
		hintText.borderSize = 1.5;
		hintText.cameras = [camHUD];
		add(hintText);
		refreshHint();

		// Controller pointer
		controllerPointer = new FlxShapeCircle(0, 0, 20, {thickness: 0}, FlxColor.WHITE);
		controllerPointer.offset.set(20, 20);
		controllerPointer.screenCenter();
		controllerPointer.alpha = 0.6;
		controllerPointer.visible = controls.controllerMode;
		controllerPointer.cameras = [camHUD];
		add(controllerPointer);

		// Music (steady beat for tapping)
		Conductor.bpm = 128.0;
		FlxG.sound.playMusic(Paths.music('offsetSong'), 1, true);

		// Touch controls for mobile
		addTouchPad('NONE', 'A_B_C');
		addTouchPadCamera();

		super.create();
	}

	override public function update(elapsed:Float)
	{
		if(FlxG.gamepads.anyJustPressed(ANY)) controls.controllerMode = true;
		else if(FlxG.mouse.justPressed) controls.controllerMode = false;

		if(controls.controllerMode != _lastControllerMode)
		{
			FlxG.mouse.visible = !controls.controllerMode;
			controllerPointer.visible = controls.controllerMode;
			if(controls.controllerMode)
			{
				var mousePos = FlxG.mouse.getScreenPosition(camHUD);
				controllerPointer.x = mousePos.x;
				controllerPointer.y = mousePos.y;
			}
			refreshHint();
			_lastControllerMode = controls.controllerMode;
		}

		// Controller pointer movement
		if(controls.controllerMode)
		{
			for (gamepad in FlxG.gamepads.getActiveGamepads())
			{
				var ax = gamepad.getXAxis(LEFT_ANALOG_STICK);
				var ay = gamepad.getYAxis(LEFT_ANALOG_STICK);
				if(ax != 0 || ay != 0)
				{
					controllerPointer.x = Math.max(0, Math.min(FlxG.width, controllerPointer.x + ax * 1000 * elapsed));
					controllerPointer.y = Math.max(0, Math.min(FlxG.height, controllerPointer.y + ay * 1000 * elapsed));
				}
			}
		}

		// Sync music clock (same source as judgment logic)
		Conductor.songPosition = FlxG.sound.music.time;

		// ---- Input: register a tap sample ----
		var tapped:Bool = false;
		if(!controls.controllerMode)
		{
			if(FlxG.keys.justPressed.ANY &&
				!FlxG.keys.justPressed.ESCAPE &&
				!FlxG.keys.justPressed.BACKSPACE &&
				!FlxG.keys.justPressed.P &&
				!FlxG.keys.justPressed.R)
			{
				tapped = true;
			}
		}
		else
		{
			// gamepad: A = tap
			if(FlxG.gamepads.anyJustPressed(A)) tapped = true;
		}

		// touch / mobile: a touch counts as a tap sample only if it's outside the bottom
		// 25% of the screen AND not on any on-screen button (avoids accidental taps on the pad UI)
		// NOTE: touch.x/y are in window/device-pixel space, while FlxG.height is logical (720).
		// Scale everything to the window space so the dead-zone is actually 18% of the screen.
		var screenW:Float = FlxG.stage.stageWidth;
		var screenH:Float = FlxG.stage.stageHeight;
		var sx:Float = screenW / 1280.0;
		var sy:Float = screenH / 720.0;
		var bottomLimit:Float = screenH * 0.82;
		var touchIsSample:Bool = false;
		for (touch in FlxG.touches.justStarted())
		{
			if(touch.y < bottomLimit && !touchOverlapsPad(touch, sx, sy)) touchIsSample = true;
		}
		if(touchIsSample) tapped = true;

		if(tapped) registerTap();

		// ---- Apply (A on touchPad / P on keyboard / Y on gamepad) ----
		if(FlxG.keys.justPressed.P ||
			(touchPad != null && touchPad.buttonA.justPressed) ||
			(controls.controllerMode && FlxG.gamepads.anyJustPressed(Y)))
		{
			applyOffset();
		}

		// ---- Reset (C on touchPad / R on keyboard / X on gamepad) ----
		if(FlxG.keys.justPressed.R ||
			(controls.controllerMode && FlxG.gamepads.anyJustPressed(X)) ||
			(touchPad != null && touchPad.buttonC.justPressed))
		{
			resetSamples();
		}

		// ---- Back (B on touchPad / ESC or Android back / B on gamepad) ----
		if(controls.BACK ||
			(touchPad != null && touchPad.buttonB.justPressed) ||
			(controls.controllerMode && FlxG.gamepads.anyJustPressed(B)))
		{
			goBack();
		}

		super.update(elapsed);
	}

	var lastBeatHit:Int = -1;
	override public function beatHit()
	{
		super.beatHit();

		if(lastBeatHit == curBeat)
			return;
		lastBeatHit = curBeat;

		if(curBeat % 2 == 0)
		{
			boyfriend.dance();
			gf.dance();
		}

		if(curBeat % 4 == 0)
		{
			FlxG.camera.zoom = 1.1;
			if(zoomTween != null) zoomTween.cancel();
			zoomTween = FlxTween.tween(FlxG.camera, {zoom: 1}, 0.8, {ease: FlxEase.circOut, onComplete: function(twn:FlxTween)
				{
					zoomTween = null;
				}
			});

			// pulse ring
			pulseRing.scale.set(0.5, 0.5);
			pulseRing.alpha = 0.85;
			FlxTween.cancelTweensOf(pulseRing);
			FlxTween.tween(pulseRing.scale, {x: 1.8, y: 1.8}, 0.6, {ease: FlxEase.circOut});
			FlxTween.tween(pulseRing, {alpha: 0}, 0.6, {ease: FlxEase.sineIn});

			// beat text
			beatText.alpha = 1;
			beatText.y = 320;
			beatText.velocity.y = -150;
			if(beatTween != null) beatTween.cancel();
			beatTween = FlxTween.tween(beatText, {alpha: 0}, 1, {ease: FlxEase.sineIn, onComplete: function(twn:FlxTween)
				{
					beatTween = null;
				}
			});
		}
	}

	function registerTap()
	{
		var beatInterval:Float = 60000 / Conductor.bpm;
		var barInterval:Float = beatInterval * 4; // downbeat grid (matches the %4 visual pulse)
		// Match the visual beat reference: MusicBeatState drives beatHit from (songPosition - noteOffset)
		var pos:Float = Conductor.songPosition - ClientPrefs.data.noteOffset;
		if(pos < warmupBeats * beatInterval) return; // warm-up, let the player find the beat

		var nearestBeat:Float = Math.round(pos / barInterval) * barInterval;
		var delta:Float = pos - nearestBeat; // + = late, - = early
		var ms:Int = Math.round(delta);
		samples.push(ms);
		if(samples.length > 500) samples.shift();

		var early:Bool = ms < 0;
		var abs:Int = Std.int(Math.abs(ms));
		var label:String = early ? Language.get("ratingoffset_cal_early") : Language.get("ratingoffset_cal_late");
		feedbackText.text = '${label} ${early ? "-" : "+"}${abs}ms';
		feedbackText.color = early ? _colorEarly : _colorLate;
		feedbackText.scale.set(1.3, 1.3);
		FlxTween.cancelTweensOf(feedbackText.scale);
		FlxTween.tween(feedbackText.scale, {x: 1, y: 1}, 0.18, {ease: FlxEase.circOut});

		refreshBars();
		refreshStats();
	}

	function refreshBars()
	{
		var count:Int = bars.length;
		var start:Int = samples.length - count;
		for (i in 0...count)
		{
			var bar = bars[i];
			var idx:Int = start + i;
			if(idx >= 0 && idx < samples.length)
			{
				var v:Float = samples[idx];
				var h:Float = Math.min(barMaxH, (Math.abs(v) / barMaxMs) * barMaxH);
				bar.scale.y = Math.max(1, h);
				bar.color = v < 0 ? _colorEarly : _colorLate;
				bar.visible = true;
			}
			else
			{
				bar.visible = false;
			}
		}
	}

	function refreshStats()
	{
		var avg:Float = 0;
		if(samples.length > 0)
		{
			var sum:Float = 0;
			for (s in samples) sum += s;
			avg = sum / samples.length;
		}
		var avgMs:Int = Math.round(avg);
		var suggested:Int = samples.length > 0 ? clamp(Math.round(avg), -180, 180) : 0;
		statsText.text = '${Language.get("ratingoffset_cal_samples")}: ${samples.length}    |    ${Language.get("ratingoffset_cal_avg")}: ${avgMs >= 0 ? "+" : ""}${avgMs}ms    |    ${Language.get("ratingoffset_cal_suggested")}: ${suggested >= 0 ? "+" : ""}${suggested}ms';
	}

	function applyOffset()
	{
		if(samples.length == 0) return;
		var sum:Float = 0;
		for (s in samples) sum += s;
		var avg:Float = sum / samples.length;
		var val:Int = clamp(Math.round(avg), -180, 180);
		ClientPrefs.data.ratingOffset = val;
		ClientPrefs.saveSettings();
		refreshCurrentText();

		statusText.text = Language.get("ratingoffset_cal_applied", [Std.string(val)]);
		statusText.alpha = 1;
		FlxTween.cancelTweensOf(statusText);
		FlxTween.tween(statusText, {alpha: 0}, 1.2, {startDelay: 1.2, ease: FlxEase.sineIn});
	}

	function resetSamples()
	{
		samples = [];
		refreshBars();
		refreshStats();
		feedbackText.text = Language.get("ratingoffset_cal_warmup");
		feedbackText.color = FlxColor.WHITE;

		statusText.text = Language.get("ratingoffset_cal_cleared");
		statusText.alpha = 1;
		FlxTween.cancelTweensOf(statusText);
		FlxTween.tween(statusText, {alpha: 0}, 1.0, {startDelay: 0.8, ease: FlxEase.sineIn});
	}

	function refreshCurrentText()
	{
		currentText.text = Language.get("ratingoffset_cal_current", [Std.string(ClientPrefs.data.ratingOffset)]);
	}

	function goBack()
	{
		if(zoomTween != null) zoomTween.cancel();
		if(beatTween != null) beatTween.cancel();

		persistentUpdate = false;
		MusicBeatState.switchState(new options.OptionsState());
		if(OptionsState.onPlayState)
		{
			if(ClientPrefs.data.pauseMusic != 'None')
				FlxG.sound.playMusic(Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic)));
			else
				FlxG.sound.music.volume = 0;
		}
		else FlxG.sound.playMusic(Paths.menuMusicAudio());
		FlxG.mouse.visible = false;
	}

	function refreshHint()
	{
		var tapKey:String = controls.controllerMode ? "A" : Language.get("ratingoffset_cal_anykey");
		var applyKey:String = controls.controllerMode ? "Y" : (controls.mobileC ? "A" : "P");
		var resetKey:String = controls.controllerMode ? "X" : (controls.mobileC ? "C" : "R");
		var backKey:String = controls.controllerMode ? "B" : (controls.mobileC ? "B" : "ESC");
		hintText.text = '${tapKey} = ${Language.get("ratingoffset_cal_tap")}  •  ${applyKey} = ${Language.get("ratingoffset_cal_apply")}  •  ${resetKey} = ${Language.get("ratingoffset_cal_reset")}  •  ${backKey} = ${Language.get("ratingoffset_cal_back")}';
	}

	function clamp(v:Float, min:Float, max:Float):Int
	{
		return Std.int(Math.max(min, Math.min(max, v)));
	}

	// Returns true if the touch lands on any on-screen touchPad button,
	// so a tap there isn't mistaken for a beat-tap sample.
	// sx/sy scale the button's logical (1280x720) coords into window space to match touch.x/y.
	function touchOverlapsPad(touch:FlxTouch, sx:Float, sy:Float):Bool
	{
		if(touchPad == null) return false;
		var buttons = [touchPad.buttonA, touchPad.buttonB, touchPad.buttonC];
		for (btn in buttons)
		{
			var bx = btn.x * sx;
			var by = btn.y * sy;
			var bw = btn.width * sx;
			var bh = btn.height * sy;
			if(touch.x >= bx && touch.x <= bx + bw &&
				touch.y >= by && touch.y <= by + bh)
			{
				return true;
			}
		}
		return false;
	}
}
