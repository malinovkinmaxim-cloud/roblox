--[[
	GameConfig - every tunable number of 67 SURVIVAL in one place.

	Coordinates inside a run are 2D "arena coordinates" (x, z) in studs, relative to
	Arena.Center. The ground is flat (Arena.GroundY), so the simulation never needs Y.
]]

local GameConfig = {}

GameConfig.GameName = "67 SURVIVAL"
GameConfig.Tagline = "Survive. Level up. Become unstoppable."
-- what the purple FRAGMENT currency is for and where it comes from (tooltips, the heroes menu)
GameConfig.FragmentsHelp = "FRAGMENTS unlock heroes and abilities. You get them for every run over a minute (more for long runs and bosses), from elites, daily quests, weekly challenges, achievements and the AFK Camp."
GameConfig.Description = "Pick a hero, survive a huge horde, build your abilities, evolve them, beat the bosses. Short runs, rare 67 events, lots to collect."
GameConfig.Version = 2

-- Server simulation / network
GameConfig.Sim = {
	Rate = 20, -- fixed simulation steps per second
	SnapshotEvery = 2, -- a network frame every N steps (10 Hz)
	MaxStepsPerHeartbeat = 3, -- a lagging server skips time instead of spiralling
	MaxEnemiesPerRun = 260,
	InvasionEnemies = 440, -- temporary cap during a 67 INVASION (the "whole screen is enemies" moment)
	GlobalEnemyBudget = 1300, -- shared by all runs on one server (per-run cap shrinks when crowded)
	MaxGems = 180,
	MaxPickups = 24,
	MaxProjectiles = 120,
	MaxEnemyProjectiles = 70,
	MaxAllies = 8,
	MaxZones = 12, -- lingering weapon zones (poison clouds, black holes)
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
	HurtCooldown = 0.5, -- invulnerability after taking contact damage
	BaseRegen = 0.25, -- HP per second for everyone: chip damage heals, big mistakes still hurt
	PickupRange = 8,
	ReviveInvulnerable = 2.5,
	ReviveHeal = 0.6, -- fraction of max HP
	MaxWeapons = 6, -- + meta upgrade "Weapon Slot"
	MaxPassives = 8,
}

-- seeing your hero in a crowd (Settings: "Hero outline", "Fewer effects")
GameConfig.Visuals = {
	OutlineColor = Color3.fromRGB(255, 255, 255), -- the outline around your own hero in a run
	OutlineTransparency = 0.05,
	FillColor = Color3.fromRGB(120, 220, 255), -- a faint glow over the hero
	FillTransparency = 0.85,
	FewerEffectsParticles = 1 / 3, -- particle count with "Fewer effects" on
	FewerEffectsFade = 0.25, -- ability areas and auras get this much more see-through
}

-- ponds in the arena: water slows everyone who wades through (bosses and flyers do not)
GameConfig.Water = {
	PlayerSpeed = 0.75, -- walk speed multiplier in water
	EnemySpeed = 0.75,
}

GameConfig.Run = {
	Length = 13 * 60, -- soft end; the final boss spawns at FinalBossAt
	FinalBossAt = 12 * 60,
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
	NewWeaponWeight = 1.0, -- x rarity weight (shared/Rarity.lua)
	WeaponLevelWeight = 1.35,
	PassiveWeight = 0.9,
	FreeRerolls = 1,
	Heal = 8, -- HP healed on every level up (matters early, not late)
	SkipCoins = 5,
}

GameConfig.Drops = {
	GemTiers = { 1, 5, 25, 100 }, -- tier thresholds by value
	HealAmount = 30, -- Snack pickup
	NukeRadius = 70,
	MagnetDuration = 1.2,
	BaseItemChance = 0.003, -- per regular kill (x Luck)
	CoinChance = 0.035,
	CrateEvery = 38, -- a loot crate appears near the player every N seconds
	EliteChance = 0.012, -- a regular spawn becomes an ELITE (x3 HP, bigger, more XP) after EliteFrom
	EliteFrom = 150,
	EliteFragmentChance = 0.2, -- an elite drops a hero fragment
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
	XPPerMinute = 20, -- account XP
	XPPerKill = 1 / 10,
	-- fragments: unlock heroes and new abilities. A 5-minute first run with a boss pays ~6
	-- (2 + 1 + 2 from the boss + an elite drop): the first paid hero (15) in 2-3 runs
	FragmentsBase = 2, -- every run that lasts at least a minute
	FragmentsPerStep = 1, -- + this many ...
	FragmentsTimeStep = 180, -- ... for every this many seconds survived
	FragmentsPerBoss = 2, -- dropped by every boss (picked up in the run)
	FragmentsVictory = 5,
	FragmentsThe67 = 5,
	PartyBonusPerMember = 0.1, -- coins + XP per other party member (max 3)
	FriendBonusPerFriend = 0.05, -- per friend in the server (max 3)
}

-- AFK CAMP: optional idle rewards with a hard cap (active play always pays much more)
GameConfig.Afk = {
	CapacityMinutes = 120,
	CapacityPassMinutes = 120, -- extra with the AFK Capacity pass
	CoinsPerMinute = 1.2, -- per hero in camp
	XPPerMinute = 3,
	FragmentMinutes = 90, -- one fragment per this many hero-minutes
	LevelBonus = 0.04, -- +4% per account level (max x3)
	SlotCosts = { 0, 1500, 5000 }, -- coins for slot 1 / 2 / 3 (a 4th with the Extra Hero Slot pass)
	BoostMult = 2, -- AFK Boost product
}

GameConfig.Party = {
	MaxSize = 4,
	InviteSeconds = 20,
	ServerGoal = 6700, -- kills by everyone on the server -> a reward for everyone
	ServerGoalCoins = 67,
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

-- the DEBUG panel and commands: the game's creator, plus these user ids (e.g. co-developers).
-- For a group game: group members with at least this rank (255 = the group owner).
GameConfig.AdminUserIds = {}
GameConfig.AdminGroupRank = 254

return GameConfig
