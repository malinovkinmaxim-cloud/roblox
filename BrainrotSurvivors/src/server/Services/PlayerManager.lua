--[[
	PlayerManager - player sessions: load profile on join, save + release on leave, the
	lobby data snapshot (Sync), settings, daily reward and daily quests.
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

local Guard = require(script.Parent.Parent.Util.Guard)
local Defaults = require(script.Parent.Parent.Data.Defaults)

local PlayerManager = {}

local DAY = 86400

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

function PlayerManager:IsAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if table.find(GameConfig.AdminUserIds, player.UserId) then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
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

---------------------------------------------------------------------------
-- snapshot for the client
---------------------------------------------------------------------------
function PlayerManager:Snapshot(session)
	local d = session.Data
	local level, xp, need = MetaData.BrainLevel(d.BrainXP)
	local today = PlayerManager.Today()
	local streak = if d.Daily.Day == today - 1 then d.Daily.Streak + 1 elseif d.Daily.Day == today then d.Daily.Streak else 1
	local rewards = MetaData.DailyRewards
	local quests = {}
	for _, q in d.Quests.List do
		local def = AchievementData.QuestByKey[q.Key]
		table.insert(quests, {
			Key = q.Key,
			Text = def.Text,
			Goal = def.Goal,
			Progress = math.min(q.Progress, def.Goal),
			Claimed = q.Claimed,
			Coins = def.Coins,
		})
	end
	local passes = {}
	local Monetization = self.Services.MonetizationManager
	for _, def in MonetizationData.Passes do
		passes[def.Key] = Monetization:HasPass(session.Player, def.Key)
	end
	return {
		Coins = d.Coins,
		BrainXP = d.BrainXP,
		BrainLevel = level,
		BrainLevelXP = xp,
		BrainLevelNeed = need,
		Title = MetaData.TitleFor(level),
		Characters = d.Characters,
		Selected = d.Selected,
		Weapons = d.Weapons,
		StartWeapon = d.StartWeapon,
		Skins = d.Skins,
		EquippedSkin = d.EquippedSkin,
		Meta = d.Meta,
		Achievements = d.Achievements,
		Stats = d.Stats,
		Collection = d.Collection,
		Daily = {
			CanClaim = d.Daily.Day < today,
			Streak = streak,
			Reward = rewards[(streak - 1) % #rewards + 1] + level * 2,
		},
		Quests = quests,
		Settings = d.Settings,
		Passes = passes,
		CoinRushLeft = math.max(0, d.CoinRushUntil - os.time()),
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
	local level = MetaData.BrainLevel(session.Data.BrainXP)
	player:SetAttribute("BrainLevel", level)
	player:SetAttribute("Title", MetaData.TitleFor(level))
	player:SetAttribute("Character", session.Data.Selected)
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
	local level = MetaData.BrainLevel(d.BrainXP)
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
	self:Notify(player, string.format("Quest complete: +%d coins!", def.Coins), "Reward")
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
	Guard.Connect(Net.Event("SetSetting"), { Rate = 4, Burst = 8 }, function(player, key, value)
		self:SetSetting(player, key, value)
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
