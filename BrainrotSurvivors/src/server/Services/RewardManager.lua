--[[
	RewardManager - everything a finished run gives: BRAIN COINS, Brain XP (account level),
	statistics and bests, enemy / boss collection, daily quest progress, achievements (and
	the weapons / characters they unlock), leaderboard submissions. Also secret places.

	All numbers come from the server-side run summary; the client never reports rewards.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local AchievementData = require(Shared.AchievementData)
local WeaponData = require(Shared.WeaponData)
local CharacterData = require(Shared.CharacterData)
local EnemyData = require(Shared.EnemyData)
local MetaData = require(Shared.MetaData)
local MonetizationData = require(Shared.MonetizationData)
local SkinData = require(Shared.SkinData)

local RewardManager = {}

function RewardManager:Init(services)
	self.Services = services
end

function RewardManager:Start() end

function RewardManager:GiveCoins(session, amount: number)
	amount = math.max(0, math.floor(amount))
	session.Data.Coins += amount
	session.Data.Stats.LifetimeCoins += amount
end

-- coin multiplier from passes / boosts (never affects gameplay)
function RewardManager:CoinMultiplier(session): number
	local M = self.Services.MonetizationManager
	local mult = 1
	if M:HasPass(session.Player, "VIP") then
		mult += MonetizationData.VIPCoinBonus
	end
	if session.Data.CoinRushUntil > os.time() then
		mult += MonetizationData.CoinRushBonus
	end
	if M:HasPass(session.Player, "DoubleCoins") then
		mult *= 2
	end
	return mult
end

---------------------------------------------------------------------------
-- achievements & unlocks
---------------------------------------------------------------------------
local function unlockByAchievement(data, key: string, out: { string })
	for _, def in WeaponData.List do
		if def.Unlock.Achievement == key and not data.Weapons[def.Key] then
			data.Weapons[def.Key] = true
			table.insert(out, def.Icon .. " " .. def.Name)
		end
	end
	for _, def in CharacterData.List do
		if def.Unlock.Achievement == key and not data.Characters[def.Key] then
			data.Characters[def.Key] = true
			table.insert(out, def.Icon .. " " .. def.Name)
		end
	end
	for _, def in SkinData.List do
		if def.Achievement == key and not data.Skins[def.Key] then
			data.Skins[def.Key] = true
			table.insert(out, def.Icon .. " " .. def.Name .. " (hat)")
		end
	end
end

--[[
	Unlocks every achievement whose condition holds. `run` (a run summary) enables the
	single-run conditions and secret flags. Returns new achievement keys and new unlocks.
]]
function RewardManager:CheckAchievements(session, run: any?): ({ string }, { string })
	local data = session.Data
	local stats = data.Stats
	local new, unlocks = {}, {}
	for _, def in AchievementData.List do
		if not data.Achievements[def.Key] then
			local done = false
			if def.Stat then
				done = (stats[def.Stat] or 0) >= def.Goal
			elseif def.Run and run then
				done = (run[def.Run] or 0) >= def.Goal
			elseif def.Flag and run and run.Flags then
				done = run.Flags[def.Key] == true
			end
			if done then
				data.Achievements[def.Key] = os.time()
				self:GiveCoins(session, def.Coins)
				table.insert(new, def.Key)
				unlockByAchievement(data, def.Key, unlocks)
			end
		end
	end
	-- achievements unlocked earlier also unlock content added later
	for key in data.Achievements do
		unlockByAchievement(data, key, unlocks)
	end
	local player = session.Player
	if player and player.Parent then
		local PM = self.Services.PlayerManager
		for _, key in new do
			local def = AchievementData.ByKey[key]
			PM:Notify(player, string.format("🏆 %s  +%d coins", def.Name, def.Coins), "Achievement")
		end
		for _, name in unlocks do
			PM:Notify(player, "UNLOCKED: " .. name, "Unlock")
		end
	end
	return new, unlocks
end

function RewardManager:FoundSecret(player: Player, key: string)
	local session = self.Services.PlayerManager:Get(player)
	if not session or session.Data.SecretsFound[key] then
		return
	end
	session.Data.SecretsFound[key] = true
	local flags = {}
	flags[key] = true
	self:CheckAchievements(session, { Flags = flags })
	self.Services.PlayerManager:Sync(player)
end

---------------------------------------------------------------------------
-- quests
---------------------------------------------------------------------------
local function advanceQuests(data, run)
	local per = {
		Kills = run.Kills,
		Time = run.Time,
		Bosses = #run.Bosses,
		Level = run.Level,
		Rares = run.Rares,
		Gems = run.Gems,
		Runs = 1,
		Crates = run.Crates,
	}
	for _, q in data.Quests.List do
		local def = AchievementData.QuestByKey[q.Key]
		if def and not q.Claimed then
			local value = per[def.Kind] or 0
			if def.Single then
				q.Progress = math.max(q.Progress, value)
			else
				q.Progress += value
			end
			q.Progress = math.min(q.Progress, def.Goal)
		end
	end
end

---------------------------------------------------------------------------
-- run end
---------------------------------------------------------------------------
function RewardManager:OnRunEnd(session, run)
	local data = session.Data
	local stats = data.Stats
	local R = GameConfig.Rewards
	local today = os.time() // 86400

	-- coins
	local bonus = math.floor(
		run.Time / 60 * R.PerMinute + run.Kills * R.PerKill + run.Level * R.PerLevel + #run.Bosses * R.PerBoss + (if run.Victory then R.Victory else 0)
	)
	local firstToday = data.LastRunDay < today
	if firstToday then
		bonus += R.FirstRunOfDay
		data.LastRunDay = today
	end
	local mult = self:CoinMultiplier(session)
	local total = math.floor((run.Coins + bonus) * mult)
	self:GiveCoins(session, total)

	-- account XP
	local levelBefore = MetaData.BrainLevel(data.BrainXP)
	local xp = math.floor(run.Time / 60 * R.BrainXPPerMinute + run.Kills * R.BrainXPPerKill + (if run.Victory then 150 else 0))
	if self.Services.MonetizationManager:HasPass(session.Player, "DoubleXP") then
		xp *= 2
	end
	data.BrainXP += xp
	local levelAfter = MetaData.BrainLevel(data.BrainXP)

	-- stats & bests
	local best = {
		Time = run.Time > stats.BestTime,
		Level = run.Level > stats.BestLevel,
		Kills = run.Kills > stats.BestKills,
	}
	stats.Runs += 1
	stats.Kills += run.Kills
	stats.Bosses += #run.Bosses
	stats.BestTime = math.max(stats.BestTime, run.Time)
	stats.BestLevel = math.max(stats.BestLevel, run.Level)
	stats.BestKills = math.max(stats.BestKills, run.Kills)
	stats.Events67 += run.Events67
	stats.Crates += run.Crates
	stats.Rares += run.Rares
	stats.Gems += run.Gems
	if run.Victory then
		stats.Wins += 1
	end
	if run.Reason == "Death" then
		stats.Deaths += 1
	end

	-- collection (kills per enemy; bosses included)
	for key, n in run.EnemyKills do
		if EnemyData.ByKey[key] then
			data.Collection[key] = (data.Collection[key] or 0) + n
		end
	end
	for _, key in run.Bosses do
		if EnemyData.ByKey[key] and not run.EnemyKills[key] then
			data.Collection[key] = (data.Collection[key] or 0) + 1
		end
	end
	local kinds = 0
	for _, def in EnemyData.List do
		if (def.Boss or def.MiniBoss) and (data.Collection[def.Key] or 0) > 0 then
			kinds += 1
		end
	end
	stats.BossKinds = kinds

	advanceQuests(data, run)
	local newAchievements, unlocks = self:CheckAchievements(session, run)

	self.Services.LeaderboardManager:Submit(session)

	return {
		Coins = total,
		Collected = run.Coins,
		Bonus = bonus,
		Multiplier = mult,
		FirstToday = firstToday,
		BrainXP = xp,
		BrainLevelBefore = levelBefore,
		BrainLevelAfter = levelAfter,
		Achievements = newAchievements,
		Unlocks = unlocks,
		Best = best,
		BestTime = stats.BestTime,
		BestLevel = stats.BestLevel,
	}
end

return RewardManager
