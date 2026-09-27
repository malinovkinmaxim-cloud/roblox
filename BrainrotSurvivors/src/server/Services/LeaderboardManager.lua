--[[
	LeaderboardManager - global top lists (OrderedDataStore), refreshed periodically.

	Boards: Highest Level, Longest Survival, Most Enemies Defeated, Most Bosses Defeated,
	Coins (lifetime earned, so spending never drops you). Values are submitted at the end of
	every run. Without DataStore access (Studio) the boards show the players on this server.
	The lobby board (a part with attribute Leaderboard) shows Longest Survival.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local Net = require(Shared.Net)
local GameConfig = require(Shared.GameConfig)

local Guard = require(script.Parent.Parent.Util.Guard)

local LeaderboardManager = {}

LeaderboardManager.Boards = {
	{ Key = "BestLevel", Title = "Highest Level", Stat = "BestLevel", Format = "Level" },
	{ Key = "BestTime", Title = "Longest Survival", Stat = "BestTime", Format = "Time" },
	{ Key = "Kills", Title = "Enemies Defeated", Stat = "Kills", Format = "Number" },
	{ Key = "Bosses", Title = "Bosses Defeated", Stat = "Bosses", Format = "Number" },
	{ Key = "Coins", Title = "Coins Earned", Stat = "LifetimeCoins", Format = "Number" },
}

function LeaderboardManager:Init(services)
	self.Services = services
	self.Stores = {}
	self.Top = {}
	self.Submitted = {} -- [userId][board] = last value
	self.Names = {}
	for _, board in self.Boards do
		self.Top[board.Key] = {}
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore("BrainrotSurvivors_" .. board.Key .. "_v1")
		end)
		if ok then
			self.Stores[board.Key] = store
		end
	end
	self.Remote = Net.Event("Leaderboard")
end

function LeaderboardManager:Submit(session)
	if not self.Services.DataManager.Persistent then
		return
	end
	local userId = session.UserId
	self.Submitted[userId] = self.Submitted[userId] or {}
	local last = self.Submitted[userId]
	for _, board in self.Boards do
		local value = math.floor(session.Data.Stats[board.Stat] or 0)
		local store = self.Stores[board.Key]
		if store and value > 0 and last[board.Key] ~= value then
			last[board.Key] = value
			task.spawn(function()
				local ok, err = pcall(function()
					store:SetAsync(tostring(userId), value)
				end)
				if not ok then
					warn("[Leaderboard] submit failed: " .. tostring(err))
				end
			end)
		end
	end
end

function LeaderboardManager:NameOf(userId: number): string
	local cached = self.Names[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	local name = player and player.DisplayName
	if not name then
		local ok, result = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		name = if ok then result else "Player" .. userId
	end
	self.Names[userId] = name
	return name
end

function LeaderboardManager:Refresh()
	local persistent = self.Services.DataManager.Persistent
	for _, board in self.Boards do
		local rows = {}
		local store = self.Stores[board.Key]
		if persistent and store then
			local ok, pages = pcall(function()
				return store:GetSortedAsync(false, GameConfig.Leaderboard.Size)
			end)
			if ok and pages then
				for rank, entry in pages:GetCurrentPage() do
					local userId = tonumber(entry.key) or 0
					table.insert(rows, { Rank = rank, Name = self:NameOf(userId), Value = entry.value, UserId = userId })
				end
			end
		else
			-- memory mode: players on this server
			for _, session in self.Services.PlayerManager:GetSessions() do
				if session.Loaded then
					table.insert(rows, { Name = session.Player.DisplayName, Value = session.Data.Stats[board.Stat] or 0, UserId = session.UserId })
				end
			end
			table.sort(rows, function(a, b)
				return a.Value > b.Value
			end)
			for i, row in rows do
				row.Rank = i
			end
		end
		self.Top[board.Key] = rows
	end
	self:UpdateLobbyBoard()
end

function LeaderboardManager:Payload(player: Player)
	local session = self.Services.PlayerManager:Get(player)
	local mine = {}
	if session then
		for _, board in self.Boards do
			mine[board.Key] = session.Data.Stats[board.Stat] or 0
		end
	end
	local boards = {}
	for _, board in self.Boards do
		table.insert(boards, { Key = board.Key, Title = board.Title, Format = board.Format, Rows = self.Top[board.Key] })
	end
	return { Boards = boards, Mine = mine }
end

local function formatTime(s: number): string
	return string.format("%d:%02d", s // 60, s % 60)
end

function LeaderboardManager:UpdateLobbyBoard()
	local map = Workspace:FindFirstChild("Map")
	if not map then
		return
	end
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Leaderboard") then
			local key = d:GetAttribute("Leaderboard")
			local gui = d:FindFirstChild("BoardGui") :: SurfaceGui?
			if not gui then
				local g = Instance.new("SurfaceGui")
				g.Name = "BoardGui"
				g.Face = Enum.NormalId.Front
				g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				g.PixelsPerStud = 20
				g.LightInfluence = 0
				g.Parent = d
				local list = Instance.new("TextLabel")
				list.Name = "List"
				list.Size = UDim2.fromScale(1, 1)
				list.BackgroundColor3 = Color3.fromRGB(30, 25, 50)
				list.TextColor3 = Color3.fromRGB(255, 255, 255)
				list.Font = Enum.Font.FredokaOne
				list.TextScaled = true
				list.TextXAlignment = Enum.TextXAlignment.Left
				list.TextYAlignment = Enum.TextYAlignment.Top
				list.Parent = g
				gui = g
			end
			assert(gui)
			local lines = { "🏆 LONGEST SURVIVAL" }
			for _, row in self.Top[key] or {} do
				table.insert(lines, string.format("%d. %s  %s", row.Rank, row.Name, formatTime(row.Value)))
			end
			if #lines == 1 then
				table.insert(lines, "Be the first survivor!")
			end
			(gui:FindFirstChild("List") :: TextLabel).Text = table.concat(lines, "\n")
		end
	end
end

function LeaderboardManager:Start()
	Guard.Connect(Net.Event("RequestLeaderboard"), { Rate = 0.5, Burst = 2 }, function(player)
		self.Remote:FireClient(player, self:Payload(player))
	end)
	task.spawn(function()
		task.wait(5)
		while true do
			local ok, err = pcall(function()
				self:Refresh()
			end)
			if not ok then
				warn("[Leaderboard] refresh failed: " .. tostring(err))
			end
			task.wait(GameConfig.Leaderboard.RefreshInterval)
		end
	end)
end

return LeaderboardManager
