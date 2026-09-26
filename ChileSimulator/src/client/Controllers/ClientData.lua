--[[
	ClientData - the client's read-only copy of its own data (from the server "Sync" remote).

	State sections: Stats, Rates, Pets, Boosts, Cosmetics, Rewards, Settings, Passes, Meta.
	ClientData.Changed:Fire(sectionName) after each merge. The client NEVER changes these values
	itself - it only asks the server via remotes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)

local ClientData = {}
ClientData.State = {} :: { [string]: any }
ClientData.Changed = Signal.new()
ClientData.Loaded = false
ClientData.LoadedSignal = Signal.new()
-- os.clock() when the last Rewards section arrived (for counting playtime / daily timers locally)
ClientData.RewardsClock = 0
ClientData.BoostsClock = 0

function ClientData:Init(controllers)
	self.Controllers = controllers
	self.Remotes = {}
	for _, name in Net.ClientToServer do
		self.Remotes[name] = Net.Event(name)
	end
	Net.Event("Sync").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		for section, value in payload do
			self.State[section] = value
			if section == "Rewards" then
				self.RewardsClock = os.clock()
			elseif section == "Boosts" then
				self.BoostsClock = os.clock()
			end
		end
		if not self.Loaded and self.State.Stats then
			self.Loaded = true
			self.LoadedSignal:Fire()
		end
		for section in payload do
			self.Changed:Fire(section)
		end
	end)
end

function ClientData:Start() end

-- Send intent to the server
function ClientData:Fire(remote: string, ...: any)
	local r = self.Remotes[remote]
	if r then
		r:FireServer(...)
	end
end

function ClientData:Get(section: string): any
	return self.State[section]
end

function ClientData:Setting(key: string): boolean
	local settings = self.State.Settings
	if settings and settings[key] ~= nil then
		return settings[key]
	end
	return true
end

-- Seconds left on an active boost, counted down locally since the last sync
function ClientData:BoostLeft(id: string): number
	local boosts = self.State.Boosts
	local left = boosts and boosts.Active and boosts.Active[id]
	if not left then
		return 0
	end
	return math.max(0, left - (os.clock() - self.BoostsClock))
end

return ClientData
