--[[
	CollectionPanel - the COLLECTION BOOK (full screen).
	  tabs: HEROES · ABILITIES · PASSIVES · BOSSES · ENEMIES · 67 EVENTS · SECRETS
	  "Collected: 42 / 121" (and per tab)
	Every entry is a small tile with its picture (3D previews), name and rarity. Things not
	collected yet are dimmed; SECRET entries show "???" until found.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local CollectionData = require(Shared.CollectionData)
local WeaponData = require(Shared.WeaponData)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)
local Icons = require(script.Parent.Parent.Icons)

local C = Theme.Colors
local F = Theme.Fonts

local Panel = {}
Panel.Kind = "Screen"
Panel.Title = "COLLECTION"

local TILE = Vector2.new(150, 186)
local LABELS = {
	Heroes = "HEROES",
	Weapons = "ABILITIES",
	Abilities = "PASSIVES",
	Bosses = "BOSSES",
	Enemies = "ENEMIES",
	Events = "67 EVENTS",
	Secrets = "SECRETS",
}

local function picture(holder: Frame, category: string, key: string)
	local props = { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) }
	if category == "Heroes" then
		return Icons.Make(holder, "Hero", key, 104, props)
	elseif category == "Weapons" then
		return Icons.Make(holder, "Weapon", key, 90, props)
	elseif category == "Abilities" then
		if WeaponData.ByKey[key] then
			return Icons.Make(holder, "Weapon", key, 90, props)
		end
		return Icons.Make(holder, "Stat", key, 60, props)
	elseif category == "Bosses" or category == "Enemies" then
		return Icons.Make(holder, "Enemy", key, 100, props)
	elseif category == "Events" then
		return Widgets.Mono(holder, "67", C.Gold, 64, props)
	end
	return Widgets.Mono(holder, "?", C.TextMuted, 64, props)
end

function Panel.Build(body: Frame, controllers)
	local state = { C = controllers, Pages = {}, Tiles = {} }
	local names = {}
	for _, cat in CollectionData.Categories do
		table.insert(names, cat.Key)
	end
	state.Tabs = Widgets.Tabs(body, names, LABELS, function(name)
		Panel.Show(state, name)
	end)
	for _, button in state.Tabs.Buttons do
		button.Size = UDim2.fromOffset(108, 36)
		button.TextSize = 14
	end
	state.Tabs.Frame.Size = UDim2.fromOffset(#names * 108 + 8, 44)
	state.Summary = Kit.Label({
		Name = "Summary",
		Text = "",
		Size = UDim2.fromOffset(360, 20),
		Position = UDim2.fromOffset(0, 52),
		Font = F.Bold,
		MaxTextSize = 16,
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = body,
	})
	local holder = Kit.New("Frame", { Name = "Pages", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -82), Position = UDim2.fromOffset(0, 82), Parent = body })
	for _, cat in CollectionData.Categories do
		local page = Widgets.Scroll(holder, TILE, 10)
		page.Name = cat.Key
		page.Visible = false
		state.Pages[cat.Key] = page
		for i, entry in cat.Entries do
			local tile = Kit.Panel({ Name = entry.Key, Size = UDim2.fromScale(1, 1), LayoutOrder = i, Radius = 14, Parent = page })
			local pic = Kit.New("Frame", {
				Name = "Picture",
				Size = UDim2.new(1, -16, 0, 110),
				Position = UDim2.fromOffset(8, 8),
				BackgroundColor3 = Theme.Rarity[entry.Rarity] or C.SurfaceLight,
				BackgroundTransparency = 0.88,
				Parent = tile,
			})
			Kit.Corner(pic, 10)
			local name = Kit.Label({
				Name = "Title",
				Text = entry.Name,
				Size = UDim2.new(1, -16, 0, 20),
				Position = UDim2.fromOffset(8, 124),
				Font = F.Bold,
				MaxTextSize = 14,
				Parent = tile,
			})
			local rarity = Kit.Label({
				Name = "Rarity",
				Text = string.upper(entry.Rarity),
				Size = UDim2.new(1, -16, 0, 14),
				Position = UDim2.fromOffset(8, 148),
				Font = F.Bold,
				MaxTextSize = 11,
				TextColor3 = Theme.Rarity[entry.Rarity] or C.TextDim,
				Parent = tile,
			})
			local status = Kit.Label({
				Name = "Status",
				Text = "",
				Size = UDim2.new(1, -16, 0, 14),
				Position = UDim2.fromOffset(8, 164),
				Font = F.Medium,
				MaxTextSize = 11,
				TextColor3 = C.TextMuted,
				Parent = tile,
			})
			state.Tiles[cat.Key .. ":" .. entry.Key] = {
				Tile = tile,
				Picture = pic,
				Name = name,
				Rarity = rarity,
				Status = status,
				Entry = entry,
				Category = cat.Key,
				Built = false,
			}
		end
	end
	Panel.Show(state, "Heroes")
	return state
end

function Panel.Show(state, name: string)
	state.Current = name
	state.Tabs.Select(name)
	for key, page in state.Pages do
		page.Visible = key == name
	end
	if state.Data then
		Panel.Refresh(state, state.Data)
	end
end

function Panel.Refresh(state, data)
	state.Data = data
	local collected, total, per = CollectionData.Count(data)
	local current = CollectionData.ByKey[state.Current]
	state.Summary.Text = string.format("Collected: %d / %d", collected, total)
	if current then
		state.Summary.Text ..= string.format("  ·  %d/%d here", per[current.Key] or 0, #current.Entries)
	end
	for _, ui in state.Tiles do
		if ui.Category == state.Current then
			local entry = ui.Entry
			local has = CollectionData.Has(data, ui.Category, entry.Key)
			local hidden = entry.Secret and not has
			local mark = if hidden then "hidden" elseif has then "has" else "missing"
			if ui.Mark ~= mark then
				ui.Mark = mark
				Widgets.Clear(ui.Picture)
				local pic = if hidden then Widgets.Mono(ui.Picture, "?", C.TextMuted, 64, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) }) else picture(ui.Picture, ui.Category, entry.Key)
				local vf = pic:FindFirstChildWhichIsA("ViewportFrame", true)
				if vf then
					vf.ImageColor3 = if has then Color3.new(1, 1, 1) else Color3.fromRGB(40, 40, 52)
				end
			end
			ui.Name.Text = if hidden then "???" else entry.Name
			ui.Name.TextColor3 = if has then C.Text else C.TextMuted
			ui.Rarity.Text = if hidden then "SECRET" else string.upper(entry.Rarity)
			ui.Status.Text = if has then "COLLECTED" else "NOT YET"
			ui.Status.TextColor3 = if has then C.Success else C.TextMuted
			ui.Tile.BackgroundTransparency = if has then Theme.Glass else 0.45
		end
	end
end

function Panel.OnOpen(state, _controllers, arg)
	if type(arg) == "string" and state.Pages[arg] then
		Panel.Show(state, arg)
	end
end

return Panel
