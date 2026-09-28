--[[
	DifficultyData - the difficulty ladder picked before a run: HERO -> DIFFICULTY -> PLAY.

	Seven tiers, from a gentle start to THE 67. Every tier is clearly harder than the one
	before it AND pays more. Harder tiers do not only raise numbers: from tier III on they
	switch on new RULES (modifiers), a few at a time:

	  FASTER HORDE    the whole horde moves faster
	  ELITE INVASION  elites from 1:30 instead of 2:30, and far more of them
	  BOSS RAGE       bosses arrive with their enraged attacks and enrage sooner
	  CHAOS           67 events come sooner and the arena throws random surprises at you
	  GLITCH          every few seconds part of the horde glitches in next to you
	  LOW XP          -15% XP
	  NO MERCY        shorter wind-ups, faster enemy shots, a denser horde
	  67 CHAOS        67 events last longer and give double loot; THE 67 comes more often

	Numbers per tier (multipliers of the normal game):
	  EnemyHP EnemyDamage EnemySpeed Spawn (rate + minimum horde) Elite (chance)
	  BossHP BossDamage XP Reward (coins + account XP) Fragments (+ per run, again on a win)
	  Luck (+ rarer cards and drops) Events (67 event frequency)

	Unlocks: the next tier opens after a goal on the one before (defeat a boss, survive 10
	minutes, win). Higher tiers are never needed for normal progress: heroes, abilities and
	upgrades are earned on any tier; hard tiers pay faster and have their own rewards
	(achievements, cosmetics, titles, a first clear bonus).

	Tier II (HUNT) is the classic balance of the game; tier I is gentler for new players.
]]

local DifficultyData = {}

local rgb = Color3.fromRGB

export type Modifier = { Key: string, Name: string, Desc: string }

DifficultyData.Modifiers = {
	FasterHorde = { Key = "FasterHorde", Name = "FASTER HORDE", Desc = "The horde moves faster." },
	EliteInvasion = { Key = "EliteInvasion", Name = "ELITE INVASION", Desc = "Elites from 1:30, far more often." },
	BossRage = { Key = "BossRage", Name = "BOSS RAGE", Desc = "Bosses start with their enraged attacks." },
	Chaos = { Key = "Chaos", Name = "CHAOS", Desc = "67 events sooner, random arena surprises." },
	Glitch = { Key = "Glitch", Name = "GLITCH", Desc = "Part of the horde glitches in next to you." },
	LowXP = { Key = "LowXP", Name = "LOW XP", Desc = "-15% XP." },
	NoMercy = { Key = "NoMercy", Name = "NO MERCY", Desc = "Faster attacks and shots, a denser horde." },
	Chaos67 = { Key = "Chaos67", Name = "67 CHAOS", Desc = "67 events are stronger and loot doubles." },
} :: { [string]: Modifier }

export type Unlock = { Kind: string, Tier: number, Value: number?, Text: string }

export type Tier = {
	Index: number,
	Key: string,
	Name: string,
	Numeral: string,
	Desc: string,
	Color: Color3,
	Recommended: number, -- account level
	Title: string?, -- shown on the name tag once this tier is won (tier IV and up)
	Unlock: Unlock?,
	FirstClear: { Coins: number, Fragments: number },
	Mods: { string },
	EnemyHP: number,
	EnemyDamage: number,
	EnemySpeed: number,
	Spawn: number,
	Elite: number,
	BossHP: number,
	BossDamage: number,
	XP: number,
	Reward: number,
	Fragments: number,
	Luck: number,
	Events: number,
}

