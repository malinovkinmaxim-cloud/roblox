--[[
	ShopPanel - full-screen shop, one page at a time:
	  UPGRADES    permanent upgrades bought with coins (small bonuses, never required)
	  PREMIUM     the 7 Mythic abilities (Robux; hero-card style with the Mythic shine), the
	              daily FREE TRIAL (one of them for your next run), ability skins and the trail
	              pack (shared/AbilityConfig.lua). No id yet: COMING SOON (Studio: TEST BUY)
	  COSMETICS   12 categories (left list): hats, hero skins, ability skins, kill effects,
	              spawn effects, trails, emotes, name effects, lobby decor, victory poses,
	              UI themes, auras. Looks only. Coins, achievements, levels, the collection
	              book or a pass.
	  BOOSTS      67 Aura (30 min), AFK Boost (x2 camp rewards, 4 h)
	  GAMEPASSES  VIP Cosmetics, Cosmetic Collection, Extra Loadout Slots, Extra AFK Hero
	              Slot, AFK Capacity
	  SUPPORT     donations (Say Thanks / Big Thanks / Legendary Supporter): no reward
	Robux prices come from Roblox when the ids are set; items without an id show SOON in the
	published game (shared/MonetizationData.lua).
	Nothing here wins a run: the paid revive / extra reroll / extra chest only appear at the
	moment they apply (death screen, level up, results).
	OnOpen(arg) selects a page ("Upgrades", "Premium", "Cosmetics", "Boosts", "Passes", "Support").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local MetaData = require(Shared.MetaData)
local CosmeticData = require(Shared.CosmeticData)
local AchievementData = require(Shared.AchievementData)
local MonetizationData = require(Shared.MonetizationData)
local WeaponData = require(Shared.WeaponData)
local AbilityConfig = require(Shared.AbilityConfig)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)
local Cards = require(script.Parent.Parent.Cards)
local Icons = require(script.Parent.Parent.Icons)
local Previews = require(script.Parent.Parent.Previews)

local C = Theme.Colors
local F = Theme.Fonts

local Panel = {}
Panel.Kind = "Screen"
Panel.Title = "SHOP"

local PAGES = { "Upgrades", "Premium", "Cosmetics", "Boosts", "Passes", "Support" }
local LABELS = { Upgrades = "UPGRADES", Premium = "PREMIUM", Cosmetics = "COSMETICS", Boosts = "BOOSTS", Passes = "GAMEPASSES", Support = "SUPPORT" }
local SUPPORT = { { "Product", "Support1" }, { "Product", "Support2" }, { "Product", "Support3" } }
local BOOSTS = { { "Product", "CosmeticBoost" }, { "Product", "AfkBoost" } }
local PASSES = {
	{ "Pass", "VIPCosmetics" },
	{ "Pass", "CosmeticPass" },
	{ "Pass", "ExtraLoadout" },
	{ "Pass", "ExtraHeroSlot" },
	{ "Pass", "AfkCapacity" },
}
local SIDEBAR = 170

local function robux(price: number): string
	return "R$ " .. Widgets.Commas(price)
end

-- a page = a scrolling grid; only the selected one is visible
local function page(holder: Instance, name: string, cell: Vector2): ScrollingFrame
	local scroll = Widgets.Scroll(holder, cell, 12)
	scroll.Name = name
	scroll.Visible = false
	return scroll
end

local function productCard(state, scroll: Instance, order: number, kind: string, key: string)
	local def = if kind == "Pass" then MonetizationData.PassByKey[key] else MonetizationData.ProductByKey[key]
	local ui = Cards.Item(scroll, {
		Name = def.Name,
		Desc = def.Desc,
		Order = order,
		PictureHeight = 96,
		Width = 300,
		OnClick = function()
			local data = state.C.ClientData.Data
			if kind == "Pass" and data and data.Passes and data.Passes[key] then
				return
			end
			if not state.C.ClientData:CanBuy(key) then
				return -- not on sale yet (no id)
			end
			state.C.ClientData:Fire("Buy", kind, key)
		end,
	})
	Icons.Make(ui.Picture, "Product", key, 60, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
	ui.Def = def
	ui.Kind = kind
	state.Products[key] = ui
end

-- the Robux button of a premium sale: owned / COMING SOON (no id yet) / TEST BUY (Studio) / price
local function saleButton(state, ui, key: string, owned: boolean)
	local cd = state.C.ClientData
	local def = MonetizationData.PassByKey[key] or MonetizationData.ProductByKey[key]
	if owned then
		Cards.Set(ui, "OWNED", "OWNED", C.SuccessDark)
	elseif not cd:CanBuy(key) then
		Cards.Set(ui, "", "COMING SOON", C.Neutral)
	elseif def and def.Id == 0 then
		Cards.Set(ui, "", "TEST BUY", C.AccentSoft)
		ui.Need.Text = "Studio test (no id yet)"
	else
		local price = cd:RobuxPrice(key)
		Cards.Set(ui, "", if price > 0 then robux(price) else "BUY", C.AccentSoft)
	end
end

local function buy(state, key: string)
	local data = state.C.ClientData.Data
	if not data or not state.C.ClientData:CanBuy(key) then
		return -- not on sale yet (no id)
	end
	if data.Passes and data.Passes[key] then
		return
	end
	state.C.ClientData:Fire("Buy", if MonetizationData.PassByKey[key] then "Pass" else "Product", key)
end

-- PREMIUM: the daily trial, the 7 Mythic abilities, ability skins, the trail pack
local function buildPremium(state, scroll: Instance)
	local center = { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) }
	local trial = Cards.Item(scroll, {
		Name = "FREE TRIAL",
		Desc = "",
		Rarity = "Mythic",
		RarityBorder = true,
		Order = 0,
		PictureHeight = 110,
		Width = 230,
		OnClick = function()
			local premium = state.C.ClientData.Data and state.C.ClientData.Data.Premium
			if premium and premium.Trial and premium.TrialLeft > 0 and not premium.TrialArmed then
				state.C.ClientData:Fire("PremiumTrial")
			end
		end,
	})
	state.Trial = trial
	for i, def in WeaponData.Premium do
		local sale = MonetizationData.ForAbility(def.Key)
		local ui = Cards.Item(scroll, {
			Name = def.Name,
			Desc = def.Desc,
			Rarity = "Mythic",
			RarityBorder = true,
			Order = i,
			PictureHeight = 110,
			Width = 230,
			OnClick = function()
				if sale then
					buy(state, sale.Key)
				end
			end,
		})
		Icons.Make(ui.Picture, "Weapon", def.Key, 104, center)
		ui.Key = def.Key
		ui.Sale = sale and sale.Key
		state.PremiumCards[def.Key] = ui
	end
	-- ability skins and the trail pack (cosmetic only)
	local extras = {}
	for _, style in AbilityConfig.SkinOrder do
		table.insert(extras, { "Skin." .. style, CosmeticData.ById["WeaponSkin." .. style] })
	end
	table.insert(extras, { "TrailPack", CosmeticData.ById["Trail." .. AbilityConfig.TrailPack.Trails[1]] })
	for i, entry in extras do
		local sale = MonetizationData.PassByKey[entry[1]] or MonetizationData.ProductByKey[entry[1]]
		local ui = Cards.Item(scroll, {
			Name = string.upper(sale.Name),
			Desc = sale.Desc,
			Rarity = entry[2].Rarity,
			RarityBorder = true,
			Order = 20 + i,
			PictureHeight = 110,
			Width = 230,
			OnClick = function()
				buy(state, sale.Key)
			end,
		})
		Icons.Cosmetic(ui.Picture, entry[2], 72, center)
		ui.Sale = sale.Key
		ui.Cosmetics = sale.Cosmetics
		state.PremiumExtras[sale.Key] = ui
	end
end

local function refreshPremium(state, data)
	local premium = data.Premium or { Owned = {}, TrialLeft = 0 }
	local owned = premium.Owned or {}
	-- the trial card: today's ability (its picture changes with it)
	local trial = state.Trial
	local key = premium.Trial
	if key ~= state.TrialKey then
		state.TrialKey = key
		local old = trial.Picture:FindFirstChild("Icon")
		if old then
			old:Destroy()
		end
		if key then
			Icons.Make(trial.Picture, "Weapon", key, 104, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
		end
	end
	local def = key and WeaponData.ByKey[key]
	if not def then
		trial.Desc.Text = "You own every premium ability. Thank you!"
		Cards.Set(trial, "OWNED", nil)
	else
		trial.Desc.Text = string.format("Today: %s. Take it into your next run for free, once a day.", def.Name)
		if premium.TrialArmed then
			Cards.Set(trial, "EQUIPPED", "NEXT RUN", C.SuccessDark)
			trial.State.Text = "READY"
		elseif (premium.TrialLeft or 0) > 0 then
			Cards.Set(trial, "", "TRY IT FREE", C.AccentSoft)
		else
			Cards.Set(trial, "", "TOMORROW", C.Neutral)
			trial.Need.Text = "Used today: a new one tomorrow"
		end
	end
	for k, ui in state.PremiumCards do
		if ui.Sale then
			saleButton(state, ui, ui.Sale, owned[k] == true)
		else
			Cards.Set(ui, "", "COMING SOON", C.Neutral)
		end
		if premium.TrialArmed and premium.Trial == k and not owned[k] then
			ui.State.Text = "TRIAL"
			ui.State.Visible = true
		end
	end
	local cos = data.Cosmetics and data.Cosmetics.Owned or {}
	for key2, ui in state.PremiumExtras do
		local all = true
		for _, id in ui.Cosmetics or {} do
			all = all and cos[id] == true
		end
		saleButton(state, ui, key2, all or (data.Passes ~= nil and data.Passes[key2] == true))
	end
end

-- the picture of a cosmetic: a real preview when there is one, else an icon tile
local function cosmeticPicture(ui, def, heroKey: string)
	local picture = ui.Picture
	if def.Category == "Hat" then
		Previews.Hat(picture, def.Style)
	elseif def.Category == "HeroSkin" then
		ui.SkinHolder = Kit.New("Frame", { Name = "Model", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = picture })
		Previews.Hero(ui.SkinHolder, heroKey, { Skin = def.Style })
	elseif def.Style == "Default" or def.Style == "None" then
		Widgets.Mono(picture, "—", C.TextMuted, 64, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
	else
		-- no 3D preview: a tile in the cosmetic's colour (a real icon from UI/IconImages when set)
		Icons.Cosmetic(picture, def, 64, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
	end
end

function Panel.Build(body: Frame, controllers)
	local state = { C = controllers, Upgrades = {}, Cosmetics = {}, Products = {}, Pages = {}, CatButtons = {}, CatPages = {}, PremiumCards = {}, PremiumExtras = {} }

	-- top row: page tabs (left) and your coins (right)
	local tabs = Widgets.Tabs(body, PAGES, LABELS, function(name)
		Panel.Show(state, name)
	end)
	state.Tabs = tabs

	local wallet = Kit.New("Frame", {
		Name = "Wallet",
		Size = UDim2.fromOffset(150, 40),
		Position = UDim2.new(1, 0, 0, 2),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = Theme.Glass,
		Parent = body,
	})
	Kit.Corner(wallet, 20)
	Kit.Stroke(wallet)
	Widgets.Coin(wallet, 20, { Position = UDim2.new(0, 12, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
	state.Wallet = Kit.Label({
		Name = "Amount",
		Text = "0",
		Size = UDim2.new(1, -52, 0, 18),
		Position = UDim2.fromOffset(40, 4),
		Font = F.Bold,
		TextScaled = false,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = wallet,
	})
	Kit.Label({
		Name = "Caption",
		Text = "COINS",
		Size = UDim2.new(1, -52, 0, 12),
		Position = UDim2.fromOffset(40, 23),
		Font = F.Bold,
		TextScaled = false,
		TextSize = 11,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = wallet,
	})

	local holder = Kit.New("Frame", { Name = "Pages", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -58), Position = UDim2.fromOffset(0, 58), Parent = body })

	-- UPGRADES
	local upgrades = page(holder, "Upgrades", Vector2.new(240, 122))
	state.Pages.Upgrades = upgrades
	for i, def in MetaData.Upgrades do
		local ui = Cards.Item(upgrades, {
			Name = def.Name,
			Desc = def.Desc,
			Order = i,
			PictureHeight = 46,
			Side = true,
			ButtonWidth = 104,
			OnClick = function()
				controllers.ClientData:Fire("BuyMeta", def.Key)
			end,
		})
		Icons.Make(ui.Picture, "Stat", def.Key, 40, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
		ui.Desc.Position = UDim2.fromOffset(70, 40)
		ui.Desc.Size = UDim2.new(1, -82, 0, 36)
		-- level: pips + "2/5", bottom-left next to the buy button
		local pips = Kit.New("Frame", {
			Name = "Pips",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(110, 6),
			Position = UDim2.new(0, 12, 1, -38),
			Parent = ui.Card,
		})
		Kit.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = pips })
		ui.Pips = {}
		for level = 1, def.MaxLevel do
			local pip = Kit.New("Frame", { Size = UDim2.fromOffset(18, 6), BackgroundColor3 = C.SurfaceLight, LayoutOrder = level, Parent = pips })
			Kit.Corner(pip, 3)
			ui.Pips[level] = pip
		end
		ui.Level = Kit.Label({
			Name = "Level",
			Text = "",
			Size = UDim2.fromOffset(100, 14),
			Position = UDim2.new(0, 12, 1, -26),
			Font = F.Bold,
			MaxTextSize = 12,
			TextColor3 = C.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = ui.Card,
		})
		state.Upgrades[def.Key] = ui
	end

	-- PREMIUM: hero-card style Mythic cards
	local premium = page(holder, "Premium", Vector2.new(230, 330))
	state.Pages.Premium = premium
	buildPremium(state, premium)

	-- COSMETICS: categories on the left, one grid per category on the right
	local cosmetics = Kit.New("Frame", { Name = "Cosmetics", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = holder })
	state.Pages.Cosmetics = cosmetics
	local sidebar = Widgets.Scroll(cosmetics, nil, 4)
	sidebar.Name = "Categories"
	sidebar.Size = UDim2.new(0, SIDEBAR, 1, 0)
	local grids = Kit.New("Frame", {
		Name = "Grids",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -(SIDEBAR + 12), 1, 0),
		Position = UDim2.fromOffset(SIDEBAR + 12, 0),
		Parent = cosmetics,
	})
	local heroKey = if controllers.ClientData.Data then controllers.ClientData.Data.Selected else "Rookie"
	for i, cat in CosmeticData.Categories do
		local button = Kit.New("TextButton", {
			Name = cat.Key,
			Text = string.upper(cat.Name),
			AutoButtonColor = false,
			Font = F.Bold,
			TextSize = 14,
			TextColor3 = C.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = C.Accent,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -8, 0, 34),
			LayoutOrder = i,
			Parent = sidebar,
		})
		Kit.Corner(button, 12)
		Kit.Padding(button, 12, 0)
		local dot = Kit.New("Frame", {
			Name = "Dot",
			Size = UDim2.fromOffset(8, 8),
			Position = UDim2.new(1, -4, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = C.Mythic,
			Visible = false,
			Parent = button,
		})
		Kit.Corner(dot, 4)
		button.Activated:Connect(function()
			if Kit.ClickSound then
				Kit.ClickSound()
			end
			Panel.ShowCategory(state, cat.Key)
		end)
		state.CatButtons[cat.Key] = button
		local grid = page(grids, cat.Key, Vector2.new(188, 300))
		state.CatPages[cat.Key] = grid
		for j, def in CosmeticData.ByCategory[cat.Key] do
			local ui = Cards.Item(grid, {
				Name = def.Name,
				Desc = def.Desc,
				Rarity = def.Rarity,
				Order = j,
				PictureHeight = 100,
				Width = 188,
				OnClick = function()
					Panel.ClickCosmetic(state, def)
				end,
			})
			cosmeticPicture(ui, def, heroKey)
			state.Cosmetics[def.Id] = ui
		end
	end

	-- BOOSTS / GAMEPASSES
	local cell = Vector2.new(300, 264)
	for _, entry in { { "Boosts", BOOSTS }, { "Passes", PASSES }, { "Support", SUPPORT } } do
		local scroll = page(holder, entry[1], cell)
		state.Pages[entry[1]] = scroll
		for i, item in entry[2] do
			productCard(state, scroll, i, item[1], item[2])
		end
	end
	-- codes live next to the boosts
	local codes = Cards.Item(state.Pages.Boosts, {
		Name = "Have a code?",
		Desc = "Redeem a code for free coins or fragments.",
		Order = 10,
		PictureHeight = 96,
		OnClick = function()
			controllers.LobbyController:OpenPanel("Codes")
		end,
	})
	Icons.Make(codes.Picture, "Menu", "Codes", 60, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
	Cards.Set(codes, "", "REDEEM", C.Neutral)

	Panel.ShowCategory(state, "Hat")
	Panel.Show(state, "Upgrades")
	return state
end

function Panel.Show(state, name: string)
	state.Current = name
	state.Tabs.Select(name)
	for key, p in state.Pages do
		p.Visible = key == name
	end
	if name == "Cosmetics" then
		-- the player looked: NEW badges go away (they stay on the cards until then)
		state.C.ClientData:Fire("SeenCosmetics")
	end
end

function Panel.ShowCategory(state, key: string)
	state.Category = key
	for k, grid in state.CatPages do
		grid.Visible = k == key
	end
	for k, button in state.CatButtons do
		local on = k == key
		button.BackgroundTransparency = if on then 0 else 1
		button.TextColor3 = if on then C.Text else C.TextDim
	end
end

function Panel.ClickCosmetic(state, def)
	local data = state.C.ClientData.Data
	if not data then
		return
	end
	local owned = data.Cosmetics and data.Cosmetics.Owned[def.Id]
	if owned then
		if def.Category == "Emote" then
			state.C.ClientData:Fire("Emote", def.Style)
		end
		state.C.ClientData:Fire("EquipCosmetic", def.Id)
	elseif def.Cost then
		state.C.ClientData:Fire("BuyCosmetic", def.Id)
	elseif def.Pass then
		state.C.ClientData:Fire("Buy", "Pass", def.Pass)
	elseif def.Robux then
		Panel.Show(state, "Premium") -- ability skins and the trail pack are sold there
	end
end

function Panel.Refresh(state, data)
	state.Wallet.Text = Widgets.Commas(data.Coins)
	refreshPremium(state, data)

	for _, def in MetaData.Upgrades do
		local ui = state.Upgrades[def.Key]
		local level = data.Meta[def.Key] or 0
		for i, pip in ui.Pips do
			pip.BackgroundColor3 = if i <= level then C.Accent else C.SurfaceLight
		end
		ui.Level.Text = string.format("LEVEL %d/%d", level, def.MaxLevel)
		local cost = MetaData.Cost(def.Key, level)
		if cost then
			Cards.Set(ui, "", nil, if data.Coins >= cost then C.AccentSoft else C.Neutral, cost)
		else
			Cards.Set(ui, "", "MAX", C.SuccessDark)
		end
	end

	local cos = data.Cosmetics or { Owned = {}, Equipped = {}, New = {} }
	local newIn = {}
	for _, def in CosmeticData.List do
		local ui = state.Cosmetics[def.Id]
		local owned = cos.Owned[def.Id] == true
		local isNew = cos.New and cos.New[def.Id] == true
		if isNew then
			newIn[def.Category] = true
		end
		if owned then
			if cos.Equipped[def.Category] == def.Id then
				Cards.Set(ui, "EQUIPPED", if def.Category == "Emote" then "PLAY" else "EQUIPPED", C.SuccessDark)
			else
				Cards.Set(ui, if isNew then "NEW" else "OWNED", "EQUIP", C.AccentSoft)
			end
		elseif def.Cost then
			Cards.Set(ui, "LOCKED", nil, if data.Coins >= def.Cost then C.AccentSoft else C.Neutral, def.Cost)
		elseif def.Pass then
			Cards.Set(ui, "LOCKED", "GAMEPASS", C.Neutral)
			ui.Need.Text = CosmeticData.SourceText(def)
		elseif def.Robux and not def.Collection then
			Cards.Set(ui, "LOCKED", "PREMIUM", C.Neutral)
			ui.Need.Text = CosmeticData.SourceText(def)
		else
			Cards.Set(ui, "LOCKED", "LOCKED", C.Neutral)
			local ach = def.Achievement and AchievementData.ByKey[def.Achievement]
			ui.Need.Text = if ach then "Achievement: " .. ach.Name else CosmeticData.SourceText(def)
		end
	end
	for key, button in state.CatButtons do
		(button:FindFirstChild("Dot") :: Frame).Visible = newIn[key] == true
	end

	local passes = data.Passes or {}
	for key, ui in state.Products do
		if ui.Kind == "Pass" and passes[key] then
			Cards.Set(ui, "OWNED", "OWNED", C.SuccessDark)
		elseif key == "CosmeticBoost" and (data.CosmeticBoostLeft or 0) > 0 then
			Cards.Set(ui, "EQUIPPED", string.format("ACTIVE %dm", math.ceil(data.CosmeticBoostLeft / 60)), C.SuccessDark)
			ui.State.Text = "ACTIVE"
		elseif key == "AfkBoost" and data.Afk and (data.Afk.BoostLeft or 0) > 0 then
			Cards.Set(ui, "EQUIPPED", string.format("ACTIVE %dm", math.ceil(data.Afk.BoostLeft / 60)), C.SuccessDark)
			ui.State.Text = "ACTIVE"
		elseif not state.C.ClientData:CanBuy(key) then
			-- no id yet (published game): visible, but it can't be bought
			Cards.Set(ui, "", "SOON", C.Neutral)
			ui.Need.Text = "Not on sale yet"
		else
			Cards.Set(ui, "", robux(state.C.ClientData:RobuxPrice(key)), C.AccentSoft)
		end
	end
end

function Panel.OnOpen(state, _controllers, arg)
	Panel.Show(state, if type(arg) == "string" and state.Pages[arg] then arg else "Upgrades")
end

return Panel
