--[[
	PartyManager - small, optional social features:

	  * PARTY: up to GameConfig.Party.MaxSize players. Invites expire after a few seconds and
	    are never repeated automatically. When anyone in the party presses PLAY, everyone in
	    the lobby starts together: next to each other in the arena, and the 67 EVENTS of the
	    player who pressed PLAY happen in everyone's run at the same moment. (Every player
	    still fights their own horde: runs are simulated separately.)
	    Party bonus: +10% coins and XP per other member (max +30%).
	  * FRIENDS: +5% coins and XP per friend in the same server (max +15%).
	  * SERVER GOAL: every enemy defeated on the server counts towards a shared goal; when it
	    is reached everyone online gets a reward and a new goal starts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local Net = require(Shared.Net)
local GameConfig = require(Shared.GameConfig)

local Guard = require(script.Parent.Parent.Util.Guard)

local PartyManager = {}

local P = GameConfig.Party

function PartyManager:Init(services)
	self.Services = services
	self.PartyOf = {} -- [Player] = party { Id, Leader, Members = { Player } }
	self.Invites = {} -- [Player target] = { [Player from] = expires (os.clock) }
	self.Friends = {} -- [Player] = { [userId] = true } (friends in this server)
	self.NextId = 0
	self.GoalKills = 0
	self.GoalsReached = 0
	self.Remote = Net.Event("Party")
end

---------------------------------------------------------------------------
-- queries
---------------------------------------------------------------------------
function PartyManager:Get(player: Player)
	return self.PartyOf[player]
end

function PartyManager:Members(player: Player): { Player }
	local party = self.PartyOf[player]
	if not party then
		return { player }
	end
	return table.clone(party.Members)
end

function PartyManager:FriendsOnline(player: Player): number
	local set = self.Friends[player]
	if not set then
		return 0
	end
	local n = 0
	for _, other in Players:GetPlayers() do
		if other ~= player and set[other.UserId] then
			n += 1
		end
	end
	return n
end

function PartyManager:Snapshot(player: Player)
	local party = self.PartyOf[player]
	local members = {}
	if party then
		for _, m in party.Members do
			table.insert(members, {
				UserId = m.UserId,
				Name = m.DisplayName,
				Hero = m:GetAttribute("Hero") or "",
				Leader = m == party.Leader,
				InRun = m:GetAttribute("InRun") == true,
			})
		end
	end
	local invites = {}
	local now = os.clock()
	for from, expires in self.Invites[player] or {} do
		if expires > now and from.Parent then
			table.insert(invites, { UserId = from.UserId, Name = from.DisplayName, Left = math.ceil(expires - now) })
		end
	end
	return {
		InParty = party ~= nil,
		Leader = party ~= nil and party.Leader == player,
		Members = members,
		Invites = invites,
		MaxSize = P.MaxSize,
		Friends = self:FriendsOnline(player),
	}
end

function PartyManager:GoalSnapshot()
	return { Kills = self.GoalKills, Goal = P.ServerGoal, Coins = P.ServerGoalCoins, Reached = self.GoalsReached }
end

local function syncAll(self, players: { Player })
	for _, p in players do
		if p.Parent then
			self.Services.PlayerManager:Sync(p)
		end
	end
end

---------------------------------------------------------------------------
-- actions
---------------------------------------------------------------------------
function PartyManager:Invite(player: Player, target: Player)
	local PM = self.Services.PlayerManager
	if target == player or not target.Parent or not PM:Get(target) then
		return
	end
	local party = self.PartyOf[player]
	if party and #party.Members >= P.MaxSize then
		PM:Notify(player, "Your party is full", "Error")
		return
	end
	if self.PartyOf[target] then
		PM:Notify(player, target.DisplayName .. " is already in a party", "Error")
		return
	end
	self.Invites[target] = self.Invites[target] or {}
	local existing = self.Invites[target][player]
	if existing and existing > os.clock() then
		return -- one invite at a time, no spam
	end
	self.Invites[target][player] = os.clock() + P.InviteSeconds
	self.Remote:FireClient(target, { Kind = "Invite", From = player.DisplayName, FromId = player.UserId, Seconds = P.InviteSeconds })
	PM:Notify(player, "Invite sent to " .. target.DisplayName, "Info")
	PM:Sync(target)
end

local function removeFrom(self, player: Player)
	local party = self.PartyOf[player]
	if not party then
		return nil
	end
	self.PartyOf[player] = nil
	local i = table.find(party.Members, player)
	if i then
		table.remove(party.Members, i)
	end
	if #party.Members <= 1 then
		-- a party of one is no party
		for _, m in party.Members do
			self.PartyOf[m] = nil
		end
		local left = party.Members
		party.Members = {}
		return left
	end
	if party.Leader == player then
		party.Leader = party.Members[1]
	end
	return party.Members
end

function PartyManager:Accept(player: Player, from: Player)
	local PM = self.Services.PlayerManager
	local invites = self.Invites[player]
	local expires = invites and invites[from]
	if not expires or expires < os.clock() or not from.Parent then
		PM:Notify(player, "That invite expired", "Error")
		return
	end
	invites[from] = nil
	if self.PartyOf[player] then
		removeFrom(self, player)
	end
	local party = self.PartyOf[from]
	if not party then
		self.NextId += 1
		party = { Id = self.NextId, Leader = from, Members = { from } }
		self.PartyOf[from] = party
	end
	if #party.Members >= P.MaxSize then
		PM:Notify(player, "That party is full", "Error")
		return
	end
	table.insert(party.Members, player)
	self.PartyOf[player] = party
	for _, m in party.Members do
		PM:Notify(m, player.DisplayName .. " joined the party", "Success")
	end
	syncAll(self, party.Members)
end

function PartyManager:Decline(player: Player, from: Player)
	local invites = self.Invites[player]
	if invites then
		invites[from] = nil
	end
	self.Services.PlayerManager:Sync(player)
end

function PartyManager:Leave(player: Player)
	local rest = removeFrom(self, player)
	if rest then
		for _, m in rest do
			self.Services.PlayerManager:Notify(m, player.DisplayName .. " left the party", "Info")
		end
		syncAll(self, rest)
	end
	if player.Parent then
		self.Services.PlayerManager:Sync(player)
	end
end

function PartyManager:Kick(player: Player, target: Player)
	local party = self.PartyOf[player]
	if party and party.Leader == player and self.PartyOf[target] == party and target ~= player then
		self:Leave(target)
		self.Services.PlayerManager:Notify(target, "You were removed from the party", "Info")
	end
end

---------------------------------------------------------------------------
-- server goal
---------------------------------------------------------------------------
function PartyManager:AddKills(n: number)
	if n <= 0 then
		return
	end
	self.GoalKills += n
	if self.GoalKills < P.ServerGoal then
		return
	end
	self.GoalKills -= P.ServerGoal
	self.GoalsReached += 1
	local PM = self.Services.PlayerManager
	for _, player in Players:GetPlayers() do
		local session = PM:Get(player)
		if session then
			self.Services.RewardManager:GiveCoins(session, P.ServerGoalCoins)
			PM:Notify(player, string.format("SERVER GOAL: %d enemies defeated together! +%d coins", P.ServerGoal, P.ServerGoalCoins), "Reward")
			PM:Sync(player)
		end
	end
end

---------------------------------------------------------------------------
-- lifecycle
---------------------------------------------------------------------------
local function loadFriends(self, player: Player)
	local set = {}
	self.Friends[player] = set
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local ok, isFriend = pcall(function()
				return player:IsFriendsWithAsync(other.UserId)
			end)
			if ok and isFriend then
				set[other.UserId] = true
				self.Friends[other] = self.Friends[other] or {}
				self.Friends[other][player.UserId] = true
			end
		end
	end
end

local function playerById(userId: any): Player?
	if type(userId) ~= "number" then
		return nil
	end
	return Players:GetPlayerByUserId(userId)
end

function PartyManager:Start()
	Guard.Connect(Net.Event("PartyInvite"), { Rate = 1, Burst = 3 }, function(player, userId)
		local target = playerById(userId)
		if target then
			self:Invite(player, target)
		end
	end)
	Guard.Connect(Net.Event("PartyAccept"), { Rate = 1, Burst = 3 }, function(player, userId)
		local from = playerById(userId)
		if from then
			self:Accept(player, from)
		end
	end)
	Guard.Connect(Net.Event("PartyDecline"), { Rate = 2, Burst = 4 }, function(player, userId)
		local from = playerById(userId)
		if from then
			self:Decline(player, from)
		end
	end)
	Guard.Connect(Net.Event("PartyLeave"), { Rate = 1, Burst = 2 }, function(player)
		self:Leave(player)
	end)
	Guard.Connect(Net.Event("PartyKick"), { Rate = 1, Burst = 2 }, function(player, userId)
		local target = playerById(userId)
		if target then
			self:Kick(player, target)
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		task.spawn(loadFriends, self, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(loadFriends, self, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		self:Leave(player)
		self.Invites[player] = nil
		self.Friends[player] = nil
		for _, invites in self.Invites do
			invites[player] = nil
		end
		for _, set in self.Friends do
			set[player.UserId] = nil
		end
	end)
end

return PartyManager
