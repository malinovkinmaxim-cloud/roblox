-- Server-only: per-player save shared by the hub and the game place (same experience).
--   paws      soft currency, spent in the wardrobe
--   stars     score; only ever grows, sorts the leaderboards
--   completed modes per party size ("duo:easy" = true), endless records per party size
--   owned buddies/skins, current selection, processed Robux receipts
--   lastPlayedDate (daily bonus), clearedLevels (replays pay less), referral state
-- Loaded on join, saved on leave, on shutdown, before teleports and every AUTOSAVE seconds.
-- Publishes leaderstats (Paws, Stars) and player attributes for the UI, plus "SaveStatus".
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Buddies = require(script.Parent.Buddies)
local Config = require(script.Parent.Config)
local Modes = require(script.Parent.Modes)
local Parties = require(script.Parent.Parties)

local ProgressStore = {}

local STORE_NAME = "HopPalsProgress_v2"
local MAX_RECEIPTS = 50
local MAX_CLEARED = 600
local AUTOSAVE = 60

local STUDIO_HINT = "Progress is NOT saved: in Studio open Game Settings > Security and turn on "
	.. "'Enable Studio Access to API Services' (the place must be published)."

local store = nil
local storeError = nil
do
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(STORE_NAME)
	end)
	if not ok then
		storeError = tostring(err)
	end
end

local cache = {}
local dirty = {}

local function storeKey(player)
	return `p_{player.UserId}`
end

local function studioUnlocked()
	return RunService:IsStudio() and Config.STUDIO_UNLOCK_ALL
end

local function fresh()
	return {
		completed = {},
		endlessBest = {},
		paws = 0,
		stars = 0,
		classes = { bunny = true },
		skins = { classic = true },
		class = "bunny",
		skin = "classic",
		receipts = {},
		lastPlayedDate = "",
		clearedLevels = {},
		referredBy = 0,
		referralDone = false,
	}
end

local function today()
	return os.date("!%Y-%m-%d")
end

local function copySet(source, order)
	local set = {}
	if type(source) == "table" then
		for _, id in order do
			if source[id] == true then
				set[id] = true
			end
		end
	end
	return set
end

local function sanitize(saved)
	local data = fresh()
	if type(saved) ~= "table" then
		return data
	end
	if type(saved.completed) == "table" then
		for _, partyId in Parties.order do
			for _, modeId in Modes.order do
				local key = Modes.completedKey(partyId, modeId)
				if saved.completed[key] == true then
					data.completed[key] = true
				end
			end
		end
	end
	if type(saved.endlessBest) == "table" then
		for _, partyId in Parties.order do
			data.endlessBest[partyId] = math.max(0, math.floor(tonumber(saved.endlessBest[partyId]) or 0))
		end
	end
	data.paws = math.max(0, math.floor(tonumber(saved.paws) or 0))
	data.stars = math.max(0, math.floor(tonumber(saved.stars) or 0))
	data.classes = copySet(saved.classes, Buddies.classOrder)
	data.classes.bunny = true
	data.skins = copySet(saved.skins, Buddies.skinOrder)
	data.skins.classic = true
	if type(saved.class) == "string" and data.classes[saved.class] then
		data.class = saved.class
	end
	if type(saved.skin) == "string" and data.skins[saved.skin] then
		data.skin = saved.skin
	end
	if type(saved.receipts) == "table" then
		for _, receipt in saved.receipts do
			if type(receipt) == "string" then
				table.insert(data.receipts, receipt)
			end
		end
	end
	if type(saved.lastPlayedDate) == "string" then
		data.lastPlayedDate = saved.lastPlayedDate
	end
	if type(saved.clearedLevels) == "table" then
		local count = 0
		for key, value in saved.clearedLevels do
			if value == true and type(key) == "string" and count < MAX_CLEARED then
				data.clearedLevels[key] = true
				count += 1
			end
		end
	end
	data.referredBy = math.max(0, math.floor(tonumber(saved.referredBy) or 0))
	data.referralDone = saved.referralDone == true
	return data
end

