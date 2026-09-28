--[[
	ClientData - the latest profile snapshot from the server (Sync) + helpers to send requests.
	UI reads from here and listens to Changed. Nothing here is trusted by the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)

local ClientData = {}

function ClientData:Init(controllers)
	self.Controllers = controllers
	self.Data = nil :: any
	self.Loaded = false
	self.Changed = Signal.new()
	self.Remotes = {}
end

function ClientData:Remote(name: string): RemoteEvent
	local remote = self.Remotes[name]
	if not remote then
		remote = Net.Event(name)
		self.Remotes[name] = remote
	end
	return remote
end

function ClientData:Fire(name: string, ...: any)
	self:Remote(name):FireServer(...)
end

-- a setting with a safe default before the first Sync
function ClientData:Setting(key: string): any
	local data = self.Data
	if data and data.Settings and data.Settings[key] ~= nil then
		return data.Settings[key]
	end
	if key == "LowQuality" then
		return false
	end
	return true
end

function ClientData:SetSetting(key: string, value: any)
	if self.Data and self.Data.Settings then
		self.Data.Settings[key] = value
		self.Changed:Fire(self.Data)
	end
	self:Fire("SetSetting", key, value)
end

function ClientData:Start()
	self:Remote("Sync").OnClientEvent:Connect(function(data)
		if type(data) ~= "table" then
			return
		end
		self.Data = data
		self.Loaded = true
		self.Changed:Fire(data)
	end)
	self:Fire("Ready")
end

return ClientData
