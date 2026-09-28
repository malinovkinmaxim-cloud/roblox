--[[
	StatisticsPanel - lifetime numbers in a clean two-column grid.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local Format = require(Shared.Util.Format)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)

local C = Theme.Colors
local F = Theme.Fonts

local Panel = {}
Panel.Kind = "Window"
Panel.Title = "STATISTICS"
Panel.Size = Vector2.new(580, 446)

local function hours(seconds: number): string
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	return if h > 0 then string.format("%dh %02dm", h, m) else string.format("%dm", m)
end

local ROWS = {
	{ Key = "Runs", Text = "RUNS PLAYED" },
	{ Key = "Wins", Text = "VICTORIES" },
	{ Key = "BestTime", Text = "LONGEST SURVIVAL", Format = Format.Time },
	{ Key = "BestLevel", Text = "HIGHEST LEVEL" },
	{ Key = "Kills", Text = "ENEMIES DEFEATED" },
	{ Key = "BestKills", Text = "MOST KILLS IN A RUN" },
	{ Key = "Bosses", Text = "BOSSES DEFEATED" },
	{ Key = "Events67", Text = "67 EVENTS SEEN" },
	{ Key = "LifetimeCoins", Text = "COINS EARNED" },
	{ Key = "PlayTime", Text = "TIME PLAYED", Format = hours },
}

function Panel.Build(body: Frame, _controllers)
	local grid = Kit.New("Frame", { Name = "Grid", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = body })
	Kit.New("UIGridLayout", {
		CellSize = UDim2.new(0.5, -6, 0, 60),
		CellPadding = UDim2.fromOffset(12, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local state = { Values = {} }
	for i, entry in ROWS do
		local tile = Kit.Panel({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.SurfaceLight, BackgroundTransparency = 0.45, LayoutOrder = i, Radius = 12, Parent = grid })
		Widgets.Caption(tile, entry.Text, UDim2.fromOffset(14, 9), 220)
		state.Values[entry.Key] = Kit.Label({
			Name = "Value",
			Text = "0",
			Size = UDim2.new(1, -28, 0, 24),
			Position = UDim2.fromOffset(14, 28),
			Font = F.Title,
			MaxTextSize = 21,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = tile,
		})
	end
	return state
end

function Panel.Refresh(state, data)
	local stats = data.Stats or {}
	for _, entry in ROWS do
		local value = stats[entry.Key] or 0
		state.Values[entry.Key].Text = if entry.Format then entry.Format(value) else Widgets.Commas(value)
	end
end

return Panel
