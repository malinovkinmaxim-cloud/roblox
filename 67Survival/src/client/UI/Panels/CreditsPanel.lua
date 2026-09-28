--[[
	CreditsPanel - who made the game.
]]

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)

local F = Theme.Fonts

local Panel = {}
Panel.Kind = "Window"
Panel.Title = "CREDITS"
Panel.Size = Vector2.new(480, 340)

local LINES = {
	{ "GAME", "67 Survival team" },
	{ "BUILT WITH", "Roblox Studio, Luau and Rojo" },
	{ "FONTS", "Builder Sans, Luckiest Guy" },
	{ "INSPIRED BY", "the survivors-like genre" },
	{ "SPECIAL THANKS", "everyone who stood still for 6.7 seconds" },
}

function Panel.Build(body: Frame, _controllers)
	for i, line in LINES do
		local y = (i - 1) * 46
		Widgets.Caption(body, line[1], UDim2.fromOffset(0, y), 300)
		Kit.Label({
			Text = line[2],
			Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.fromOffset(0, y + 18),
			Font = F.Medium,
			MaxTextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = body,
		})
	end
	return {}
end

function Panel.Refresh(_state, _data) end

return Panel
