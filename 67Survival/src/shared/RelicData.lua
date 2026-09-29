--[[
	RelicData - RELICS: the physical loot of 67 TOWN. Mini-bosses, 67 VAULTS, elites and secrets
	drop them on the ground (floating, with a beam in the colour of their rarity); walk over one
	to take it. A relic lasts for the run and changes how you play: speed, reach, extra shots,
	cooldowns, crits, lifesteal, ability-type buffs, a DASH, on-kill explosions, chain zaps,
	fire trails, bonus damage to bosses...

	Rarity (shared/Rarity.lua colours): Common, Rare, Epic, Legendary + Secret (never random).
	A relic you already own stacks (up to MaxStacks); a maxed relic is not dropped again.

	Fields
	  Stats     Stats keys added per stack (shared/Stats.lua), like passives
	  Effect    a behaviour in Sim/Relics.lua with its Params (numbers per stack where noted)
	  Requires  only drops when this relic is owned (Spare Skate needs Rocket Skates)
	  Symbol    UI icon symbol (UI/Icons categories)

	Adding a relic: append it to the list (the order is the network id), give it Stats and/or
	an Effect that Sim/Relics.lua knows. Nothing else is needed: drops, the HUD, the loot
	beams and the pickup card read this table.
]]

export type RelicDef = {
	Id: number,
	Key: string,
	Name: string,
	Rarity: string,
	Desc: string,
	Flavor: string,
	Symbol: string,
	MaxStacks: number,
	Stats: { [string]: number }?,
	Effect: string?,
	Params: { [string]: any }?,
	Requires: string?,
	Secret: boolean?,
}

