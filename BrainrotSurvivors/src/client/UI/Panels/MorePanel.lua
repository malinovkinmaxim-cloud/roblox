--[[
	MorePanel - everything secondary, in one compact 2x3 grid:
	  ACHIEVEMENTS  LEADERBOARD  STATISTICS
	  CODES         SETTINGS     CREDITS
	Each tile opens its own screen / window.
]]

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)
local Icons = require(script.Parent.Parent.Icons)

local C = Theme.Colors
local F = Theme.Fonts

local Panel = {}
Panel.Kind = "Window"
Panel.Title = "MORE"
Panel.Size = Vector2.new(520, 410)

local TILES = {
	{ Key = "Achievements", Text = "ACHIEVEMENTS" },
	{ Key = "Leaderboard", Text = "LEADERBOARD" },
	{ Key = "Statistics", Text = "STATISTICS" },
	{ Key = "Codes", Text = "CODES" },
	{ Key = "Settings", Text = "SETTINGS" },
	{ Key = "Credits", Text = "CREDITS" },
}

function Panel.Build(body: Frame, controllers)
	local grid = Kit.New("Frame", { Name = "Grid", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 252), Parent = body })
	Kit.New("UIGridLayout", {
		CellSize = UDim2.fromOffset(148, 120),
		CellPadding = UDim2.fromOffset(12, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local state = { Tiles = {} }
	for i, tile in TILES do
		local card = Widgets.Card(grid, UDim2.fromScale(1, 1), i, tile.Key)
		card.BackgroundColor3 = C.SurfaceLight
		card.BackgroundTransparency = 0.35
		Icons.Make(card, "Menu", tile.Key, 46, { Position = UDim2.new(0.5, 0, 0, 20), AnchorPoint = Vector2.new(0.5, 0) })
		Kit.Label({
			Name = "Label",
			Text = tile.Text,
			Size = UDim2.new(1, -16, 0, 18),
			Position = UDim2.new(0.5, 0, 1, -16),
			AnchorPoint = Vector2.new(0.5, 1),
			Font = F.Bold,
			MaxTextSize = 14,
			Parent = card,
		})
		card.Activated:Connect(function()
			if Kit.ClickSound then
				Kit.ClickSound()
			end
			controllers.LobbyController:OpenPanel(tile.Key)
		end)
		state.Tiles[tile.Key] = card
	end
	Kit.Button({
		Name = "CloseMore",
		Text = "CLOSE",
		Size = UDim2.fromOffset(180, 42),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = C.Neutral,
		TextSize = 16,
		OnClick = function()
			controllers.LobbyController:ClosePanel()
		end,
		Parent = body,
	})
	return state
end

function Panel.Refresh(_state, _data) end

return Panel
