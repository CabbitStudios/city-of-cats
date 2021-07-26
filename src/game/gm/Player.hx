package gm;

import h3d.Vector;
import h2d.Flow;
import h2d.filter.Outline;

enum InputCommand {
	Jump;
	Vault;
}

/**
	SamplePlayer is an Entity with some extra functionalities:
	- falls with gravity
	- has basic level collisions
	- controllable (using gamepad or keyboard)
	- some squash animations, because it's cheap and they do the job
**/
class Player extends gm.Entity {
	var anims = Assets.catDict;

	var ca:ControllerAccess;
	var walkSpeed = 0.;
	var commands:Map<InputCommand, Float> = new Map();
	var wallCurrentlyTouching:Null<Int> = null;

	var isWallClinging(get, never):Bool;
	var seenStoryMarks:Map<String, Int> = new Map();

	function get_isWallClinging():Bool {
		return isAlive() && wallCurrentlyTouching != null && cd.has("wallClinging");
	}

	public function new() {
		super(5, 5);

		// Start point using level entity "PlayerStart"
		var start = level.data.l_Entities.all_PlayerStart[0];
		if (start != null)
			setPosCase(start.cx, start.cy);

		// Misc inits
		frictX = 0.84;
		frictY = 0.94;

		// Camera tracks this
		camera.trackEntity(this, true);
		camera.clampToLevelBounds = true;

		// Init controller
		ca = App.ME.controller.createAccess("entitySample");
		ca.setLeftDeadZone(0.3);

		// Placeholder display
		spr.set(Assets.cat);
		spr.anim.registerStateAnim(anims.wallCling, 20, 1, () -> isWallClinging);
		spr.anim.registerStateAnim(anims.fall, 10, 1, () -> !onGround);
		spr.anim.registerStateAnim(anims.walk, 2, 0.5, () -> M.fabs(dx) > 0.01);
		spr.anim.registerStateAnim(anims.idle, 0);
		spr.filter = new h2d.filter.Outline(.5, 0xaec6cf);
	}

	override function dispose() {
		super.dispose();
		ca.dispose(); // don't forget to dispose controller accesses
	}

	override function onTouchWall(wallDirection:Int) {
		super.onTouchWall(wallDirection);
		wallCurrentlyTouching = wallDirection;
	}

	override function onLand(cHei:Float) {
		super.onLand(cHei);

		if (cHei > 2)
			setSquashY(0.8 - M.fmax(0.2, cHei / 30));

		fx.dirt(centerX, bottom, M.fmin(8, cHei) * 5);
	}

	function clearWallClinging() {
		cd.unset("wallClinging");
	}

	/**
		Control inputs are checked at the beginning of the frame.
		VERY IMPORTANT NOTE: because game physics only occur during the `fixedUpdate` (at a constant 30 FPS), no physics increment should ever happen here! What this means is that you can SET a physics value (eg. see the Jump below), but not make any calculation that happens over multiple frames (eg. increment X speed when walking).
	**/
	override function preUpdate() {
		super.preUpdate();

		walkSpeed = 0;
		if (onGround)
			cd.setS("recentlyOnGround", 0.1); // allows "just-in-time" jumps

		if (!ca.locked() && !isChargingAction("vault")) {
			// Jump
			if (ca.aPressed() || ca.isKeyboardPressed(K.SPACE)) {
				queueCommand(Jump);
			}

			// Walk
			if (!App.ME.anyInputHasFocus() && ca.leftDist() > 0) {
				// As mentioned above, we don't touch physics values (eg. `dx`) here. We just store some "requested walk speed", which will be applied to actual physics in fixedUpdate.
				walkSpeed = Math.cos(ca.leftAngle()) * ca.leftDist();

				if (cd.has("directionLocked")) {
					walkSpeed = M.sign(walkSpeed) == M.sign(dx) ? walkSpeed : 0;
				} else {
					dir = M.radDistance(0, ca.leftAngle()) <= M.PIHALF ? 1 : -1;
				}

				if (dir == wallCurrentlyTouching && !onGround)
					cd.setS("wallClinging", 0.1);
			}

			if (ifQueuedRemove(Jump)) {
				if (recentlyOnGround) {
					chargeAction("jump", 0.08, () -> {
						dy = -0.45;
						setSquashX(0.6);
						clearRecentlyOnGround();
					});
				}

				if (isWallClinging && !recentlyOnGround) {
					chargeAction("jump", 0.08, () -> {
						dy = -0.5;
						dx = 0.45 * -wallCurrentlyTouching;
						setSquashY(0.6);
						clearWallClinging();
						cd.setS("directionLocked", 0.4);
						dir = -wallCurrentlyTouching;
					});
				}
			}
		}
	}

