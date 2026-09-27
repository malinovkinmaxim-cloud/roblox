--[[
	GameConfig - every tunable number of BRAINROT SURVIVORS in one place.

	Coordinates inside a run are 2D "arena coordinates" (x, z) in studs, relative to
	Arena.Center. The ground is flat (Arena.GroundY), so the simulation never needs Y.
]]

local GameConfig = {}

GameConfig.GameName = "BRAINROT SURVIVORS"
GameConfig.Version = 1

-- Server simulation / network
GameConfig.Sim = {
	Rate = 20, -- fixed simulation steps per second
	SnapshotEvery = 2, -- a network frame every N steps (10 Hz)
	MaxStepsPerHeartbeat = 3, -- a lagging server skips time instead of spiralling
	MaxEnemiesPerRun = 240,
	GlobalEnemyBudget = 1000, -- shared by all runs on one server (per-run cap shrinks when crowded)
	MaxGems = 180,
	MaxPickups = 24,
	MaxProjectiles = 120,
	MaxEnemyProjectiles = 70,
	MaxAllies = 6,
	GridCell = 8, -- spatial hash cell size (studs)
	CoordScale = 100, -- positions are sent as int16 of (studs * CoordScale): +-327 studs
	MaxHitsPerFrame = 90, -- damage numbers per network frame (the rest still counts)
}

GameConfig.Arena = {
	Center = Vector3.new(0, 0, 0),
	GroundY = 0, -- top of the ground
	HalfSize = 240, -- playable square is [-HalfSize, HalfSize] on x and z
	SpawnRadiusMin = 58, -- enemies appear just outside the camera view
	SpawnRadiusMax = 74,
	RelocateDistance = 105, -- enemies left further behind than this are moved ahead of the player
	StartOffsets = { -- where runs start (a random one, so ghosts of other players spread out)
		Vector3.new(0, 0, 0),
		Vector3.new(-60, 0, -40),
		Vector3.new(60, 0, -40),
		Vector3.new(-60, 0, 50),
		Vector3.new(60, 0, 50),
	},
}

GameConfig.Lobby = {
	Center = Vector3.new(0, 0, 400),
}

GameConfig.Player = {
	BaseHP = 100,
	BaseWalkSpeed = 17,
	MaxWalkSpeed = 34,
	Radius = 1.6, -- contact radius against enemies
	HurtCooldown = 0.45, -- invulnerability after taking contact damage
	PickupRange = 8,
	ReviveInvulnerable = 2.5,
	ReviveHeal = 0.6, -- fraction of max HP
	MaxWeapons = 6, -- + meta upgrade "Weapon Slot"
	MaxPassives = 8,
}

GameConfig.Run = {
	Length = 15 * 60, -- soft end; the final boss spawns at FinalBossAt
	FinalBossAt = 13 * 60,
	LevelUpAutoPick = 60, -- safety net: a choice nobody makes is auto-picked after this
	DeathReviveWindow = 10, -- seconds to accept a Robux revive before RUN OVER
	RecentDamageWindow = 1.0,
	StandStillSecret = 6.7, -- SIGMA STARE secret
	FirstEnemyDelay = 0.6,
}

-- XP needed to go from `level` to `level + 1`
function GameConfig.XPNeeded(level: number): number
	if level < 20 then
		return 5 + (level - 1) * 8
	elseif level < 40 then
		return 170 + (level - 20) * 26
	end
	return 700 + (level - 40) * 42
end

GameConfig.LevelUp = {
	Choices = 3,
	RareChance = 0.035, -- per card, multiplied by Luck
	NewWeaponWeight = 1.0,
	WeaponLevelWeight = 1.35,
	PassiveWeight = 1.0,
	FreeRerolls = 1,
	SkipCoins = 5,
}

GameConfig.Drops = {
	GemTiers = { 1, 5, 25, 100 }, -- tier thresholds by value
	HealAmount = 30, -- Pizza pickup
	NukeRadius = 70,
	MagnetDuration = 1.2,
	BaseItemChance = 0.003, -- per regular kill (x Luck)
	CoinChance = 0.035,
	CrateEvery = 38, -- a loot crate appears near the player every N seconds
}

GameConfig.Rewards = {
	PerMinute = 12,
	PerKill = 1 / 40,
	PerLevel = 3,
	PerBoss = 60,
	Victory = 300,
	FirstRunOfDay = 50,
	CoinDropValue = 1, -- coins inside a coin pickup (x Greed)
	CoinBagValue = 8,
	BrainXPPerMinute = 20,
	BrainXPPerKill = 1 / 10,
}

GameConfig.Save = {
	AutosaveInterval = 120,
	MaxRetries = 5,
	SessionLockTimeout = 1800,
}

GameConfig.Leaderboard = {
	RefreshInterval = 90,
	Size = 10,
}

-- Studio / admins get the DEBUG panel and chat commands
GameConfig.AdminUserIds = {}

return GameConfig
