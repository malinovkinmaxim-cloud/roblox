--[[
	CodesPanel - type a code, get free Brain Coins (each code works once per player;
	the server checks everything, see server/Data/Codes.lua).
]]

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)

local C = Theme.Colors
local F = Theme.Fonts

local Panel = {}
Panel.Kind = "Window"
Panel.Title = "CODES"
Panel.Size = Vector2.new(480, 290)

function Panel.Build(body: Frame, controllers)
	local state = {}
	Kit.Label({
		Text = "Enter a code for free Brain Coins.",
		Size = UDim2.new(1, 0, 0, 20),
		Font = F.Medium,
		MaxTextSize = 16,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = body,
	})
	local box = Kit.New("TextBox", {
		Name = "Input",
		Text = "",
		PlaceholderText = "CODE",
		PlaceholderColor3 = C.TextMuted,
		ClearTextOnFocus = false,
		Font = F.Bold,
		TextSize = 20,
		TextColor3 = C.Text,
		BackgroundColor3 = C.SurfaceDark,
		BackgroundTransparency = 0.2,
		Size = UDim2.new(1, 0, 0, 52),
		Position = UDim2.fromOffset(0, 36),
		Parent = body,
	})
	Kit.Corner(box, 12)
	Kit.Stroke(box)
	state.Box = box
	local function redeem()
		local code = string.gsub(box.Text, "%s", "")
		if code ~= "" then
			controllers.ClientData:Fire("RedeemCode", string.sub(code, 1, 24))
			box.Text = ""
		end
	end
	box.FocusLost:Connect(function(enter)
		if enter then
			redeem()
		end
	end)
	Kit.Button({
		Name = "Redeem",
		Text = "REDEEM",
		Size = UDim2.new(1, 0, 0, 48),
		Position = UDim2.fromOffset(0, 102),
		Color = C.Accent,
		Dark = C.AccentDark,
		TextSize = 18,
		OnClick = redeem,
		Parent = body,
	})
	Kit.Label({
		Text = "New codes drop with updates. Try 67.",
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

function Panel.Refresh(_state, _data) end

return Panel
