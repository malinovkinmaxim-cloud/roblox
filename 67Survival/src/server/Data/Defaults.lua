--[[
	Defaults - the saved profile: default values and Reconcile().

	Reconcile(raw) returns a CLEAN DEEP COPY of a profile: unknown keys are dropped, missing
	keys get defaults, wrong types are replaced, numbers are finite and clamped. It is used
	on load (old / corrupted data) and before every save (nothing weird ever reaches the
	DataStore). Version 1 profiles (before 67 SURVIVAL) are migrated here too.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local WeaponData = require(Shared.WeaponData)
local UpgradeData = require(Shared.UpgradeData)
local HeroData = require(Shared.HeroData)
local MetaData = require(Shared.MetaData)
local AchievementData = require(Shared.AchievementData)
local EnemyData = require(Shared.EnemyData)
local WaveData = require(Shared.WaveData)
local MonetizationData = require(Shared.MonetizationData)
local CosmeticData = require(Shared.CosmeticData)
local DifficultyData = require(Shared.DifficultyData)
local GameConfig = require(Shared.GameConfig)

local Defaults = {}

Defaults.Version = 2

Defaults.StatKeys = {
	"Runs", "Wins", "Kills", "Bosses", "BossKinds", "BestTime", "BestLevel", "BestKills", "Deaths",
	"Events67", "EventKinds", "LifetimeCoins", "PlayTime", "Crates", "Rares", "Gems", "Evolutions",
	"Collected", "HeroCount", "PartyRuns", "LifetimeFragments", "BestEvolutions",
	"HighestWin", -- the highest difficulty tier won
	"Supported", "SupportedRobux", -- SUPPORT purchases (donations): how many, Robux in total
}

Defaults.SettingKeys = {
	Sfx = true,
	Music = true,
	Shake = true,
	DamageNumbers = true,
	LowQuality = false,
	HeroOutline = true, -- an outline around your hero in a run (easy to find in a crowd)
	FewerEffects = false, -- fewer particles, fainter ability areas
}

Defaults.MaxLoadouts = 3

local function finite(n: any, fallback: number, lo: number?, hi: number?): number
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return fallback
	end
	if lo and n < lo then
		n = lo
	end
	if hi and n > hi then
		n = hi
	end
	return n
end

local function int(n: any, fallback: number, lo: number?, hi: number?): number
	return math.floor(finite(n, fallback, lo, hi))
end

local function str(s: any, fallback: string, maxLen: number?): string
	if type(s) ~= "string" then
		return fallback
	end
	return string.sub(s, 1, maxLen or 64)
end

local function tbl(t: any): { [any]: any }
	return if type(t) == "table" then t else {}
end

-- a set of known keys -> true
local function keySet(raw: any, known: { [string]: any }): { [string]: boolean }
	local out = {}
	for key, v in tbl(raw) do
		if v == true and type(key) == "string" and known[key] then
			out[key] = true
		end
	end
	return out
end

-- a daily / weekly quest list
local function questList(raw: any, byKey: { [string]: any }, max: number)
	local out = {}
	local list = tbl(raw)
	for i = 1, math.min(#list, max) do
		local q = list[i]
		if type(q) == "table" and type(q.Key) == "string" and byKey[q.Key] then
			table.insert(out, {
				Key = q.Key,
				Progress = int(q.Progress, 0, 0, 1e9),
				Claimed = q.Claimed == true,
			})
		end
	end
	return out
end

function Defaults.New()
	return Defaults.Reconcile(nil)
end

function Defaults.Reconcile(raw: any)
	local r = tbl(raw)
	local out = {}
	out.Version = Defaults.Version
	out.Coins = int(r.Coins, 0, 0, 1e12)
	out.Fragments = int(r.Fragments, 0, 0, 1e9)
	out.XP = int(r.XP or r.BrainXP, 0, 0, 1e12) -- BrainXP: version 1 name
	out.CreatedAt = int(r.CreatedAt, 0, 0)
	out.LastSeen = int(r.LastSeen, 0, 0)

	-- heroes
	out.Heroes = {}
	local rh = tbl(r.Heroes)
	for _, def in HeroData.List do
		out.Heroes[def.Key] = (def.Unlock.Default == true) or rh[def.Key] == true
	end
	out.Selected = str(r.Selected, HeroData.Default)
	if not out.Heroes[out.Selected] then
		out.Selected = HeroData.Default
	end

	-- abilities that can show up in runs (weapons + secret passives)
	out.Weapons = {}
	local rw = tbl(r.Weapons)
	for _, def in WeaponData.List do
		if def.Evolution == nil then
			out.Weapons[def.Key] = (def.Unlock.Default == true) or rw[def.Key] == true
		end
	end
	for _, def in UpgradeData.Passives do
		if def.Secret then
			out.Weapons[def.Key] = rw[def.Key] == true
		end
	end
	out.StartWeapon = str(r.StartWeapon, "")
	if out.StartWeapon ~= "" and not (out.Weapons[out.StartWeapon] and WeaponData.ByKey[out.StartWeapon]) then
		out.StartWeapon = ""
	end

	-- loadouts: hero + starting ability (1 slot, 3 with the Extra Loadout pass)
	out.Loadouts = {}
	local rl = tbl(r.Loadouts)
	for i = 1, Defaults.MaxLoadouts do
		local l = tbl(rl[i])
		local hero = str(l.Hero, "")
		local weapon = str(l.StartWeapon, "")
		if not out.Heroes[hero] then
			hero = if i == 1 then out.Selected else ""
		end
		if weapon ~= "" and not (out.Weapons[weapon] and WeaponData.ByKey[weapon]) then
			weapon = ""
		end
		out.Loadouts[i] = { Hero = hero, StartWeapon = weapon }
	end
	out.Loadout = int(r.Loadout, 1, 1, Defaults.MaxLoadouts)

	out.Meta = {}
	local rm = tbl(r.Meta)
	for _, def in MetaData.Upgrades do
		out.Meta[def.Key] = int(rm[def.Key], 0, 0, def.MaxLevel)
	end

	-- cosmetics
	local rc = tbl(r.Cosmetics)
	out.Cosmetics = { Owned = {}, Equipped = {}, New = {} }
	local owned = tbl(rc.Owned)
	for _, def in CosmeticData.List do
		if def.Default or owned[def.Id] == true then
			out.Cosmetics.Owned[def.Id] = true
		end
	end
	if type(r.Skins) == "table" then -- version 1 hats
		for key, v in r.Skins do
			local id = "Hat." .. tostring(key)
			if v == true and CosmeticData.ById[id] then
				out.Cosmetics.Owned[id] = true
			end
		end
	end
	local equipped = tbl(rc.Equipped)
	if equipped.Hat == nil and type(r.EquippedSkin) == "string" then
		equipped.Hat = "Hat." .. r.EquippedSkin
	end
	for _, cat in CosmeticData.Categories do
		local id = equipped[cat.Key]
		local def = type(id) == "string" and CosmeticData.ById[id]
		if def and def.Category == cat.Key and out.Cosmetics.Owned[id] then
			out.Cosmetics.Equipped[cat.Key] = id
		else
			out.Cosmetics.Equipped[cat.Key] = CosmeticData.DefaultOf[cat.Key]
		end
	end
	for id, v in tbl(rc.New) do
		if v == true and out.Cosmetics.Owned[id] then
			out.Cosmetics.New[id] = true
		end
	end
	out.CosmeticBoostUntil = int(r.CosmeticBoostUntil, 0, 0)

	-- achievements: key -> unix time (0 = not unlocked)
	out.Achievements = {}
	local ra = tbl(r.Achievements)
	for _, def in AchievementData.List do
		local t = int(ra[def.Key], 0, 0)
		if t > 0 then
			out.Achievements[def.Key] = t
		end
	end

	out.Stats = {}
	local rs = tbl(r.Stats)
	for _, key in Defaults.StatKeys do
		out.Stats[key] = int(rs[key], 0, 0, 1e12)
	end

	-- collection: kills per enemy / boss, and what was seen in runs
	out.Collection = {}
	local rcol = tbl(r.Collection)
	for _, def in EnemyData.List do
		local n = int(rcol[def.Key], 0, 0, 1e12)
		if n > 0 then
			out.Collection[def.Key] = n
		end
	end
	local rseen = tbl(r.Seen)
	local passives, evolutions, events = {}, {}, {}
	for _, def in UpgradeData.Passives do
		passives[def.Key] = true
	end
	for _, def in WeaponData.Evolutions do
		evolutions[def.Key] = true
	end
	for _, e in WaveData.Events do
		events[e.Key] = true
	end
	local weapons = {}
	for _, def in WeaponData.List do
		if def.Evolution == nil then
			weapons[def.Key] = true
		end
	end
	out.Seen = {
		Weapons = keySet(rseen.Weapons, weapons),
		Passives = keySet(rseen.Passives, passives),
		Evolutions = keySet(rseen.Evolutions, evolutions),
		Events = keySet(rseen.Events, events),
	}

	-- difficulty: the selected tier, the best result per tier (unlocks), first clears paid
	local rdiff = r.Difficulty
	local best = {}
	local cleared = {}
	if type(rdiff) == "table" then
		local rbest = tbl(rdiff.Best)
		for i = 1, DifficultyData.Count do
			local b = tbl(rbest[i])
			best[i] = { Time = int(b.Time, 0, 0, 1e6), Bosses = int(b.Bosses, 0, 0, 1e9), Wins = int(b.Wins, 0, 0, 1e9) }
			cleared[i] = tbl(rdiff.Cleared)[i] == true
		end
	else
		-- a profile from before difficulties: everything so far was played on the classic
		-- balance (tier II). Nobody loses access to what they could already play.
		local stats = out.Stats
		for i = 1, DifficultyData.Count do
			best[i] = { Time = 0, Bosses = 0, Wins = 0 }
			cleared[i] = false
		end
		if stats.Bosses > 0 or stats.BestTime > 0 then
			best[1] = { Time = stats.BestTime, Bosses = math.min(stats.Bosses, 1), Wins = 0 }
			best[2] = { Time = stats.BestTime, Bosses = stats.Bosses, Wins = stats.Wins }
			cleared[2] = stats.Wins > 0
			if stats.Wins > 0 then
				out.Stats.HighestWin = math.max(out.Stats.HighestWin, 2)
			end
		end
	end
	local open = DifficultyData.Unlocked(best)
	local selected = if type(rdiff) == "table" then int(tbl(rdiff).Selected, 1, 1, DifficultyData.Count) else (if open >= 2 then 2 else 1)
	out.Difficulty = {
		Selected = math.min(selected, open),
		Best = best,
		Cleared = cleared,
	}

	-- daily reward
	local rd = tbl(r.Daily)
	out.Daily = {
		Day = int(rd.Day, 0, 0),
		Streak = int(rd.Streak, 0, 0, 10000),
	}

	-- daily quests / weekly challenges
	local rq = tbl(r.Quests)
	out.Quests = { Day = int(rq.Day, 0, 0), List = questList(rq.List, AchievementData.QuestByKey, AchievementData.QuestsPerDay) }
	local rwk = tbl(r.Weekly)
	local heroes = {}
	for _, def in HeroData.List do
		heroes[def.Key] = true
	end
	out.Weekly = {
		Week = int(rwk.Week, 0, 0),
		List = questList(rwk.List, AchievementData.WeeklyByKey, AchievementData.WeeklyPerWeek),
		Heroes = keySet(rwk.Heroes, heroes),
	}

	-- AFK camp
	local rafk = tbl(r.Afk)
	local slots = {}
	local rslots = tbl(rafk.Slots)
	for i = 1, #GameConfig.Afk.SlotCosts + 1 do
		local key = rslots[i]
		slots[i] = if type(key) == "string" and out.Heroes[key] then key else ""
	end
	out.Afk = {
		Since = int(rafk.Since, 0, 0),
		SlotCount = int(rafk.SlotCount, 1, 1, #GameConfig.Afk.SlotCosts),
		Slots = slots,
		BoostUntil = int(rafk.BoostUntil, 0, 0),
	}

	out.Settings = {}
	local rset = tbl(r.Settings)
	for key, default in Defaults.SettingKeys do
		local v = rset[key]
		out.Settings[key] = if type(v) == type(default) then v else default
	end

	-- purchases
	out.Receipts = {}
	if type(r.Receipts) == "table" then
		-- keep the most recent 50 receipt ids (idempotent ProcessReceipt)
		local n = 0
		for _, id in r.Receipts do
			if type(id) == "string" and n < 50 then
				n += 1
				out.Receipts[n] = string.sub(id, 1, 64)
			end
		end
	end
	out.StudioPasses = {}
	for _, def in MonetizationData.Passes do
		if tbl(r.StudioPasses)[def.Key] == true then
			out.StudioPasses[def.Key] = true
		end
	end
	out.SecretsFound = {}
	for _, key in { "TouchGrass", "Backrooms" } do
		if tbl(r.SecretsFound)[key] == true then
			out.SecretsFound[key] = true
		end
	end
	out.LastRunDay = int(r.LastRunDay, 0, 0)
	out.RedeemedCodes = {}
	local n = 0
	for code, done in tbl(r.RedeemedCodes) do
		if type(code) == "string" and #code <= 20 and done == true and n < 200 then
			n += 1
			out.RedeemedCodes[code] = true
		end
	end
	return out
end

return Defaults
