--[[
	MetaData - permanent progression bought with BRAIN COINS between runs, and the
	account level ("Brain Level") earned by playing.

	Permanent upgrades are small on purpose (+5% per level): they make the next run a
	little easier without replacing skill and level-up choices.
]]

export type MetaDef = {
	Key: string,
	Name: string,
	Icon: string,
	Desc: string,
	Stat: string,
	PerLevel: number,
	MaxLevel: number,
	Costs: { number },
}

local MetaData = {}

MetaData.Upgrades = {
	{ Key = "Might", Name = "Starting Damage", Icon = "💪", Desc = "+5% damage", Stat = "Might", PerLevel = 0.05, MaxLevel = 5, Costs = { 100, 220, 400, 650, 1000 } },
	{ Key = "MaxHP", Name = "Starting HP", Icon = "❤️", Desc = "+5% max HP", Stat = "MaxHPMult", PerLevel = 0.05, MaxLevel = 5, Costs = { 100, 220, 400, 650, 1000 } },
	{ Key = "MoveSpeed", Name = "Movement Speed", Icon = "👟", Desc = "+5% movement speed", Stat = "MoveSpeed", PerLevel = 0.05, MaxLevel = 3, Costs = { 150, 350, 700 } },
	{ Key = "Growth", Name = "XP Gain", Icon = "📈", Desc = "+5% XP", Stat = "Growth", PerLevel = 0.05, MaxLevel = 5, Costs = { 120, 260, 450, 700, 1100 } },
	{ Key = "Greed", Name = "Coin Gain", Icon = "🪙", Desc = "+10% coins", Stat = "Greed", PerLevel = 0.1, MaxLevel = 5, Costs = { 150, 300, 550, 900, 1400 } },
	{ Key = "Magnet", Name = "Pickup Range", Icon = "🧲", Desc = "+10% pickup range", Stat = "Magnet", PerLevel = 0.1, MaxLevel = 3, Costs = { 100, 250, 500 } },
	{ Key = "Armor", Name = "Armor", Icon = "🛡️", Desc = "-1 damage from every hit", Stat = "Armor", PerLevel = 1, MaxLevel = 2, Costs = { 400, 1200 } },
	{ Key = "Regen", Name = "Regeneration", Icon = "🌱", Desc = "+0.2 HP per second", Stat = "Regen", PerLevel = 0.2, MaxLevel = 3, Costs = { 200, 450, 900 } },
	{ Key = "Luck", Name = "Luck", Icon = "🍀", Desc = "+5% luck", Stat = "Luck", PerLevel = 0.05, MaxLevel = 3, Costs = { 250, 550, 1000 } },
	{ Key = "Reroll", Name = "Rerolls", Icon = "🔄", Desc = "+1 reroll per run", Stat = "Rerolls", PerLevel = 1, MaxLevel = 3, Costs = { 300, 700, 1500 } },
	{ Key = "Revive", Name = "Revival", Icon = "💖", Desc = "+1 revive per run", Stat = "Revives", PerLevel = 1, MaxLevel = 1, Costs = { 2500 } },
	{ Key = "ExtraWeapon", Name = "+1 Starting Weapon", Icon = "🎁", Desc = "Start with a random extra weapon", Stat = "ExtraWeapons", PerLevel = 1, MaxLevel = 1, Costs = { 3000 } },
	{ Key = "WeaponSlot", Name = "Weapon Slot", Icon = "🎒", Desc = "+1 weapon slot (up to 10 weapons)", Stat = "WeaponSlots", PerLevel = 1, MaxLevel = 4, Costs = { 600, 1400, 3000, 6000 } },
} :: { MetaDef }

MetaData.ByKey = {} :: { [string]: MetaDef }
for _, def in MetaData.Upgrades do
	MetaData.ByKey[def.Key] = def
end

function MetaData.Cost(key: string, currentLevel: number): number?
	local def = MetaData.ByKey[key]
	if not def or currentLevel >= def.MaxLevel then
		return nil
	end
	return def.Costs[currentLevel + 1]
end

-- Brain Level (account level): XP needed for level -> level + 1
function MetaData.BrainXPNeeded(level: number): number
	return math.floor(120 * level ^ 1.35)
end

function MetaData.BrainLevel(totalXP: number): (number, number, number)
	local level = 1
	local xp = math.max(0, math.floor(totalXP))
	while level < 999 do
		local need = MetaData.BrainXPNeeded(level)
		if xp < need then
			return level, xp, need
		end
		xp -= need
		level += 1
	end
	return level, 0, 1
end

MetaData.Titles = {
	{ Level = 1, Title = "Fresh Goober" },
	{ Level = 5, Title = "Certified NPC" },
	{ Level = 10, Title = "Side Character" },
	{ Level = 20, Title = "Sigma Apprentice" },
	{ Level = 35, Title = "Main Character" },
	{ Level = 50, Title = "Brainrot Legend" },
	{ Level = 67, Title = "THE 67" },
}

function MetaData.TitleFor(level: number): string
	local title = MetaData.Titles[1].Title
	for _, t in MetaData.Titles do
		if level >= t.Level then
			title = t.Title
		end
	end
	return title
end

-- daily login reward by streak day (1..7, day 7 repeats)
MetaData.DailyRewards = { 50, 75, 100, 150, 200, 250, 500 }

return MetaData
