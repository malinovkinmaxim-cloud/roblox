--[[
	SettingsPanel - sound, music, screen shake, damage numbers, low quality mode (fewer
	particles, no death flips: for older phones). Saved in the profile.
]]

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)

local C = Theme.Colors

local Panel = {}
Panel.Title = "SETTINGS"
Panel.Size = Vector2.new(560, 470)

local OPTIONS = {
	{ Key = "Sfx", Text = "🔊 Sound effects" },
	{ Key = "Music", Text = "🎵 Boss beat" },
	{ Key = "Shake", Text = "📳 Screen shake" },
	{ Key = "DamageNumbers", Text = "💯 Damage numbers" },
	{ Key = "LowQuality", Text = "📱 Low quality (faster)" },
}

function Panel.Build(body: Frame, controllers)
	local state = { Rows = {}, C = controllers }
	for i, opt in OPTIONS do
		Kit.Label({ Text = opt.Text, Size = UDim2.fromOffset(300, 44), Position = UDim2.fromOffset(10, (i - 1) * 58), TextXAlignment = Enum.TextXAlignment.Left, Parent = body })
		local button, label = Kit.Button({
			Text = "",
			Size = UDim2.fromOffset(130, 44),
			Position = UDim2.new(1, -10, 0, (i - 1) * 58),
			AnchorPoint = Vector2.new(1, 0),
			Color = C.Lime,
			OnClick = function()
				local current = controllers.ClientData:Setting(opt.Key)
				controllers.ClientData:SetSetting(opt.Key, not current)
			end,
			Parent = body,
		})
		state.Rows[opt.Key] = { Button = button, Label = label }
	end
	state.Save = Kit.Label({
		Text = "",
		Size = UDim2.new(1, -20, 0, 26),
		Position = UDim2.new(0, 10, 1, -30),
		Font = Theme.Fonts.Body,
		TextColor3 = C.TextDim,
		Parent = body,
	})
	return state
end

function Panel.Refresh(state, data)
	for key, row in state.Rows do
		local on = state.C.ClientData:Setting(key)
		row.Label.Text = if on then "ON" else "OFF"
		Kit.SetButtonColor(row.Button, if on then C.Lime else C.Gray)
	end
	state.Save.Text = data.SaveStatus or ""
end

return Panel
