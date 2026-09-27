--[[
	BRAINROT SURVIVORS - server entry point.
	Init() every service in order (no yielding across services), then Start() every service.
	PlayerManager starts last: it loads joining players, and everything else must be ready.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Modules").Net)

Net.Setup()

local Services = script.Parent:WaitForChild("Services")

local ORDER = {
	"DataManager",
	"MapBuilder",
	"MonetizationManager",
	"CharacterManager",
	"LeaderboardManager",
	"RewardManager",
	"ShopManager",
	"GameManager",
	"AdminManager",
	"PlayerManager",
}

local services = {}
for _, name in ORDER do
	services[name] = require(Services:WaitForChild(name))
end

for _, name in ORDER do
	local started = os.clock()
	services[name]:Init(services)
	local took = os.clock() - started
	if took > 0.5 then
		print(string.format("[Main] %s:Init took %.2fs", name, took))
	end
end

for _, name in ORDER do
	local ok, err = pcall(function()
		services[name]:Start()
	end)
	if not ok then
		warn(string.format("[Main] %s:Start failed: %s", name, tostring(err)))
	end
end

print("[BRAINROT SURVIVORS] server ready")
