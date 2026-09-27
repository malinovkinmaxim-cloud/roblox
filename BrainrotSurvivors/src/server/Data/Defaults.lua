--[[
	Defaults - the saved profile: default values and Reconcile().

	Reconcile(raw) returns a CLEAN DEEP COPY of a profile: unknown keys are dropped, missing
	keys get defaults, wrong types are replaced, numbers are finite and clamped. It is used
	on load (old / corrupted data) and before every save (nothing weird ever reaches the
	DataStore).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local WeaponData = require(Shared.WeaponData)
local CharacterData = require(Shared.CharacterData)
local MetaData = require(Shared.MetaData)
local AchievementData = require(Shared.AchievementData)
local EnemyData = require(Shared.EnemyData)
local MonetizationData = require(Shared.MonetizationData)
local SkinData = require(Shared.SkinData)

local Defaults = {}

Defaults.Version = 1

Defaults.StatKeys = {
	"Runs", "Wins", "Kills", "Bosses", "BossKinds", "BestTime", "BestLevel", "BestKills", "Deaths",
	"Events67", "LifetimeCoins", "PlayTime", "Crates", "Rares", "Gems",
}

Defaults.SettingKeys = {
	Sfx = true,
	Music = true,
	Shake = true,
	DamageNumbers = true,
	LowQuality = false,
}

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

function Defaults.New()
	return Defaults.Reconcile(nil)
end

function Defaults.Reconcile(raw: any)
	local r = if type(raw) == "table" then raw else {}
	local out = {}
	out.Version = Defaults.Version
	out.Coins = int(r.Coins, 0, 0, 1e12)
	out.BrainXP = int(r.BrainXP, 0, 0, 1e12)
	out.CreatedAt = int(r.CreatedAt, 0, 0)
	out.LastSeen = int(r.LastSeen, 0, 0)

	-- unlocks
	out.Characters = {}
	local rc = if type(r.Characters) == "table" then r.Characters else {}
	for _, def in CharacterData.List do
		out.Characters[def.Key] = (def.Unlock.Default == true) or rc[def.Key] == true
	end
	out.Selected = str(r.Selected, CharacterData.Default)
	if not out.Characters[out.Selected] then
		out.Selected = CharacterData.Default
	end

	out.Weapons = {}
	local rw = if type(r.Weapons) == "table" then r.Weapons else {}
	for _, def in WeaponData.List do
		out.Weapons[def.Key] = (def.Unlock.Default == true) or rw[def.Key] == true
	end
	out.StartWeapon = str(r.StartWeapon, "")
	if out.StartWeapon ~= "" and not out.Weapons[out.StartWeapon] then
		out.StartWeapon = ""
	end

	out.Skins = {}
	local rsk = if type(r.Skins) == "table" then r.Skins else {}
	for _, def in SkinData.List do
		out.Skins[def.Key] = (def.Default == true) or rsk[def.Key] == true
	end
	out.EquippedSkin = str(r.EquippedSkin, SkinData.Default)
	if not out.Skins[out.EquippedSkin] then
		out.EquippedSkin = SkinData.Default
	end

	out.Meta = {}
	local rm = if type(r.Meta) == "table" then r.Meta else {}
	for _, def in MetaData.Upgrades do
		out.Meta[def.Key] = int(rm[def.Key], 0, 0, def.MaxLevel)
	end

	-- achievements: key -> unix time (0 = not unlocked)
	out.Achievements = {}
	local ra = if type(r.Achievements) == "table" then r.Achievements else {}
	for _, def in AchievementData.List do
		local t = int(ra[def.Key], 0, 0)
		if t > 0 then
			out.Achievements[def.Key] = t
		end
	end

	out.Stats = {}
	local rs = if type(r.Stats) == "table" then r.Stats else {}
	for _, key in Defaults.StatKeys do
		out.Stats[key] = int(rs[key], 0, 0, 1e12)
	end

	-- collections: kills per enemy, kills per boss
	out.Collection = {}
	local rcol = if type(r.Collection) == "table" then r.Collection else {}
	for _, def in EnemyData.List do
		local n = int(rcol[def.Key], 0, 0, 1e12)
		if n > 0 then
			out.Collection[def.Key] = n
		end
	end

	-- daily reward
	local rd = if type(r.Daily) == "table" then r.Daily else {}
	out.Daily = {
		Day = int(rd.Day, 0, 0),
		Streak = int(rd.Streak, 0, 0, 10000),
	}

	-- daily quests
	local rq = if type(r.Quests) == "table" then r.Quests else {}
	out.Quests = { Day = int(rq.Day, 0, 0), List = {} }
	if type(rq.List) == "table" then
		for i = 1, math.min(#rq.List, AchievementData.QuestsPerDay) do
			local q = rq.List[i]
			if type(q) == "table" and type(q.Key) == "string" and AchievementData.QuestByKey[q.Key] then
				table.insert(out.Quests.List, {
					Key = q.Key,
					Progress = int(q.Progress, 0, 0, 1e9),
					Claimed = q.Claimed == true,
				})
			end
		end
	end

	out.Settings = {}
	local rset = if type(r.Settings) == "table" then r.Settings else {}
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
	out.CoinRushUntil = int(r.CoinRushUntil, 0, 0)
	out.StudioPasses = {}
	if type(r.StudioPasses) == "table" then
		for _, def in MonetizationData.Passes do
			if r.StudioPasses[def.Key] == true then
				out.StudioPasses[def.Key] = true
			end
		end
	end
	out.SecretsFound = {}
	if type(r.SecretsFound) == "table" then
		for _, key in { "TouchGrass", "Backrooms" } do
			if r.SecretsFound[key] == true then
				out.SecretsFound[key] = true
			end
		end
	end
	out.LastRunDay = int(r.LastRunDay, 0, 0)
	return out
end

return Defaults
