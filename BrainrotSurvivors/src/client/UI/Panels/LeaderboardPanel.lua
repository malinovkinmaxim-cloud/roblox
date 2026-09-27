--[[
	LeaderboardPanel - full-screen global top 10 (saved in OrderedDataStores) for Highest
	Level, Longest Survival, Enemies Defeated, Bosses Defeated and Coins Earned, plus your
	own best. The server sends every board at once on request.
]]

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)

local C = Theme.Colors
local F = Theme.Fonts

local Panel = {}
Panel.Kind = "Screen"
Panel.Title = "LEADERBOARD"

local BOARDS = { "BestLevel", "BestTime", "Kills", "Bosses", "Coins" }
local LABELS = { BestLevel = "LEVEL", BestTime = "SURVIVAL", Kills = "KILLS", Bosses = "BOSSES", Coins = "COINS" }
local MEDALS = { Theme.Colors.Gold, Color3.fromRGB(205, 210, 226), Color3.fromRGB(214, 140, 86) }

local function fmt(format: string, value: number): string
	if format == "Time" then
		return string.format("%d:%02d", value // 60, value % 60)
	end
	return Widgets.Commas(value)
end

function Panel.Build(body: Frame, controllers)
	local state = { C = controllers, Board = "BestLevel", Payload = nil }
	local column = Kit.New("Frame", {
		Name = "Column",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = body,
	})
	Kit.New("UISizeConstraint", { MaxSize = Vector2.new(780, math.huge), Parent = column })
	state.Tabs = Widgets.Tabs(column, BOARDS, LABELS, function(name)
		state.Board = name
		Panel.Render(state)
	end)
	for _, button in state.Tabs.Buttons do
		button.Size = UDim2.fromOffset(136, 36)
	end
	state.Tabs.Frame.Size = UDim2.fromOffset(#BOARDS * 136 + 8, 44)
	state.Tabs.Frame.Position = UDim2.fromScale(0.5, 0)
	state.Tabs.Frame.AnchorPoint = Vector2.new(0.5, 0)

	local holder = Kit.New("Frame", { Name = "List", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -116), Position = UDim2.fromOffset(0, 58), Parent = column })
	state.List = Widgets.Scroll(holder, nil, 8)

	-- your own best, pinned under the list
	local mine = Kit.Panel({ Name = "Mine", Size = UDim2.new(1, 0, 0, 46), Position = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(0, 1), Radius = 14, Parent = column })
	local mineStroke = mine:FindFirstChildOfClass("UIStroke") :: UIStroke
	mineStroke.Color = C.Accent
	mineStroke.Transparency = 0.5
	Kit.Label({
		Text = "YOUR BEST",
		Size = UDim2.fromOffset(200, 20),
		Position = UDim2.new(0, 18, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = F.Bold,
		MaxTextSize = 14,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = mine,
	})
	state.Mine = Kit.Label({
		Text = "",
		Size = UDim2.fromOffset(200, 22),
		Position = UDim2.new(1, -18, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Font = F.Title,
		MaxTextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = mine,
	})

	controllers.ClientData:Remote("Leaderboard").OnClientEvent:Connect(function(payload)
		state.Payload = payload
		Panel.Render(state)
	end)
	return state
end

local function message(state, text: string)
	Kit.Label({
		Text = text,
		Size = UDim2.new(1, 0, 0, 40),
		Font = F.Medium,
		MaxTextSize = 16,
		TextColor3 = C.TextDim,
		Parent = state.List,
	})
end

function Panel.Render(state)
	state.Tabs.Select(state.Board)
	Widgets.Clear(state.List)
	local payload = state.Payload
	if not payload then
		message(state, "Loading...")
		state.Mine.Text = "-"
		return
	end
	local board = nil
	for _, b in payload.Boards do
		if b.Key == state.Board then
			board = b
		end
	end
	if not board then
		message(state, "No data.")
		return
	end
	if #board.Rows == 0 then
		message(state, "No scores yet. Be the first!")
	end
	for i, entry in board.Rows do
		local frame = Kit.Panel({
			Size = UDim2.new(1, -8, 0, 46),
			LayoutOrder = i,
			Radius = 12,
			BackgroundTransparency = if i <= 3 then 0.1 else Theme.Glass,
			Parent = state.List,
		})
		local medal = MEDALS[entry.Rank]
		local rank = Kit.Label({
			Text = tostring(entry.Rank),
			Size = UDim2.fromOffset(30, 30),
			Position = UDim2.new(0, 12, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Font = F.Title,
			MaxTextSize = 16,
			TextColor3 = if medal then C.SurfaceDark else C.TextDim,
			BackgroundTransparency = if medal then 0 else 1,
			BackgroundColor3 = medal or C.Surface,
			Parent = frame,
		})
		Kit.Corner(rank, 15)
		Kit.Label({
			Text = entry.Name,
			Size = UDim2.new(1, -260, 0, 22),
			Position = UDim2.new(0, 56, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Font = F.Bold,
			MaxTextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		Kit.Label({
			Text = fmt(board.Format, entry.Value),
			Size = UDim2.fromOffset(180, 22),
			Position = UDim2.new(1, -16, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Font = F.Title,
			MaxTextSize = 17,
			TextColor3 = if i <= 3 then C.Text else C.TextDim,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = frame,
		})
	end
	local mine = payload.Mine and payload.Mine[state.Board] or 0
	state.Mine.Text = fmt(board.Format, mine)
end

function Panel.Refresh(_state, _data) end

function Panel.OnOpen(state, controllers)
	controllers.ClientData:Fire("RequestLeaderboard")
	Panel.Render(state)
end

return Panel
