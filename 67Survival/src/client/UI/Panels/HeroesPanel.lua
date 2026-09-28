--[[
	HeroesPanel - HERO SELECT (full screen): every hero as a big card
	  3D model · NAME · RARITY · status (LOCKED / OWNED / EQUIPPED)
	  passive (stats) · unique mechanic · starting ability · SELECT / EQUIPPED / unlock price
	Heroes are unlocked with FRAGMENTS (earned in runs, challenges, the AFK camp) or with an
	achievement. Secret heroes show "???" until found.
	Top strip: LOADOUT 1 / 2 / 3 (2 and 3 with the Extra Loadout pass).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local HeroData = require(Shared.HeroData)
local WeaponData = require(Shared.WeaponData)
local AchievementData = require(Shared.AchievementData)
local CosmeticData = require(Shared.CosmeticData)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)
local Cards = require(script.Parent.Parent.Cards)
local Previews = require(script.Parent.Parent.Previews)

local C = Theme.Colors
local F = Theme.Fonts

local Panel = {}
Panel.Kind = "Screen"
Panel.Title = "HEROES"

local CARD = Vector2.new(206, 446)

function Panel.Build(body: Frame, controllers)
	local state = { Cards = {}, C = controllers, Skin = "" }

	-- loadouts + fragments (top strip)
	local top = Kit.New("Frame", { Name = "Top", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = body })
	Kit.Label({
		Text = "LOADOUT",
		Size = UDim2.fromOffset(80, 20),
		Position = UDim2.fromScale(0, 0.5),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = F.Bold,
		MaxTextSize = 14,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = top,
	})
	state.Loadouts = {}
	for i = 1, 3 do
		local button, label = Kit.Button({
			Name = "Loadout" .. i,
			Text = tostring(i),
			Size = UDim2.fromOffset(44, 36),
			Position = UDim2.new(0, 84 + (i - 1) * 52, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Color = C.Neutral,
			TextSize = 16,
			OnClick = function()
				controllers.ClientData:Fire("SelectLoadout", i)
			end,
			Parent = top,
		})
		state.Loadouts[i] = { Button = button, Label = label }
	end
	state.StartLabel = Kit.Label({
		Name = "Start",
		Text = "",
		Size = UDim2.new(1, -520, 0, 20),
		Position = UDim2.new(0, 250, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = F.Medium,
		MaxTextSize = 14,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = top,
	})
	local fragments = Kit.Panel({
		Name = "Fragments",
		Size = UDim2.fromOffset(150, 34),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Radius = 17,
		Parent = top,
	})
	Widgets.Fragment(fragments, 20, { Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
	state.Fragments = Kit.Label({
		Name = "Amount",
		Text = "0",
		Size = UDim2.new(1, -44, 0, 20),
		Position = UDim2.new(0, 36, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = F.Bold,
		MaxTextSize = 16,
		TextColor3 = C.Fragment,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = fragments,
	})

	local holder = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -52), Position = UDim2.fromOffset(0, 52), Parent = body })
	local scroll = Widgets.Scroll(holder, CARD, 14)
	for i, def in HeroData.List do
		local ui = Cards.Item(scroll, {
			Name = def.Name,
			Desc = def.Desc,
			Rarity = def.Rarity,
			Order = i,
			PictureHeight = 150,
			OnClick = function()
				Panel.Click(state, def)
			end,
		})
		ui.Def = def
		ui.PreviewHolder = Kit.New("Frame", { Name = "Model", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = ui.Picture })
		ui.Preview = Previews.Hero(ui.PreviewHolder, def.Key)
		ui.Desc.Size = UDim2.new(1, -24, 0, 34)
		-- passive (stats) + the unique mechanic
		ui.Passive = Kit.Label({
			Name = "Passive",
			Text = def.Passive,
			Size = UDim2.new(1, -24, 0, 34),
			Position = UDim2.fromOffset(12, 266),
			Font = F.Bold,
			MaxTextSize = 13,
			TextWrapped = true,
			TextColor3 = C.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = ui.Card,
		})
		ui.Mechanic = Kit.Label({
			Name = "Mechanic",
			Text = def.MechanicText,
			Size = UDim2.new(1, -24, 0, 48),
			Position = UDim2.fromOffset(12, 302),
			Font = F.Body,
			MaxTextSize = 13,
			TextWrapped = true,
			TextColor3 = C.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = ui.Card,
		})
		local weapon = WeaponData.ByKey[def.StartWeapon]
		local start = Kit.New("Frame", {
			Name = "StartWeapon",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -24, 0, 28),
			Position = UDim2.fromOffset(12, 352),
			Parent = ui.Card,
		})
		local icon = Kit.New("Frame", { Name = "WeaponIcon", Size = UDim2.fromOffset(28, 28), BackgroundColor3 = C.SurfaceLight, BackgroundTransparency = 0.3, Parent = start })
		Kit.Corner(icon, 8)
		ui.WeaponPreview = Previews.Weapon(icon, def.StartWeapon)
		ui.Start = Kit.Label({
			Text = if weapon then weapon.Name else "",
			Size = UDim2.new(1, -36, 1, 0),
			Position = UDim2.fromOffset(36, 0),
			Font = F.Medium,
			MaxTextSize = 13,
			TextColor3 = C.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = start,
		})
		state.Cards[def.Key] = ui
	end
	return state
end

function Panel.Click(state, def)
	local data = state.C.ClientData.Data
	if not data then
		return
	end
	if data.Heroes[def.Key] then
		if data.Selected ~= def.Key then
			state.C.ClientData:Fire("SelectHero", def.Key)
		end
	elseif def.Unlock.Fragments and not def.Secret then
		state.C.ClientData:Fire("UnlockHero", def.Key)
	end
end

function Panel.Refresh(state, data)
	state.Fragments.Text = Widgets.Commas(data.Fragments or 0)
	local slots = data.LoadoutSlots or 1
	for i, entry in state.Loadouts do
		local active = data.Loadout == i
		entry.Label.Text = if i <= slots then tostring(i) else "+"
		Kit.SetButtonColor(entry.Button, if active then C.Accent elseif i <= slots then C.Neutral else C.SurfaceLight)
	end
	local startKey = data.StartWeapon
	local start = startKey and startKey ~= "" and WeaponData.ByKey[startKey]
	state.StartLabel.Text = if start then "Starting ability: " .. start.Name .. " (change it in ABILITIES)" else "Starting ability: the hero's own"

	local skin = CosmeticData.Style(data.Cosmetics and data.Cosmetics.Equipped, "HeroSkin")
	local skinChanged = skin ~= state.Skin
	state.Skin = skin
	for _, def in HeroData.List do
		local ui = state.Cards[def.Key]
		local unlocked = data.Heroes[def.Key]
		local hidden = def.Secret and not unlocked
		ui.Name.Text = if hidden then "???" else def.Name
		ui.Desc.Text = if hidden then "A secret hero." else def.Desc
		ui.Passive.Text = if hidden then "???" else def.Passive
		ui.Mechanic.Text = if hidden then "Something rare has to happen first..." else def.MechanicText
		ui.Start.Text = if hidden then "???" else (WeaponData.ByKey[def.StartWeapon] or { Name = "" }).Name
		if skinChanged and unlocked then
			Widgets.Clear(ui.PreviewHolder)
			ui.Preview = Previews.Hero(ui.PreviewHolder, def.Key, { Skin = skin })
		end
		ui.Preview.ImageColor3 = if hidden then Color3.fromRGB(12, 11, 20) elseif unlocked then Color3.new(1, 1, 1) else Color3.fromRGB(150, 150, 160)
		ui.WeaponPreview.Visible = not hidden
		if unlocked then
			if data.Selected == def.Key then
				Cards.Set(ui, "EQUIPPED", "EQUIPPED", C.SuccessDark)
			else
				Cards.Set(ui, "OWNED", "SELECT", C.Accent)
			end
		elseif hidden then
			Cards.Set(ui, "LOCKED", "SECRET", C.Neutral)
		else
			local ach = def.Unlock.Achievement and AchievementData.ByKey[def.Unlock.Achievement]
			if def.Unlock.Fragments then
				local affordable = (data.Fragments or 0) >= def.Unlock.Fragments
				Cards.Set(ui, "LOCKED", nil, if affordable then C.AccentSoft else C.Neutral, def.Unlock.Fragments, "Fragment")
				if ach then
					ui.Need.Text = "or achievement: " .. ach.Name
				end
			else
				Cards.Set(ui, "LOCKED", "LOCKED", C.Neutral)
				ui.Need.Text = if ach then "Achievement: " .. ach.Name else ""
			end
		end
	end
end

return Panel
