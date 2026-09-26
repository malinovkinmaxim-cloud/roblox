--[[
	RewardService - daily streak, playtime gifts, quests, boosts activation and random chests.
	Time comes from the server clock only (os.time / os.clock), never from the client.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RewardConfig = require(Shared.RewardConfig)
local ZoneConfig = require(Shared.ZoneConfig)
local Num = require(Shared.Util.Num)

local Logic = script.Parent.Parent.Logic
local Rewards = require(Logic.Rewards)
local Boosts = require(Logic.Boosts)
local Session = require(Logic.Session)
local Guard = require(script.Parent.Parent.Util.Guard)

local RewardService = {}

function RewardService:Init(services)
	self.Services = services
	self.Rng = Random.new()
end

local function announce(session, title: string, labels: { string }?)
	if labels and #labels > 0 then
		Session.Notify(session, "Reward", title .. "  " .. table.concat(labels, "  •  "), { Sound = "Reward" })
	end
end

---------------------------------------------------------------------------
-- Random chests: ONE chest at a time for the whole server, first come first served.
---------------------------------------------------------------------------
function RewardService:SpawnChest()
	local candidates = {}
	for _, player in Players:GetPlayers() do
		if self.Services.WorldService:RootPosition(player) then
			table.insert(candidates, player)
		end
	end
	if #candidates == 0 then
		return
	end
	local target = candidates[self.Rng:NextInteger(1, #candidates)]
	local root = self.Services.WorldService:RootPosition(target)
	if not root then
		return
	end
	local zone = ZoneConfig.IndexFromX(root.X)
	local angle = self.Rng:NextNumber(0, math.pi * 2)
	local dist = self.Rng:NextNumber(40, 90)
	local cx = ZoneConfig.CenterX(zone)
	local x = math.clamp(root.X + math.cos(angle) * dist, cx - ZoneConfig.Length / 2 + 15, cx + ZoneConfig.Length / 2 - 15)
	local z = math.clamp(root.Z + math.sin(angle) * dist, -ZoneConfig.Width / 2 + 15, ZoneConfig.Width / 2 - 15)
	local position = Vector3.new(x, 0, z)
	self.Chest = {
		Model = self.Services.WorldService:BuildChest(position),
		Position = position,
		ExpiresAt = os.clock() + RewardConfig.Chest.Lifetime,
	}
	self.Services.PlayerService:NotifyAll("Info", "🎁 A TREASURE CHEST appeared in " .. ZoneConfig.Zones[zone].Name .. "! Grab it first!", { Sound = "Chest" })
end

function RewardService:RollChest()
	local total = 0
	for _, entry in RewardConfig.Chest.Table do
		total += entry.Weight
	end
	local r = self.Rng:NextNumber(0, total)
	for _, entry in RewardConfig.Chest.Table do
		r -= entry.Weight
		if r <= 0 then
			return entry
		end
	end
	return RewardConfig.Chest.Table[1]
end

function RewardService:CheckChest()
	local chest = self.Chest
	if not chest then
		return
	end
	if os.clock() > chest.ExpiresAt then
		chest.Model:Destroy()
		self.Chest = nil
		return
	end
	local PlayerService = self.Services.PlayerService
	for player, session in PlayerService:GetSessions() do
		local root = self.Services.WorldService:RootPosition(player)
		if root and (Vector3.new(root.X, 0, root.Z) - chest.Position).Magnitude <= RewardConfig.Chest.GrabRange then
			self.Chest = nil
			chest.Model:Destroy()
			local entry = self:RollChest()
			local labels = Rewards.Grant(session, entry.Reward, PlayerService:World(), self.Rng)
			session.Data.Stats.Chests += 1
			Rewards.CheckAchievements(session)
			announce(session, "🎁 CHEST!", labels)
			Session.Effect(session, "Chest", { Position = chest.Position })
			PlayerService:NotifyAll("Info", "🎁 " .. player.DisplayName .. " grabbed the chest!")
			return
		end
	end
end

function RewardService:Start()
	local PlayerService = self.Services.PlayerService

	Guard.On("ClaimDaily", 1, function(session)
		local labels, err = Rewards.ClaimDaily(session, PlayerService:World(), self.Rng)
		if labels then
			announce(session, "📅 DAILY REWARD!", labels)
		elseif err then
			Session.Notify(session, "Error", err)
		end
	end)

	Guard.On("ClaimPlaytime", 2, function(session, _player, index)
		local i = Num.ValidInt(index, 1, #RewardConfig.Playtime)
		if not i then
			return
		end
		local labels, err = Rewards.ClaimPlaytime(session, i, os.clock(), PlayerService:World(), self.Rng)
		if labels then
			announce(session, "🎁 FREE GIFT!", labels)
		elseif err then
			Session.Notify(session, "Error", err)
		end
	end)

	Guard.On("ClaimQuest", 2, function(session, _player, questId)
		if type(questId) ~= "string" then
			return
		end
		local labels, err = Rewards.ClaimQuest(session, questId, PlayerService:World(), self.Rng)
		if labels then
			announce(session, "📜 QUEST DONE!", labels)
		elseif err then
			Session.Notify(session, "Error", err)
		end
	end)

	Guard.On("ActivateBoost", 3, function(session, _player, boostId)
		if type(boostId) ~= "string" then
			return
		end
		local ok, err = Boosts.Activate(session, boostId)
		if not ok and err then
			Session.Notify(session, "Error", err)
		end
	end)

	-- chest spawner + grab check (4 Hz, a handful of distance checks)
	task.spawn(function()
		local nextSpawn = os.clock() + self.Rng:NextNumber(RewardConfig.Chest.MinInterval, RewardConfig.Chest.MaxInterval) * 0.5
		while true do
			task.wait(0.25)
			if self.Chest then
				self:CheckChest()
			elseif os.clock() >= nextSpawn then
				self:SpawnChest()
				nextSpawn = os.clock() + self.Rng:NextNumber(RewardConfig.Chest.MinInterval, RewardConfig.Chest.MaxInterval)
			end
		end
	end)
end

return RewardService
