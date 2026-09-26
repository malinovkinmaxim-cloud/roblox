--[[
	CHILE SIMULATOR - server entry point.
	Init() every service (in order, no yielding across services), then Start() every service.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

Net.Setup()

local Services = script.Parent:WaitForChild("Services")

local ORDER = {
	"DataService",
	"AdminService",
	"EventService",
	"WorldService",
	"PlayerService",
	"CharacterService",
	"MonetizationService",
	"LeaderboardService",
	"GrowthService",
	"PetService",
	"RewardService",
	"CosmeticService",
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

print("[CHILE SIMULATOR] server ready")
