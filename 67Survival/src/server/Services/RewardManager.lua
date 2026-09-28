--[[
	RewardManager - everything a finished run gives: coins, account XP, FRAGMENTS,
	statistics and bests, the Collection Book (enemies, abilities, events seen), daily quest
	and weekly challenge progress, achievements (and the heroes / abilities / cosmetics they
	unlock), leaderboard submissions. Also secret places and the Extra Chest product.

	All numbers come from the server-side run summary; the client never reports rewards.
	Bonuses: party (+10% coins / XP per other member, max 3), friends in the server (+5%
	each, max 3), limited-time events (LiveEvents). No paid multipliers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local AchievementData = require(Shared.AchievementData)
local WeaponData = require(Shared.WeaponData)
local UpgradeData = require(Shared.UpgradeData)
local HeroData = require(Shared.HeroData)
local EnemyData = require(Shared.EnemyData)
local WaveData = require(Shared.WaveData)
local MetaData = require(Shared.MetaData)
local CosmeticData = require(Shared.CosmeticData)
local CollectionData = require(Shared.CollectionData)
local LiveEvents = require(Shared.LiveEvents)
local DifficultyData = require(Shared.DifficultyData)

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

function RewardManager:GiveFragments(session, amount: number)
	amount = math.max(0, math.floor(amount))
	session.Data.Fragments += amount
	session.Data.Stats.LifetimeFragments += amount
end

---------------------------------------------------------------------------
-- unlocks: achievements -> heroes / abilities, cosmetics from every source
---------------------------------------------------------------------------
local function unlockByAchievement(data, key: string, out: { string })
	for _, def in WeaponData.List do
		if def.Evolution == nil and (def.Unlock.Achievement == key or def.Unlock.Secret == key) and not data.Weapons[def.Key] then
			data.Weapons[def.Key] = true
			table.insert(out, def.Name)
		end
	end
	for _, def in UpgradeData.Passives do
		if def.Secret == key and not data.Weapons[def.Key] then
			data.Weapons[def.Key] = true
			table.insert(out, def.Name)
		end
	end
	for _, def in HeroData.List do
		if def.Unlock.Achievement == key and not data.Heroes[def.Key] then
			data.Heroes[def.Key] = true
			table.insert(out, def.Name)
		end
	end
end

-- grants every cosmetic whose condition holds. Returns the names of the new ones.
function RewardManager:CheckCosmetics(session): { string }
	local data = session.Data
	local owned = data.Cosmetics.Owned
	local level = MetaData.Level(data.XP)
	local collected = CollectionData.Count(data)
	local M = self.Services.MonetizationManager
	local new = {}
	for _, def in CosmeticData.List do
		if not owned[def.Id] then
			local ok = (def.Achievement ~= nil and (data.Achievements[def.Achievement] or 0) > 0)
				or (def.Level ~= nil and level >= def.Level)
				or (def.Collection ~= nil and collected >= def.Collection)
				or (def.Pass ~= nil and session.Player ~= nil and M:HasPass(session.Player, def.Pass))
			if ok then
				owned[def.Id] = true
				data.Cosmetics.New[def.Id] = true
				table.insert(new, def.Name)
			end
		end
	end
	local player = session.Player
	if #new > 0 and player and player.Parent then
		local text = if #new == 1 then new[1] else (new[1] .. " +" .. (#new - 1) .. " more")
		self.Services.PlayerManager:Notify(player, "NEW COSMETIC AVAILABLE: " .. text, "Cosmetic")
	end
	return new
end

-- derived stats used by achievements (collection size, heroes, 67 events seen...)
local function refreshDerived(data)
	local stats = data.Stats
	stats.Collected = CollectionData.Count(data)
	local heroes = 0
	for _, owned in data.Heroes do
		if owned then
			heroes += 1
		end
	end
	stats.HeroCount = heroes
	local kinds = 0
	for _ in data.Seen.Events do
		kinds += 1
	end
	stats.EventKinds = kinds
	local bosses = 0
	for _, def in EnemyData.List do
		if (def.Boss or def.MiniBoss) and (data.Collection[def.Key] or 0) > 0 then
			bosses += 1
		end
	end
	stats.BossKinds = bosses
end

--[[
	Unlocks every achievement whose condition holds. `run` (a run summary) enables the
	single-run conditions and secret flags. Returns new achievement keys and new unlocks.
]]
function RewardManager:CheckAchievements(session, run: any?): ({ string }, { string })
	local data = session.Data
	refreshDerived(data)
	local stats = data.Stats
	local new, unlocks = {}, {}
	for _ = 1, 3 do -- an achievement can complete another one (Collected, HeroCount)
		local changed = false
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
					self:GiveFragments(session, def.Fragments or 0)
					table.insert(new, def.Key)
					unlockByAchievement(data, def.Key, unlocks)
					changed = true
				end
			end
		end
		if not changed then
			break
		end
		refreshDerived(data)
	end
	-- achievements unlocked earlier also unlock content added later
	for key in data.Achievements do
		unlockByAchievement(data, key, unlocks)
	end
	refreshDerived(data)
	local player = session.Player
	if player and player.Parent then
		local PM = self.Services.PlayerManager
		for _, key in new do
			local def = AchievementData.ByKey[key]
			local reward = "+" .. def.Coins .. " coins" .. (if def.Fragments then ", +" .. def.Fragments .. " fragments" else "")
			PM:Notify(player, string.format("Achievement: %s  %s", def.Name, reward), "Achievement")
		end
		for _, name in unlocks do
			PM:Notify(player, "UNLOCKED: " .. name, "Unlock")
		end
	end
	self:CheckCosmetics(session)
	return new, unlocks
end

function RewardManager:FoundSecret(player: Player, key: string)
	local session = self.Services.PlayerManager:Get(player)
	if not session or session.Data.SecretsFound[key] then
		return
	end
	session.Data.SecretsFound[key] = true
	self:CheckAchievements(session, { Flags = { [key] = true } })
	self.Services.PlayerManager:Sync(player)
end

---------------------------------------------------------------------------
-- quests & weekly challenges
---------------------------------------------------------------------------
local function counters(run, context)
	return {
		Kills = run.Kills,
		Time = run.Time,
		Bosses = #run.Bosses,
		Level = run.Level,
		Rares = run.Rares,
		Gems = run.Gems,
		Runs = 1,
		Crates = run.Crates,
		Events67 = run.Events67,
		Evolved = run.Evolved,
		LongRuns = if run.Time >= 600 then 1 else 0,
		Fragments = run.Fragments,
		Wins = if run.Victory then 1 else 0,
		PartyRuns = if context.Party > 1 then 1 else 0,
	}
end

local function advance(list, byKey, per)
	for _, q in list do
		local def = byKey[q.Key]
		if def and not q.Claimed and def.Kind ~= "Heroes" then
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

local function advanceWeekly(data, run, per)
	local weekly = data.Weekly
	weekly.Heroes[run.Hero] = true
	local heroes = 0
	for _ in weekly.Heroes do
		heroes += 1
	end
	advance(weekly.List, AchievementData.WeeklyByKey, per)
	for _, q in weekly.List do
		local def = AchievementData.WeeklyByKey[q.Key]
		if def and def.Kind == "Heroes" and not q.Claimed then
			q.Progress = math.min(heroes, def.Goal)
		end
	end
end

---------------------------------------------------------------------------
-- run end
---------------------------------------------------------------------------
--[[
	context: { Party = members in the party (1 = solo), Friends = friends in the server }
	Returns the results payload for the client.
]]
function RewardManager:OnRunEnd(session, run, context: { Party: number, Friends: number }?)
	local ctx = context or { Party = 1, Friends = 0 }
	local data = session.Data
	local stats = data.Stats
	local R = GameConfig.Rewards
	local now = os.time()
	local today = now // 86400
	local live = LiveEvents.Mods(now)

	-- bonuses (social + limited-time events), then the difficulty multiplier
	local tier = DifficultyData.Get(run.Difficulty or 2)
	local partyBonus = math.min(3, math.max(0, ctx.Party - 1)) * R.PartyBonusPerMember
	local friendBonus = math.min(3, math.max(0, ctx.Friends)) * R.FriendBonusPerFriend
	local mult = (1 + partyBonus + friendBonus + (live.CoinBonus or 0)) * tier.Reward

	-- coins
	local bonus = math.floor(
		run.Time / 60 * R.PerMinute + run.Kills * R.PerKill + run.Level * R.PerLevel + #run.Bosses * R.PerBoss + (if run.Victory then R.Victory else 0)
	)
	local firstToday = data.LastRunDay < today
	if firstToday then
		bonus += R.FirstRunOfDay
		data.LastRunDay = today
	end
	local total = math.floor((run.Coins + bonus) * mult)
	self:GiveCoins(session, total)

	-- account XP
	local levelBefore = MetaData.Level(data.XP)
	local xp = math.floor((run.Time / 60 * R.XPPerMinute + run.Kills * R.XPPerKill + (if run.Victory then 150 else 0)) * (1 + partyBonus + friendBonus) * tier.Reward)
	data.XP += xp
	local levelAfter = MetaData.Level(data.XP)

	-- fragments: a little for every real run, more for bosses / long runs / wins
	local fragments = run.Fragments
	if run.Time >= 60 then
		fragments += R.FragmentsBase + math.floor(run.Time / R.FragmentsTimeStep) * R.FragmentsPerStep
	end
	if run.Victory then
		fragments += R.FragmentsVictory
	end
	-- harder tiers: extra fragments for every real run, and again for a win
	if run.Time >= 60 then
		fragments += tier.Fragments
	end
	if run.Victory then
		fragments += tier.Fragments
	end
	fragments = math.floor(fragments * (1 + (live.FragmentBonus or 0)) + 0.5)
	self:GiveFragments(session, fragments)

	-- difficulty progress: bests per tier open the next tiers; a first win pays a bonus
	local diff = data.Difficulty
	local openBefore = DifficultyData.Unlocked(diff.Best)
	local best = diff.Best[tier.Index]
	best.Time = math.max(best.Time, run.Time)
	best.Bosses += #run.Bosses
	if run.Victory then
		best.Wins += 1
		stats.HighestWin = math.max(stats.HighestWin, tier.Index)
	end
	local openAfter = DifficultyData.Unlocked(diff.Best)
	local firstClear = nil
	if run.Victory and not diff.Cleared[tier.Index] then
		diff.Cleared[tier.Index] = true
		firstClear = { Coins = tier.FirstClear.Coins, Fragments = tier.FirstClear.Fragments }
		self:GiveCoins(session, firstClear.Coins)
		self:GiveFragments(session, firstClear.Fragments)
	end
	local newTier = if openAfter > openBefore then openAfter else nil
	local player = session.Player
	if player and player.Parent then
		local PM = self.Services.PlayerManager
		if firstClear then
			PM:Notify(player, string.format("FIRST CLEAR: %s %s  +%d coins, +%d fragments", tier.Name, tier.Numeral, firstClear.Coins, firstClear.Fragments), "Reward")
		end
		if newTier then
			local t = DifficultyData.Get(newTier)
			PM:Notify(player, string.format("NEW DIFFICULTY: %s %s", t.Name, t.Numeral), "Unlock")
		end
	end

	-- stats & bests
	local bests = {
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
	stats.Evolutions += run.Evolved
	stats.BestEvolutions = math.max(stats.BestEvolutions, run.Evolved)
	if run.Victory then
		stats.Wins += 1
	end
	if run.Reason == "Death" then
		stats.Deaths += 1
	end
	if ctx.Party > 1 then
		stats.PartyRuns += 1
	end

	-- collection
	local collectedBefore = CollectionData.Count(data)
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
	local seen = data.Seen
	for _, key in run.Picked do
		local def = WeaponData.ByKey[key]
		if def then
			if def.Evolution then
				seen.Evolutions[key] = true
			else
				seen.Weapons[key] = true
			end
		elseif UpgradeData.PassiveByKey[key] then
			seen.Passives[key] = true
		end
	end
	for _, key in run.EventsSeen do
		if WaveData.EventByKey[key] then
			seen.Events[key] = true
		end
	end

	-- quests & challenges
	local per = counters(run, ctx)
	advance(data.Quests.List, AchievementData.QuestByKey, per)
	self.Services.PlayerManager:RollWeekly(session)
	advanceWeekly(data, run, per)

	local newAchievements, unlocks = self:CheckAchievements(session, run)
	local collectedAfter, collectionTotal = CollectionData.Count(data)

	self.Services.LeaderboardManager:Submit(session)

	session.LastResult = { Coins = total, ChestOpened = false }
	return {
		Coins = total,
		Collected = run.Coins,
		Bonus = bonus,
		Multiplier = mult,
		PartyBonus = partyBonus,
		FriendBonus = friendBonus,
		FirstToday = firstToday,
		XP = xp,
		LevelBefore = levelBefore,
		LevelAfter = levelAfter,
		Fragments = fragments,
		FragmentsTotal = data.Fragments,
		NewCollection = collectedAfter - collectedBefore,
		CollectionCount = collectedAfter,
		CollectionTotal = collectionTotal,
		Achievements = newAchievements,
		Unlocks = unlocks,
		Best = bests,
		BestTime = stats.BestTime,
		BestLevel = stats.BestLevel,
		Difficulty = tier.Index,
		RewardMult = tier.Reward,
		FirstClear = firstClear,
		NewTier = newTier,
	}
end

-- Extra Chest (developer product): one more reward chest for the run that just ended
function RewardManager:OpenExtraChest(session): (boolean, number, number)
	local last = session.LastResult
	if not last or last.ChestOpened then
		return false, 0, 0
	end
	last.ChestOpened = true
	local coins = math.max(100, math.floor(last.Coins * 0.3))
	self:GiveCoins(session, coins)
	self:GiveFragments(session, 1)
	return true, coins, 1
end

return RewardManager
