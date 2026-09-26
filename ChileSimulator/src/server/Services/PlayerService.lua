--[[
	PlayerService - player sessions, replication and the ONE server tick.

	  * join: load data -> create Session -> passes -> leaderstats + attributes -> full Sync
	  * leave: save + release the session lock
	  * one 1 Hz tick for ALL players: zone check, boosts, auto growth, auto tap, playtime
	  * one 8 Hz flush for ALL players: partial Sync of dirty sections, attributes, queued
	    notifications / effects (so 20 taps per second never become 20 network messages)

	Replicated player attributes (everyone can read them - used for the stretched bodies,
	name tags, height comparisons): Height, BestHeight, Rebirths, Taps, Zone, Trail, Aura,
	VIP, Pets (equipped pet ids, comma separated), Loaded.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Formulas = require(Shared.Formulas)
local ZoneConfig = require(Shared.ZoneConfig)
local Format = require(Shared.Util.Format)
local Num = require(Shared.Util.Num)

local Logic = script.Parent.Parent.Logic
local Session = require(Logic.Session)
local Growth = require(Logic.Growth)
local Boosts = require(Logic.Boosts)
local Pets = require(Logic.Pets)
local Rewards = require(Logic.Rewards)
local Mults = require(Logic.Mults)
local AutoPlay = require(Logic.AutoPlay)
local Guard = require(script.Parent.Parent.Util.Guard)

local TICK = 1
local FLUSH = 0.125

local PlayerService = {}
PlayerService.Sessions = {} :: { [Player]: any }

function PlayerService:Init(services)
	self.Services = services
	self.Rng = Random.new()
	Guard.SetSessionProvider(function(player)
		return self.Sessions[player]
	end)
	self.SyncRemote = Net.Event("Sync")
	self.NotifyRemote = Net.Event("Notify")
	self.EffectRemote = Net.Event("Effect")
end

function PlayerService:GetSessions()
	return self.Sessions
end

function PlayerService:Get(player: Player)
	return self.Sessions[player]
end

function PlayerService:World()
	return self.Services.EventService:World()
end

---------------------------------------------------------------------------
-- Sync
---------------------------------------------------------------------------
local function copy(t)
	local out = {}
	for k, v in t do
		out[k] = if type(v) == "table" then copy(v) else v
	end
	return out
end

function PlayerService:BuildSync(session, dirty)
	local all = dirty.All
	local d = session.Data
	local world = self:World()
	local out = {}
	if all or dirty.Stats or dirty.Rates or dirty.Zones then
		out.Stats = {
			Height = d.Height,
			BestHeight = d.BestHeight,
			Coins = d.Coins,
			Gems = d.Gems,
			Rebirths = d.Rebirths,
			Taps = d.Taps,
			TapLevel = d.TapLevel,
			AutoLevel = d.AutoLevel,
			Gem = copy(d.Gem),
			Tutorial = d.Tutorial,
			RebirthCost = Formulas.RebirthCost(d.Rebirths),
			ZoneIndex = session.ZoneIndex,
			HighestZone = ZoneConfig.HighestUnlocked(d.BestHeight),
			Hatched = d.Stats.Hatched,
			Percentile = session.Percentile,
			InVIPArea = session.InVIPArea == true,
		}
		out.Rates = Mults.Rates(session, world)
	end
	if all or dirty.Pets then
		out.Pets = {
			List = copy(d.Pets),
			Capacity = Pets.Capacity(session),
			EquipLimit = Pets.EquipLimit(session),
			Multiplier = Pets.Multiplier(session),
			Luck = Pets.LuckMultiplier(session),
		}
	end
	if all or dirty.Boosts then
		out.Boosts = { Inventory = copy(d.Boosts.Inventory), Active = copy(d.Boosts.Active) }
	end
	if all or dirty.Cosmetics then
		out.Cosmetics = { Trails = copy(d.Trails), Auras = copy(d.Auras) }
	end
	if all or dirty.Rewards or dirty.Quests then
		Rewards.EnsureQuestDay(session, world.Now)
		out.Rewards = {
			Daily = Rewards.DailyStatus(session, world.Now),
			PlaytimeElapsed = Rewards.PlaytimeSeconds(session, os.clock()),
			-- string keys: a sparse numeric table ({[1]=..,[3]=..}) is truncated by remote serialization
			PlaytimeClaimed = (function()
				local claimed = {}
				for index, value in session.PlaytimeClaimed do
					claimed[tostring(index)] = value
				end
				return claimed
			end)(),
			Quests = { Progress = copy(d.Quests.Progress), Claimed = copy(d.Quests.Claimed) },
			Achievements = copy(d.Achievements),
			Stats = copy(d.Stats),
		}
	end
	if all or dirty.Settings then
		out.Settings = copy(d.Settings)
	end
	if all or dirty.Passes then
		out.Passes = copy(session.Passes)
	end
	if all then
		out.Meta = {
			SaveStatus = self.Services.DataService.Status,
			Persistent = self.Services.DataService.Persistent,
			IsStudio = RunService:IsStudio(),
			IsAdmin = self.Services.AdminService:IsAdmin(session.UserId),
		}
	end
	return out
end

function PlayerService:UpdateAttributes(player: Player, session)
	local d = session.Data
	local function set(name: string, value: any)
		if player:GetAttribute(name) ~= value then
			player:SetAttribute(name, value)
		end
	end
	set("Height", Num.Sanitize(d.Height, 1))
	set("BestHeight", Num.Sanitize(d.BestHeight, 1))
	set("Rebirths", d.Rebirths)
	set("Taps", Num.Sanitize(d.Taps))
	set("Zone", session.ZoneIndex)
	set("Trail", d.Trails.Equipped)
	set("Aura", d.Auras.Equipped)
	set("VIP", session.Passes.VIP == true)

	local equipped = {}
	for _, uid in Pets.EquippedList(session) do
		table.insert(equipped, d.Pets[uid].Id)
	end
	table.sort(equipped)
	set("Pets", table.concat(equipped, ","))

	local stats = player:FindFirstChild("leaderstats")
	if stats then
		local height = stats:FindFirstChild("Height")
		if height and height:IsA("StringValue") then
			height.Value = Format.Length(d.Height)
		end
		local rebirths = stats:FindFirstChild("Rebirths")
		if rebirths and rebirths:IsA("StringValue") then
			rebirths.Value = Format.Number(d.Rebirths)
		end
	end
end

function PlayerService:Flush(player: Player, session)
	if next(session.Dirty) then
		local payload = self:BuildSync(session, session.Dirty)
		table.clear(session.Dirty)
		self.SyncRemote:FireClient(player, payload)
	end
	if session.AttrDirty then
		session.AttrDirty = false
		self:UpdateAttributes(player, session)
	end
	if #session.Out > 0 then
		local out = Session.TakeOut(session)
		for i, item in out do
			if i > 12 then
				break -- never flood a client (the client queues and dedupes anyway)
			end
			if item.Type == "Notify" then
				self.NotifyRemote:FireClient(player, item)
			elseif item.Broadcast then
				self.EffectRemote:FireAllClients(item)
			else
				self.EffectRemote:FireClient(player, item)
			end
		end
	end
end

-- Server-wide banner (events, rare hatches...)
function PlayerService:NotifyAll(kind: string, text: string, extra: { [string]: any }?)
	local payload = { Type = "Notify", Kind = kind, Text = text }
	if extra then
		for k, v in extra do
			payload[k] = v
		end
	end
	self.NotifyRemote:FireAllClients(payload)
end

function PlayerService:EffectAll(name: string, payload: { [string]: any }?)
	local out = payload or {}
	out.Type = "Effect"
	out.Name = name
	self.EffectRemote:FireAllClients(out)
end

---------------------------------------------------------------------------
-- Join / leave
---------------------------------------------------------------------------
function PlayerService:OnPlayerAdded(player: Player)
	local DataService = self.Services.DataService
	local data = DataService:Load(player)
	if not data then
		if player.Parent then
			player:Kick("Could not load your progress (Roblox servers are busy). Please rejoin in a minute!")
		end
		return
	end
	local session = Session.new(player.UserId, player.Name, data, os.clock())
	if not player.Parent then
		-- left while loading: release the lock we just took
		DataService:Save(session, true)
		return
	end

	self.Services.MonetizationService:LoadPasses(player, session)
	Pets.Validate(session)
	Rewards.EnsureQuestDay(session, os.time())
	Rewards.CheckAchievements(session)
	session.ZoneIndex = 1

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local height = Instance.new("StringValue")
	height.Name = "Height"
	height.Parent = stats
	local rebirths = Instance.new("StringValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = stats
	stats.Parent = player

	self.Sessions[player] = session
	self:UpdateAttributes(player, session)
	player:SetAttribute("Loaded", true)
	self.Services.LeaderboardService:OnJoin(player, session)
	session.Dirty.All = true
	self:Flush(player, session)
end

function PlayerService:OnPlayerRemoving(player: Player)
	local session = self.Sessions[player]
	Guard.Forget(player)
	if not session then
		return
	end
	session.Leaving = true
	self.Services.LeaderboardService:OnLeave(player, session)
	self.Services.DataService:Save(session, true)
	session.Released = true
	self.Sessions[player] = nil
end

---------------------------------------------------------------------------
-- Tick
---------------------------------------------------------------------------
function PlayerService:Tick(dt: number)
	local world = self:World()
	local clock = os.clock()
	local WorldService = self.Services.WorldService
	for player, session in self.Sessions do
		if session.Leaving then
			continue
		end
		local zone = WorldService:ZoneFor(player, session)
		if zone ~= session.ZoneIndex then
			session.ZoneIndex = zone
			session.AttrDirty = true
			Session.MarkDirty(session, "Rates")
		end
		Boosts.Tick(session, dt)
		Growth.Tick(session, dt, world, clock)
		session.Data.Stats.PlayTime += dt
		if AutoPlay.Enabled(session) then
			self:AutoPlay(player, session, world, clock)
		end
	end
end

-- ONE-BUTTON MODE: upgrades, gems, rewards, boosts and eggs happen by themselves, and a
-- newly unlocked world (or the best world on join) is where you get moved to.
function PlayerService:AutoPlay(player: Player, session, world, clock: number)
	local results = AutoPlay.Tick(session, world, self.Rng, clock)
	if results then
		self.Services.PetService:AnnounceHatch(player, session, results)
	end
	local best = ZoneConfig.HighestUnlocked(session.Data.BestHeight)
	if best > (session.AutoZone or 0) then
		if best > session.ZoneIndex then
			if self.Services.WorldService:Teleport(player, best) then
				session.AutoZone = best
				session.ZoneIndex = best
				session.AttrDirty = true
				Session.MarkDirty(session, "Rates")
				Session.Effect(session, "Teleported", { Zone = best })
			end
		else
			session.AutoZone = best
		end
	end
end

function PlayerService:Start()
	Players.PlayerAdded:Connect(function(player)
		self:OnPlayerAdded(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:OnPlayerAdded(player)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		self:OnPlayerRemoving(player)
	end)

	local tickAcc, flushAcc = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		tickAcc += dt
		flushAcc += dt
		if tickAcc >= TICK then
			local step = math.min(tickAcc, 5)
			tickAcc = 0
			self:Tick(step)
		end
		if flushAcc >= FLUSH then
			flushAcc = 0
			for player, session in self.Sessions do
				self:Flush(player, session)
			end
		end
	end)

	-- small settings / tutorial remotes live here
	Guard.On("SetSetting", 5, function(session, _player, key, value)
		if type(key) ~= "string" or type(value) ~= "boolean" then
			return
		end
		if session.Data.Settings[key] == nil then
			return
		end
		session.Data.Settings[key] = value
		Session.MarkDirty(session, "Settings")
	end)

	Guard.On("SetAutoTap", 3, function(session, _player, enabled)
		if type(enabled) ~= "boolean" then
			return
		end
		session.Data.Settings.AutoTap = enabled
		Session.MarkDirty(session, "Settings")
	end)

	Guard.On("Tutorial", 2, function(session, _player, step)
		local value = Num.ValidInt(step, 0, 10)
		if value and value > session.Data.Tutorial then
			session.Data.Tutorial = value
			Session.MarkDirty(session, "Stats")
		end
	end)
end

return PlayerService
