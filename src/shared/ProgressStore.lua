-- Server-only: per-player save shared by the hub and the game place (same experience).
-- Holds completed modes, endless record, stars, owned buddies/skins and the current selection.
-- Publishes player attributes: UnlockedModes, EndlessBest, Stars, OwnedClasses, OwnedSkins, Class, Skin.
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Buddies = require(script.Parent.Buddies)
local Config = require(script.Parent.Config)
local Modes = require(script.Parent.Modes)

local ProgressStore = {}

local MAX_RECEIPTS = 50

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore("HopPalsProgress_v1")
end)

local cache = {}

local function storeKey(player)
	return `p_{player.UserId}`
end

local function studioUnlocked()
	return RunService:IsStudio() and Config.STUDIO_UNLOCK_ALL
end

local function fresh()
	return {
		completed = {},
		endlessBest = 0,
		stars = 0,
		classes = { bunny = true },
		skins = { classic = true },
		class = "bunny",
		skin = "classic",
		receipts = {},
	}
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
	data.completed = copySet(saved.completed, Modes.order)
	data.endlessBest = math.max(0, tonumber(saved.endlessBest) or 0)
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
	return data
end

function ProgressStore.get(player)
	return cache[player] or fresh()
end

function ProgressStore.isUnlocked(player, modeId)
	if studioUnlocked() then
		return Modes.get(modeId) ~= nil
	end
	return Modes.isUnlocked(modeId, ProgressStore.get(player).completed)
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

local function publish(player)
	if not player.Parent then
		return
	end
	local data = ProgressStore.get(player)
	local unlocked = {}
	for _, id in Modes.order do
		if ProgressStore.isUnlocked(player, id) then
			table.insert(unlocked, id)
		end
	end
	player:SetAttribute("UnlockedModes", table.concat(unlocked, ","))
	player:SetAttribute("EndlessBest", data.endlessBest)
	player:SetAttribute("Stars", data.stars)
	player:SetAttribute("OwnedClasses", ownedList(player, "class"))
	player:SetAttribute("OwnedSkins", ownedList(player, "skin"))
	player:SetAttribute("Class", data.class)
	player:SetAttribute("Skin", data.skin)
end

function ProgressStore.load(player)
	cache[player] = fresh()
	publish(player)
	if store then
		local ok, saved = pcall(function()
			return store:GetAsync(storeKey(player))
		end)
		if ok then
			cache[player] = sanitize(saved)
		else
			warn("Loading progress failed:", saved)
		end
	end
	publish(player)
end

-- Applies `mutate` to the cached copy right away and to the saved copy in the background.
-- `mutate` must be safe to run on both (it re-checks its own conditions).
local function update(player, mutate)
	local data = ProgressStore.get(player)
	mutate(data)
	cache[player] = data
	publish(player)
	if not store then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			store:UpdateAsync(storeKey(player), function(saved)
				local merged = sanitize(saved)
				mutate(merged)
				return merged
			end)
		end)
		if not ok then
			warn("Saving progress failed:", err)
		end
	end)
end

function ProgressStore.markCompleted(player, modeId)
	update(player, function(data)
		data.completed[modeId] = true
	end)
end

function ProgressStore.recordEndless(player, level)
	if level <= ProgressStore.get(player).endlessBest then
		return
	end
	update(player, function(data)
		data.endlessBest = math.max(data.endlessBest, level)
	end)
end

function ProgressStore.addStars(player, amount)
	update(player, function(data)
		data.stars += amount
	end)
end

-- Buys a buddy or skin with stars. Returns true on success.
function ProgressStore.buy(player, kind, id)
	local catalog = Buddies.catalog(kind)
	local item = catalog and catalog[id]
	if not item or ProgressStore.owns(player, kind, id) or ProgressStore.get(player).stars < item.cost then
		return false
	end
	update(player, function(data)
		local owned = if kind == "class" then data.classes else data.skins
		if not owned[id] and data.stars >= item.cost then
			data.stars -= item.cost
			owned[id] = true
		end
	end)
	ProgressStore.select(player, kind, id)
	return true
end

function ProgressStore.select(player, kind, id)
	if not ProgressStore.owns(player, kind, id) then
		return false
	end
	update(player, function(data)
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
	if not store then
		return false
	end
	local merged = nil
	local ok, err = pcall(function()
		store:UpdateAsync(storeKey(player), function(saved)
			merged = sanitize(saved)
			if table.find(merged.receipts, receiptId) then
				return merged
			end
			grant(merged)
			table.insert(merged.receipts, receiptId)
			while #merged.receipts > MAX_RECEIPTS do
				table.remove(merged.receipts, 1)
			end
			return merged
		end)
	end)
	if not ok then
		warn("Granting purchase failed:", err)
		return false
	end
	cache[player] = merged
	publish(player)
	return true
end

function ProgressStore.release(player)
	cache[player] = nil
end

return ProgressStore
