-- Server-only: saves which modes each player has completed and their best endless level.
-- The hub and the game place are in the same experience, so they share this DataStore.
-- Publishes "UnlockedModes" (comma-separated ids) and "EndlessBest" as player attributes.
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)
local Modes = require(script.Parent.Modes)

local ProgressStore = {}

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore("HopPalsProgress_v1")
end)

local cache = {}

local function storeKey(player)
	return `p_{player.UserId}`
end

local function fresh()
	return { completed = {}, endlessBest = 0 }
end

local function sanitize(saved)
	local data = fresh()
	if type(saved) == "table" then
		if type(saved.completed) == "table" then
			for _, id in Modes.order do
				data.completed[id] = saved.completed[id] == true or nil
			end
		end
		data.endlessBest = tonumber(saved.endlessBest) or 0
	end
	return data
end

function ProgressStore.isUnlocked(player, modeId)
	if RunService:IsStudio() and Config.STUDIO_UNLOCK_ALL then
		return Modes.get(modeId) ~= nil
	end
	return Modes.isUnlocked(modeId, ProgressStore.get(player).completed)
end

local function publish(player)
	local unlocked = {}
	for _, id in Modes.order do
		if ProgressStore.isUnlocked(player, id) then
			table.insert(unlocked, id)
		end
	end
	player:SetAttribute("UnlockedModes", table.concat(unlocked, ","))
	player:SetAttribute("EndlessBest", ProgressStore.get(player).endlessBest)
end

function ProgressStore.get(player)
	return cache[player] or fresh()
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
	if player.Parent then
		publish(player)
	end
end

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

function ProgressStore.release(player)
	cache[player] = nil
end

return ProgressStore
