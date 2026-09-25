--[[
	Config
	All balance / tuning values of THE DOPPELGÄNGER OBBY live here.
	Change numbers here - no gameplay logic reads hard-coded values.
]]

local Config = {}

---------------------------------------------------------------------------
-- Player
---------------------------------------------------------------------------
Config.PLAYER_WALKSPEED = 16
Config.PLAYER_JUMP_HEIGHT = 7.2
Config.RESPAWN_DELAY = 1.6 -- seconds between "YOU DIED" and respawn at checkpoint

---------------------------------------------------------------------------
-- Doppelgänger (all roles)
---------------------------------------------------------------------------
Config.DOPPELGANGER_SPEED = 16
Config.DOPPEL_RESPAWN_DELAY = 1.4
Config.KILL_Y_OFFSET = -40 -- anything below level origin + this dies (players and doppels)
Config.DOPPEL_GRAVITY = 196.2
Config.DOPPEL_AURA = true -- small particle aura (disable for very low-end devices)

-- Follower (Level 1 / 3): walks your exact footsteps a few studs behind you
Config.FOLLOW_DISTANCE = 6
Config.FOLLOW_DELAY = 0.25
Config.FOLLOW_CATCHUP_MULTIPLIER = 1.5
Config.FOLLOW_REGROUP_AFTER = 2.5 -- blocked this long -> glitch-teleport back to you

-- Shadow: records you and replays your moves with a delay
Config.SHADOW_DELAY = 0.7
Config.SHADOW_SAMPLE_RATE = 15 -- snapshots per second
Config.SHADOW_CATCHUP_MULTIPLIER = 1.6 -- playback speed when the shadow is behind schedule
Config.SHADOW_PHASE_AFTER = 3 -- blocked this long -> shadow phases through (unless level disables it)
Config.SHADOW_BUFFER_SECONDS = 30
Config.FREEZE_DURATION = 8 -- ability: hold your shadow in place
Config.FREEZE_COOLDOWN = 1.5

-- Rival: races you to the finish
Config.RIVAL_SPEED_MULTIPLIER = 1.1
Config.RIVAL_START_DELAY = 1.5
Config.RIVAL_RESTART_DELAY = 1.0 -- head start you get after respawning
Config.RIVAL_PAUSE_CHANCE = 0.12 -- chance to hesitate at a node
Config.RIVAL_PAUSE_TIME = { 0.35, 1.1 }
Config.RIVAL_MISJUMP_CHANCE = 0.07 -- chance to jump short and fall
Config.RIVAL_HAZARD_IGNORE_CHANCE = 0.12 -- chance to run into an active hazard
Config.RIVAL_RUBBERBAND_AHEAD = 45 -- studs ahead of the player before the rival slows down
Config.RIVAL_RUBBERBAND_BEHIND = 30 -- studs behind before it speeds up
Config.RIVAL_BLOCKED_TIMEOUT = 2.5
Config.RIVAL_STATUS_MARGIN = 5 -- studs used for AHEAD / BEHIND hysteresis
Config.JUMP_RANGE = 13 -- max distance the rival jumps to a moving platform

-- Ally / Troll (Phase 6)
Config.ALLY_SEND_RANGE = 55
Config.ALLY_SEND_CONE = 0.35 -- dot product with player's look direction
Config.ALLY_GLIDE_SPEED = 26
Config.ALLY_COOLDOWN = 0.6
Config.TROLL_BETRAY_CHANCE = 0.55 -- first betrayal chance per command while disguised
Config.TROLL_REVEALED_BETRAY_CHANCE = 0.6
Config.TROLL_HESITATION = 0.45 -- the "tell": it always waits a moment before obeying
Config.TROLL_GLITCH_INTERVAL = { 6, 11 }
Config.TROLL_LURE_INTERVAL = { 8, 14 }

---------------------------------------------------------------------------
-- Role randomizer (used by levels with Role = { Pool = {...} })
---------------------------------------------------------------------------
Config.ROLE_CHANCES = {
	Rival = 35,
	Shadow = 35,
	Ally = 20,
	Troll = 10,
}

---------------------------------------------------------------------------
-- Obstacles / interaction
---------------------------------------------------------------------------
Config.INTERACTION_RATE = 30 -- overlap checks per second
Config.HAZARD_GRACE = 0.12 -- lasers become lethal this long after turning on
Config.LASER_WARNING = 0.5 -- flicker before a cycling laser turns on
Config.TRAP_WARNING = 0.6 -- flicker before a trap laser turns on
Config.DOOR_TWEEN_TIME = 0.45
Config.FALLING_PLATFORM_DELAY = 0.45
Config.FALLING_PLATFORM_RESPAWN = 3
Config.DOPPEL_ONLY_HINT_COOLDOWN = 6

---------------------------------------------------------------------------
-- Rewards
---------------------------------------------------------------------------
Config.LEVEL_REWARD = { Coins = 50, XP = 100 }
Config.REPLAY_MULTIPLIER = 0.4 -- replays of completed levels
Config.CHECKPOINT_REWARD = 5 -- coins, first playthrough only
Config.NO_DEATH_BONUS = { Coins = 25, XP = 40 }
Config.TIME_BONUS = { Coins = 20, XP = 30 } -- finished under ParTime
Config.PERFECT_BONUS = { Coins = 40, XP = 60 } -- no deaths AND under ParTime
Config.RIVAL_WIN_BONUS = { Coins = 30, XP = 40 } -- beat the Rival to the finish
Config.DUO_PARTNER_MULTIPLIER = 0.8
Config.BETRAYAL_TRAITOR_BONUS = { Coins = 60, XP = 60 }
Config.BETRAYAL_DEATHS_REQUIRED = 3

---------------------------------------------------------------------------
-- Progression
---------------------------------------------------------------------------
Config.XP_PER_LEVEL = 200 -- XP needed for level 1 -> 2
Config.XP_LEVEL_GROWTH = 50 -- each next level needs this much more

---------------------------------------------------------------------------
-- World layout
---------------------------------------------------------------------------
Config.LOBBY_POSITION = Vector3.new(0, 0, 0)
Config.LEVEL_ORIGIN = Vector3.new(0, 0, 900) -- slot 0 origin; slots are spaced along +Z
Config.LEVEL_SLOT_SPACING = 320
Config.RESULTS_AUTO_RETURN = 45 -- seconds on the results screen before auto-return to lobby
Config.LOBBY_DOPPEL = true -- your doppelgänger follows you around the lobby too

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
Config.DATASTORE_NAME = "DoppelgangerObby_Profiles_v1"
Config.LEADERBOARD_STORE_PREFIX = "DoppelgangerObby_BestTime_v1_L"
Config.LEADERBOARD_REFRESH = 90
Config.AUTOSAVE_INTERVAL = 120
Config.SESSION_LOCK_TIMEOUT = 300
Config.SESSION_LOCK_RETRIES = 5
Config.SESSION_LOCK_WAIT = 3
Config.DATASTORE_RETRIES = 4

---------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------
Config.DEBUG_IN_STUDIO = true -- debug UI + chat commands automatically enabled in Studio
Config.ADMIN_USER_IDS = {} -- user ids allowed to use debug tools in live servers

return Config
