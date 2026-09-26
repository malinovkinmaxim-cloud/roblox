--[[
	Rewards (logic) - granting rewards, daily streak, playtime gifts, daily quests,
	achievements and height milestones. Pure: time and randomness are passed in.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local RewardConfig = require(Shared.RewardConfig)
local BoostConfig = require(Shared.BoostConfig)
local PetConfig = require(Shared.PetConfig)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Num = require(Shared.Util.Num)

local Session = require(script.Parent.Session)
local Pets = require(script.Parent.Pets)
local Boosts = require(script.Parent.Boosts)
local Mults = require(script.Parent.Mults)

local Rewards = {}

Rewards.PET_FULL_GEMS = 10 -- given instead of a pet when storage is full

function Rewards.DayIndex(now: number): number
	return math.floor(now / 86400)
end

---------------------------------------------------------------------------
-- Grant
---------------------------------------------------------------------------
-- Applies a reward (or list of rewards). Returns human readable labels.
function Rewards.Grant(session, reward, world, rng): { string }
	local labels = {}
	if type(reward) ~= "table" then
		return labels
	end
	if reward.Kind == nil then
		for _, sub in reward do
			for _, label in Rewards.Grant(session, sub, world, rng) do
				table.insert(labels, label)
			end
		end
		return labels
	end

	local data = session.Data
	if reward.Kind == "Coins" then
		local base = Mults.Get(session, world, false)
		local amount = Formulas.CoinsForTaps(reward.Taps or 100, data.TapLevel, base, data.Height)
		data.Coins = Num.Add(data.Coins, amount)
		table.insert(labels, "🪙 +" .. Format.Number(amount) .. " Coins")
		Session.MarkDirty(session, "Stats")
	elseif reward.Kind == "Gems" then
		local amount = math.max(0, math.floor(reward.Amount or 0))
		data.Gems = Num.Add(data.Gems, amount)
		table.insert(labels, "💎 +" .. Format.Number(amount) .. " Gems")
		Session.MarkDirty(session, "Stats")
	elseif reward.Kind == "Boost" then
		local def = BoostConfig.Boosts[reward.Id]
		if def and Boosts.Add(session, reward.Id, reward.Count or 1) then
			local count = reward.Count or 1
			table.insert(labels, def.Icon .. " " .. def.Name .. (if count > 1 then " x" .. count else ""))
		end
	elseif reward.Kind == "Pet" then
		local petId = Pets.GrantReward(session, reward.Rarity, rng)
		if petId then
			local def = PetConfig.Pets[petId]
			table.insert(labels, "🐾 " .. def.Name .. " (" .. def.Rarity .. ")")
			Session.Effect(session, "PetReward", { Id = petId })
		else
			data.Gems = Num.Add(data.Gems, Rewards.PET_FULL_GEMS)
			table.insert(labels, "💎 +" .. Rewards.PET_FULL_GEMS .. " Gems (pet storage full)")
			Session.MarkDirty(session, "Stats")
		end
	end
	return labels
end

---------------------------------------------------------------------------
-- Daily streak
---------------------------------------------------------------------------
-- Which day of the 7-day cycle would be claimed now, and whether it can be claimed
function Rewards.DailyStatus(session, now: number)
	local daily = session.Data.Daily
	local today = Rewards.DayIndex(now)
	local claimedToday = daily.LastDay == today
	local streak = daily.Streak
	local nextStreak
	if claimedToday then
		nextStreak = streak
	elseif daily.LastDay == today - 1 then
		nextStreak = streak + 1
	else
		nextStreak = 1
	end
	local cycleDay = ((math.max(1, nextStreak) - 1) % #RewardConfig.Daily) + 1
	local secondsToReset = (today + 1) * 86400 - now
	return {
		CanClaim = not claimedToday,
		Day = cycleDay,
		Streak = nextStreak,
		SecondsToReset = secondsToReset,
	}
end

function Rewards.ClaimDaily(session, world, rng): ({ string }?, string?)
	local status = Rewards.DailyStatus(session, world.Now)
	if not status.CanClaim then
		return nil, "Come back tomorrow!"
	end
	local entry = RewardConfig.Daily[status.Day]
	session.Data.Daily.Streak = status.Streak
	session.Data.Daily.LastDay = Rewards.DayIndex(world.Now)
	local labels = Rewards.Grant(session, entry.Reward, world, rng)
	Session.MarkDirty(session, "Rewards")
	return labels
end

---------------------------------------------------------------------------
-- Playtime gifts (per session)
---------------------------------------------------------------------------
function Rewards.PlaytimeSeconds(session, clock: number): number
	return math.max(0, clock - session.JoinClock)
end

function Rewards.ClaimPlaytime(session, index: number, clock: number, world, rng): ({ string }?, string?)
	local entry = RewardConfig.Playtime[index]
	if not entry then
		return nil, "Unknown gift"
	end
	if session.PlaytimeClaimed[index] then
		return nil, "Already claimed"
	end
	if Rewards.PlaytimeSeconds(session, clock) < entry.Minutes * 60 then
		return nil, "Not ready yet"
	end
	session.PlaytimeClaimed[index] = true
	local labels = Rewards.Grant(session, entry.Reward, world, rng)
	Session.MarkDirty(session, "Rewards")
	return labels
end

---------------------------------------------------------------------------
-- Daily quests
---------------------------------------------------------------------------
function Rewards.EnsureQuestDay(session, now: number)
	local quests = session.Data.Quests
	local today = Rewards.DayIndex(now)
	if quests.Day ~= today then
		quests.Day = today
		quests.Progress = { Taps = 0, Grown = 0, Rebirths = 0 }
		quests.Claimed = {}
		Session.MarkDirty(session, "Rewards")
	end
end

function Rewards.AddQuestProgress(session, stat: string, amount: number, now: number)
	Rewards.EnsureQuestDay(session, now)
	local progress = session.Data.Quests.Progress
	if progress[stat] == nil then
		return
	end
	local before = progress[stat]
	progress[stat] = Num.Add(before, amount)
	for _, quest in RewardConfig.Quests do
		if quest.Stat == stat and before < quest.Goal and progress[stat] >= quest.Goal then
			Session.Notify(session, "Success", "📜 Quest complete! Claim your reward.")
		end
	end
	Session.MarkDirty(session, "Quests")
end

function Rewards.ClaimQuest(session, questId: string, world, rng): ({ string }?, string?)
	Rewards.EnsureQuestDay(session, world.Now)
	local quests = session.Data.Quests
	for _, quest in RewardConfig.Quests do
		if quest.Id == questId then
			if quests.Claimed[questId] then
				return nil, "Already claimed"
			end
			if (quests.Progress[quest.Stat] or 0) < quest.Goal then
				return nil, "Not finished yet"
			end
			quests.Claimed[questId] = true
			local labels = Rewards.Grant(session, quest.Reward, world, rng)
			Session.MarkDirty(session, "Rewards")
			return labels
		end
	end
	return nil, "Unknown quest"
end

---------------------------------------------------------------------------
-- Achievements (auto-claimed)
---------------------------------------------------------------------------
function Rewards.StatValue(session, stat: string): number
	local data = session.Data
	if stat == "BestHeight" or stat == "Taps" or stat == "Rebirths" then
		return data[stat]
	end
	return data.Stats[stat] or 0
end

function Rewards.CheckAchievements(session): number
	local data = session.Data
	local unlocked = 0
	for _, ach in RewardConfig.Achievements do
		if not data.Achievements[ach.Id] and Rewards.StatValue(session, ach.Stat) >= ach.Goal then
			data.Achievements[ach.Id] = true
			unlocked += 1
			data.Gems = Num.Add(data.Gems, ach.Gems)
			local text = "🏆 ACHIEVEMENT: " .. ach.Name .. "  +" .. ach.Gems .. " 💎"
			if ach.Boost and Boosts.Add(session, ach.Boost, 1) then
				text ..= " + " .. BoostConfig.Boosts[ach.Boost].Name
			end
			Session.Notify(session, "Reward", text, { Sound = "Achievement" })
			Session.MarkDirty(session, "Stats", "Rewards")
		end
	end
	return unlocked
end

---------------------------------------------------------------------------
-- Milestones (viral moments, once per player)
---------------------------------------------------------------------------
function Rewards.CheckMilestones(session)
	local data = session.Data
	local meters = data.Height / 100
	for _, milestone in Config.Milestones do
		if not data.Milestones[milestone.Id] and meters >= milestone.Meters then
			data.Milestones[milestone.Id] = true
			Session.Notify(session, "Big", milestone.Text, { Sound = "BigGrowth", Milestone = milestone.Id })
		end
	end
end

return Rewards
