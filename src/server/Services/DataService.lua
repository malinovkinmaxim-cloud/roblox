--[[
	DataService
	Player profiles with:
	  - pcall + retry with backoff on every DataStore call
	  - session locking through UpdateAsync (prevents two servers overwriting each other)
	  - autosave + save on leave + BindToClose
	  - schema reconcile (new fields get defaults, old saves never break)
	  - automatic in-memory fallback in Studio when API access is disabled

	Saved: Coins, XP, Level, CompletedLevels, BestTimes, OwnedCosmetics, EquippedCosmetic,
	       Settings, Stats, ClaimedQuests
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local DataService = {}
DataService.Profiles = {} :: { [Player]: any }
DataService.ProfileLoaded = Signal.new()

local SCHEMA_VERSION = 1

local TEMPLATE = {
	Version = SCHEMA_VERSION,
	Coins = 0,
	XP = 0,
	Level = 1,
	CompletedLevels = {}, -- ["L1"] = true
	BestTimes = {}, -- ["L1"] = 42.31
	OwnedCosmetics = { Default = true },
	EquippedCosmetic = "Default",
	Settings = {
		Sfx = true,
		Hints = true,
		ReducedEffects = false,
	},
	Stats = {
		LevelsCompleted = 0,
		UniqueLevelsCompleted = 0,
		NoDeathClears = 0,
		RivalWins = 0,
		DoppelPresses = 0,
		Freezes = 0,
		TimeBonuses = 0,
		Deaths = 0,
	},
	ClaimedQuests = {},
}

local store: DataStore? = nil
local memoryOnly = false

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[key] = deepCopy(inner)
	end
	return copy
end

-- Fill in missing keys from the template (recursively for dictionary sub-tables).
local function reconcile(data, template)
	for key, default in template do
		if data[key] == nil then
			data[key] = deepCopy(default)
		elseif type(default) == "table" and type(data[key]) == "table" and next(default) ~= nil then
			reconcile(data[key], default)
		end
	end
	return data
end

local function keyFor(player: Player): string
	return "Player_" .. tostring(player.UserId)
end

local function isStudioApiError(message: string): boolean
	message = string.lower(tostring(message))
	return string.find(message, "studioaccesstoapisnotallowed", 1, true) ~= nil
		or string.find(message, "api services", 1, true) ~= nil
		or string.find(message, "cannot write to datastore from studio", 1, true) ~= nil
		or string.find(message, "publish", 1, true) ~= nil and RunService:IsStudio()
end

local function withRetries(label: string, attempts: number, fn: () -> any): (boolean, any)
	local lastError
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		if RunService:IsStudio() and isStudioApiError(result) then
			if not memoryOnly then
				warn("[DataService] DataStore unavailable in Studio (enable API Services to test saving). Using memory-only profiles.")
			end
			memoryOnly = true
			return false, result
		end
		warn(string.format("[DataService] %s failed (attempt %d/%d): %s", label, attempt, attempts, tostring(result)))
		if attempt < attempts then
			task.wait(math.min(2 ^ attempt, 10))
		end
	end
	return false, lastError
end

function DataService:Init(services)
	self.Services = services
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DATASTORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[DataService] GetDataStore failed, memory-only mode: " .. tostring(result))
		memoryOnly = true
	end
end

function DataService:Start()
	Players.PlayerAdded:Connect(function(player)
		self:_loadProfile(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:_loadProfile(player)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		self:_releaseProfile(player)
	end)

	-- autosave loop (one thread for everybody)
	task.spawn(function()
		while true do
			task.wait(Config.AUTOSAVE_INTERVAL)
			for player, profile in self.Profiles do
				if profile.Loaded and not profile.Releasing then
					task.spawn(function()
						self:_save(player, profile, false)
					end)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player, profile in self.Profiles do
			if profile.Loaded and not profile.Released then
				pending += 1
				task.spawn(function()
					self:_save(player, profile, true)
					pending -= 1
				end)
			end
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

function DataService:_loadProfile(player: Player)
	if self.Profiles[player] then
		return
	end
	local profile = {
		Data = nil,
		Loaded = false,
		SaveEnabled = false,
		Releasing = false,
		Released = false,
		LastPush = 0,
		PushQueued = false,
	}
	self.Profiles[player] = profile

	local data = nil
	if store and not memoryOnly then
		local key = keyFor(player)
		local lockAttempts = 0
		while player.Parent do
			local lockedByOther = false
			local ok, result = withRetries("Load " .. key, Config.DATASTORE_RETRIES, function()
				return (store :: DataStore):UpdateAsync(key, function(old)
					old = old or deepCopy(TEMPLATE)
					local lock = old.SessionLock
					if lock and lock.JobId ~= game.JobId and os.time() - (lock.Time or 0) < Config.SESSION_LOCK_TIMEOUT and lockAttempts < Config.SESSION_LOCK_RETRIES then
						lockedByOther = true
						return nil -- cancel, retry shortly
					end
					old.SessionLock = { JobId = game.JobId, Time = os.time() }
					return old
				end)
			end)
			if not ok then
				if memoryOnly then
					break -- Studio without API access
				end
				warn("[DataService] could not load data for " .. player.Name .. " - progress will NOT be saved this session")
				profile.LoadFailed = true
				break
			end
			if lockedByOther then
				lockAttempts += 1
				task.wait(Config.SESSION_LOCK_WAIT)
				continue
			end
			data = result
			profile.SaveEnabled = true
			break
		end
	end

	if not player.Parent then
		self.Profiles[player] = nil
		return
	end

	if data == nil then
		data = deepCopy(TEMPLATE)
	end
	data.SessionLock = nil
	reconcile(data, TEMPLATE)
	data.Version = SCHEMA_VERSION
	data.Level = Progression.FromXP(data.XP)
	profile.Data = data
	profile.Loaded = true
	self.ProfileLoaded:Fire(player, profile)
	self:PushToClient(player)
end

function DataService:_save(player: Player, profile, release: boolean): boolean
	if not profile.Loaded or not profile.SaveEnabled or not store or memoryOnly then
		return true
	end
	local key = keyFor(player)
	local snapshot = deepCopy(profile.Data)
	local stolen = false
	local ok = withRetries("Save " .. key, Config.DATASTORE_RETRIES, function()
		return (store :: DataStore):UpdateAsync(key, function(old)
			if old and old.SessionLock and old.SessionLock.JobId ~= game.JobId then
				stolen = true
				return nil -- another server owns this profile now; never overwrite it
			end
			snapshot.SessionLock = if release then nil else { JobId = game.JobId, Time = os.time() }
			return snapshot
		end)
	end)
	if stolen then
		warn("[DataService] session lock for " .. player.Name .. " was taken by another server; not saving")
		profile.SaveEnabled = false
	end
	return ok
end

function DataService:_releaseProfile(player: Player)
	local profile = self.Profiles[player]
	if not profile then
		return
	end
	profile.Releasing = true
	if profile.Loaded then
		self:_save(player, profile, true)
	end
	profile.Released = true
	self.Profiles[player] = nil
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function DataService:GetData(player: Player)
	local profile = self.Profiles[player]
	if profile and profile.Loaded then
		return profile.Data
	end
	return nil
end

function DataService:WaitForData(player: Player, timeout: number?)
	local deadline = os.clock() + (timeout or 30)
	while player.Parent and os.clock() < deadline do
		local data = self:GetData(player)
		if data then
			return data
		end
		task.wait(0.1)
	end
	return self:GetData(player)
end

function DataService:IsMemoryOnly(): boolean
	return memoryOnly or store == nil
end

-- Client-safe copy of the profile.
function DataService:Snapshot(player: Player)
	local data = self:GetData(player)
	if not data then
		return nil
	end
	local copy = deepCopy(data)
	copy.SessionLock = nil
	local level, into, need = Progression.FromXP(copy.XP)
	copy.Level = level
	copy.LevelXP = into
	copy.LevelXPNeeded = need
	return copy
end

-- Coalesces many changes in one frame into a single network message.
function DataService:PushToClient(player: Player)
	local profile = self.Profiles[player]
	if not profile or profile.PushQueued then
		return
	end
	profile.PushQueued = true
	task.defer(function()
		profile.PushQueued = false
		if player.Parent and profile.Loaded then
			Net.Event("ProfileUpdated"):FireClient(player, self:Snapshot(player))
		end
	end)
end

-- Mutate a profile safely. fn(data) may change anything; the client is updated afterwards.
function DataService:Update(player: Player, fn: (any) -> ())
	local data = self:GetData(player)
	if not data then
		return false
	end
	fn(data)
	data.Level = Progression.FromXP(data.XP)
	self:PushToClient(player)
	return true
end

function DataService:AddCoins(player: Player, amount: number)
	amount = math.floor(amount)
	return self:Update(player, function(data)
		data.Coins = math.max(0, data.Coins + amount)
	end)
end

-- Returns the number of levels gained.
function DataService:AddXP(player: Player, amount: number): number
	local data = self:GetData(player)
	if not data then
		return 0
	end
	local before = Progression.FromXP(data.XP)
	self:Update(player, function(d)
		d.XP = math.max(0, d.XP + math.floor(amount))
	end)
	local after = Progression.FromXP(data.XP)
	return after - before
end

function DataService:IncrementStat(player: Player, stat: string, amount: number?)
	return self:Update(player, function(data)
		data.Stats[stat] = (data.Stats[stat] or 0) + (amount or 1)
	end)
end

-- Debug helper
function DataService:ResetData(player: Player)
	local profile = self.Profiles[player]
	if not profile or not profile.Loaded then
		return
	end
	profile.Data = deepCopy(TEMPLATE)
	self:PushToClient(player)
end

DataService.Template = TEMPLATE
DataService._reconcile = reconcile

return DataService