local LIST: { RelicDef } = ({
	-------------------------------------------------------------------- COMMON
	{
		Key = "Sneakers",
		Name = "Speedy Sneakers",
		Rarity = "Common",
		Desc = "+10% movement speed",
		Flavor = "Velcro. For speed.",
		Symbol = "Speed",
		MaxStacks = 3,
		Stats = { MoveSpeed = 0.1 },
	},
	{
		Key = "LongSpoon",
		Name = "Very Long Spoon",
		Rarity = "Common",
		Desc = "+20% range: shots fly further",
		Flavor = "For reaching things. And enemies.",
		Symbol = "Area",
		MaxStacks = 3,
		Stats = { Range = 0.2, ProjSpeed = 0.1 },
	},
	{
		Key = "FridgeMagnet",
		Name = "Fridge Magnet",
		Rarity = "Common",
		Desc = "+50% pickup range",
		Flavor = "Holds up one (1) drawing.",
		Symbol = "Area",
		MaxStacks = 2,
		Stats = { Magnet = 0.5 },
	},
	{
		Key = "LuckyPenny",
		Name = "Lucky Penny",
		Rarity = "Common",
		Desc = "+15% luck and coins",
		Flavor = "Heads: 6. Tails: 7.",
		Symbol = "Coin",
		MaxStacks = 3,
		Stats = { Luck = 0.15, Greed = 0.15 },
	},
	{
		Key = "BandAid",
		Name = "Band-Aid",
		Rarity = "Common",
		Desc = "+25 max HP, +0.3 HP per second",
		Flavor = "Has a dinosaur on it.",
		Symbol = "Health",
		MaxStacks = 3,
		Stats = { MaxHP = 25, Regen = 0.3 },
	},
	{
		Key = "ProteinBar",
		Name = "Protein Bar",
		Rarity = "Common",
		Desc = "+10% damage",
		Flavor = "Tastes like a gym.",
		Symbol = "Attack",
		MaxStacks = 3,
		Stats = { Might = 0.1 },
	},
	-------------------------------------------------------------------- RARE
	{
		Key = "ThirdArm",
		Name = "Third Arm",
		Rarity = "Rare",
		Desc = "+1 projectile for every ability",
		Flavor = "Don't ask where it came from.",
		Symbol = "Attack",
		MaxStacks = 1,
		Stats = { Amount = 1 },
	},
	{
		Key = "Espresso67",
		Name = "Espresso 67",
		Rarity = "Rare",
		Desc = "+15% attack speed: abilities recharge faster",
		Flavor = "67 shots. Hands are vibrating.",
		Symbol = "Speed",
		MaxStacks = 2,
		Stats = { AttackSpeed = 0.15 },
	},
	{
		Key = "CritGoggles",
		Name = "Crit Goggles",
		Rarity = "Rare",
		Desc = "+8% crit chance, crits deal +30%",
		Flavor = "You can see weak spots. And through walls (no).",
		Symbol = "Attack",
		MaxStacks = 2,
		Stats = { Crit = 0.08, CritMult = 0.3 },
	},
	{
		Key = "VampireFangs",
		Name = "Vampire Fangs",
		Rarity = "Rare",
		Desc = "10% chance to heal 3 HP on every kill",
		Flavor = "Plastic. Still works.",
		Symbol = "Health",
		MaxStacks = 2,
		Stats = { Lifesteal = 0.1 },
	},
	{
		Key = "PocketSand",
		Name = "Pocket Sand",
		Rarity = "Rare",
		Desc = "Hits have a 12% chance to slow the enemy by 50% for 2s",
		Flavor = "Sha-sha-sha!",
		Symbol = "Defense",
		MaxStacks = 2,
		Effect = "Slow",
		Params = { Chance = 0.12, Factor = 0.5, Time = 2 }, -- Chance per stack
	},
	{
		Key = "StaticSock",
		Name = "Static Sock",
		Rarity = "Rare",
		Desc = "Every 10th hit zaps 3 more enemies nearby",
		Flavor = "Rubbed on a carpet for 67 minutes.",
		Symbol = "Special",
		MaxStacks = 2,
		Effect = "Chain",
		Params = { Every = 10, EveryPerStack = -3, Targets = 3, Range = 14, Share = 0.6 },
	},
	{
		Key = "SpareSkate",
		Name = "Spare Skate",
		Rarity = "Rare",
		Desc = "+1 DASH charge",
		Flavor = "Left foot only.",
		Symbol = "Speed",
		MaxStacks = 2,
		Effect = "DashCharge",
		Requires = "RocketSkates",
	},
	{
		Key = "SlingshotScope",
		Name = "Slingshot Scope",
		Rarity = "Rare",
		Desc = "PROJECTILE abilities: +25% damage, +20% shot speed",
		Flavor = "Aim small, miss small.",
		Symbol = "Attack",
		MaxStacks = 2,
		Effect = "Category",
		Params = { Category = "PROJECTILE", Damage = 0.25, Speed = 0.2 },
	},
	{
		Key = "DogTreats",
		Name = "Dog Treats",
		Rarity = "Rare",
		Desc = "SUMMON abilities: +30% damage, +1 summon",
		Flavor = "Good boys only. All of them are good boys.",
		Symbol = "Growth",
		MaxStacks = 1,
		Effect = "Category",
		Params = { Category = "SUMMON", Damage = 0.3, Amount = 1 },
	},
	-------------------------------------------------------------------- EPIC
	{
		Key = "RocketSkates",
		Name = "Rocket Skates",
		Rarity = "Epic",
		Desc = "Unlocks DASH (SPACE / dash button): a burst forward, briefly untouchable",
		Flavor = "Warranty void if used.",
		Symbol = "Speed",
		MaxStacks = 1,
		Effect = "Dash",
		Params = { Charges = 1, Recharge = 3.2, Distance = 11, Invulnerable = 0.35 },
	},
	{
		Key = "BoomJuice",
		Name = "Boom Juice",
		Rarity = "Epic",
		Desc = "Kills have an 18% chance to explode and hurt the horde around",
		Flavor = "Shake well. Do not drink.",
		Symbol = "Area",
		MaxStacks = 2,
		Effect = "Explode",
		Params = { Chance = 0.18, ChancePerStack = 0.1, Radius = 6, Damage = 30 },
	},
	{
		Key = "ChampionBelt",
		Name = "Champion Belt",
		Rarity = "Epic",
		Desc = "+50% damage to bosses and mini-bosses, +25% to elites",
		Flavor = "Undisputed. Unwashed.",
		Symbol = "Defense",
		MaxStacks = 2,
		Effect = "Champion",
		Params = { Boss = 0.5, Elite = 0.25 }, -- per stack
	},
	{
		Key = "CactusHug",
		Name = "Cactus Hug",
		Rarity = "Epic",
		Desc = "Enemies that touch you get hurt",
		Flavor = "Free hugs. Terms apply.",
		Symbol = "Defense",
		MaxStacks = 2,
		Effect = "Thorns",
		Params = { Damage = 14, PerLevel = 1.2 }, -- per stack
	},
	{
		Key = "HotSauceSocks",
		Name = "Hot Sauce Socks",
		Rarity = "Epic",
		Desc = "You leave a trail of fire while you move: enemies on it burn",
		Flavor = "Spicy steps only.",
		Symbol = "Area",
		MaxStacks = 1,
		Effect = "Trail",
		Params = { Every = 0.35, Radius = 3.4, Burn = 10, BurnTime = 2.5, Life = 3 },
	},
	{
		Key = "MomentumShoes",
		Name = "Momentum Shoes",
		Rarity = "Epic",
		Desc = "Keep moving: damage builds up to +30%. Stopping resets it",
		Flavor = "Never stop. Never stopping.",
		Symbol = "Speed",
		MaxStacks = 1,
		Effect = "Momentum",
		Params = { Max = 0.3, Build = 4 }, -- seconds of movement to full bonus
	},
	{
		Key = "BrassKnuckles",
		Name = "Brass Knuckles",
		Rarity = "Epic",
		Desc = "MELEE abilities: +30% damage, +15% area",
		Flavor = "Brass. Knuckles. Self-explanatory.",
		Symbol = "Attack",
		MaxStacks = 1,
		Effect = "Category",
		Params = { Category = "MELEE", Damage = 0.3, Area = 0.15 },
	},
	{
		Key = "BucketHat",
		Name = "Bucket Hat",
		Rarity = "Epic",
		Desc = "AREA abilities: +15% damage, +20% area",
		Flavor = "Holds exactly 6.7 liters of confidence.",
		Symbol = "Area",
		MaxStacks = 1,
		Effect = "Category",
		Params = { Category = "AREA", Damage = 0.15, Area = 0.2 },
	},
	-------------------------------------------------------------------- LEGENDARY
	{
		Key = "Crown67",
		Name = "Crown of 67",
		Rarity = "Legendary",
		Desc = "+6.7% damage. Every 67 kills: a golden 67 blast",
		Flavor = "Heavy is the head. Six. Seven.",
		Symbol = "Special",
		MaxStacks = 1,
		Stats = { Might = 0.067 },
		Effect = "Crown",
		Params = { Every = 67 },
	},
	{
		Key = "PocketWatch",
		Name = "Pocket Watch",
		Rarity = "Legendary",
		Desc = "Every 18s time stops around you for 2.5s",
		Flavor = "Always shows 6:07.",
		Symbol = "Special",
		MaxStacks = 1,
		Effect = "Freeze",
		Params = { Every = 18, Radius = 30, Time = 2.5 },
	},
	{
		Key = "GoldenSnack",
		Name = "Golden Snack",
		Rarity = "Legendary",
		Desc = "+1 revive, +20% max HP",
		Flavor = "Too shiny to eat. Eat it anyway.",
		Symbol = "Health",
		MaxStacks = 1,
		Stats = { Revives = 1, MaxHPMult = 0.2 },
	},
	{
		Key = "Dice67",
		Name = "Loaded 67 Dice",
		Rarity = "Legendary",
		Desc = "+12% crit chance. Crits have a 6.7% chance to deal 6.7x damage",
		Flavor = "Both dice say 67. Somehow.",
		Symbol = "Coin",
		MaxStacks = 1,
		Stats = { Crit = 0.12 },
		Effect = "Dice",
		Params = { Chance = 0.067, Mult = 6.7 },
	},
	-------------------------------------------------------------------- SECRET
	{
		Key = "SuspiciousRock",
		Name = "Suspicious Rock",
		Rarity = "Secret",
		Desc = "+6.7% damage, movement speed and XP",
		Flavor = "It's a rock. It says 67 on it.",
		Symbol = "Special",
		MaxStacks = 1,
		Stats = { Might = 0.067, MoveSpeed = 0.067, Growth = 0.067 },
		Secret = true,
	},
} :: any)

