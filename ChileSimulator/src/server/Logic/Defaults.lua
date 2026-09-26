--[[
	Defaults - the saved data schema + Reconcile (fills missing fields, repairs bad values).

	Reconcile runs on every load, so adding a field later only means adding it here.
	Every number is sanitized (NaN / inf / negative -> safe value) so a corrupted save or an
	old bug can never poison the economy.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Config = require(Shared.Config)
local PetConfig = require(Shared.PetConfig)
local BoostConfig = require(Shared.BoostConfig)
local CosmeticConfig = require(Shared.CosmeticConfig)
local ShopConfig = require(Shared.ShopConfig)
local Num = require(Shared.Util.Num)

local Defaults = {}

Defaults.MAX_RECEIPTS = 60

function Defaults.New()
	return {
		Version = Config.DATA_VERSION,
		Height = Config.START_HEIGHT,
		BestHeight = Config.START_HEIGHT,
		Coins = 0,
		Gems = 0,
		Rebirths = 0,
		Taps = 0,
		TapLevel = 1,
		AutoLevel = 0,
		Gem = { TapBonus = 0, AutoBonus = 0, CoinBonus = 0, Luck = 0, Storage = 0 },
		Pets = {}, -- [uid] = { Id = petId, E = equipped? }
		NextPetUid = 1,
		Boosts = { Inventory = {}, Active = {} }, -- [boostId] = count / seconds left
		Trails = { Owned = {}, Equipped = "" },
		Auras = { Owned = {}, Equipped = "" },
		Achievements = {}, -- [id] = true
		Milestones = {}, -- [id] = true
		Daily = { Streak = 0, LastDay = -1 },
		Quests = { Day = -1, Progress = { Taps = 0, Grown = 0, Rebirths = 0 }, Claimed = {} },
		Stats = { Hatched = 0, Legendaries = 0, Secrets = 0, Events = 0, Chests = 0, PlayTime = 0 },
		Settings = {
			Sfx = true,
			Shake = true,
			Numbers = true,
			OthersFx = true,
			LowGraphics = false,
			AutoTap = true,
			OneButton = true, -- one-button mode: tap only, the server plays the rest (Logic/AutoPlay)
		},
		Tutorial = 0,
		HistogramBucket = -1, -- bucket this player is counted in (global "taller than X%")
		AnnouncedPercentile = 0,
		Receipts = {}, -- processed developer product receipts (idempotency)
		CreatedAt = 0,
		LastSeen = 0,
	}
end

local function num(value: any, fallback: number, min: number?, max: number?): number
	local v = Num.Sanitize(value, fallback)
	if min and v < min then
		v = min
	end
	if max and v > max then
		v = max
	end
	return v
end

local function int(value: any, fallback: number, min: number?, max: number?): number
	return math.floor(num(value, fallback, min, max))
end

local function bool(value: any, fallback: boolean): boolean
	if type(value) == "boolean" then
		return value
	end
	return fallback
end

local function tableOr(value: any): { [any]: any }
	return if type(value) == "table" then value else {}
end

-- Returns a clean data table (new table; the input is not trusted).
function Defaults.Reconcile(raw: any)
	local d = Defaults.New()
	if type(raw) ~= "table" then
		return d
	end

	d.Height = num(raw.Height, Config.START_HEIGHT, Config.START_HEIGHT)
	d.BestHeight = math.max(d.Height, num(raw.BestHeight, d.Height, Config.START_HEIGHT))
	d.Coins = num(raw.Coins, 0, 0)
	d.Gems = num(raw.Gems, 0, 0)
	d.Rebirths = int(raw.Rebirths, 0, 0)
	d.Taps = num(raw.Taps, 0, 0)
	d.TapLevel = int(raw.TapLevel, 1, 1, Config.Upgrades.TapPower.MaxLevel)
	d.AutoLevel = int(raw.AutoLevel, 0, 0, Config.Upgrades.AutoGrow.MaxLevel)

	local gem = tableOr(raw.Gem)
	for id, def in ShopConfig.GemUpgrades do
		d.Gem[id] = int(gem[id], 0, 0, def.MaxLevel)
	end

	-- pets: drop unknown ids, keep uids as strings
	local maxUid = 0
	for uid, pet in tableOr(raw.Pets) do
		if type(pet) == "table" and type(pet.Id) == "string" and PetConfig.Pets[pet.Id] then
			local key = tostring(uid)
			d.Pets[key] = { Id = pet.Id, E = pet.E == true }
			local n = tonumber(key)
			if n and n > maxUid then
				maxUid = n
			end
		end
	end
	d.NextPetUid = math.max(int(raw.NextPetUid, 1, 1), maxUid + 1)

	local boosts = tableOr(raw.Boosts)
	for id in BoostConfig.Boosts do
		local count = int(tableOr(boosts.Inventory)[id], 0, 0, 9999)
		if count > 0 then
			d.Boosts.Inventory[id] = count
		end
		local left = num(tableOr(boosts.Active)[id], 0, 0, BoostConfig.MaxStackedSeconds)
		if left > 0 then
			d.Boosts.Active[id] = left
		end
	end

	for _, kind in { "Trails", "Auras" } do
		local list = if kind == "Trails" then CosmeticConfig.Trails else CosmeticConfig.Auras
		local src = tableOr(raw[kind])
		for id, owned in tableOr(src.Owned) do
			if owned == true and list[id] then
				d[kind].Owned[id] = true
			end
		end
		local equipped = src.Equipped
		if type(equipped) == "string" and list[equipped] then
			d[kind].Equipped = equipped
		end
	end

	for id, v in tableOr(raw.Achievements) do
		if v == true and type(id) == "string" then
			d.Achievements[id] = true
		end
	end
	for id, v in tableOr(raw.Milestones) do
		if v == true and type(id) == "string" then
			d.Milestones[id] = true
		end
	end

	local daily = tableOr(raw.Daily)
	d.Daily.Streak = int(daily.Streak, 0, 0, 1e6)
	d.Daily.LastDay = int(daily.LastDay, -1, -1)

	local quests = tableOr(raw.Quests)
	d.Quests.Day = int(quests.Day, -1, -1)
	local progress = tableOr(quests.Progress)
	d.Quests.Progress.Taps = num(progress.Taps, 0, 0)
	d.Quests.Progress.Grown = num(progress.Grown, 0, 0)
	d.Quests.Progress.Rebirths = num(progress.Rebirths, 0, 0)
	for id, v in tableOr(quests.Claimed) do
		if v == true and type(id) == "string" then
			d.Quests.Claimed[id] = true
		end
	end

	local stats = tableOr(raw.Stats)
	for key in d.Stats do
		d.Stats[key] = num(stats[key], 0, 0)
	end

	local settings = tableOr(raw.Settings)
	for key, default in d.Settings do
		d.Settings[key] = bool(settings[key], default)
	end

	d.Tutorial = int(raw.Tutorial, 0, 0, 100)
	d.HistogramBucket = int(raw.HistogramBucket, -1, -1, 5000)
	d.AnnouncedPercentile = num(raw.AnnouncedPercentile, 0, 0, 100)

	-- keep the most recent receipts
	local receipts = tableOr(raw.Receipts)
	for i = math.max(1, #receipts - Defaults.MAX_RECEIPTS + 1), #receipts do
		if type(receipts[i]) == "string" then
			table.insert(d.Receipts, receipts[i])
		end
	end

	d.CreatedAt = int(raw.CreatedAt, 0, 0)
	d.LastSeen = int(raw.LastSeen, 0, 0)
	return d
end

return Defaults