-- Keeps the best of both copies, so a slower save from another server never loses progress
local function mergeInto(saved, current)
	local merged = sanitize(saved)
	for key in current.completed do
		merged.completed[key] = true
	end
	for partyId, best in current.endlessBest do
		merged.endlessBest[partyId] = math.max(merged.endlessBest[partyId] or 0, best)
	end
	merged.paws = current.paws
	merged.stars = math.max(merged.stars, current.stars)
	for id in current.classes do
		merged.classes[id] = true
	end
	for id in current.skins do
		merged.skins[id] = true
	end
	merged.class = current.class
	merged.skin = current.skin
	for _, receipt in current.receipts do
		if not table.find(merged.receipts, receipt) then
			table.insert(merged.receipts, receipt)
		end
	end
	while #merged.receipts > MAX_RECEIPTS do
		table.remove(merged.receipts, 1)
	end
	if current.lastPlayedDate > merged.lastPlayedDate then
		merged.lastPlayedDate = current.lastPlayedDate
	end
	for key in current.clearedLevels do
		merged.clearedLevels[key] = true
	end
	if merged.referredBy == 0 then
		merged.referredBy = current.referredBy
	end
	merged.referralDone = merged.referralDone or current.referralDone
	return merged
end

local function setSaveStatus(player, status, message)
	player:SetAttribute("SaveStatus", status)
	player:SetAttribute("SaveMessage", message or "")
end

local function describeFailure(err)
	local text = tostring(err)
	if RunService:IsStudio() then
		warn(`[HopPals] DataStore unavailable ({text}). {STUDIO_HINT}`)
		return "off", STUDIO_HINT
	end
	warn(`[HopPals] DataStore error: {text}`)
	return "failed", "Saving is having trouble right now. Your progress this session may not be kept."
end

function ProgressStore.get(player)
	return cache[player] or fresh()
end

function ProgressStore.isUnlocked(player, modeId, partyId)
	if studioUnlocked() then
		return Modes.get(modeId) ~= nil
	end
	return Modes.isUnlocked(modeId, ProgressStore.get(player).completed, partyId)
end

function ProgressStore.owns(player, kind, id)
	local catalog = Buddies.catalog(kind)
	if not catalog or not catalog[id] then
		return false
	end
	if studioUnlocked() then
		return true
	end
	local data = ProgressStore.get(player)
	local owned = if kind == "class" then data.classes else data.skins
	return owned[id] == true
end

local function ownedList(player, kind)
	local _, order = Buddies.catalog(kind)
	local list = {}
	for _, id in order do
		if ProgressStore.owns(player, kind, id) then
			table.insert(list, id)
		end
	end
	return table.concat(list, ",")
end

local function ensureLeaderstats(player)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		for _, name in { "Paws", "Stars" } do
			local value = Instance.new("IntValue")
			value.Name = name
			value.Parent = stats
		end
		stats.Parent = player
	end
	return stats
end

local function publish(player)
	if not player.Parent then
		return
	end
	local data = ProgressStore.get(player)
	local stats = ensureLeaderstats(player)
	stats.Paws.Value = data.paws
	stats.Stars.Value = data.stars

	for _, partyId in Parties.order do
		local unlocked = {}
		for _, modeId in Modes.order do
			if ProgressStore.isUnlocked(player, modeId, partyId) then
				table.insert(unlocked, modeId)
			end
		end
		player:SetAttribute(`Unlocked_{partyId}`, table.concat(unlocked, ","))
	end
	local best = 0
	for _, value in data.endlessBest do
		best = math.max(best, value)
	end
	player:SetAttribute("EndlessBest", best)
	player:SetAttribute("Paws", data.paws)
	player:SetAttribute("Stars", data.stars)
	player:SetAttribute("OwnedClasses", ownedList(player, "class"))
	player:SetAttribute("OwnedSkins", ownedList(player, "skin"))
	player:SetAttribute("Class", data.class)
	player:SetAttribute("Skin", data.skin)
end

function ProgressStore.load(player)
	cache[player] = fresh()
	publish(player)
	if not store then
		setSaveStatus(player, describeFailure(storeError or "no DataStore"))
		return
	end
	local ok, saved = pcall(function()
		return store:GetAsync(storeKey(player))
	end)
	if not player.Parent then
		return
	end
	if ok then
		cache[player] = sanitize(saved)
		setSaveStatus(player, "ok")
	else
		setSaveStatus(player, describeFailure(saved))
	end
	publish(player)
end

