--[[
	WeaponsPanel - full-screen: every weapon as a card (3D preview, name, rarity, what it
	does, LOCKED / OWNED / EQUIPPED). Owned weapons can show up in level-up offers.
	With the Extra Loadout pass an owned weapon can be picked as the starting weapon
	(EQUIPPED); without it the starting weapon comes from the character.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local WeaponData = require(Shared.WeaponData)
local AchievementData = require(Shared.AchievementData)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)
local Cards = require(script.Parent.Parent.Cards)
local Previews = require(script.Parent.Parent.Previews)

local C = Theme.Colors
local F = Theme.Fonts

local Panel = {}
Panel.Kind = "Screen"
Panel.Title = "WEAPONS"

local CARD = Vector2.new(240, 190)

function Panel.Build(body: Frame, controllers)
	local state = { Cards = {}, C = controllers }

	-- one line of context + the loadout control on the right
	local top = Kit.New("Frame", { Name = "Top", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = body })
	Kit.Label({
		Text = "Owned weapons can show up when you level up.",
		Size = UDim2.new(0.5, 0, 0, 20),
		Position = UDim2.fromScale(0, 0.5),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = F.Medium,
		MaxTextSize = 15,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = top,
	})
	state.Loadout = Kit.Label({
		Name = "Loadout",
		Text = "",
		Size = UDim2.new(0.5, -170, 0, 20),
		Position = UDim2.new(1, -170, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Font = F.Medium,
		MaxTextSize = 15,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = top,
	})
	state.LoadoutButton, state.LoadoutLabel = Kit.Button({
		Name = "LoadoutButton",
		Text = "",
		Size = UDim2.fromOffset(156, 38),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = C.Neutral,
		TextSize = 15,
		OnClick = function()
			local data = controllers.ClientData.Data
			if not data then
				return
			end
			if data.Passes and data.Passes.ExtraLoadout then
				controllers.ClientData:Fire("SetStartWeapon", "")
			else
				controllers.LobbyController:OpenPanel("Shop", false, "Passes")
			end
		end,
		Parent = top,
	})

	local holder = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -52), Position = UDim2.fromOffset(0, 52), Parent = body })
	local scroll = Widgets.Scroll(holder, CARD, 12)
	for i, def in WeaponData.List do
		local ui = Cards.Item(scroll, {
			Name = def.Name,
			Desc = def.Desc,
			Rarity = def.Rarity,
			Order = i,
			PictureHeight = 72,
			Side = true,
			ButtonWidth = 104,
			OnClick = function()
				Panel.Click(state, def)
			end,
		})
		Previews.Weapon(ui.Picture, def.Key)
		state.Cards[def.Key] = ui
	end
	return state
end

function Panel.Click(state, def)
	local data = state.C.ClientData.Data
	if not data then
		return
	end
	if data.Weapons[def.Key] then
		if data.Passes and data.Passes.ExtraLoadout then
			state.C.ClientData:Fire("SetStartWeapon", if data.StartWeapon == def.Key then "" else def.Key)
		end
	elseif def.Unlock.Cost then
		state.C.ClientData:Fire("UnlockWeapon", def.Key)
	end
end

function Panel.Refresh(state, data)
	local loadout = data.Passes and data.Passes.ExtraLoadout
	local start = data.StartWeapon ~= nil and data.StartWeapon ~= "" and WeaponData.ByKey[data.StartWeapon]
	if loadout then
		state.Loadout.Text = if start then "Starting weapon: " .. start.Name else "Starting weapon: from your character"
		state.LoadoutLabel.Text = "RESET"
		state.LoadoutButton.Visible = start ~= nil
	else
		state.Loadout.Text = "Pick your starting weapon"
		state.LoadoutLabel.Text = "EXTRA LOADOUT"
		state.LoadoutButton.Visible = true
	end
	for _, def in WeaponData.List do
		local ui = state.Cards[def.Key]
		if data.Weapons[def.Key] then
			if start and data.StartWeapon == def.Key then
				Cards.Set(ui, "EQUIPPED", if loadout then "UNEQUIP" else nil, C.Neutral)
			else
				Cards.Set(ui, "OWNED", if loadout then "SET START" else nil, C.Neutral)
			end
		else
			local ach = def.Unlock.Achievement and AchievementData.ByKey[def.Unlock.Achievement]
			if def.Unlock.Cost then
				local affordable = data.Coins >= def.Unlock.Cost
				Cards.Set(ui, "LOCKED", nil, if affordable then C.AccentSoft else C.Neutral, def.Unlock.Cost)
				ui.Need.Text = if ach then "or achievement: " .. ach.Name else ""
			else
				Cards.Set(ui, "LOCKED", "LOCKED", C.Neutral)
				ui.Need.Text = if ach then "Achievement: " .. ach.Name else ""
			end
		end
	end
end

return Panel