local RelicData = {}
RelicData.List = LIST
RelicData.ByKey = {} :: { [string]: RelicDef }
RelicData.ById = {} :: { [number]: RelicDef }
for id, def in LIST do
	def.Id = id
	RelicData.ByKey[def.Key] = def
	RelicData.ById[id] = def
end

-- the rarity tiers a relic can drop at
RelicData.Tiers = { "Common", "Rare", "Epic", "Legendary" }

--[[
	Rarity weights by loot tier (0 = the square ... 4 = THE RIFT): a mini-boss of a dangerous
	zone drops better relics. Luck pushes the weights up the ladder (Rarity.WeightFor).
]]
RelicData.TierWeights = {
	[0] = { Common = 70, Rare = 25, Epic = 5, Legendary = 0 },
	[1] = { Common = 55, Rare = 32, Epic = 11, Legendary = 2 },
	[2] = { Common = 40, Rare = 38, Epic = 18, Legendary = 4 },
	[3] = { Common = 25, Rare = 40, Epic = 27, Legendary = 8 },
	[4] = { Common = 10, Rare = 35, Epic = 38, Legendary = 17 },
}

function RelicData.Get(key: string): RelicDef
	local def = RelicData.ByKey[key]
	assert(def, "unknown relic " .. tostring(key))
	return def
end

return RelicData
