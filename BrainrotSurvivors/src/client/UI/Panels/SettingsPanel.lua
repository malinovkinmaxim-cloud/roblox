--[[
	SettingsPanel - sound, music, screen shake, damage numbers, low quality mode (fewer
	particles, no death flips: for older phones). Saved in the profile.
]]

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)

local C = Theme.Colors
local F = Theme.Fonts

local Panel = {}
Panel.Kind = "Window"
Panel.Title = "SETTINGS"
Panel.Size = Vector2.new(520, 400)

local OPTIONS = {
	{ Key = "Sfx", Text = "Sound effects" },
	{ Key = "Music", Text = "Boss music" },
	{ Key = "Shake", Text = "Screen shake" },
	{ Key = "DamageNumbers", Text = "Damage numbers" },
	{ Key = "LowQuality", Text = "Low quality (faster on phones)" },
}

local ROW = 56

function Panel.Build(body: Frame, controllers)
	local state = { Rows = {}, C = controllers }
	for i, opt in OPTIONS do
		local y = (i - 1) * ROW
		Kit.Label({
			Text = opt.Text,
			Size = UDim2.new(1, -90, 0, 22),
			Position = UDim2.fromOffset(4, y + ROW / 2 - 11),
			Font = F.Medium,
			MaxTextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = body,
		})
		state.Rows[opt.Key] = Widgets.Toggle(body, UDim2.new(1, -4, 0, y + ROW / 2), function(value)
			controllers.ClientData:SetSetting(opt.Key, value)
			state.Rows[opt.Key].Set(value)
		end)
		if i < #OPTIONS then
			Kit.New("Frame", {
				Name = "Divider",
				Size = UDim2.new(1, 0, 0, 1),
				Position = UDim2.fromOffset(0, y + ROW),
				BackgroundColor3 = C.Border,
				BackgroundTransparency = 0.92,
				BorderSizePixel = 0,
				Parent = body,
			})
		end
	end
	state.Save = Kit.Label({
		Name = "SaveStatus",
		Text = "",
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		Font = F.Body,
		MaxTextSize = 14,
		TextColor3 = C.TextMuted,
		Parent = body,
	})
	return state
end

function Panel.Refresh(state, data)
	for key, toggle in state.Rows do
		toggle.Set(state.C.ClientData:Setting(key) == true)
	end
	state.Save.Text = data.SaveStatus or ""
end

return Panel
