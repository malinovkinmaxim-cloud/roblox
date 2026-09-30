--[[
	SynergyData - BUILDS: level ups + abilities + items that work together. When everything a
	synergy Needs is in your build, it switches on ("SYNERGY: BULLET HELL") and adds its
	mechanic (Sim/Perks.lua reads run.Synergies[Key]). Level-up cards and item cards show when
	a pick belongs to a synergy you are building ("BULLET HELL 2/4").

	Needs: every entry must hold
	  { Upgrade = key, Level = n }      a level-up upgrade (shared/UpgradeData) at level n+
	  { Item = key, Level = n }         an item (shared/ItemData) at level n+
	  { Ability = { keys } }            any of these abilities (evolutions count too)
	  { Any = { entries } }             any one of these entries
	  { Dash = true }                   you can dash
	Base-only synergies exist on purpose: a free player can build every kind of run.
]]

local SynergyData = {}

SynergyData.List = {
	{
		Key = "BloodPact",
		Name = "BLOOD PACT",
		Desc = "Lifesteal heals double below 50% HP; Berserk's bonus +50%.",
		Needs = { { Item = "BloodEngine" }, { Upgrade = "Berserk", Level = 2 }, { Upgrade = "Vampire", Level = 2 } },
	},
	{
		Key = "PerpetualMotion",
		Name = "PERPETUAL MOTION",
		Desc = "At full speed dashes recharge twice as fast and every dash fires a shockwave.",
		Needs = { { Item = "KingOfMovement" }, { Upgrade = "Momentum", Level = 3 }, { Upgrade = "Swiftness", Level = 3 }, { Dash = true } },
	},
	{
		Key = "BulletHell",
		Name = "BULLET HELL",
		Desc = "Split shards also ricochet and pierce.",
		Needs = {
			{ Any = { { Item = "RicochetCore" }, { Upgrade = "Ricochet", Level = 2 } } },
			{ Upgrade = "DoubleShot", Level = 1 },
			{ Upgrade = "Penetration", Level = 2 },
			{ Upgrade = "Split", Level = 1 },
		},
	},
	{
		Key = "Executioner",
		Name = "EXECUTIONER",
		Desc = "Crits on a marked enemy count 3 hits towards its detonation; a detonation refunds 5 Predator stacks.",
		Needs = { { Item = "Predator" }, { Item = "DeathMark" }, { Upgrade = "CritMaster", Level = 3 }, { Upgrade = "Brutal", Level = 2 } },
	},
	{
		Key = "StormFront",
		Name = "STORM FRONT",
		Desc = "Every zap and chain jump can call down a lightning strike (15%).",
		Needs = { { Ability = { "Lightning", "ChainLightning", "StormCaller" } }, { Item = "StaticSock" }, { Upgrade = "ChainShot", Level = 2 } },
	},
	{
		Key = "ScorchedEarth",
		Name = "SCORCHED EARTH",
		Desc = "Burning enemies explode when they die.",
		Needs = { { Ability = { "FireRing", "Meteor", "InfernoRing" } }, { Item = "HotSauceSocks" }, { Upgrade = "BurnMastery", Level = 2 } },
	},
	{
		Key = "DeepFreeze",
		Name = "DEEP FREEZE",
		Desc = "Frozen and slowed enemies shatter for area damage when they die.",
		Needs = { { Ability = { "IceField", "AbsoluteZero" } }, { Any = { { Item = "PocketWatch" }, { Item = "TimeFracture" } } }, { Item = "PocketSand" } },
	},
	{
		Key = "IronFortress",
		Name = "IRON FORTRESS",
		Desc = "Broken plating releases a thorn nova; thorns deal double.",
		Needs = { { Upgrade = "Armor", Level = 3 }, { Upgrade = "Plating", Level = 3 }, { Item = "CactusHug" } },
	},
	{
		Key = "GoldRush",
		Name = "GOLD RUSH",
		Desc = "Every coin also gives XP; the Rusty Token pays double.",
		Needs = { { Upgrade = "Greed", Level = 3 }, { Item = "RustyToken" }, { Any = { { Item = "LuckyLever" }, { Item = "Dice67" } } } },
	},
	{
		Key = "GravityWell",
		Name = "GRAVITY WELL",
		Desc = "Vortexes and gravity wells deal +50% damage and pull XP to you.",
		Needs = { { Ability = { "BlackHole", "Singularity" } }, { Item = "GravitySeed" } },
	},
	{
		Key = "ShadowDance",
		Name = "SHADOW DANCE",
		Desc = "Dodging calls your shadow for 3 s.",
		Needs = { { Item = "SecondShadow" }, { Upgrade = "Dodge", Level = 2 }, { Ability = { "Clone" } } },
	},
	{
		Key = "BossHunter",
		Name = "BOSS HUNTER",
		Desc = "Weak points take double bonus and stay open 1 s longer.",
		Needs = {
			{ Item = "ChampionBelt" },
			{ Upgrade = "GiantSlayer", Level = 3 },
			{ Any = { { Item = "DeathMark" }, { Item = "KingsCrown" }, { Item = "Fragment67" } } },
		},
	},
	{
		Key = "SixtySeven",
		Name = "SIXTY-SEVEN",
		Desc = "Every 67th hit triggers a free 67 BLAST.",
		Needs = { { Item = "Crown67" }, { Ability = { "Blast67", "Orb67", "ChaosOrb67" } }, { Upgrade = "Percent67", Level = 1 } },
	},
	{
		Key = "SoulHarvest",
		Name = "SOUL HARVEST",
		Desc = "Normal kills can drop a soul too (1%).",
		Needs = { { Item = "SoulCollector" }, { Upgrade = "BountyHunter", Level = 2 }, { Item = "Fang" } },
	},
	{
		Key = "TimeLord",
		Name = "TIME LORD",
		Desc = "Time stops last 1 s longer; frozen enemies take +25% more damage.",
		Needs = { { Item = "PocketWatch" }, { Item = "TimeFracture" }, { Upgrade = "Duration", Level = 2 } },
	},
	{
		Key = "Brawler",
		Name = "BRAWLER",
		Desc = "Melee hits heal 1 HP (up to 5 HP/s) and knock twice as hard.",
		Needs = { { Item = "BrassKnuckles" }, { Ability = { "Katana", "GiantFist", "SwordStorm", "BloodMoon", "OrbitalBlades" } }, { Upgrade = "Expansion", Level = 2 } },
	},
	{
		Key = "TheSwarm",
		Name = "THE SWARM",
		Desc = "+1 summon, and summon hits can zap a second enemy.",
		Needs = { { Item = "DogTreats" }, { Ability = { "Drone", "GooberFriends", "DroneSwarm" } }, { Upgrade = "RapidFire", Level = 2 } },
	},
	{
		Key = "XPEngine",
		Name = "XP ENGINE",
		Desc = "The XP streak bonus doubles; the magnetic pulse comes every 20 s.",
		Needs = { { Item = "MagneticBolt" }, { Upgrade = "Wisdom", Level = 3 }, { Upgrade = "XPStreak", Level = 2 } },
	},
	{
		Key = "Sharpshooter",
		Name = "SHARPSHOOTER",
		Desc = "Shots deal more the further they fly: up to +30%.",
		Needs = { { Item = "SlingshotScope" }, { Upgrade = "Velocity", Level = 3 }, { Ability = { "Arrow", "BasicBlaster", "OverdriveBlaster", "PulseBlast" } } },
	},
}

