--[[
	ItemsPanel - full screen: every ITEM of 67 TOWN (shared/ItemData.lua) and your CHIPS.
	  tabs: BASE · PREMIUM · BOSS RELICS
	BASE items drop for everyone. PREMIUM items and BOSS RELICS are unlocked once with CHIPS
	(earned in runs only, never with Robux): an unlock adds the item to the loot of your runs,
	you still have to find it (level I) and find it again (II, III...). A boss relic only
	drops from its own boss. Items you have found at least once say FOUND.
	Each card: icon, name, rarity + price class, what it does, its levels, the price.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local ItemData = require(Shared.ItemData)
local BossData = require(Shared.BossData)
local Format = require(Shared.Util.Format)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)
local Cards = require(script.Parent.Parent.Cards)
local Icons = require(script.Parent.Parent.Icons)

local C = Theme.Colors
local F = Theme.Fonts

local Panel = {}
Panel.Kind = "Screen"
Panel.Title = "ITEMS"

local CARD = Vector2.new(300, 252)
local TABS = { "Base", "Premium", "BossRelic" }
local LABELS = { Base = "BASE", Premium = "PREMIUM", BossRelic = "BOSS RELICS" }
local ROMAN = { "I", "II", "III", "IV", "V" }

-- "I: +40% pickup range  ·  III: NEW a pulse every 30 s"
local function levelsText(def): string
	local parts = {}
	for i, l in def.Levels do
		if i == 1 or l.New or i == def.MaxLevel then
			table.insert(parts, (ROMAN[i] or tostring(i)) .. ": " .. (if l.New then "NEW " .. l.New else l.Desc))
		end
	end
	return table.concat(parts, "\n")
end

function Panel.Build(body: Frame, controllers)
	local state = { Cards = {}, Pages = {}, C = controllers }
	-- your CHIPS (top right of the tabs row)
	local balance = Kit.Panel({
		Name = "Chips",
		Size = UDim2.fromOffset(170, 40),
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Radius = 20,
		Parent = body,
	})
	Widgets.Chip(balance, 22, { Position = UDim2.new(0, 12, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
	state.Balance = Kit.Label({
		Name = "Amount",
		Text = "0",
		Size = UDim2.new(1, -50, 0, 22),
		Position = UDim2.new(0, 42, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = F.Title,
		MaxTextSize = 20,
		TextColor3 = Widgets.ChipColor,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = balance,
	})
	state.Tabs = Widgets.Tabs(body, TABS, LABELS, function(name)
		for key, page in state.Pages do
			page.Visible = key == name
		end
	end)
	-- how it works, under the tabs
	Kit.Label({
		Name = "Help",
		Text = "Earn CHIPS in runs (bosses, elites, time). Unlocking adds an item to your loot: you still find it and level it up in runs.",
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 50),
		Font = F.Medium,
		MaxTextSize = 14,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = body,
	})
	local holder = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -78), Position = UDim2.fromOffset(0, 78), Parent = body })
	for _, tab in TABS do
		local page = Widgets.Scroll(holder, CARD, 12)
		page.Name = tab
		page.Visible = false
		state.Pages[tab] = page
	end
	for i, def in ItemData.List do
		local page = state.Pages[def.Type]
		if page and not def.Secret then
			local ui = Cards.Item(page, {
				Name = def.Name,
				Desc = def.Desc,
				Rarity = def.Rarity,
				Order = (if def.Price then def.Price else 0) * 100 + i,
				PictureHeight = 64,
				Side = true,
				ButtonWidth = 120,
				Width = CARD.X,
				OnClick = function()
					Panel.Click(state, def)
				end,
			})
			Icons.Make(ui.Picture, "Item", def.Key, 52, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
			-- what it does, then its levels (the first one, the mechanic, the last one)
			ui.Desc.Text = def.Desc .. "\n" .. levelsText(def)
			ui.Desc.TextSize = 13
			state.Cards[def.Key] = ui
		end
	end
	state.Tabs.Select("Base")
	for key, page in state.Pages do
		page.Visible = key == "Base"
	end
	return state
end

function Panel.Click(state, def)
	local data = state.C.ClientData.Data
	if not data or not ItemData.NeedsUnlock(def) or (data.ItemUnlocks or {})[def.Key] then
		return
	end
	if (data.Chips or 0) < (def.Price or 0) then
		state.C.BannerController:Toast(string.format("Needs %s CHIPS (you have %s)", Format.Commas(def.Price or 0), Format.Commas(data.Chips or 0)), "Error", "Earn CHIPS by beating bosses and elites in runs")
		return
	end
	state.C.ClientData:Fire("UnlockItem", def.Key)
end

function Panel.Refresh(state, data)
	state.Balance.Text = Format.Commas(data.Chips or 0)
	local unlocks = data.ItemUnlocks or {}
	local found = (data.Seen and data.Seen.Items) or {}
	for _, def in ItemData.List do
		local ui = state.Cards[def.Key]
		if ui then
			local where = ""
			if def.Type == "BossRelic" then
				local boss = BossData.ByKey[def.Boss or ""]
				where = if boss then "Drops from " .. boss.Title .. (if boss.Slot == 5 then "" else " (boss " .. boss.Slot .. ")") else ""
			end
			local levels = def.MaxLevel .. (if def.MaxLevel == 1 then " level" else " levels")
			if not ItemData.NeedsUnlock(def) then
				Cards.Set(ui, if found[def.Key] then "FOUND" else "", nil)
				ui.Need.Text = levels .. "  ·  in every run's loot"
			elseif unlocks[def.Key] then
				Cards.Set(ui, if found[def.Key] then "FOUND" else "UNLOCKED", nil)
				ui.Need.Text = levels .. (if where ~= "" then "  ·  " .. where else "  ·  in your loot")
			else
				local affordable = (data.Chips or 0) >= (def.Price or 0)
				Cards.Set(ui, "LOCKED", nil, if affordable then C.AccentSoft else C.Neutral, def.Price, "Chip")
				ui.Need.Text = ItemData.PriceClass(def) .. (if where ~= "" then "  ·  " .. where else "")
			end
		end
	end
end

return Panel
