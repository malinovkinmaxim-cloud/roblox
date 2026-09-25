--[[
	LeaderboardService
	Global best time per level through OrderedDataStore (times stored in centiseconds,
	ascending = best first). Cached and refreshed on a single background loop.
	Fails silently (e.g. Studio without API access) - personal bests still work.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local LeaderboardService = {}
LeaderboardService.Bests = {} -- [levelId] = { Time, UserId, Name }

local stores = {}
local names = {}
local disabled = false

function LeaderboardService:Init(services)
	self.Services = services
end

local function getStore(levelId: number): OrderedDataStore?
	if disabled then
		return nil
	end
	if stores[levelId] then
		return stores[levelId]
	end
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.LEADERBOARD_STORE_PREFIX .. levelId)
	end)
	if not ok then
		disabled = true
		return nil
	end
	stores[levelId] = store
	return store
end

local function nameFor(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	names[userId] = if ok and name then name else "Player"
	return names[userId]
end

function LeaderboardService:Start()
	if self.Services.DataService:IsMemoryOnly() then
		disabled = true
	end
	task.spawn(function()
		task.wait(5)
		while not disabled do
			for _, levelId in self.Services.LevelService.Order do
				self:_refresh(levelId)
				task.wait(1)
				if disabled then
					break
				end
			end
			task.wait(Config.LEADERBOARD_REFRESH)
		end
	end)
end

function LeaderboardService:_refresh(levelId: number)
	local store = getStore(levelId)
	if not store then
		return
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(true, 1)
	end)
	if not ok then
		if string.find(string.lower(tostring(pages)), "studio", 1, true) then
			disabled = true
		end
		return
	end
	local entries = pages:GetCurrentPage()
	local top = entries[1]
	if top then
		local userId = tonumber(top.key) or 0
		self.Bests[levelId] = {
			Time = top.value / 100,
			UserId = userId,
			Name = nameFor(userId),
		}
	end
end

function LeaderboardService:Submit(player: Player, levelId: number, time: number)
	if player.UserId <= 0 then
		return
	end
	local centis = math.floor(time * 100)
	local current = self.Bests[levelId]
	if not current or time < current.Time then
		self.Bests[levelId] = { Time = time, UserId = player.UserId, Name = player.DisplayName }
	end
	task.spawn(function()
		local store = getStore(levelId)
		if not store then
			return
		end
		pcall(function()
			store:UpdateAsync(tostring(player.UserId), function(old)
				if old and old <= centis then
					return nil
				end
				return centis
			end)
		end)
	end)
end

function LeaderboardService:GetBest(levelId: number)
	return self.Bests[levelId]
end

-- String keys ("L1") so the table survives remote serialization.
function LeaderboardService:GetAll()
	local result = {}
	for levelId, best in self.Bests do
		result["L" .. tostring(levelId)] = best
	end
	return result
end

return LeaderboardService