DifficultyData.List = {
	{
		Index = 1,
		Key = "Calm",
		Name = "CALM",
		Numeral = "I",
		Desc = "A gentler horde. Learn your hero.",
		Color = rgb(96, 196, 206),
		Recommended = 1,
		FirstClear = { Coins = 300, Fragments = 3 },
		Mods = {},
		EnemyHP = 0.7,
		EnemyDamage = 0.6,
		EnemySpeed = 1,
		Spawn = 1, -- the same horde (same XP), only softer
		Elite = 0.5,
		BossHP = 0.65,
		BossDamage = 0.6,
		XP = 1,
		Reward = 0.9,
		Fragments = 0,
		Luck = 0,
		Events = 1,
	},
	{
		Index = 2,
		Key = "Hunt",
		Name = "HUNT",
		Numeral = "II",
		Desc = "The real horde. The classic run.",
		Color = rgb(112, 204, 120),
		Recommended = 5,
		Unlock = { Kind = "Boss", Tier = 1, Text = "Defeat a boss on CALM" },
		FirstClear = { Coins = 600, Fragments = 5 },
		Mods = {},
		EnemyHP = 1,
		EnemyDamage = 1,
		EnemySpeed = 1,
		Spawn = 1,
		Elite = 1,
		BossHP = 1,
		BossDamage = 1,
		XP = 1,
		Reward = 1,
		Fragments = 0,
		Luck = 0,
		Events = 1,
	},
	{
		Index = 3,
		Key = "Horde",
		Name = "HORDE",
		Numeral = "III",
		Desc = "More of them, and faster.",
		Color = rgb(232, 202, 84),
		Recommended = 10,
		Unlock = { Kind = "Time", Tier = 2, Value = 600, Text = "Survive 10:00 on HUNT" },
		FirstClear = { Coins = 1000, Fragments = 8 },
		Mods = { "FasterHorde" },
		EnemyHP = 1.2,
		EnemyDamage = 1.1,
		EnemySpeed = 1.08,
		Spawn = 1.1,
		Elite = 1.3,
		BossHP = 1.2,
		BossDamage = 1.1,
		XP = 1.05,
		Reward = 1.3,
		Fragments = 1,
		Luck = 0.05,
		Events = 1.1,
	},
	{
		Index = 4,
		Key = "Nightmare",
		Name = "NIGHTMARE",
		Numeral = "IV",
		Desc = "Elites everywhere. Bosses come angry.",
		Color = rgb(240, 144, 64),
		Recommended = 15,
		Title = "Nightmare Walker",
		Unlock = { Kind = "Win", Tier = 3, Text = "Win on HORDE" },
		FirstClear = { Coins = 1600, Fragments = 12 },
		Mods = { "FasterHorde", "EliteInvasion", "BossRage" },
		EnemyHP = 1.5,
		EnemyDamage = 1.25,
		EnemySpeed = 1.1,
		Spawn = 1.2,
		Elite = 2.5,
		BossHP = 1.45,
		BossDamage = 1.2,
		XP = 1.1,
		Reward = 1.6,
		Fragments = 2,
		Luck = 0.1,
		Events = 1.2,
	},
	{
		Index = 5,
		Key = "Inferno",
		Name = "INFERNO",
		Numeral = "V",
		Desc = "The arena turns against you.",
		Color = rgb(236, 84, 72),
		Recommended = 20,
		Title = "Inferno Walker",
		Unlock = { Kind = "Win", Tier = 4, Text = "Win on NIGHTMARE" },
		FirstClear = { Coins = 2500, Fragments = 16 },
		Mods = { "FasterHorde", "EliteInvasion", "BossRage", "Chaos", "Glitch" },
		EnemyHP = 1.9,
		EnemyDamage = 1.4,
		EnemySpeed = 1.12,
		Spawn = 1.3,
		Elite = 3,
		BossHP = 1.8,
		BossDamage = 1.3,
		XP = 1.15,
		Reward = 2,
		Fragments = 3,
		Luck = 0.15,
		Events = 1.5,
	},
	{
		Index = 6,
		Key = "Oblivion",
		Name = "OBLIVION",
		Numeral = "VI",
		Desc = "No mercy. Every mistake counts.",
		Color = rgb(172, 96, 240),
		Recommended = 25,
		Title = "Beyond Oblivion",
		Unlock = { Kind = "Win", Tier = 5, Text = "Win on INFERNO" },
		FirstClear = { Coins = 4000, Fragments = 22 },
		Mods = { "FasterHorde", "EliteInvasion", "BossRage", "Chaos", "Glitch", "LowXP", "NoMercy" },
		EnemyHP = 2.4,
		EnemyDamage = 1.6,
		EnemySpeed = 1.15,
		Spawn = 1.4,
		Elite = 3.5,
		BossHP = 2.2,
		BossDamage = 1.45,
		XP = 0.85,
		Reward = 2.5,
		Fragments = 4,
		Luck = 0.2,
		Events = 1.5,
	},
	{
		Index = 7,
		Key = "The67",
		Name = "THE 67",
		Numeral = "VII",
		Desc = "Everything at once. Six. Seven.",
		Color = rgb(255, 204, 52),
		Recommended = 30,
		Title = "THE 67",
		Unlock = { Kind = "Win", Tier = 6, Text = "Win on OBLIVION" },
		FirstClear = { Coins = 6700, Fragments = 30 },
		Mods = { "FasterHorde", "EliteInvasion", "BossRage", "Chaos", "Glitch", "LowXP", "NoMercy", "Chaos67" },
		EnemyHP = 3,
		EnemyDamage = 1.8,
		EnemySpeed = 1.18,
		Spawn = 1.5,
		Elite = 4,
		BossHP = 2.7,
		BossDamage = 1.6,
		XP = 0.85,
		Reward = 3.2,
		Fragments = 6,
		Luck = 0.3,
		Events = 1.67,
	},
} :: { Tier }

