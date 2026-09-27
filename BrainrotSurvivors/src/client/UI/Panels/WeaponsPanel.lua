--[[
	WeaponsPanel - every weapon: what it does, rarity, locked / unlocked. Unlocked weapons can
	appear in level-up offers. With the Extra Loadout pass a starting weapon can be chosen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local WeaponData = require(Shared.WeaponData)
local AchievementData = require(Shared.AchievementData)
local Format = require(Shared.Util.Format)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)

local C = Theme.Colors

local Panel = {}
Panel.Title = "WEAPONS"
Panel.Size = Vector2.new(900, 520)

function Panel.Build(body: Frame, controllers)
	local scroll = Widgets.Scroll(body, Vector2.new(270, 150), 10)
	local state = { Rows = {}, C = controllers }
	for i, def in WeaponData.List do
		local rarity = Theme.Rarity[def.Rarity] or Theme.Rarity.Common
		local card = Kit.Panel({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.PanelLight, LayoutOrder = i, Radius = 14, Parent = scroll })
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = rarity
		end
		Kit.Label({ Text = def.Icon, Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(8, 8), StrokeThickness = 0, Parent = card })
		Kit.Label({ Text = def.Name, Size = UDim2.new(1, -76, 0, 28), Position = UDim2.fromOffset(70, 8), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.Fonts.Title, Parent = card })
		Kit.Label({ Text = def.Rarity, Size = UDim2.new(1, -76, 0, 18), Position = UDim2.fromOffset(70, 36), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = rarity, Font = Theme.Fonts.Body, Parent = card })
		Kit.Label({
			Text = def.Desc,
			Size = UDim2.new(1, -16, 0, 40),
			Position = UDim2.fromOffset(8, 62),
			TextWrapped = true,
			Font = Theme.Fonts.Body,
			TextColor3 = C.TextDim,
			StrokeThickness = 0,
			Parent = card,
		})
		local button, label = Kit.Button({
			Text = "",
			Size = UDim2.new(1, -16, 0, 36),
			Position = UDim2.new(0, 8, 1, -42),
			Color = C.Gray,
			OnClick = function()
				Panel.Click(state, def)
			end,
			Parent = card,
		})
		state.Rows[def.Key] = { Button = button, Label = label }
	end
	return state
end

function Panel.Click(state, def)
	local data = state.C.ClientData.Data
	if not data then
		return
	end
	if data.Weapons[def.Key] then
		local passes = data.Passes or {}
		if passes.ExtraLoadout then
			state.C.ClientData:Fire("SetStartWeapon", if data.StartWeapon == def.Key then "" else def.Key)
		else
			state.C.ClientData:Fire("Buy", "Pass", "ExtraLoadout")
		end
	elseif def.Unlock.Cost then
		state.C.ClientData:Fire("UnlockWeapon", def.Key)
	end
end

function Panel.Refresh(state, data)
	local loadout = data.Passes and data.Passes.ExtraLoadout
	for _, def in WeaponData.List do
		local row = state.Rows[def.Key]
		if data.Weapons[def.Key] then
			if data.StartWeapon == def.Key then
				row.Label.Text = "★ STARTING WEAPON"
				Kit.SetButtonColor(row.Button, C.Gold)
			else
				row.Label.Text = if loadout then "SET AS START" else "✔ UNLOCKED"
				Kit.SetButtonColor(row.Button, if loadout then C.Blue else C.LimeDark)
			end
		else
			local parts = {}
			if def.Unlock.Cost then
				table.insert(parts, "🪙 " .. Format.Commas(def.Unlock.Cost))
			end
			if def.Unlock.Achievement then
				local ach = AchievementData.ByKey[def.Unlock.Achievement]
				table.insert(parts, "🏆 " .. (if ach then ach.Name else "?"))
			end
			row.Label.Text = "🔒 " .. table.concat(parts, " or ")
			local affordable = def.Unlock.Cost and data.Coins >= def.Unlock.Cost
			Kit.SetButtonColor(row.Button, if affordable then C.Orange else C.Gray)
		end
	end
end

return Panel
