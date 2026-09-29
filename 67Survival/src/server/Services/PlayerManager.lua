--[[
	PlayerManager - player sessions: load profile on join, save + release on leave, the
	lobby data snapshot (Sync), settings, daily reward, daily quests and weekly challenges.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local Net = require(Shared.Net)
local GameConfig = require(Shared.GameConfig)
local MetaData = require(Shared.MetaData)
local AchievementData = require(Shared.AchievementData)
local MonetizationData = require(Shared.MonetizationData)
local LiveEvents = require(Shared.LiveEvents)
local CollectionData = require(Shared.CollectionData)
local DifficultyData = require(Shared.DifficultyData)

local Guard = require(script.Parent.Parent.Util.Guard)
local Defaults = require(script.Parent.Parent.Data.Defaults)

local PlayerManager = {}

local DAY = 86400
local WEEK = 7 * DAY
local MONDAY = 4 * DAY -- 1970-01-05 was a Monday

function PlayerManager:Init(services)
	self.Services = services
	self.Sessions = {} -- [Player] = session
	self.Remotes = {
		Sync = Net.Event("Sync"),
		Notify = Net.Event("Notify"),
	}
end

function PlayerManager:GetSessions()
	return self.Sessions
end

function PlayerManager:Get(player: Player)
	local session = self.Sessions[player]
	if session and session.Loaded then
		return session
	end
	return nil
end

function PlayerManager.Today(): number
	return os.time() // DAY
end

function PlayerManager.Week(): number
	return (os.time() - MONDAY) // WEEK
end

-- seconds until the next weekly reset (Monday 00:00 UTC)
function PlayerManager.WeekLeft(): number
	local now = os.time()
	return (PlayerManager.Week() + 1) * WEEK + MONDAY - now
end

-- who gets the DEBUG panel: the game's creator (the owner, or a group owner/admin for a group
-- game) and GameConfig.AdminUserIds. Everyone else never gets it, in Studio too: "Local
-- Server" test players (negative ids) are regular players. Only an unpublished place (no
-- creator yet) lets the person testing in Studio in.
function PlayerManager:IsAdmin(player: Player): boolean
	if table.find(GameConfig.AdminUserIds, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		if game.CreatorId ~= 0 and player.UserId == game.CreatorId then
			return true
		end
	elseif game.CreatorType == Enum.CreatorType.Group and game.CreatorId ~= 0 then
		local ok, rank = pcall(function()
			return player:GetRankInGroup(game.CreatorId)
		end)
		if ok and type(rank) == "number" and rank >= GameConfig.AdminGroupRank then
			return true
		end
	end
	return RunService:IsStudio() and game.CreatorId == 0 and player.UserId > 0
end

---------------------------------------------------------------------------
-- daily quests
---------------------------------------------------------------------------
function PlayerManager:RollQuests(session)
	local today = PlayerManager.Today()
	local q = session.Data.Quests
	if q.Day == today and #q.List > 0 then
		return
	end
	local rng = Random.new(session.UserId * 31 + today)
	local pool = {}
	for _, def in AchievementData.Quests do
		table.insert(pool, def.Key)
	end
	local list = {}
	local usedKinds = {}
	while #list < AchievementData.QuestsPerDay and #pool > 0 do
		local i = rng:NextInteger(1, #pool)
		local key = table.remove(pool, i)
		local def = AchievementData.QuestByKey[key]
		if not usedKinds[def.Kind] then
			usedKinds[def.Kind] = true
			table.insert(list, { Key = key, Progress = 0, Claimed = false })
		end
	end
	session.Data.Quests = { Day = today, List = list }
end

function PlayerManager:RollWeekly(session)
	local week = PlayerManager.Week()
	local w = session.Data.Weekly
	if w.Week == week and #w.List > 0 then
		return
	end
	local rng = Random.new(session.UserId * 67 + week)
	local pool = {}
	for _, def in AchievementData.Weekly do
		table.insert(pool, def.Key)
	end
	local list = {}
	while #list < AchievementData.WeeklyPerWeek and #pool > 0 do
		local key = table.remove(pool, rng:NextInteger(1, #pool))
		table.insert(list, { Key = key, Progress = 0, Claimed = false })
	end
	session.Data.Weekly = { Week = week, List = list, Heroes = {} }
end

local function questView(list, byKey)
	local out = {}
	for _, q in list do
		local def = byKey[q.Key]
		table.insert(out, {
			Key = q.Key,
			Text = def.Text,
			Goal = def.Goal,
			Progress = math.min(q.Progress, def.Goal),
			Claimed = q.Claimed,
			Coins = def.Coins,
			Fragments = def.Fragments or 0,
		})
	end
	return out
end

---------------------------------------------------------------------------
-- snapshot for the client
---------------------------------------------------------------------------
-- the title shown on the name tag and the profile: a difficulty title (won on NIGHTMARE
-- or harder) beats the account level title
function PlayerManager.TitleOf(data): string
	return DifficultyData.TitleFor(data.Stats.HighestWin) or MetaData.TitleFor((MetaData.Level(data.XP)))
end

function PlayerManager:Snapshot(session)
	local d = session.Data
	local level, xp, need = MetaData.Level(d.XP)
	local now = os.time()
	local today = PlayerManager.Today()
	local streak = if d.Daily.Day == today - 1 then d.Daily.Streak + 1 elseif d.Daily.Day == today then d.Daily.Streak else 1
	local rewards = MetaData.DailyRewards
	local passes = {}
	local Monetization = self.Services.MonetizationManager
	for _, def in MonetizationData.Passes do
		passes[def.Key] = Monetization:HasPass(session.Player, def.Key)
	end
	local collected, total, perCategory = CollectionData.Count(d)
	return {
		Coins = d.Coins,
		Fragments = d.Fragments,
		XP = d.XP,
		Level = level,
		LevelXP = xp,
		LevelNeed = need,
		Title = PlayerManager.TitleOf(d),
		Difficulty = {
			Selected = d.Difficulty.Selected,
			Unlocked = DifficultyData.Unlocked(d.Difficulty.Best),
			Best = d.Difficulty.Best,
			Cleared = d.Difficulty.Cleared,
			HighestWin = d.Stats.HighestWin,
		},
		Heroes = d.Heroes,
		Selected = d.Selected,
		Weapons = d.Weapons,
		StartWeapon = d.StartWeapon,
		Loadouts = d.Loadouts,
		Loadout = d.Loadout,
		LoadoutSlots = if passes.ExtraLoadout then 3 else 1,
		Meta = d.Meta,
		Achievements = d.Achievements,
		Stats = d.Stats,
		Collection = d.Collection,
		Seen = d.Seen,
		CollectionCount = collected,
		CollectionTotal = total,
		CollectionPer = perCategory,
		Cosmetics = d.Cosmetics,
		CosmeticBoostLeft = math.max(0, d.CosmeticBoostUntil - now),
		Daily = {
			CanClaim = d.Daily.Day < today,
			Streak = streak,
			Reward = rewards[(streak - 1) % #rewards + 1] + level * 2,
		},
		Quests = questView(d.Quests.List, AchievementData.QuestByKey),
		Weekly = { List = questView(d.Weekly.List, AchievementData.WeeklyByKey), Left = PlayerManager.WeekLeft() },
		Afk = self.Services.AfkManager:Snapshot(session),
		Party = self.Services.PartyManager:Snapshot(session.Player),
		ServerGoal = self.Services.PartyManager:GoalSnapshot(),
		LiveEvents = LiveEvents.Active(now),
		Settings = d.Settings,
		Passes = passes,
		Prices = self.Services.MonetizationManager.Prices,
		SaveStatus = self.Services.DataManager.Status,
		Admin = self:IsAdmin(session.Player),
		Studio = RunService:IsStudio(),
	}
end

function PlayerManager:Sync(player: Player)
	local session = self:Get(player)
	if not session then
		return
	end
	local level = MetaData.Level(session.Data.XP)
	player:SetAttribute("AccountLevel", level)
	player:SetAttribute("Title", PlayerManager.TitleOf(session.Data))
	player:SetAttribute("Hero", session.Data.Selected)
	self.Remotes.Sync:FireClient(player, self:Snapshot(session))
end

function PlayerManager:Notify(player: Player, text: string, kind: string?)
	self.Remotes.Notify:FireClient(player, { Text = text, Kind = kind or "Info" })
end

---------------------------------------------------------------------------
-- remotes
---------------------------------------------------------------------------
function PlayerManager:ClaimDaily(player: Player)
	local session = self:Get(player)
	if not session then
		return
	end
	local d = session.Data
	local today = PlayerManager.Today()
	if d.Daily.Day >= today then
		self:Notify(player, "Come back tomorrow for the next reward!", "Error")
		return
	end
	local streak = if d.Daily.Day == today - 1 then d.Daily.Streak + 1 else 1
	local level = MetaData.Level(d.XP)
	local rewards = MetaData.DailyRewards
	local coins = rewards[(streak - 1) % #rewards + 1] + level * 2
	d.Daily.Day = today
	d.Daily.Streak = streak
	self.Services.RewardManager:GiveCoins(session, coins)
	self:Notify(player, string.format("Day %d reward: +%d coins!", streak, coins), "Reward")
	self:Sync(player)
end

function PlayerManager:ClaimQuest(player: Player, index: number)
	local session = self:Get(player)
	if not session then
		return
	end
	self:RollQuests(session)
	local q = session.Data.Quests.List[index]
	if not q then
		return
	end
	local def = AchievementData.QuestByKey[q.Key]
	if q.Claimed or q.Progress < def.Goal then
		self:Notify(player, "Quest not finished yet", "Error")
		return
	end
	q.Claimed = true
	self.Services.RewardManager:GiveCoins(session, def.Coins)
	local fragments = def.Fragments or 0
	if fragments > 0 then
		self.Services.RewardManager:GiveFragments(session, fragments)
	end
	self:Notify(player, string.format("Quest complete: +%d coins%s!", def.Coins, if fragments > 0 then string.format(", +%d fragment%s", fragments, if fragments == 1 then "" else "s") else ""), "Reward")
	self:Sync(player)
end

function PlayerManager:ClaimWeekly(player: Player, index: number)
	local session = self:Get(player)
	if not session then
		return
	end
	self:RollWeekly(session)
	local q = session.Data.Weekly.List[index]
	if not q then
		return
	end
	local def = AchievementData.WeeklyByKey[q.Key]
	if q.Claimed or q.Progress < def.Goal then
		self:Notify(player, "Challenge not finished yet", "Error")
		return
	end
	q.Claimed = true
	self.Services.RewardManager:GiveCoins(session, def.Coins)
	self.Services.RewardManager:GiveFragments(session, def.Fragments or 0)
	self:Notify(player, string.format("Challenge complete: +%d coins, +%d fragments!", def.Coins, def.Fragments or 0), "Reward")
	self:Sync(player)
end

-- the difficulty for the next runs (only tiers the player has opened)
function PlayerManager:SelectDifficulty(player: Player, index: number)
	local session = self:Get(player)
	if not session then
		return
	end
	local d = session.Data.Difficulty
	local open = DifficultyData.Unlocked(d.Best)
	if index < 1 or index > open then
		local tier = DifficultyData.Get(index)
		self:Notify(player, string.format("%s is locked: %s", tier.Name, if tier.Unlock then tier.Unlock.Text else ""), "Error")
		return
	end
	d.Selected = index
	self:Sync(player)
end

function PlayerManager:SetSetting(player: Player, key: any, value: any)
	local session = self:Get(player)
	if not session or type(key) ~= "string" then
		return
	end
	local default = Defaults.SettingKeys[key]
	if default == nil or type(value) ~= type(default) then
		return
	end
	session.Data.Settings[key] = value
	self:Sync(player)
end

---------------------------------------------------------------------------
-- lifecycle
---------------------------------------------------------------------------
function PlayerManager:OnJoin(player: Player)
	local session = {
		Player = player,
		UserId = player.UserId,
		Loaded = false,
		Leaving = false,
		Released = false,
		JoinedAt = os.clock(),
	}
	self.Sessions[player] = session
	local data = self.Services.DataManager:Load(player)
	if not player.Parent then
		-- left while loading: release the lock we just took
		if data then
			session.Data = data
			self.Services.DataManager:Save(session, true)
		end
		self.Sessions[player] = nil
		return
	end
	if not data then
		self.Sessions[player] = nil
		player:Kick("Could not load your data. Please rejoin in a moment.")
		return
	end
	session.Data = data
	session.Loaded = true
	self:RollQuests(session)
	self:RollWeekly(session)
	self.Services.MonetizationManager:LoadPasses(player)
	self.Services.CharacterManager:SpawnInLobby(player)
	self:Sync(player)
	self.Services.RewardManager:CheckAchievements(session)
end

function PlayerManager:OnLeave(player: Player)
	local session = self.Sessions[player]
	if not session then
		return
	end
	session.Leaving = true
	if session.Loaded then
		self.Services.GameManager:OnPlayerLeaving(player)
		session.Data.Stats.PlayTime += math.floor(os.clock() - session.JoinedAt)
		self.Services.DataManager:Save(session, true)
		session.Released = true
	end
	self.Sessions[player] = nil
end

function PlayerManager:Start()
	Guard.Connect(Net.Event("Ready"), { Rate = 1, Burst = 3 }, function(player)
		self:Sync(player)
	end)
	Guard.Connect(Net.Event("ClaimDaily"), { Rate = 1, Burst = 2 }, function(player)
		self:ClaimDaily(player)
	end)
	Guard.Connect(Net.Event("ClaimQuest"), { Rate = 2, Burst = 4 }, function(player, index)
		local i = Guard.Int(index, 1, AchievementData.QuestsPerDay)
		if i then
			self:ClaimQuest(player, i)
		end
	end)
	Guard.Connect(Net.Event("ClaimWeekly"), { Rate = 2, Burst = 4 }, function(player, index)
		local i = Guard.Int(index, 1, AchievementData.WeeklyPerWeek)
		if i then
			self:ClaimWeekly(player, i)
		end
	end)
	Guard.Connect(Net.Event("SetSetting"), { Rate = 4, Burst = 8 }, function(player, key, value)
		self:SetSetting(player, key, value)
	end)
	Guard.Connect(Net.Event("SelectDifficulty"), { Rate = 4, Burst = 8 }, function(player, index)
		local i = Guard.Int(index, 1, DifficultyData.Count)
		if i then
			self:SelectDifficulty(player, i)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		self:OnJoin(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:OnLeave(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:OnJoin(player)
		end)
	end
end

return PlayerManager
