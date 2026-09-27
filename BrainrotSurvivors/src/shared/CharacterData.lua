--[[
	CharacterData - playable characters. Stats are bonuses on top of the base player
	(same keys as passives, see shared/Stats.lua). Every character has one small unique
	mechanic, implemented in the run simulation (search for the character Key).
]]

export type CharacterDef = {
	Key: string,
	Name: string,
	Icon: string,
	Desc: string,
	Perk: string,
	StartWeapon: string,
	Stats: { [string]: number },
	Color: Color3,
	Unlock: { Default: boolean?, Cost: number?, Achievement: string? },
	Rarity: string, -- Common / Rare / Epic / Legendary / Secret (menu colour only)
	Secret: boolean?,
}

local rgb = Color3.fromRGB

local LIST: { CharacterDef } = ({
	{
		Key = "Goober",
		Name = "DEFAULT GOOBER",
		Icon = "🙂",
		Desc = "Just a guy. Balanced. Surprisingly durable.",
		Perk = "Goofy Resilience: +1 armor and +10 max HP.",
		StartWeapon = "BrainBlast",
		Stats = { Armor = 1, MaxHP = 10 },
		Color = rgb(120, 220, 90),
		Unlock = { Default = true },
		Rarity = "Common",
	},
	{
		Key = "Sigma",
		Name = "SIGMA",
		Icon = "🗿",
		Desc = "+25% movement speed, +10% area, -10% damage.",
		Perk = "Mog: enemies inside your auras are slowed by 30%.",
		StartWeapon = "SigmaAura",
		Stats = { MoveSpeed = 0.25, Area = 0.1, Might = -0.1 },
		Color = rgb(40, 40, 50),
		Unlock = { Cost = 1500, Achievement = "Survivor10" },
		Rarity = "Rare",
	},
	{
		Key = "SixSeven",
		Name = "67",
		Icon = "🎲",
		Desc = "+67% luck. Every run your other stats are rolled at random.",
		Perk = "67 events happen 3x more often. Rare cards show up way more.",
		StartWeapon = "Orb67",
		Stats = { Luck = 0.67 },
		Color = rgb(255, 205, 50),
		Unlock = { Cost = 2500, Achievement = "SixSeven" },
		Rarity = "Epic",
	},
	{
		Key = "Brainrot",
		Name = "BRAINROT",
		Icon = "🧠",
		Desc = "+30% XP, -25% max HP.",
		Perk = "Galaxy brain: 4 cards on every level up instead of 3.",
		StartWeapon = "BrainrotBeam",
		Stats = { Growth = 0.3, MaxHPMult = -0.25 },
		Color = rgb(255, 130, 190),
		Unlock = { Cost = 2000, Achievement = "Level25" },
		Rarity = "Epic",
	},
	{
		Key = "TheNPC",
		Name = "THE NPC",
		Icon = "😐",
		Desc = "+10% to everything. Says nothing.",
		Perk = "Just Standing There: regenerates 3 HP/s while not moving.",
		StartWeapon = "ZapZap",
		Stats = { Might = 0.1, AttackSpeed = 0.1, Area = 0.1, MoveSpeed = 0.1, Growth = 0.1 },
		Color = rgb(245, 205, 48),
		Unlock = { Achievement = "JustStanding" },
		Rarity = "Secret",
		Secret = true,
	},
} :: any)

local CharacterData = {}
CharacterData.List = LIST
CharacterData.ByKey = {} :: { [string]: CharacterDef }
for _, def in LIST do
	CharacterData.ByKey[def.Key] = def
end
CharacterData.Default = "Goober"

-- stats that the "67" character rolls every run (min, max bonus)
CharacterData.RandomRolls = {
	Might = { -0.2, 0.35 },
	AttackSpeed = { -0.15, 0.3 },
	Area = { -0.15, 0.3 },
	MoveSpeed = { -0.1, 0.2 },
	MaxHPMult = { -0.2, 0.25 },
}

return CharacterData
