--[[
	SessionService
	Client bootstrap + small per-player settings.
	GetBootstrap returns everything the UI needs on join: profile, level catalog, global bests,
	debug flag and the current run (if the client reloaded mid-run).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local SessionService = {}

local SETTINGS = { Sfx = true, Hints = true, ReducedEffects = true }

function SessionService:Init(services)
	self.Services = services
end

function SessionService:Start()
	local services = self.Services
	Net.Function("GetBootstrap").OnServerInvoke = function(player)
		local data = services.DataService:WaitForData(player, 20)
		local run = services.RoundService:GetRun(player)
		return {
			Profile = if data then services.DataService:Snapshot(player) else nil,
			Catalog = services.LevelService:GetCatalog(),
			GlobalBests = services.LeaderboardService:GetAll(),
			IsDebug = services.DebugService:IsDebug(player),
			Run = if run then services.RoundService:GetRunInfo(run, player) else nil,
			RoleState = if run and run.Doppel then services.RoleService:GetRoleState(run) else nil,
			MemoryOnly = services.DataService:IsMemoryOnly(),
		}
	end

	local limiter = RateLimiter.new(4, 8)
	Net.Event("UpdateSettings").OnServerEvent:Connect(function(player, key, value)
		if not limiter:Allow(player) then
			return
		end
		if type(key) ~= "string" or not SETTINGS[key] or type(value) ~= "boolean" then
			return
		end
		services.DataService:Update(player, function(profile)
			profile.Settings[key] = value
		end)
	end)

	-- global bests change rarely: push them to everyone every few minutes
	task.spawn(function()
		while true do
			task.wait(120)
			Net.Event("CatalogUpdated"):FireAllClients({
				GlobalBests = services.LeaderboardService:GetAll(),
			})
		end
	end)
end

return SessionService
