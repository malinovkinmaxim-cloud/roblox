--[[
	HowToPlayPanel - MORE > HOW TO PLAY: the whole game on one page, short sections:
	controls (computer and phone), the goal of a run, level ups and evolutions, bosses and
	67 events, coins and fragments, difficulty. Text only, fixed sizes (never shrunk).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules").GameConfig)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)

local C = Theme.Colors
local F = Theme.Fonts

local Panel = {}
Panel.Kind = "Window"
Panel.Title = "HOW TO PLAY"
Panel.Size = Vector2.new(640, 560)

Panel.Sections = {
	{
		"CONTROLS",
		"Computer: WASD or the arrow keys to move. Your abilities attack on their own. Level up: keys 1-3 pick a card, R rerolls. Esc or P pauses, I / O zoom. In the lobby: Enter plays, G does your emote.",
	},
	{
		"ON A PHONE",
		"Move with the joystick (left thumb). Your abilities attack on their own. Tap a card to pick it. The pause button is at the top right.",
	},
	{
		"THE GOAL",
		"Survive the horde as long as you can. Grab the XP crystals enemies drop to level up. Bosses come at 3:00, 6:00 and 9:00; defeat THE FINAL ONE at 12:00 to win.",
	},
	{
		"LEVEL UPS AND EVOLUTIONS",
		"Every level up offers 3 cards: a new ability, a stronger one or a passive. An ability at its max level + its passive (shown on the card) = an EVOLUTION: the next level up offers it.",
	},
	{
		"67 EVENTS",
		"Now and then a rare 67 EVENT changes the run: +67% XP and damage, a golden chest, a huge (but weaker) invasion, a runaway golden goblin... Enjoy the chaos.",
	},
	{
		"COINS AND FRAGMENTS",
		"COINS buy permanent upgrades (SHOP) and cosmetics. " .. GameConfig.FragmentsHelp,
	},
	{
		"DIFFICULTY",
		"Pick it above PLAY. Harder tiers pay more and add new rules; you never need them to unlock heroes or abilities. Win a tier to open the next one.",
	},
}

function Panel.Build(body: Frame, controllers)
	local list = Widgets.Scroll(body, nil, 14)
	list.Size = UDim2.new(1, 0, 1, -56)
	local layout = list:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	end
	for i, section in Panel.Sections do
		local block = Kit.New("Frame", {
			Name = "Section" .. i,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -12, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = i,
			Parent = list,
		})
		Kit.New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = block })
		Kit.Label({
			Name = "Heading",
			Text = section[1],
			Size = UDim2.new(1, 0, 0, 18),
			Font = F.Bold,
			TextScaled = false,
			TextSize = 13,
			TextColor3 = C.Gold,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
			Parent = block,
		})
		Kit.Label({
			Name = "Body",
			Text = section[2],
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Font = F.Medium,
			TextScaled = false,
			TextSize = 15,
			TextWrapped = true,
			TextColor3 = C.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			LayoutOrder = 2,
			Parent = block,
		})
	end
	Kit.Button({
		Name = "GotIt",
		Text = "GOT IT",
		Size = UDim2.fromOffset(180, 42),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = C.Accent,
		TextSize = 16,
		OnClick = function()
			controllers.LobbyController:ClosePanel()
		end,
		Parent = body,
	})
	return {}
end

function Panel.Refresh(_state, _data) end

return Panel
