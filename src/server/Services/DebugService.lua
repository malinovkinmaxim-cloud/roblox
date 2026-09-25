--[[
	DebugService
	Studio (or admin) tools. Commands come from the Admin Debug UI or chat (/level 5 ...),
	both through the DebugCommand remote. Every command is re-checked on the server.

	  /level N        start level N (any level, unlock ignored)
	  /role NAME      set the doppelgänger role now (and for the next run)
	  /cp N           teleport to checkpoint N
	  /killdoppel     kill the doppelgänger
	  /kill           kill yourself
	  /finish         finish the level now
	  /restart        restart the level
	  /ai [on|off]    toggle doppelgänger AI
	  /coins N        add coins        /xp N   add XP
	  /unlockall      mark every level completed
	  /resetdata      wipe your profile (this session)
	  /lobby          leave the level
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local DebugService = {}

function DebugService:Init(services)
	self.Services = services
	self.PendingRole = {}
end

function DebugService:IsDebug(player: Player): boolean
	if RunService:IsStudio() and Config.DEBUG_IN_STUDIO then
		return true
	end
	if table.find(Config.ADMIN_USER_IDS, player.UserId) then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId and game.CreatorId ~= 0
end

function DebugService:Start()
	local limiter = RateLimiter.new(5, 8)
	Net.Event("DebugCommand").OnServerEvent:Connect(function(player, command, argument)
		if not self:IsDebug(player) or not limiter:Allow(player) then
			return
		end
		if type(command) ~= "string" or #command > 32 then
			return
		end
		if argument ~= nil and (type(argument) ~= "string" or #argument > 32) then
			return
		end
		local ok, err = pcall(self.Run, self, player, string.lower(command), argument)
		if not ok then
			warn("[DebugService] " .. tostring(err))
			self:_reply(player, "Error: " .. tostring(err))
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("IsDebug", self:IsDebug(player))
	end)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("IsDebug", self:IsDebug(player))
	end
end

function DebugService:_reply(player: Player, text: string)
	Net.Event("Toast"):FireClient(player, "DEBUG: " .. text, "Debug")
end

function DebugService:Run(player: Player, command: string, argument: string?)
	local services = self.Services
	local rounds = services.RoundService
	local run = rounds:GetRun(player)
	local number = argument and tonumber(argument)

	if command == "level" then
		if not number then
			return self:_reply(player, "usage: /level 5")
		end
		local ok, message = rounds:StartRun(player, number, { Force = true, Role = self.PendingRole[player] })
		self:_reply(player, if ok then "level " .. number else tostring(message))
	elseif command == "role" then
		local name = argument and (string.upper(string.sub(argument, 1, 1)) .. string.lower(string.sub(argument, 2))) or ""
		if not services.RoleService:HasRole(name) then
			return self:_reply(player, "unknown role (Follower, Rival, Shadow, Ally, Troll)")
		end
		self.PendingRole[player] = name
		if run and run.Doppel and not run.Partner then
			services.RoleService:SetRole(run, name, { Reveal = true })
		end
		self:_reply(player, "role " .. name)
	elseif command == "cp" then
		if not run or not number then
			return self:_reply(player, "usage (in a level): /cp 2")
		end
		services.CheckpointService:TeleportTo(run, number)
		self:_reply(player, "checkpoint " .. number)
	elseif command == "killdoppel" then
		if run then
			services.DoppelgangerService:KillDoppel(run, "Debug")
		end
	elseif command == "kill" then
		if run then
			rounds:KillPlayer(run, player, "Debug")
		else
			local _, humanoid = services.CharacterService:GetLiving(player)
			if humanoid then
				humanoid.Health = 0
			end
		end
	elseif command == "finish" then
		if run then
			rounds:ForceFinish(run)
		end
	elseif command == "restart" then
		if run then
			rounds:StartRun(player, run.LevelId, { Force = true, Role = self.PendingRole[player] })
		end
	elseif command == "ai" then
		if run then
			local enabled
			if argument == "on" then
				enabled = true
			elseif argument == "off" then
				enabled = false
			else
				enabled = not run.AIEnabled
			end
			services.DoppelgangerService:SetAIEnabled(run, enabled)
			self:_reply(player, "AI " .. (if enabled then "ON" else "OFF"))
		end
	elseif command == "coins" then
		services.DataService:AddCoins(player, number or 1000)
	elseif command == "xp" then
		services.DataService:AddXP(player, number or 500)
	elseif command == "unlockall" then
		services.DataService:Update(player, function(data)
			for _, id in services.LevelService.Order do
				data.CompletedLevels[Progression.LevelKey(id)] = true
			end
		end)
		self:_reply(player, "all levels unlocked")
	elseif command == "resetdata" then
		services.DataService:ResetData(player)
		self:_reply(player, "profile reset")
	elseif command == "lobby" then
		if run then
			rounds:EndRun(run, "Left")
		end
	else
		self:_reply(player, "unknown command " .. command)
	end
	return nil
end

return DebugService