-- Writes the player's data now (yields). Safe to call often; merges with what is stored.
function ProgressStore.save(player)
	local data = cache[player]
	if not store or not data or player:GetAttribute("SaveStatus") == "off" then
		return false
	end
	local ok, err = pcall(function()
		store:UpdateAsync(storeKey(player), function(saved)
			return mergeInto(saved, data)
		end)
	end)
	if ok then
		dirty[player] = nil
	elseif player.Parent then
		setSaveStatus(player, describeFailure(err))
	end
	return ok
end

local function change(player, mutate)
	local data = ProgressStore.get(player)
	mutate(data)
	cache[player] = data
	dirty[player] = true
	publish(player)
end

function ProgressStore.markCompleted(player, partyId, modeId)
	change(player, function(data)
		data.completed[Modes.completedKey(partyId, modeId)] = true
	end)
end

function ProgressStore.recordEndless(player, partyId, level)
	change(player, function(data)
		data.endlessBest[partyId] = math.max(data.endlessBest[partyId] or 0, level)
	end)
end

function ProgressStore.addReward(player, paws, stars)
	change(player, function(data)
		data.paws += paws
		data.stars += stars
	end)
end

-- First level cleared on a new (UTC) calendar day? Returns true once per day.
function ProgressStore.claimDaily(player)
	if ProgressStore.get(player).lastPlayedDate == today() then
		return false
	end
	change(player, function(data)
		data.lastPlayedDate = today()
	end)
	return true
end

-- Remembers a cleared level ("duo:easy:3"); returns true the first time, so replays can pay less
function ProgressStore.markLevelCleared(player, key)
	if ProgressStore.get(player).clearedLevels[key] then
		return false
	end
	change(player, function(data)
		data.clearedLevels[key] = true
	end)
	return true
end

-- Referral: only brand-new players (no Stars yet) can be referred, once
function ProgressStore.setReferrer(player, referrerId)
	local data = ProgressStore.get(player)
	if referrerId == player.UserId or referrerId <= 0 or data.referredBy ~= 0 or data.stars > 0 then
		return
	end
	change(player, function(d)
		d.referredBy = referrerId
	end)
end

function ProgressStore.pendingReferrer(player)
	local data = ProgressStore.get(player)
	if data.referredBy ~= 0 and not data.referralDone then
		return data.referredBy
	end
	return nil
end

function ProgressStore.completeReferral(player)
	change(player, function(data)
		data.referralDone = true
	end)
end

-- Buys a buddy or skin with Paws. Returns true on success.
function ProgressStore.buy(player, kind, id)
	local catalog = Buddies.catalog(kind)
	local item = catalog and catalog[id]
	if not item or ProgressStore.owns(player, kind, id) or ProgressStore.get(player).paws < item.cost then
		return false
	end
	change(player, function(data)
		local owned = if kind == "class" then data.classes else data.skins
		data.paws -= item.cost
		owned[id] = true
	end)
	ProgressStore.select(player, kind, id)
	return true
end

function ProgressStore.select(player, kind, id)
	if not ProgressStore.owns(player, kind, id) then
		return false
	end
	change(player, function(data)
		if kind == "class" then
			data.class = id
			data.classes[id] = true
		else
			data.skin = id
			data.skins[id] = true
		end
	end)
	return true
end

-- For MarketplaceService.ProcessReceipt: saves synchronously and ignores receipts already granted.
-- Returns true once the grant is safely stored.
function ProgressStore.grantReceipt(player, receiptId, grant)
	local data = cache[player]
	if not store or not data then
		return false
	end
	if not table.find(data.receipts, receiptId) then
		grant(data)
		table.insert(data.receipts, receiptId)
		publish(player)
	end
	return ProgressStore.save(player)
end

function ProgressStore.release(player)
	if dirty[player] then
		ProgressStore.save(player)
	end
	cache[player] = nil
	dirty[player] = nil
end

-- Call once per place: wires joining, leaving, autosave and shutdown
function ProgressStore.start()
	Players.PlayerAdded:Connect(ProgressStore.load)
	for _, player in Players:GetPlayers() do
		task.spawn(ProgressStore.load, player)
	end
	Players.PlayerRemoving:Connect(ProgressStore.release)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			task.spawn(ProgressStore.save, player)
		end
		task.wait(if RunService:IsStudio() then 1 else 5)
	end)
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE)
			for player in dirty do
				task.spawn(ProgressStore.save, player)
			end
		end
	end)
end

return ProgressStore
