--[[
	THE DOPPELGÄNGER OBBY - server entry point.
	Loads every service, calls Init() on all of them (no yielding, no cross-service calls
	that need other services started), then Start() on all of them.

	Services talk to each other through the `services` table passed to Init.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

Net.Setup()

local SERVICE_ORDER = {
	"CharacterService", -- collision groups first
	"DataService",
	"LevelService",
	"LobbyService",
	"ObstacleService",
	"InteractionService",
	"CheckpointService",
	"RoleService",
	"DoppelgangerService",
	"RewardService",
	"LeaderboardService",
	"ShopService",
	"QuestService",
	"DuoService",
	"DebugService",
	"RoundService",
	"SessionService",
}

local servicesFolder = script.Parent:WaitForChild("Services")
local services = {}

for _, name in SERVICE_ORDER do
	local module = servicesFolder:FindFirstChild(name)
	assert(module, "missing service " .. name)
	services[name] = require(module)
end

for _, name in SERVICE_ORDER do
	local service = services[name]
	if service.Init then
		local ok, err = pcall(service.Init, service, services)
		if not ok then
			warn("[Main] " .. name .. ":Init failed: " .. tostring(err))
		end
	end
end

for _, name in SERVICE_ORDER do
	local service = services[name]
	if service.Start then
		task.spawn(function()
			local ok, err = pcall(service.Start, service)
			if not ok then
				warn("[Main] " .. name .. ":Start failed: " .. tostring(err))
			end
		end)
	end
end

print("[DoppelgangerObby] server ready")
