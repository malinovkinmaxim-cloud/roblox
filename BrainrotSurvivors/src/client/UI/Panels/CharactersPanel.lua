--[[
	CharactersPanel - pick a survivor. Locked ones show how to unlock them (coins and/or an
	achievement); secret characters stay hidden until unlocked.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local CharacterData = require(Shared.CharacterData)
local WeaponData = require(Shared.WeaponData)
local AchievementData = require(Shared.AchievementData)
local Format = require(Shared.Util.Format)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)

local C = Theme.Colors

local Panel = {}
Panel.Title = "CHARACTERS"
Panel.Size = Vector2.new(900, 520)

function Panel.Build(body: Frame, controllers)
	local scroll = Widgets.Scroll(body, Vector2.new(200, 400), 10)
	local state = { Cards = {}, C = controllers }
	for i, def in CharacterData.List do
		local card = Kit.Panel({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.PanelLight, LayoutOrder = i, Radius = 16, Parent = scroll })
		Kit.Gradient(card, def.Color:Lerp(C.Panel, 0.5), C.PanelDark)
		local icon = Kit.Label({ Text = def.Icon, Size = UDim2.fromOffset(90, 90), Position = UDim2.new(0.5, 0, 0, 10), AnchorPoint = Vector2.new(0.5, 0), StrokeThickness = 0, Parent = card })
		local name = Kit.Label({ Text = def.Name, Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(8, 102), Font = Theme.Fonts.Title, Parent = card })
		local desc = Kit.Label({
			Text = def.Desc,
			Size = UDim2.new(1, -16, 0, 56),
			Position = UDim2.fromOffset(8, 136),
			Font = Theme.Fonts.Body,
			TextWrapped = true,
			TextColor3 = C.TextDim,
			StrokeThickness = 0,
			Parent = card,
		})
		local perk = Kit.Label({
			Text = def.Perk,
			Size = UDim2.new(1, -16, 0, 70),
			Position = UDim2.fromOffset(8, 196),
			Font = Theme.Fonts.Body,
			TextWrapped = true,
			TextColor3 = C.Gold,
			StrokeThickness = 0,
			Parent = card,
		})
		local weapon = WeaponData.ByKey[def.StartWeapon]
		Kit.Label({
			Text = "Starts with " .. (if weapon then weapon.Icon .. " " .. weapon.Name else "?"),
			Size = UDim2.new(1, -16, 0, 22),
			Position = UDim2.fromOffset(8, 272),
			Font = Theme.Fonts.Body,
			Parent = card,
		})
		local button, label = Kit.Button({
			Text = "SELECT",
			Size = UDim2.new(1, -20, 0, 50),
			Position = UDim2.new(0, 10, 1, -60),
			Color = C.Lime,
			OnClick = function()
				Panel.Click(state, def)
			end,
			Parent = card,
		})
		state.Cards[def.Key] = { Card = card, Icon = icon, Name = name, Desc = desc, Perk = perk, Button = button, Label = label }
	end
	return state
end

function Panel.Click(state, def)
	local data = state.C.ClientData.Data
	if not data then
		return
	end
	if data.Characters[def.Key] then
		state.C.ClientData:Fire("SelectCharacter", def.Key)
	elseif def.Unlock.Cost then
		state.C.ClientData:Fire("UnlockCharacter", def.Key)
	end
end

function Panel.Refresh(state, data)
	for _, def in CharacterData.List do
		local ui = state.Cards[def.Key]
		local unlocked = data.Characters[def.Key]
		local hidden = def.Secret and not unlocked
		ui.Icon.Text = if hidden then "❓" else def.Icon
		ui.Name.Text = if hidden then "???" else def.Name
		ui.Desc.Text = if hidden then "A secret survivor." else def.Desc
		ui.Perk.Text = if hidden then "" else def.Perk
		if unlocked then
			local selected = data.Selected == def.Key
			ui.Label.Text = if selected then "✔ SELECTED" else "SELECT"
			Kit.SetButtonColor(ui.Button, if selected then C.Gold else C.Lime)
		else
			local parts = {}
			if def.Unlock.Cost then
				table.insert(parts, "🪙 " .. Format.Commas(def.Unlock.Cost))
			end
			if def.Unlock.Achievement and not hidden then
				local ach = AchievementData.ByKey[def.Unlock.Achievement]
				table.insert(parts, "🏆 " .. (if ach then ach.Name else "?"))
			end
			ui.Label.Text = if hidden then "🔒 SECRET" else table.concat(parts, " or ")
			local affordable = def.Unlock.Cost and data.Coins >= def.Unlock.Cost
			Kit.SetButtonColor(ui.Button, if affordable then C.Blue else C.Gray)
		end
	end
end

return Panel
