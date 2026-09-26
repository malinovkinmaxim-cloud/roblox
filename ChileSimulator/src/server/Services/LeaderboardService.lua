--[[
	LeaderboardService - in-world leaderboards + global "taller than X% of players".

	Boards (built by WorldService at spawn):
	  TALLEST PLAYERS  - all-time best height (OrderedDataStore, log-encoded: ODS only stores integers)
	  MOST REBIRTHS    - OrderedDataStore
	  MOST TAPS        - OrderedDataStore
	  TALLEST RIGHT NOW - live, this server (updates every 2 s)
	Without DataStore access the global boards fall back to this server's players.

	Global percentile: a histogram of everybody's best height (4 buckets per decade) in one
	DataStore key. Each server batches its +1/-1 bucket moves and applies them with one
	UpdateAsync per refresh. From it we compute "you are taller than X% of players".
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)

local Session = require(script.Parent.Parent.Logic.Session)

local LeaderboardService = {}

local BOARDS = {
	{ Key = "Tallest", Store = "CS_Tallest_v1", Title = "🏆 TALLEST PLAYERS", Stat = "BestHeight" },
	{ Key = "Rebirths", Store = "CS_Rebirths_v1", Title = "♻️ MOST REBIRTHS", Stat = "Rebirths" },
	{ Key = "Taps", Store = "CS_Taps_v1", Title = "👆 MOST TAPS", Stat = "Taps" },
}

local HISTOGRAM_STORE = "CS_Global_v1"
local HISTOGRAM_KEY = "HeightHistogram"

function LeaderboardService:Init(services)
	self.Services = services
	self.Stores = {}
	self.LastWritten = {} -- [userId] = { [boardKey] = value }
	self.Names = {} -- userId -> name cache
	self.Pending = {} -- histogram bucket deltas
	self.Histogram = nil -- { Counts = {[string]=n}, Total = n }
	self.Global = self.Services.DataService.Persistent
	if self.Global then
		for _, board in BOARDS do
			local ok, store = pcall(function()
				return DataStoreService:GetOrderedDataStore(board.Store)
			end)
			if ok then
				self.Stores[board.Key] = store
			end
		end
		local ok, store = pcall(function()
			return DataStoreService:GetDataStore(HISTOGRAM_STORE)
		end)
		if ok then
			self.HistogramStore = store
		end
	end
end

local function statValue(session, stat: string): number
	local d = session.Data
	if stat == "BestHeight" then
		return Formulas.EncodeHeight(d.BestHeight)
	elseif stat == "Rebirths" then
		return d.Rebirths
	end
	return math.floor(math.min(d.Taps, 2 ^ 52))
end

local function formatValue(boardKey: string, value: number): string
	if boardKey == "Tallest" then
		return Format.Length(Formulas.DecodeHeight(value))
	end
	return Format.Number(value)
end

function LeaderboardService:NameFor(userId: number): string
	local cached = self.Names[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		self.Names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and name then name else "Player"
	self.Names[userId] = result
	return result
end

---------------------------------------------------------------------------
-- Histogram (percentile)
---------------------------------------------------------------------------
function LeaderboardService:TrackBucket(session)
	local bucket = Formulas.HeightBucket(session.Data.BestHeight)
	local old = session.Data.HistogramBucket
	if bucket ~= old then
		if old >= 0 then
			self.Pending[tostring(old)] = (self.Pending[tostring(old)] or 0) - 1
		end
		self.Pending[tostring(bucket)] = (self.Pending[tostring(bucket)] or 0) + 1
		session.Data.HistogramBucket = bucket
	end
end

function LeaderboardService:FlushHistogram()
	if not self.HistogramStore then
		return
	end
	local deltas = self.Pending
	self.Pending = {}
	local ok, result = pcall(function()
		return self.HistogramStore:UpdateAsync(HISTOGRAM_KEY, function(old)
			old = if type(old) == "table" then old else { Counts = {}, Total = 0 }
			old.Counts = if type(old.Counts) == "table" then old.Counts else {}
			local total = 0
			for bucket, delta in deltas do
				old.Counts[bucket] = math.max(0, (tonumber(old.Counts[bucket]) or 0) + delta)
			end
			for _, n in old.Counts do
				total += tonumber(n) or 0
			end
			old.Total = total
			return old
		end)
	end)
	if ok and type(result) == "table" then
		self.Histogram = result
	else
		-- put the deltas back and try again next refresh
		for bucket, delta in deltas do
			self.Pending[bucket] = (self.Pending[bucket] or 0) + delta
		end
	end
end

-- Fraction (0..1) of players whose best height is below `heightCm`, or nil if not enough data
function LeaderboardService:Percentile(heightCm: number): number?
	local hist = self.Histogram
	if not hist or (hist.Total or 0) < Config.PercentileMinPlayers then
		return nil
	end
	local mine = Formulas.HeightBucket(heightCm)
	local below = 0
	for bucket, n in hist.Counts do
		local b = tonumber(bucket)
		if b and b < mine then
			below += tonumber(n) or 0
		end
	end
	return below / hist.Total
end

function LeaderboardService:CheckPercentiles()
	for _, session in self.Services.PlayerService:GetSessions() do
		local fraction = self:Percentile(session.Data.Height)
		session.Percentile = fraction
		if fraction then
			local percent = fraction * 100
			for _, threshold in Config.PercentileAnnouncements do
				if percent >= threshold and threshold > session.Data.AnnouncedPercentile then
					session.Data.AnnouncedPercentile = threshold
					Session.Notify(session, "Big", string.format("🚨 YOU ARE NOW TALLER THAN %s%% OF PLAYERS!", tostring(threshold)), { Sound = "BigGrowth" })
				end
			end
		end
		Session.MarkDirty(session, "Stats")
	end
end

---------------------------------------------------------------------------
-- Boards
---------------------------------------------------------------------------
function LeaderboardService:ServerRows(stat: string)
	local rows = {}
	for player, session in self.Services.PlayerService:GetSessions() do
		table.insert(rows, { Name = player.DisplayName, Value = statValue(session, stat) })
	end
	table.sort(rows, function(a, b)
		return a.Value > b.Value
	end)
	return rows
end

function LeaderboardService:Render(boardKey: string, title: string, rows, footer: string)
	local board = self.Services.WorldService:GetBoard(boardKey)
	if not board then
		return
	end
	board.Title.Text = title
	board.Footer.Text = footer
	for i, row in board.Rows do
		local entry = rows[i]
		if entry then
			row.Name.Text = entry.Name
			row.Value.Text = formatValue(if boardKey == "Live" then "Tallest" else boardKey, entry.Value)
			row.Frame.Visible = true
		else
			row.Frame.Visible = false
		end
	end
end

function LeaderboardService:WriteScores(session)
	local written = self.LastWritten[session.UserId]
	if not written then
		written = {}
		self.LastWritten[session.UserId] = written
	end
	for _, board in BOARDS do
		local store = self.Stores[board.Key]
		local value = statValue(session, board.Stat)
		if store and written[board.Key] ~= value and value > 0 then
			local ok = pcall(function()
				store:SetAsync(tostring(session.UserId), value)
			end)
			if ok then
				written[board.Key] = value
			end
		end
	end
end

function LeaderboardService:RefreshGlobal()
	for _, session in self.Services.PlayerService:GetSessions() do
		self:WriteScores(session)
	end
	for _, board in BOARDS do
		local store = self.Stores[board.Key]
		local rows
		if store then
			local ok, page = pcall(function()
				return store:GetSortedAsync(false, Config.Leaderboards.TopCount):GetCurrentPage()
			end)
			if ok and page then
				rows = {}
				for _, entry in page do
					local userId = tonumber(entry.key)
					if userId then
						table.insert(rows, { Name = self:NameFor(userId), Value = entry.value })
					end
				end
			end
		end
		if rows then
			self:Render(board.Key, board.Title, rows, "ALL TIME • updates every minute")
		else
			self:Render(board.Key, board.Title, self:ServerRows(board.Stat), "THIS SERVER")
		end
	end
	self:FlushHistogram()
	self:CheckPercentiles()
end

function LeaderboardService:OnJoin(_player: Player, session)
	self:TrackBucket(session)
end

function LeaderboardService:OnLeave(_player: Player, session)
	self:TrackBucket(session)
	task.spawn(function()
		self:WriteScores(session)
		self.LastWritten[session.UserId] = nil
	end)
end

function LeaderboardService:Start()
	-- live board: this server, current height
	task.spawn(function()
		while true do
			local rows = {}
			for player, session in self.Services.PlayerService:GetSessions() do
				table.insert(rows, { Name = player.DisplayName, Value = Formulas.EncodeHeight(session.Data.Height) })
			end
			table.sort(rows, function(a, b)
				return a.Value > b.Value
			end)
			self:Render("Live", "📏 TALLEST RIGHT NOW", rows, "THIS SERVER • LIVE")
			for _, session in self.Services.PlayerService:GetSessions() do
				self:TrackBucket(session)
			end
			task.wait(2)
		end
	end)
	task.spawn(function()
		task.wait(5)
		while true do
			local ok, err = pcall(function()
				self:RefreshGlobal()
			end)
			if not ok then
				warn("[Leaderboard] refresh failed: " .. tostring(err))
			end
			task.wait(Config.Leaderboards.RefreshInterval)
		end
	end)
end

return LeaderboardService
