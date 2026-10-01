class_name Tuning
extends Resource
## All the gameplay numbers in one place.
## Open res://tuning.tres in the Godot editor to change them without touching code.

@export_group("Runner")
## Normal running speed, in meters per second.
@export var runner_speed := 4.0
## Speed multiplier for a moment right after the Runner is hit.
@export var runner_hit_boost_mult := 1.5
@export var runner_hit_boost_time := 1.8
@export var runner_window_vault_time := 0.55
@export var runner_barricade_vault_time := 0.75

@export_group("Hunter")
## 4.6 is 115% of the Runner's 4.0.
@export var hunter_speed := 4.6
@export var hunter_lunge_mult := 1.6
@export var hunter_lunge_time := 0.35
## How close the Runner must be (in meters) for a swing to land.
@export var hunter_attack_range := 2.2
## How long the Hunter is slowed after landing a hit.
@export var hunter_hit_cooldown := 2.7
## How long the Hunter is slowed after missing.
@export var hunter_miss_cooldown := 1.5
@export var hunter_cooldown_speed_mult := 0.35
@export var hunter_window_vault_time := 1.6
@export var hunter_break_time := 2.6
@export var hunter_stun_time := 2.0

@export_group("Rounds")
## A round ends here even if the Runner is never caught (seconds).
@export var round_time_cap := 300.0
@export var countdown_time := 3.0
## Survival times closer than this count as a draw.
@export var tie_window := 1.0
