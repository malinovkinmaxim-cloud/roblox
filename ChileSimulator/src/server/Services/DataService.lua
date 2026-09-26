--[[
	DataService - safe saving.

	  * One DataStore key per player: { Data = profile, Lock = { Server, Time }, SavedAt }
	  * SESSION LOCK: a server owns a profile while the player is in it. Another server that
	    loads the same profile waits (the old server is probably still saving) and only takes
	    it over after retries. A server that lost the lock never overwrites newer data.
	  * Every write goes through UpdateAsync with retries + exponential backoff and waits for
	    request budget.
	  * Saves on: autosave (every Config.Save.AutosaveInterval), PlayerRemoving (and releases the
	    lock), BindToClose (all players in parallel), purchases (immediately).
	  * The saved copy is passed through Defaults.Reconcile, so NaN / inf can never reach the store.
	  * If DataStores are unavailable (Studio without API access) the game runs in memory mode
	    and says so in Settings. If loading fails in a live game the player is kicked instead of
	    being given empty data that could overwrite their real progress.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local Defaults = require(script.Parent.Parent.Logic.Defaults)

local STORE_NAME = "ChileSimulator_Players_v1"

local DataService = {}
DataService.Persistent = false
DataService.Status = "Loading..."

local function keyFor(userId: number): string
	return "u_" .. userId
end

function DataService:Init(services)
	self.Services = services
	self.ServerId = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)
	self.Saving = {} -- [userId] = true while a save is running

	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok and store then
		-- in Studio without "Enable Studio Access to API Services" every request throws
		local probeOk, err = pcall(function()
			return store:GetAsync("__probe")
		end)
		if probeOk then
			self.Store = store
			self.Persistent = true
			self.Status = "Progress saves automatically"
		else
			warn("[DataService] DataStore unavailable, running in memory mode: " .. tostring(err))
			self.Status = "Saving is OFF (Studio: enable API access)"
		end
	else
		warn("[DataService] GetDataStore failed: " .. tostring(store))
		self.Status = "Saving is OFF"
	end
end

-- Waits until the request budget allows one more UpdateAsync (max ~10 s)
local function waitForBudget()
	for _ = 1, 20 do
		local ok, budget = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
		end)
		if not ok or budget > 0 then
			return
		end
		task.wait(0.5)
	end
end

-- Runs fn with retries + exponential backoff. Returns ok, result.
local function retry(label: string, fn: () -> any): (boolean, any)
	local lastErr
	for attempt = 1, Config.Save.MaxRetries do
		waitForBudget()
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		warn(string.format("[DataService] %s failed (attempt %d): %s", label, attempt, tostring(result)))
		task.wait(math.min(2 ^ attempt, 16))
	end
	return false, lastErr
end

--[[
	Loads (and locks) a player's profile. Returns the reconciled data table, or nil if it
	could not be loaded (the caller kicks the player).
]]
function DataService:Load(player: Player)
	if not self.Persistent then
		local data = Defaults.New()
		data.CreatedAt = os.time()
		return data
	end

	-- rejoined this same server while the save from leaving is still running: wait for it,
	-- otherwise we could read the profile from before that save (the lock is ours either way)
	local waited = 0
	while self.Saving[player.UserId] and waited < 30 do
		waited += task.wait(0.1)
	end

	local key = keyFor(player.UserId)
	local lockWaits = 0
	while true do
		local lockedBy = nil
		local force = lockWaits >= 4 -- ~20 s of waiting: the other server is gone or stuck
		local ok, result = retry("load " .. key, function()
			lockedBy = nil
			return self.Store:UpdateAsync(key, function(old)
				lockedBy = nil -- the transform may run more than once
				old = if type(old) == "table" then old else {}
				local lock = old.Lock
				if
					not force
					and type(lock) == "table"
					and lock.Server ~= self.ServerId
					and os.time() - (tonumber(lock.Time) or 0) < Config.Save.SessionLockTimeout
				then
					lockedBy = lock.Server
					return nil -- cancel: someone else owns the session
				end
				old.Lock = { Server = self.ServerId, Time = os.time() }
				return old
			end)
		end)
		if not ok then
			return nil
		end
		if lockedBy then
			lockWaits += 1
			warn(string.format("[DataService] %s is locked by %s, waiting (%d)", key, tostring(lockedBy), lockWaits))
			if not player.Parent then
				return nil
			end
			task.wait(5)
		else
			local raw = if type(result) == "table" then result.Data else nil
			local data = Defaults.Reconcile(raw)
			if raw == nil then
				data.CreatedAt = os.time()
			end
			return data
		end
	end
end

--[[
	Saves a session. release = true also drops the session lock (player left / shutdown).
	Returns true on success. Concurrent saves for the same player are serialized.
]]
function DataService:Save(session, release: boolean?): boolean
	if not self.Persistent then
		return true
	end
	local userId = session.UserId
	while self.Saving[userId] do
		task.wait(0.1)
	end
	self.Saving[userId] = true

	session.Data.LastSeen = os.time()
	local snapshot = Defaults.Reconcile(session.Data) -- clean deep copy (no nan/inf)
	local lostLock = false
	local ok = retry("save " .. keyFor(userId), function()
		lostLock = false
		return self.Store:UpdateAsync(keyFor(userId), function(old)
			lostLock = false -- the transform may run more than once
			old = if type(old) == "table" then old else {}
			local lock = old.Lock
			if type(lock) == "table" and lock.Server ~= self.ServerId then
				lostLock = true
				return nil -- another server took this profile over: never overwrite it
			end
			old.Data = snapshot
			old.SavedAt = os.time()
			old.Lock = if release then nil else { Server = self.ServerId, Time = os.time() }
			return old
		end)
	end)

	self.Saving[userId] = nil
	if lostLock then
		warn("[DataService] lost session lock for " .. userId)
		local player = Players:GetPlayerByUserId(userId)
		if player and not release then
			player:Kick("Your progress was opened in another server. Please rejoin.")
		end
		return false
	end
	return ok
end

function DataService:Start()
	local PlayerService = self.Services.PlayerService

	-- periodic autosave, spread over the interval so requests don't burst
	task.spawn(function()
		while true do
			task.wait(Config.Save.AutosaveInterval)
			local sessions = PlayerService:GetSessions()
			local count = 0
			for _ in sessions do
				count += 1
			end
			local gap = math.min(2, Config.Save.AutosaveInterval / math.max(1, count) / 2)
			for _, session in sessions do
				if not session.Leaving then
					task.spawn(function()
						self:Save(session, false)
					end)
					task.wait(gap)
				end
			end
		end
	end)

	game:BindToClose(function()
		if not self.Persistent then
			return
		end
		local pending = 0
		for _, session in PlayerService:GetSessions() do
			if not session.Released then
				pending += 1
				task.spawn(function()
					self:Save(session, true)
					session.Released = true
					pending -= 1
				end)
			end
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)

	if RunService:IsStudio() and not self.Persistent then
		print("[DataService] Studio memory mode - progress is NOT saved. " .. self.Status)
	end
end

return DataService
