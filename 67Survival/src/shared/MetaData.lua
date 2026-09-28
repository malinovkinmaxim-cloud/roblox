--[[
	MetaData - permanent progression between runs.

	  Coins     -> permanent upgrades (below), cosmetics, AFK camp slots
	  Fragments -> new heroes and new abilities (HeroData / WeaponData Unlock)
	  XP        -> account level (titles, AFK camp efficiency)

	Permanent upgrades are small on purpose (+5% per level): they make the next run a
	little easier without replacing skill and level-up choices. A new player is never
	helpless: every default hero and 18 abilities are available from the first run.
]]

export type MetaDef = {
	Key: string,
	Name: string,
	Desc: string,
	Stat: string,
	PerLevel: number,
	MaxLevel: number,
	Costs: { number },
}

local MetaData = {}

MetaData.Upgrades = {
	{ Key = "Might", Name = "Starting Damage", Desc = "+5% damage", Stat = "Might", PerLevel = 0.05, MaxLevel = 5, Costs = { 100, 220, 400, 650, 1000 } },
	{ Key = "MaxHP", Name = "Starting HP", Desc = "+5% max HP", Stat = "MaxHPMult", PerLevel = 0.05, MaxLevel = 5, Costs = { 100, 220, 400, 650, 1000 } },
	{ Key = "MoveSpeed", Name = "Movement Speed", Desc = "+5% movement speed", Stat = "MoveSpeed", PerLevel = 0.05, MaxLevel = 3, Costs = { 150, 350, 700 } },
	{ Key = "Growth", Name = "XP Gain", Desc = "+5% XP", Stat = "Growth", PerLevel = 0.05, MaxLevel = 5, Costs = { 120, 260, 450, 700, 1100 } },
	{ Key = "Greed", Name = "Coin Gain", Desc = "+10% coins", Stat = "Greed", PerLevel = 0.1, MaxLevel = 5, Costs = { 150, 300, 550, 900, 1400 } },
	{ Key = "Magnet", Name = "Pickup Range", Desc = "+10% pickup range", Stat = "Magnet", PerLevel = 0.1, MaxLevel = 3, Costs = { 100, 250, 500 } },
	{ Key = "Armor", Name = "Armor", Desc = "-1 damage from every hit", Stat = "Armor", PerLevel = 1, MaxLevel = 2, Costs = { 400, 1200 } },
	{ Key = "Regen", Name = "Regeneration", Desc = "+0.2 HP per second", Stat = "Regen", PerLevel = 0.2, MaxLevel = 3, Costs = { 200, 450, 900 } },
	{ Key = "Luck", Name = "Luck", Desc = "+5% luck", Stat = "Luck", PerLevel = 0.05, MaxLevel = 3, Costs = { 250, 550, 1000 } },
	{ Key = "Reroll", Name = "Rerolls", Desc = "+1 reroll per run", Stat = "Rerolls", PerLevel = 1, MaxLevel = 3, Costs = { 300, 700, 1500 } },
	{ Key = "Revive", Name = "Revival", Desc = "+1 revive per run", Stat = "Revives", PerLevel = 1, MaxLevel = 1, Costs = { 2500 } },
	{ Key = "ExtraWeapon", Name = "+1 Starting Ability", Desc = "Start with a random extra ability", Stat = "ExtraWeapons", PerLevel = 1, MaxLevel = 1, Costs = { 3000 } },
	{ Key = "WeaponSlot", Name = "Ability Slot", Desc = "+1 ability slot (up to 10)", Stat = "WeaponSlots", PerLevel = 1, MaxLevel = 4, Costs = { 600, 1400, 3000, 6000 } },
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

-- account level: XP needed for level -> level + 1
function MetaData.XPNeeded(level: number): number
	return math.floor(120 * level ^ 1.35)
end

-- account level from total XP -> level, xp into the level, xp needed for the next
function MetaData.Level(totalXP: number): (number, number, number)
	local level = 1
	local xp = math.max(0, math.floor(totalXP))
	while level < 999 do
		local need = MetaData.XPNeeded(level)
		if xp < need then
			return level, xp, need
		end
		xp -= need
		level += 1
	end
	return level, 0, 1
end

MetaData.Titles = {
	{ Level = 1, Title = "Rookie" },
	{ Level = 5, Title = "Survivor" },
	{ Level = 10, Title = "Horde Breaker" },
	{ Level = 20, Title = "Veteran" },
	{ Level = 35, Title = "Unstoppable" },
	{ Level = 50, Title = "Legend" },
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
