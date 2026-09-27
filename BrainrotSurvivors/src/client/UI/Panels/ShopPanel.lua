--[[
	ShopPanel - full-screen shop with categories (one page at a time, big simple cards):
	  UPGRADES    permanent upgrades bought with Brain Coins
	  COSMETICS   hats (coins or achievements) - looks only
	  BOOSTS      Coin Rush, 2x Coins, 2x Brain XP
	  GAMEPASSES  VIP, Cosmetic Pack, Extra Loadout
	  COINS       coin packs + codes
	Nothing here wins a run by itself; the paid revive is only offered on the death screen.
	OnOpen(arg) selects a page ("Coins", "Passes", ...).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local MetaData = require(Shared.MetaData)
local SkinData = require(Shared.SkinData)
local AchievementData = require(Shared.AchievementData)
local MonetizationData = require(Shared.MonetizationData)

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

local PAGES = { "Upgrades", "Cosmetics", "Boosts", "Passes", "Coins" }
local LABELS = { Upgrades = "UPGRADES", Cosmetics = "COSMETICS", Boosts = "BOOSTS", Passes = "GAMEPASSES", Coins = "COINS" }
local BOOSTS = { { "Product", "CoinRush" }, { "Pass", "DoubleCoins" }, { "Pass", "DoubleXP" } }
local PASSES = { { "Pass", "VIP" }, { "Pass", "Cosmetics" }, { "Pass", "ExtraLoadout" } }
local COINS = { { "Product", "CoinsSmall" }, { "Product", "CoinsBig" } }

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
		OnClick = function()
			local data = state.C.ClientData.Data
			if kind == "Pass" and data and data.Passes and data.Passes[key] then
				return
			end
			state.C.ClientData:Fire("Buy", kind, key)
		end,
	})
	Icons.Make(ui.Picture, "Product", key, 60, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
	ui.Def = def
	ui.Kind = kind
	state.Products[key] = ui
end

function Panel.Build(body: Frame, controllers)
	local state = { C = controllers, Upgrades = {}, Hats = {}, Products = {}, Pages = {} }

	-- top row: category tabs (left) and your coins (right)
	local tabs = Widgets.Tabs(body, PAGES, LABELS, function(name)
		Panel.Show(state, name)
	end)
	for _, button in tabs.Buttons do
		button.Size = UDim2.fromOffset(136, 36)
	end
	tabs.Frame.Size = UDim2.fromOffset(#PAGES * 136 + 8, 44)
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
		Size = UDim2.new(1, -52, 0, 20),
		Position = UDim2.new(0, 40, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = F.Bold,
		MaxTextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = wallet,
	})

	local holder = Kit.New("Frame", { Name = "Pages", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -58), Position = UDim2.fromOffset(0, 58), Parent = body })

	-- UPGRADES
	local upgrades = page(holder, "Upgrades", Vector2.new(240, 140))
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
		ui.Desc.Size = UDim2.new(1, -82, 0, 32)
		-- level pips
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

	-- COSMETICS
	local hats = page(holder, "Cosmetics", Vector2.new(188, 300))
	state.Pages.Cosmetics = hats
	for i, def in SkinData.List do
		local ui = Cards.Item(hats, {
			Name = def.Name,
			Desc = def.Desc,
			Rarity = def.Rarity,
			Order = i,
			PictureHeight = 110,
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
		})
		Previews.Hat(ui.Picture, def.Key)
		state.Hats[def.Key] = ui
	end

	-- BOOSTS / GAMEPASSES / COINS
	local cell = Vector2.new(300, 264)
	for _, entry in { { "Boosts", BOOSTS }, { "Passes", PASSES }, { "Coins", COINS } } do
		local scroll = page(holder, entry[1], cell)
		state.Pages[entry[1]] = scroll
		for i, item in entry[2] do
			productCard(state, scroll, i, item[1], item[2])
		end
	end
	-- codes live next to the coin packs
	local codes = Cards.Item(state.Pages.Coins, {
		Name = "Have a code?",
		Desc = "Redeem a code for free Brain Coins.",
		Order = 10,
		PictureHeight = 96,
		OnClick = function()
			controllers.LobbyController:OpenPanel("Codes")
		end,
	})
	Icons.Make(codes.Picture, "Menu", "Codes", 60, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
	Cards.Set(codes, "", "REDEEM", C.Neutral)

	Panel.Show(state, "Upgrades")
	return state
end

function Panel.Show(state, name: string)
	state.Current = name
	state.Tabs.Select(name)
	for key, scroll in state.Pages do
		scroll.Visible = key == name
	end
end

function Panel.Refresh(state, data)
	state.Wallet.Text = Widgets.Commas(data.Coins)

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

	local owned = data.Skins or {}
	for _, def in SkinData.List do
		local ui = state.Hats[def.Key]
		if owned[def.Key] then
			if data.EquippedSkin == def.Key then
				Cards.Set(ui, "EQUIPPED", "WEARING", C.SuccessDark)
			else
				Cards.Set(ui, "OWNED", "WEAR", C.AccentSoft)
			end
		elseif def.Cost then
			Cards.Set(ui, "LOCKED", nil, if data.Coins >= def.Cost then C.AccentSoft else C.Neutral, def.Cost)
		else
			local ach = def.Achievement and AchievementData.ByKey[def.Achievement]
			Cards.Set(ui, "LOCKED", "LOCKED", C.Neutral)
			ui.Need.Text = if ach then "Achievement: " .. ach.Name else ""
		end
	end

	local passes = data.Passes or {}
	for key, ui in state.Products do
		if ui.Kind == "Pass" and passes[key] then
			Cards.Set(ui, "OWNED", "OWNED", C.SuccessDark)
		elseif key == "CoinRush" and (data.CoinRushLeft or 0) > 0 then
			Cards.Set(ui, "EQUIPPED", string.format("ACTIVE %dm", math.ceil(data.CoinRushLeft / 60)), C.SuccessDark)
			ui.State.Text = "ACTIVE"
		else
			Cards.Set(ui, "", robux(ui.Def.Price), C.AccentSoft)
		end
	end
end

function Panel.OnOpen(state, _controllers, arg)
	Panel.Show(state, if type(arg) == "string" and state.Pages[arg] then arg else "Upgrades")
end

return Panel
