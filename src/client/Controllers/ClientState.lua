--[[
	ClientState
	The client's read-only view of the game (everything authoritative lives on the server).
	Controllers read from here and listen to `Changed` / specific signals.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Progression = require(ReplicatedStorage.Shared.Progression)

local ClientState = {
	Profile = nil,
	Catalog = {},
	CatalogById = {},
	GlobalBests = {},
	IsDebug = false,
	Run = nil, -- current run info (nil in lobby)
	RoleState = nil,
	CheckpointIndex = 0,
	Duo = nil, -- pair state
	Ready = false,
}

ClientState.Changed = Signal.new() -- (key)
ClientState.ReadySignal = Signal.new()

function ClientState:Set(key: string, value: any)
	(self :: any)[key] = value
	self.Changed:Fire(key, value)
end

function ClientState:IsCompleted(levelId: number): boolean
	local profile = self.Profile
	return profile ~= nil and profile.CompletedLevels[Progression.LevelKey(levelId)] == true
end

function ClientState:BestTime(levelId: number): number?
	local profile = self.Profile
	return profile and profile.BestTimes[Progression.LevelKey(levelId)] or nil
end

function ClientState:IsUnlocked(levelId: number): boolean
	if self.IsDebug then
		return true
	end
	local index
	for i, entry in self.Catalog do
		if entry.Id == levelId then
			index = i
			break
		end
	end
	if not index then
		return false
	end
	if index == 1 or self:IsCompleted(levelId) then
		return true
	end
	local previous = self.Catalog[index - 1]
	return previous ~= nil and self:IsCompleted(previous.Id)
end

-- First level that is unlocked but not completed (or the last level).
function ClientState:ContinueLevelId(): number?
	for _, entry in self.Catalog do
		if self:IsUnlocked(entry.Id) and not self:IsCompleted(entry.Id) then
			return entry.Id
		end
	end
	local last = self.Catalog[#self.Catalog]
	return last and last.Id or nil
end

function ClientState:Init()
	Net.Event("ProfileUpdated").OnClientEvent:Connect(function(profile)
		self:Set("Profile", profile)
	end)
	Net.Event("RunStarted").OnClientEvent:Connect(function(info)
		self.CheckpointIndex = info.CheckpointIndex or 0
		self.RoleState = nil -- the new role arrives separately (RoleState)
		self:Set("Run", info)
	end)
	Net.Event("RunEnded").OnClientEvent:Connect(function(results)
		if results and results.Aborted then
			self:Set("RoleState", nil)
			self:Set("Run", nil)
		end
	end)
	Net.Event("CheckpointReached").OnClientEvent:Connect(function(index)
		self:Set("CheckpointIndex", index)
	end)
	Net.Event("RoleState").OnClientEvent:Connect(function(state)
		self:Set("RoleState", state)
	end)
	Net.Event("CatalogUpdated").OnClientEvent:Connect(function(update)
		if update and update.GlobalBests then
			self:Set("GlobalBests", update.GlobalBests)
		end
	end)
	Net.Event("DuoState").OnClientEvent:Connect(function(state)
		if state.Type == "Paired" then
			self:Set("Duo", state)
		elseif state.Type == "Dissolved" then
			self:Set("Duo", nil)
		end
	end)
end

function ClientState:Start()
	task.spawn(function()
		local data
		for attempt = 1, 10 do
			local ok, result = pcall(function()
				return Net.Function("GetBootstrap"):InvokeServer()
			end)
			if ok and result then
				data = result
				break
			end
			task.wait(math.min(attempt, 3))
		end
		if not data then
			warn("[ClientState] bootstrap failed")
			return
		end
		self.Catalog = data.Catalog or {}
		self.CatalogById = {}
		for _, entry in self.Catalog do
			self.CatalogById[entry.Id] = entry
		end
		self.GlobalBests = data.GlobalBests or {}
		self.IsDebug = data.IsDebug == true
		self.MemoryOnly = data.MemoryOnly == true
		if data.Profile then
			self.Profile = data.Profile
		end
		if data.Run then
			self.CheckpointIndex = data.Run.CheckpointIndex or 0
			self.Run = data.Run
		end
		if data.RoleState then
			self.RoleState = data.RoleState
		end
		self.Ready = true
		self.ReadySignal:Fire()
		self.Changed:Fire("Profile", self.Profile)
		self.Changed:Fire("Run", self.Run)
		self.Changed:Fire("RoleState", self.RoleState)
	end)
end

function ClientState:WhenReady(fn: () -> ())
	if self.Ready then
		task.spawn(fn)
	else
		local connection
		connection = self.ReadySignal:Connect(function()
			connection:Disconnect()
			fn()
		end)
	end
end

return ClientState
