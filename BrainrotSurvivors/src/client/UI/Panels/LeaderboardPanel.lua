--[[
	LeaderboardPanel - global top 10 for Highest Level, Longest Survival, Enemies Defeated,
	Bosses Defeated and Coins Earned (saved in OrderedDataStores), plus your own values.
]]

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)

local C = Theme.Colors

local Panel = {}
Panel.Title = "LEADERBOARD"
Panel.Size = Vector2.new(820, 520)

local TABS = {
	{ Key = "BestLevel", Text = "LEVEL" },
	{ Key = "BestTime", Text = "SURVIVAL" },
	{ Key = "Kills", Text = "KILLS" },
	{ Key = "Bosses", Text = "BOSSES" },
	{ Key = "Coins", Text = "COINS" },
}

local function fmt(format: string, value: number): string
	if format == "Time" then
		return string.format("%d:%02d", value // 60, value % 60)
	end
	local s = tostring(math.floor(value))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	return (string.gsub(out, "^,", ""))
end

function Panel.Build(body: Frame, controllers)
	local state = { C = controllers, Board = "BestLevel", Payload = nil, Tabs = {} }
	local bar = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = body })
	Kit.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), Parent = bar })
	for _, tab in TABS do
		local button = Kit.Button({
			Text = tab.Text,
			Size = UDim2.fromOffset(148, 40),
			Color = C.PanelLight,
			OnClick = function()
				state.Board = tab.Key
				Panel.Render(state)
			end,
			Parent = bar,
		})
		state.Tabs[tab.Key] = button
	end
	local holder = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -100), Position = UDim2.fromOffset(0, 52), Parent = body })
	state.List = Widgets.Scroll(holder, nil, 6)
	state.Mine = Kit.Label({ Text = "", Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 1, -40), TextColor3 = C.Gold, Parent = body })
	controllers.ClientData:Remote("Leaderboard").OnClientEvent:Connect(function(payload)
		state.Payload = payload
		Panel.Render(state)
	end)
	return state
end

function Panel.Render(state)
	for key, button in state.Tabs do
		Kit.SetButtonColor(button, if key == state.Board then C.Purple else C.PanelLight)
	end
	Widgets.Clear(state.List)
	local payload = state.Payload
	if not payload then
		Kit.Label({ Text = "Loading...", Size = UDim2.new(1, 0, 0, 40), Parent = state.List })
		return
	end
	local board = nil
	for _, b in payload.Boards do
		if b.Key == state.Board then
			board = b
		end
	end
	if not board then
		return
	end
	if #board.Rows == 0 then
		Kit.Label({ Text = "No scores yet. Be the first!", Size = UDim2.new(1, 0, 0, 40), Parent = state.List })
	end
	for i, row in board.Rows do
		local frame = Widgets.Row(state.List, 40, i, if i <= 3 then C.PurpleDark else C.PanelLight)
		local medal = if row.Rank == 1 then "🥇" elseif row.Rank == 2 then "🥈" elseif row.Rank == 3 then "🥉" else "#" .. row.Rank
		Kit.Label({ Text = medal, Size = UDim2.fromOffset(60, 34), Position = UDim2.fromOffset(6, 3), Parent = frame })
		Kit.Label({ Text = row.Name, Size = UDim2.new(1, -260, 0, 34), Position = UDim2.fromOffset(70, 3), TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
		Kit.Label({ Text = fmt(board.Format, row.Value), Size = UDim2.fromOffset(160, 34), Position = UDim2.new(1, -170, 0, 3), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Gold, Parent = frame })
	end
	local mine = payload.Mine and payload.Mine[state.Board] or 0
	state.Mine.Text = "Your best: " .. fmt(board.Format, mine)
end

function Panel.Refresh(_state, _data) end

function Panel.OnOpen(state, controllers)
	controllers.ClientData:Fire("RequestLeaderboard")
	Panel.Render(state)
end

return Panel
