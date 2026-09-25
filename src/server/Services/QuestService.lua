--[[
	QuestService
	Milestone quests from Shared.QuestConfig. Progress is read from profile Stats;
	claiming is validated on the server (goal reached, not claimed yet).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local QuestService = {}

function QuestService:Init(services)
	self.Services = services
end

function QuestService:Start()
	local limiter = RateLimiter.new(3, 5)
	Net.Event("ClaimQuest").OnServerEvent:Connect(function(player, questId)
		if not limiter:Allow(player) or type(questId) ~= "string" then
			return
		end
		local ok, message = self:Claim(player, questId)
		if message then
			Net.Event("Toast"):FireClient(player, message, if ok then "Success" else "Error")
		end
	end)
end

function QuestService:GetProgress(data, questId: string): (number, number)
	local quest = QuestConfig.Quests[questId]
	if not quest or not data then
		return 0, 1
	end
	return math.min(data.Stats[quest.Stat] or 0, quest.Goal), quest.Goal
end

function QuestService:Claim(player: Player, questId: string): (boolean, string?)
	local quest = QuestConfig.Quests[questId]
	if not quest then
		return false, nil
	end
	local data = self.Services.DataService:GetData(player)
	if not data then
		return false, nil
	end
	if data.ClaimedQuests[questId] then
		return false, "Already claimed."
	end
	local progress, goal = self:GetProgress(data, questId)
	if progress < goal then
		return false, "Not finished yet."
	end
	self.Services.DataService:Update(player, function(d)
		d.ClaimedQuests[questId] = true
		d.Coins += quest.Reward.Coins
	end)
	self.Services.DataService:AddXP(player, quest.Reward.XP)
	return true, string.format("Quest complete! +%d coins, +%d XP", quest.Reward.Coins, quest.Reward.XP)
end

return QuestService