DifficultyData.ByKey = {} :: { [string]: Tier }
for i, tier in DifficultyData.List do
	assert(tier.Index == i, "difficulty tiers must be listed in order")
	DifficultyData.ByKey[tier.Key] = tier
end
DifficultyData.Count = #DifficultyData.List
DifficultyData.Default = 1

function DifficultyData.Get(index: number?): Tier
	return DifficultyData.List[math.clamp(math.floor(index or 1), 1, #DifficultyData.List)]
end

function DifficultyData.Has(tier: Tier, mod: string): boolean
	return table.find(tier.Mods, mod) ~= nil
end

-- the modifiers a tier ADDS compared with the one before (shown as "NEW" in the menu)
function DifficultyData.NewMods(index: number): { string }
	local tier = DifficultyData.Get(index)
	local before = if index > 1 then DifficultyData.Get(index - 1) else nil
	local out = {}
	for _, key in tier.Mods do
		if not before or not table.find(before.Mods, key) then
			table.insert(out, key)
		end
	end
	return out
end

--[[
	Progress per tier (saved): { Time = best seconds, Bosses = bosses defeated, Wins = wins }.
	Returns true when `index` is open: tier I always, others after their goal on the tier
	before.
]]
export type Progress = { Time: number, Bosses: number, Wins: number }

function DifficultyData.GoalMet(tier: Tier, best: { Progress }): boolean
	local u = tier.Unlock
	if not u then
		return true
	end
	local p = best[u.Tier]
	if not p then
		return false
	end
	if u.Kind == "Boss" then
		return p.Bosses > 0 or p.Wins > 0
	elseif u.Kind == "Time" then
		return p.Time >= (u.Value or 0) or p.Wins > 0
	elseif u.Kind == "Win" then
		return p.Wins > 0
	end
	return false
end

-- the highest open tier (tiers open in order)
function DifficultyData.Unlocked(best: { Progress }): number
	local open = 1
	for i = 2, #DifficultyData.List do
		if DifficultyData.GoalMet(DifficultyData.List[i], best) then
			open = i
		else
			break
		end
	end
	return open
end

-- progress text towards a tier's goal ("best 6:32 / 10:00")
function DifficultyData.GoalProgress(tier: Tier, best: { Progress }): string
	local u = tier.Unlock
	if not u then
		return ""
	end
	local p = best[u.Tier] or { Time = 0, Bosses = 0, Wins = 0 }
	if u.Kind == "Time" then
		local function mmss(s: number): string
			return string.format("%d:%02d", s // 60, s % 60)
		end
		return string.format("best %s / %s", mmss(math.floor(p.Time)), mmss(u.Value or 0))
	elseif u.Kind == "Boss" then
		return if p.Bosses > 0 then "done" else "no boss defeated yet"
	end
	return if p.Wins > 0 then "done" else "not won yet"
end

-- the title of the highest tier won (tier IV and up), or nil
function DifficultyData.TitleFor(highestWin: number): string?
	for i = math.min(highestWin, #DifficultyData.List), 1, -1 do
		local title = DifficultyData.List[i].Title
		if title then
			return title
		end
	end
	return nil
end

-- the modifiers of a tier as a set (for the simulation)
function DifficultyData.ModSet(index: number): { [string]: boolean }
	local set = {}
	for _, key in DifficultyData.Get(index).Mods do
		set[key] = true
	end
	return set
end

return DifficultyData
