--[[
	CharactersPanel - full-screen: every survivor as a card (3D preview, name, rarity,
	LOCKED / OWNED / EQUIPPED, what makes them different, how to unlock).
	Secret characters stay a silhouette until unlocked.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local CharacterData = require(Shared.CharacterData)
local WeaponData = require(Shared.WeaponData)
local AchievementData = require(Shared.AchievementData)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Cards = require(script.Parent.Parent.Cards)
local Previews = require(script.Parent.Parent.Previews)

local C = Theme.Colors
local F = Theme.Fonts

local Panel = {}
Panel.Kind = "Screen"
Panel.Title = "CHARACTERS"

local CARD = Vector2.new(196, 456)
local GAP = 14

function Panel.Build(body: Frame, controllers)
	local state = { Cards = {}, C = controllers }
	-- one row with every survivor; it shrinks as a whole on small screens (no scrolling)
	local count = #CharacterData.List
	local row = Kit.New("Frame", {
		Name = "CardRow",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(count * CARD.X + (count - 1) * GAP, CARD.Y),
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = body,
	})
	Kit.New("UIScale", { Name = "RowFit", Parent = row })
	Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	state.Row = row
	for i, def in CharacterData.List do
		local ui = Cards.Item(row, {
			Name = def.Name,
			Desc = def.Desc,
			Rarity = def.Rarity,
			Order = i,
			PictureHeight = 150,
			OnClick = function()
				Panel.Click(state, def)
			end,
		})
		ui.Card.Size = UDim2.fromOffset(CARD.X, CARD.Y)
		ui.Preview = Previews.Character(ui.Picture, def.Key)
		-- perk (the unique mechanic) and the starting weapon
		ui.Desc.Size = UDim2.new(1, -24, 0, 50)
		ui.Perk = Kit.Label({
			Name = "Perk",
			Text = def.Perk,
			Size = UDim2.new(1, -24, 0, 54),
			Position = UDim2.fromOffset(12, 284),
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
			Name = "Start",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -24, 0, 30),
			Position = UDim2.fromOffset(12, 346),
			Parent = ui.Card,
		})
		local icon = Kit.New("Frame", { Name = "WeaponIcon", Size = UDim2.fromOffset(30, 30), BackgroundColor3 = C.SurfaceLight, BackgroundTransparency = 0.3, Parent = start })
		Kit.Corner(icon, 8)
		ui.WeaponPreview = Previews.Weapon(icon, def.StartWeapon)
		ui.Start = Kit.Label({
			Text = if weapon then weapon.Name else "",
			Size = UDim2.new(1, -40, 1, 0),
			Position = UDim2.fromOffset(40, 0),
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

-- fit the row into the screen body (design units; margins as in Widgets.Screen)
function Panel.OnOpen(state)
	local view = Kit.View
	local width = view.X - 2 * (Theme.Margin + 12)
	local height = view.Y - 2 * Theme.Margin - 64
	local row = state.Row
	local scale = math.min(1, width / row.Size.X.Offset, height / row.Size.Y.Offset)
	local fit = row:FindFirstChild("RowFit") :: UIScale
	fit.Scale = scale
	-- UIScale grows around the anchor (top centre): keep the row vertically centred
	row.Position = UDim2.new(0.5, 0, 0.5, -row.Size.Y.Offset * scale / 2)
end

function Panel.Click(state, def)
	local data = state.C.ClientData.Data
	if not data then
		return
	end
	if data.Characters[def.Key] then
		if data.Selected ~= def.Key then
			state.C.ClientData:Fire("SelectCharacter", def.Key)
		end
	elseif def.Unlock.Cost then
		state.C.ClientData:Fire("UnlockCharacter", def.Key)
	end
end

function Panel.Refresh(state, data)
	for _, def in CharacterData.List do
		local ui = state.Cards[def.Key]
		local unlocked = data.Characters[def.Key]
		local hidden = def.Secret and not unlocked
		ui.Name.Text = if hidden then "???" else def.Name
		ui.Desc.Text = if hidden then "A secret survivor." else def.Desc
		ui.Perk.Text = if hidden then "Nobody knows how to unlock it. Maybe it is just standing somewhere." else def.Perk
		ui.Start.Text = if hidden then "???" else (WeaponData.ByKey[def.StartWeapon] or { Name = "" }).Name
		ui.Preview.ImageColor3 = if hidden then Color3.fromRGB(12, 11, 20) else Color3.new(1, 1, 1)
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
			if def.Unlock.Cost then
				local affordable = data.Coins >= def.Unlock.Cost
				Cards.Set(ui, "LOCKED", nil, if affordable then C.AccentSoft else C.Neutral, def.Unlock.Cost)
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
