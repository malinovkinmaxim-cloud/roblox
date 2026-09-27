--[[
	UpgradeData - level-up cards that are not weapons.

	Passives: stat cards that stack up to MaxStacks. `Stat` + `Value` are applied by
	shared/Stats.lua (Add = additive, Mul = multiplicative bonus in percent form).

	Rares: special cards (small chance per card, x Luck). Most are one-time; some stack.
	Their effects are implemented in the run simulation (look for the Key).
]]

export type PassiveDef = {
	Key: string,
	Name: string,
	Icon: string,
	Desc: string,
	Stat: string,
	Value: number,
	MaxStacks: number,
}

export type RareDef = {
	Key: string,
	Name: string,
	Icon: string,
	Desc: string,
	Rarity: string,
	MaxStacks: number,
	Weight: number,
}

local UpgradeData = {}

UpgradeData.Passives = {
	{ Key = "Might", Name = "Gigachad Juice", Icon = "💪", Desc = "+15% damage", Stat = "Might", Value = 0.15, MaxStacks = 5 },
	{ Key = "AttackSpeed", Name = "Caffeine Overload", Icon = "☕", Desc = "+12% attack speed", Stat = "AttackSpeed", Value = 0.12, MaxStacks = 5 },
	{ Key = "Cooldown", Name = "Speedrun Strats", Icon = "⏱️", Desc = "-7% weapon cooldowns", Stat = "Cooldown", Value = 0.07, MaxStacks = 4 },
	{ Key = "Area", Name = "Big Brain", Icon = "🌐", Desc = "+12% area", Stat = "Area", Value = 0.12, MaxStacks = 5 },
	{ Key = "Amount", Name = "Copy Paste", Icon = "➕", Desc = "+1 projectile for every weapon", Stat = "Amount", Value = 1, MaxStacks = 2 },
	{ Key = "MoveSpeed", Name = "Zoomies", Icon = "👟", Desc = "+10% movement speed", Stat = "MoveSpeed", Value = 0.1, MaxStacks = 5 },
	{ Key = "Growth", Name = "Brain Food", Icon = "📈", Desc = "+12% XP", Stat = "Growth", Value = 0.12, MaxStacks = 5 },
	{ Key = "Crit", Name = "Aim Assist", Icon = "🎯", Desc = "+7% critical hit chance", Stat = "Crit", Value = 0.07, MaxStacks = 5 },
	{ Key = "Magnet", Name = "Rizz Magnet", Icon = "🧲", Desc = "+40% pickup range", Stat = "Magnet", Value = 0.4, MaxStacks = 4 },
	{ Key = "MaxHP", Name = "Thicc Skin", Icon = "❤️", Desc = "+20 max HP", Stat = "MaxHP", Value = 20, MaxStacks = 5 },
	{ Key = "Regen", Name = "Touch Grass", Icon = "🌱", Desc = "+0.5 HP per second", Stat = "Regen", Value = 0.5, MaxStacks = 5 },
	{ Key = "Armor", Name = "Plot Armor", Icon = "🛡️", Desc = "-1 damage from every hit", Stat = "Armor", Value = 1, MaxStacks = 4 },
	{ Key = "Luck", Name = "Lucky Socks", Icon = "🍀", Desc = "+15% luck (rare cards, drops)", Stat = "Luck", Value = 0.15, MaxStacks = 4 },
	{ Key = "Greed", Name = "Coin Brain", Icon = "🪙", Desc = "+20% coins", Stat = "Greed", Value = 0.2, MaxStacks = 4 },
} :: { PassiveDef }

UpgradeData.Rares = {
	{
		Key = "Percent67",
		Name = "67%",
		Icon = "6️⃣",
		Desc = "Every hit has a 67% chance to deal +67% damage. Something is coming...",
		Rarity = "Rare",
		MaxStacks = 1,
		Weight = 1.2,
	},
	{
		Key = "SigmaMode",
		Name = "SIGMA MODE",
		Icon = "🗿",
		Desc = "Every 40s become SIGMA for 10s: +50% damage, +30% speed.",
		Rarity = "Rare",
		MaxStacks = 1,
		Weight = 1,
	},
	{
		Key = "Overdrive",
		Name = "BRAINROT OVERDRIVE",
		Icon = "🔥",
		Desc = "All weapons fire 25% faster. Projectiles fly 25% faster.",
		Rarity = "Rare",
		MaxStacks = 1,
		Weight = 1,
	},
	{
		Key = "GooberArmy",
		Name = "GOOBER ARMY",
		Icon = "👾",
		Desc = "+2 tiny goober allies that bite your enemies.",
		Rarity = "Rare",
		MaxStacks = 3,
		Weight = 1,
	},
	{
		Key = "MainCharacter",
		Name = "MAIN CHARACTER ENERGY",
		Icon = "🌟",
		Desc = "+1 revive. Plot armor, but real.",
		Rarity = "Rare",
		MaxStacks = 2,
		Weight = 0.8,
	},
	{
		Key = "Mewing",
		Name = "MEWING STREAK",
		Icon = "🤫",
		Desc = "+10% crit chance. Critical hits deal x3 instead of x2.",
		Rarity = "Rare",
		MaxStacks = 1,
		Weight = 1,
	},
	{
		Key = "AuraFarming",
		Name = "AURA FARMING",
		Icon = "✨",
		Desc = "+25% XP, +60% pickup range, +1 HP/s.",
		Rarity = "Rare",
		MaxStacks = 1,
		Weight = 1,
	},
	{
		Key = "Awaken",
		Name = "AWAKEN",
		Icon = "⚜️",
		Desc = "A max level weapon awakens: x1.6 damage, +25% area, +1 amount.",
		Rarity = "Legendary",
		MaxStacks = 99, -- once per weapon (checked separately)
		Weight = 2,
	},
} :: { RareDef }

-- fallback cards when nothing else can be offered
UpgradeData.Fillers = {
	{ Key = "Snack", Name = "Pizza Slice", Icon = "🍕", Desc = "Heal 30 HP" },
	{ Key = "Coins", Name = "Pocket Change", Icon = "🪙", Desc = "+8 coins" },
}

UpgradeData.PassiveByKey = {} :: { [string]: PassiveDef }
for _, def in UpgradeData.Passives do
	UpgradeData.PassiveByKey[def.Key] = def
end
UpgradeData.RareByKey = {} :: { [string]: RareDef }
for _, def in UpgradeData.Rares do
	UpgradeData.RareByKey[def.Key] = def
end

return UpgradeData