	override function update() {
		super.update();

		if (onGround && M.fabs(dx) > 0.01 && !cd.has("dirtJet")) {
			fx.dirt(centerX, bottom, rnd(1, 3));
			cd.setS("dirtJet", 0.1);
		}

		for (mark in level.data.l_Entities.all_Story_Mark) {
			if (seenStoryMarks.exists(mark.identifier))
				continue;

			if (Lib.rectangleOverlaps(mark.pixelX, mark.pixelY, mark.width, mark.height, centerX, centerY, wid, hei)) {
				say(mark.f_Story_Text, mark.f_Color_int);
				seenStoryMarks.set(mark.identifier, 0);
			}
		}
	}

	override function fixedUpdate() {
		wallCurrentlyTouching = null;
		super.fixedUpdate();

		// If we're clinging against a wall and we are moving upwards then slow down fast
		if (isWallClinging && dy < 0)
			dy *= 0.9;

		// Gravity
		// When clinging we move much slower and slide down
		if (!onGround)
			dy += isWallClinging ? 0.007 : 0.05;

		// Apply requested walk movement
		if (walkSpeed != 0) {
			var speed = 0.045;

			dx += walkSpeed * speed;
		} else if (!isChargingAction("jump"))
			dx *= 0.6;
	}

	override function postUpdate() {
		super.postUpdate();

		if (saying != null) {
			saying.scaleX += (1 - saying.scaleX) * M.fmin(1, 0.3 * tmod);
			saying.scaleY += (1 - saying.scaleY) * M.fmin(1, 0.3 * tmod);
			saying.x = Std.int(sprX - saying.outerWidth * 0.5 * saying.scaleX);
			saying.y = Std.int(sprY - saying.outerHeight * saying.scaleY - hei - 10);
			if (!cd.has("keepSaying")) {
				saying.alpha -= 0.03 * tmod;
				if (saying.alpha <= 0)
					clearSaying();
			}
		}
	}

	/**
	 * Queue a command for `duration` in seconds
	 * @param cmd 
	 * @param duration = 0.15 
	 */
	function queueCommand(cmd:InputCommand, duration = 0.15) {
		if (isAlive())
			commands.set(cmd, duration);
	}

	function clearCommand(?cmd:InputCommand) {
		if (cmd == null)
			commands = new Map();
		else
			commands.remove(cmd);
	}

	function isQueued(cmd:InputCommand) {
		return isAlive() && commands.exists(cmd);
	}

	function ifQueuedRemove(cmd:InputCommand):Bool {
		return if (isQueued(cmd)) {
			clearCommand(cmd);
			true;
		} else false;
	}

	function say(str, color) {
		clearSaying();

		saying = new h2d.Flow();
		game.scroller.add(saying, Const.DP_UI);
		saying.scaleX = 2;
		saying.scaleY = 0;
		saying.layout = Vertical;
		saying.horizontalAlign = Middle;
		saying.verticalSpacing = 3;

		var tf = new h2d.Text(Assets.fontPixel, saying);
		tf.maxWidth = 120;
		tf.text = str;
		tf.textColor = color;

		cd.setS("keepSaying", 2.5 + str.length * 0.05);

		var s = Assets.tiles.h_get(Assets.tilesDict.sayLine, saying);
		s.colorize(color);
	}

	function clearSaying() {
		if (saying != null) {
			saying.remove();
			saying = null;
		}
	}

	var saying:Flow;
}