SynergyData.ByKey = {}
-- "Upgrade:Key" / "Item:Key" / "Ability:Key" -> the synergies that need it
SynergyData.Of = {} :: { [string]: { any } }

local function index(syn, need)
	local function add(tag: string)
		SynergyData.Of[tag] = SynergyData.Of[tag] or {}
		if not table.find(SynergyData.Of[tag], syn) then
			table.insert(SynergyData.Of[tag], syn)
		end
	end
	if need.Upgrade then
		add("Upgrade:" .. need.Upgrade)
	elseif need.Item then
		add("Item:" .. need.Item)
	elseif need.Ability then
		for _, key in need.Ability do
			add("Ability:" .. key)
		end
	elseif need.Any then
		for _, n in need.Any do
			index(syn, n)
		end
	end
end

for _, syn in SynergyData.List do
	SynergyData.ByKey[syn.Key] = syn
	for _, need in syn.Needs do
		index(syn, need)
	end
end

-- does one Needs entry hold for this build?
--   build = { Upgrades = { key -> level }, Items = { key -> level }, Abilities = { key -> true }, Dash = bool }
local function holds(need, build): boolean
	if need.Upgrade then
		return (build.Upgrades[need.Upgrade] or 0) >= (need.Level or 1)
	elseif need.Item then
		return (build.Items[need.Item] or 0) >= (need.Level or 1)
	elseif need.Ability then
		for _, key in need.Ability do
			if build.Abilities[key] then
				return true
			end
		end
		return false
	elseif need.Any then
		for _, n in need.Any do
			if holds(n, build) then
				return true
			end
		end
		return false
	elseif need.Dash then
		return build.Dash == true
	end
	return false
end
SynergyData.Holds = holds

-- how many of a synergy's needs this build has (have, total)
function SynergyData.Progress(syn, build): (number, number)
	local have = 0
	for _, need in syn.Needs do
		if holds(need, build) then
			have += 1
		end
	end
	return have, #syn.Needs
end

-- the synergy a pick would help the most ("BULLET HELL 3/4"), for card tags.
-- after: the build as it would be after the pick
function SynergyData.BestFor(tag: string, after): (any?, number, number)
	local best, bestHave, bestTotal = nil, -1, 0
	for _, syn in SynergyData.Of[tag] or {} do
		local have, total = SynergyData.Progress(syn, after)
		if have > bestHave or (have == bestHave and total < bestTotal) then
			best, bestHave, bestTotal = syn, have, total
		end
	end
	return best, math.max(0, bestHave), bestTotal
end

return SynergyData
