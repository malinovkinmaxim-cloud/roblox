--[[
	UpgradeData - PASSIVE abilities (level-up cards that are not weapons).

	A passive adds `Stats` (Stats keys, see shared/Stats.lua) per stack, up to MaxStacks.
	A few have extra behaviour in the simulation (search the Key in Sim/): XPStorm,
	Percent67. Several passives are the second half of an EVOLUTION (shared/WeaponData.lua):
	RapidFire, OrbitalMastery, BurnMastery, CritMaster, Berserk, DoubleShot, Magnet,
	Wisdom, Expansion, Swiftness, Armor, Duration.

	Unlock: every passive is available from the start except Secret ones (a discovered
	secret adds them to the pool).
]]

export type PassiveDef = {
	Key: string,
	Name: string,
	Desc: string,
	Stats: { [string]: number },
	MaxStacks: number,
	Rarity: string,
	Secret: string?,
}

local UpgradeData = {}

UpgradeData.Passives = {
	{ Key = "Power", Name = "Power", Desc = "+12% damage", Stats = { Might = 0.12 }, MaxStacks = 5, Rarity = "Common" },
	{ Key = "RapidFire", Name = "Rapid Fire", Desc = "+10% attack speed", Stats = { AttackSpeed = 0.1 }, MaxStacks = 5, Rarity = "Common" },
	{ Key = "Expansion", Name = "Expansion", Desc = "+10% area", Stats = { Area = 0.1 }, MaxStacks = 5, Rarity = "Common" },
	{ Key = "Swiftness", Name = "Swiftness", Desc = "+8% movement speed", Stats = { MoveSpeed = 0.08 }, MaxStacks = 5, Rarity = "Common" },
	{ Key = "Wisdom", Name = "Wisdom", Desc = "+10% XP", Stats = { Growth = 0.1 }, MaxStacks = 5, Rarity = "Common" },
	{ Key = "Magnet", Name = "Magnet", Desc = "+35% pickup range: collect XP from far away", Stats = { Magnet = 0.35 }, MaxStacks = 4, Rarity = "Common" },
	{ Key = "Vitality", Name = "Vitality", Desc = "+20 max HP", Stats = { MaxHP = 20 }, MaxStacks = 5, Rarity = "Common" },
	{ Key = "Regeneration", Name = "Regeneration", Desc = "+0.4 HP per second", Stats = { Regen = 0.4 }, MaxStacks = 5, Rarity = "Common" },
	{ Key = "Greed", Name = "Greed", Desc = "+15% coins", Stats = { Greed = 0.15 }, MaxStacks = 4, Rarity = "Common" },
	{ Key = "Duration", Name = "Duration", Desc = "+12% effect duration", Stats = { Duration = 0.12 }, MaxStacks = 4, Rarity = "Common" },
	{ Key = "CritMaster", Name = "Crit Master", Desc = "+5% crit chance, crits deal +25%", Stats = { Crit = 0.05, CritMult = 0.25 }, MaxStacks = 5, Rarity = "Uncommon" },
	{ Key = "Armor", Name = "Armor", Desc = "-1 damage from every hit", Stats = { Armor = 1 }, MaxStacks = 4, Rarity = "Uncommon" },
	{ Key = "Luck", Name = "Luck", Desc = "+12% luck: rarer cards and drops", Stats = { Luck = 0.12 }, MaxStacks = 4, Rarity = "Uncommon" },
	{ Key = "Vampire", Name = "Vampire", Desc = "6% chance to heal 3 HP on every kill", Stats = { Lifesteal = 0.06 }, MaxStacks = 4, Rarity = "Uncommon" },
	{ Key = "Berserk", Name = "Berserk", Desc = "Up to +20% attack speed the lower your HP", Stats = { Berserk = 0.2 }, MaxStacks = 4, Rarity = "Uncommon" },
	{ Key = "OrbitalMastery", Name = "Orbital Mastery", Desc = "Orbiting weapons +20% faster and wider", Stats = { Orbital = 0.2 }, MaxStacks = 3, Rarity = "Uncommon" },
	{ Key = "BurnMastery", Name = "Burn Mastery", Desc = "Burning deals +35% damage", Stats = { Burn = 0.35 }, MaxStacks = 3, Rarity = "Uncommon" },
	{ Key = "DoubleShot", Name = "Double Shot", Desc = "+1 projectile for every ability", Stats = { Amount = 1 }, MaxStacks = 2, Rarity = "Rare" },
	{ Key = "Execution", Name = "Execution", Desc = "6% chance to instantly finish enemies below 20% HP", Stats = { Execute = 0.06 }, MaxStacks = 3, Rarity = "Rare" },
	{ Key = "XPStorm", Name = "XP Storm", Desc = "Every 45s: 8 seconds of double XP", Stats = {}, MaxStacks = 2, Rarity = "Rare" },
	{ Key = "Percent67", Name = "67%", Desc = "Every hit: 67% chance to deal +67% damage. Something is coming...", Stats = {}, MaxStacks = 1, Rarity = "Legendary" },
	{ Key = "TouchGrass", Name = "Touch Grass", Desc = "Secret. +1.5 HP per second, +25 max HP.", Stats = { Regen = 1.5, MaxHP = 25 }, MaxStacks = 1, Rarity = "Secret", Secret = "TouchGrass" },
} :: { PassiveDef }

-- fallback cards when nothing else can be offered
UpgradeData.Fillers = {
	{ Key = "Snack", Name = "Snack", Desc = "Heal 30 HP" },
	{ Key = "Coins", Name = "Pocket Change", Desc = "+8 coins" },
}

UpgradeData.PassiveByKey = {} :: { [string]: PassiveDef }
for _, def in UpgradeData.Passives do
	UpgradeData.PassiveByKey[def.Key] = def
end

return UpgradeData
