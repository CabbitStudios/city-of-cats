package gm;

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

			if ((ca.rbPressed() || ca.isKeyboardPressed(K.F)) && !cd.has("laserShot")) {
				cd.setS("laserShot", 0.3);
				fx.laser(centerX, centerY - 2, dir);
			}

			// Walk
			if (!App.ME.anyInputHasFocus() && ca.leftDist() > 0) {
				// As mentioned above, we don't touch physics values (eg. `dx`) here. We just store some "requested walk speed", which will be applied to actual physics in fixedUpdate.
				walkSpeed = Math.cos(ca.leftAngle()) * ca.leftDist();

				if (cd.has("directionLocked")) {
					walkSpeed = M.sign(walkSpeed) == M.sign(dx) ? walkSpeed : 0;
				}

				if (!cd.has("directionLocked"))
					dir = M.radDistance(0, ca.leftAngle()) <= M.PIHALF ? 1 : -1;

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

				if (isWallClinging) {
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
}