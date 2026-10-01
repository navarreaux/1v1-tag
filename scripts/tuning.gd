class_name Tuning
extends Resource
## All the gameplay numbers in one place.
## Open res://tuning.tres in the Godot editor to change them without touching code.
## Defaults are modeled on the chase in Dead by Daylight (approximate, from public info).

@export_group("Runner movement")
## Speed while holding Shift, in meters per second.
@export var runner_sprint_speed := 4.0
## Speed without Shift.
@export var runner_walk_speed := 2.26
## Speed while holding Ctrl.
@export var runner_crouch_speed := 1.13
## Speed multiplier for a moment right after the Runner is hit.
@export var runner_hit_boost_mult := 1.5
@export var runner_hit_boost_time := 1.8

@export_group("Runner vaults")
## A fast vault needs Shift held for at least this long, heading straight at the opening.
@export var fast_vault_runup := 0.35
## How far off straight-on (in degrees) you can be and still fast vault.
@export var fast_vault_max_angle := 40.0
@export var window_vault_fast := 0.5
@export var window_vault_medium := 0.9
@export var window_vault_slow := 1.7
@export var barricade_vault_fast := 0.5
@export var barricade_vault_medium := 0.9
@export var barricade_vault_slow := 1.3

@export_group("Window blocking")
## After the Runner vaults the same window this many times, it gets blocked for them.
@export var window_block_vaults := 3
@export var window_block_time := 15.0

@export_group("Hunter")
## 4.6 is 115% of the Runner's sprint.
@export var hunter_speed := 4.6
@export var hunter_lunge_mult := 1.6
## A tap gives the shortest lunge; holding the button stretches it up to the max.
@export var hunter_lunge_min := 0.3
@export var hunter_lunge_max := 0.6
## How close the Runner must be (in meters) for a swing to land.
@export var hunter_attack_range := 2.2
## How long the Hunter is slowed while wiping after a hit.
@export var hunter_hit_cooldown := 2.7
## How long the Hunter is slowed after a miss.
@export var hunter_miss_cooldown := 1.5
@export var hunter_cooldown_speed_mult := 0.35
@export var hunter_window_vault_time := 1.7
@export var hunter_break_time := 2.6
@export var hunter_stun_time := 2.0

@export_group("Chase and bloodlust")
## The Hunter is "in chase" while they can see the Runner within this distance.
@export var chase_sight_range := 30.0
## The chase ends after this many seconds without seeing the Runner.
@export var chase_lose_time := 8.0
## Seconds of chase before each bloodlust tier (I, II, III).
@export var bloodlust_tier_times := PackedFloat32Array([15.0, 25.0, 35.0])
## Extra speed (m/s) at each bloodlust tier.
@export var bloodlust_tier_speed := PackedFloat32Array([0.2, 0.4, 0.6])

@export_group("Tracking")
## The Runner's heartbeat starts when the Hunter is this close.
@export var terror_radius := 32.0
## How long scratch marks and blood stay visible to the Hunter.
@export var scratch_mark_time := 8.0
@export var blood_time := 10.0

@export_group("Rounds")
## A round ends here even if the Runner is never caught (seconds).
@export var round_time_cap := 300.0
@export var countdown_time := 3.0
## Survival times closer than this count as a draw.
@export var tie_window := 1.0
