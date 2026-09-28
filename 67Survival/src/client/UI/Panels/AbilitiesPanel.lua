--[[
	AbilitiesPanel - full screen: every ability by category, with its rarity and status.
	  tabs: PROJECTILE · AREA · MELEE · SUMMON · DEFENSIVE · SPECIAL · PASSIVE · EVOLUTIONS
	Unlocked abilities can show up when you level up. New ones are unlocked with FRAGMENTS
	(or an achievement / a secret). An unlocked ability can be the STARTING ability of the
	active loadout. The EVOLUTIONS tab shows every recipe: ability (max level) + passive.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local WeaponData = require(Shared.WeaponData)
local UpgradeData = require(Shared.UpgradeData)
local AchievementData = require(Shared.AchievementData)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)
local Cards = require(script.Parent.Parent.Cards)
local Previews = require(script.Parent.Parent.Previews)
local Icons = require(script.Parent.Parent.Icons)

local C = Theme.Colors
local F = Theme.Fonts


local Panel = {}
Panel.Kind = "Screen"
Panel.Title = "ABILITIES"

local CARD = Vector2.new(250, 196)
local TABS = { "PROJECTILE", "AREA", "MELEE", "SUMMON", "DEFENSIVE", "SPECIAL", "PASSIVE", "EVOLUTIONS" }
local LABELS = {
	PROJECTILE = "PROJECTILE",
	AREA = "AREA",
	MELEE = "MELEE",
	SUMMON = "SUMMON",
	DEFENSIVE = "DEFENSE",
	SPECIAL = "SPECIAL",
	PASSIVE = "PASSIVE",
	EVOLUTIONS = "EVOLUTIONS",
}

function Panel.Build(body: Frame, controllers)
	local state = { Cards = {}, Pages = {}, C = controllers }
	state.Tabs = Widgets.Tabs(body, TABS, LABELS, function(name)
		for key, page in state.Pages do
			page.Visible = key == name
		end
	end)
	for _, button in state.Tabs.Buttons do
		button.Size = UDim2.fromOffset(116, 36)
		button.TextSize = 14
	end
	state.Tabs.Frame.Size = UDim2.fromOffset(#TABS * 116 + 8, 44)
	local holder = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -58), Position = UDim2.fromOffset(0, 58), Parent = body })
	for _, tab in TABS do
		local page = Widgets.Scroll(holder, CARD, 12)
		page.Name = tab
		page.Visible = false
		state.Pages[tab] = page
	end

	local order = 0
	for _, def in WeaponData.List do
		order += 1
		local page = if def.Evolution then state.Pages.EVOLUTIONS else state.Pages[def.Category]
		if page then
			local ui = Cards.Item(page, {
				Name = def.Name,
				Desc = def.Desc,
				Rarity = def.Rarity,
				Order = order,
				PictureHeight = 72,
				Side = true,
				ButtonWidth = 112,
				OnClick = function()
					Panel.Click(state, def)
				end,
			})
			ui.Preview = Previews.Weapon(ui.Picture, def.Key)
			-- two lines of description, then the numbers (damage, cooldown, levels)
			ui.Desc.Size = UDim2.new(1, -24, 0, 36)
			ui.Stats = Kit.Label({
				Name = "Stats",
				Text = Cards.WeaponStats(def),
				Size = UDim2.new(1, -24, 0, 16),
				Position = UDim2.fromOffset(12, 132),
				Font = F.Bold,
				TextScaled = false,
				TextSize = 13,
				TextColor3 = (def.Color or C.Text):Lerp(Color3.new(1, 1, 1), 0.45),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = ui.Card,
			})
			if def.Evolution then
				local from = WeaponData.ByKey[def.Evolution.From]
				local with = UpgradeData.PassiveByKey[def.Evolution.With]
				ui.Recipe = (if from then from.Name else def.Evolution.From) .. " (max) + " .. (if with then with.Name else def.Evolution.With)
			end
			state.Cards[def.Key] = ui
		end
	end
	for _, def in UpgradeData.Passives do
		order += 1
		local ui = Cards.Item(state.Pages.PASSIVE, {
			Name = def.Name,
			Desc = def.Desc,
			Rarity = def.Rarity,
			Order = order,
			PictureHeight = 72,
			Side = true,
			ButtonWidth = 112,
		})
		Icons.Make(ui.Picture, "Stat", def.Key, 56, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
		ui.Passive = def
		state.Cards["P:" .. def.Key] = ui
	end
	state.Tabs.Select("PROJECTILE")
	for key, page in state.Pages do
		page.Visible = key == "PROJECTILE"
	end
	return state
end

function Panel.Click(state, def)
	local data = state.C.ClientData.Data
	if not data or def.Evolution then
		return
	end
	if data.Weapons[def.Key] then
		state.C.ClientData:Fire("SetStartWeapon", if data.StartWeapon == def.Key then "" else def.Key)
	elseif def.Unlock.Fragments and not def.Unlock.Secret then
		state.C.ClientData:Fire("UnlockWeapon", def.Key)
	end
end

local function unlockText(def): string
	local ach = def.Unlock.Achievement and AchievementData.ByKey[def.Unlock.Achievement]
	if def.Unlock.Fragments and ach then
		return "or achievement: " .. ach.Name
	elseif ach then
		return "Achievement: " .. ach.Name
	end
	return ""
end

function Panel.Refresh(state, data)
	local seenEvo = (data.Seen and data.Seen.Evolutions) or {}
	for _, def in WeaponData.List do
		local ui = state.Cards[def.Key]
		if ui then
			if def.Evolution then
				-- evolutions: the recipe; ??? until reached once
				local reached = seenEvo[def.Key] == true
				ui.Name.Text = if reached then def.Name else "???"
				ui.Desc.Text = ui.Recipe
				Cards.Set(ui, if reached then "OWNED" else "", nil)
				ui.Need.Text = if reached then "Reached" else "Evolve it in a run"
				ui.Preview.ImageColor3 = if reached then Color3.new(1, 1, 1) else Color3.fromRGB(60, 60, 70)
			elseif data.Weapons[def.Key] then
				if data.StartWeapon == def.Key then
					Cards.Set(ui, "EQUIPPED", "STARTING", C.SuccessDark)
				else
					Cards.Set(ui, "OWNED", "SET START", C.Neutral)
				end
				ui.Need.Text = def.MaxLevel .. " levels"
				ui.Name.Text = def.Name
				ui.Preview.ImageColor3 = Color3.new(1, 1, 1)
			elseif def.Unlock.Secret then
				ui.Name.Text = "???"
				ui.Desc.Text = "A secret ability. Find the secret."
				Cards.Set(ui, "LOCKED", "SECRET", C.Neutral)
				ui.Preview.ImageColor3 = Color3.fromRGB(12, 11, 20)
			elseif def.Unlock.Fragments then
				local affordable = (data.Fragments or 0) >= def.Unlock.Fragments
				Cards.Set(ui, "LOCKED", nil, if affordable then C.AccentSoft else C.Neutral, def.Unlock.Fragments, "Fragment")
				ui.Need.Text = unlockText(def)
			else
				Cards.Set(ui, "LOCKED", "LOCKED", C.Neutral)
				ui.Need.Text = unlockText(def)
			end
		end
	end
	for _, def in UpgradeData.Passives do
		local ui = state.Cards["P:" .. def.Key]
		if def.Secret and not data.Weapons[def.Key] then
			ui.Name.Text = "???"
			ui.Desc.Text = "A secret passive. Find the secret."
			Cards.Set(ui, "LOCKED", nil)
		else
			ui.Name.Text = def.Name
			ui.Desc.Text = def.Desc
			Cards.Set(ui, "", nil)
			ui.Need.Text = "Max " .. def.MaxStacks .. (if def.MaxStacks == 1 then " stack" else " stacks")
		end
	end
end

return Panel
