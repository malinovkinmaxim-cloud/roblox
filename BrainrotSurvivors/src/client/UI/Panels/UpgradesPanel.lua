--[[
	UpgradesPanel - permanent upgrades bought with BRAIN COINS. Small bonuses per level;
	the costs grow so there is always a next goal.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local MetaData = require(Shared.MetaData)
local Format = require(Shared.Util.Format)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)

local C = Theme.Colors

local Panel = {}
Panel.Title = "UPGRADES"
Panel.Size = Vector2.new(900, 520)

function Panel.Build(body: Frame, controllers)
	local scroll = Widgets.Scroll(body, Vector2.new(410, 86), 8)
	local state = { Rows = {}, C = controllers }
	for i, def in MetaData.Upgrades do
		local row = Kit.Panel({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.PanelLight, LayoutOrder = i, Radius = 12, Parent = scroll })
		Kit.Label({ Text = def.Icon, Size = UDim2.fromOffset(52, 52), Position = UDim2.fromOffset(8, 16), StrokeThickness = 0, Parent = row })
		Kit.Label({ Text = def.Name, Size = UDim2.fromOffset(200, 26), Position = UDim2.fromOffset(66, 8), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		Kit.Label({ Text = def.Desc .. " / level", Size = UDim2.fromOffset(200, 20), Position = UDim2.fromOffset(66, 34), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.Fonts.Body, TextColor3 = C.TextDim, StrokeThickness = 0, Parent = row })
		local pips = Kit.Label({ Text = "", Size = UDim2.fromOffset(200, 20), Position = UDim2.fromOffset(66, 56), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Lime, Parent = row })
		local button, label = Kit.Button({
			Text = "",
			Size = UDim2.fromOffset(130, 50),
			Position = UDim2.new(1, -10, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Color = C.Lime,
			OnClick = function()
				controllers.ClientData:Fire("BuyMeta", def.Key)
			end,
			Parent = row,
		})
		state.Rows[def.Key] = { Pips = pips, Button = button, Label = label }
	end
	return state
end

function Panel.Refresh(state, data)
	for _, def in MetaData.Upgrades do
		local row = state.Rows[def.Key]
		local level = data.Meta[def.Key] or 0
		row.Pips.Text = string.rep("■", level) .. string.rep("□", def.MaxLevel - level)
		local cost = MetaData.Cost(def.Key, level)
		if cost then
			row.Label.Text = "🪙 " .. Format.Commas(cost)
			Kit.SetButtonColor(row.Button, if data.Coins >= cost then C.Lime else C.Gray)
		else
			row.Label.Text = "MAX"
			Kit.SetButtonColor(row.Button, C.Gold)
		end
	end
end

return Panel
