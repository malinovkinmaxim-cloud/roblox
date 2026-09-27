--[[
	SkinsPanel - cosmetic hats for any character. Bought with coins or earned through
	achievements (the crown means you beat THE FINAL GOOBER).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local SkinData = require(Shared.SkinData)
local AchievementData = require(Shared.AchievementData)
local Format = require(Shared.Util.Format)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)

local C = Theme.Colors

local Panel = {}
Panel.Title = "SKINS"
Panel.Size = Vector2.new(900, 520)

function Panel.Build(body: Frame, controllers)
	local scroll = Widgets.Scroll(body, Vector2.new(200, 210), 10)
	local state = { Cards = {}, C = controllers }
	for i, def in SkinData.List do
		local card = Kit.Panel({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.PanelLight, LayoutOrder = i, Radius = 14, Parent = scroll })
		Kit.Label({ Text = def.Icon, Size = UDim2.fromOffset(70, 70), Position = UDim2.new(0.5, 0, 0, 8), AnchorPoint = Vector2.new(0.5, 0), StrokeThickness = 0, Parent = card })
		Kit.Label({ Text = def.Name, Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(6, 80), Font = Theme.Fonts.Title, Parent = card })
		Kit.Label({
			Text = def.Desc,
			Size = UDim2.new(1, -12, 0, 40),
			Position = UDim2.fromOffset(6, 108),
			TextWrapped = true,
			Font = Theme.Fonts.Body,
			TextColor3 = C.TextDim,
			StrokeThickness = 0,
			Parent = card,
		})
		local button, label = Kit.Button({
			Text = "",
			Size = UDim2.new(1, -16, 0, 42),
			Position = UDim2.new(0, 8, 1, -50),
			Color = C.Gray,
			OnClick = function()
				local data = controllers.ClientData.Data
				if not data then
					return
				end
				if data.Skins and data.Skins[def.Key] then
					controllers.ClientData:Fire("EquipSkin", def.Key)
				elseif def.Cost then
					controllers.ClientData:Fire("BuySkin", def.Key)
				end
			end,
			Parent = card,
		})
		state.Cards[def.Key] = { Button = button, Label = label }
	end
	return state
end

function Panel.Refresh(state, data)
	local owned = data.Skins or {}
	for _, def in SkinData.List do
		local ui = state.Cards[def.Key]
		if owned[def.Key] then
			local equipped = data.EquippedSkin == def.Key
			ui.Label.Text = if equipped then "✔ WEARING" else "WEAR"
			Kit.SetButtonColor(ui.Button, if equipped then C.Gold else C.Lime)
		elseif def.Cost then
			ui.Label.Text = "🪙 " .. Format.Commas(def.Cost)
			Kit.SetButtonColor(ui.Button, if data.Coins >= def.Cost then C.Blue else C.Gray)
		else
			local ach = def.Achievement and AchievementData.ByKey[def.Achievement]
			ui.Label.Text = "🏆 " .. (if ach then ach.Name else "?")
			Kit.SetButtonColor(ui.Button, C.Gray)
		end
	end
end

return Panel
