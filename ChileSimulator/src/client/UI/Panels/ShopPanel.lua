--[[
	ShopPanel - UPGRADES (coins) | GEMS (permanent) | STYLE (trails & auras) | ROBUX
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)
local ShopConfig = require(Shared.ShopConfig)
local CosmeticConfig = require(Shared.CosmeticConfig)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Widgets = require(UI.Widgets)
local Purchase = require(UI.Purchase)

local Panel = { Title = "SHOP", Icon = "🛒", Color = Theme.Colors.Green }

-- one row: icon, title, subtitle, button on the right
local function row(parent: Instance, order: number, icon: string, title: string, subtitle: string)
	local frame = Widgets.Row(parent, 64, order)
	Kit.Label({
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(48, 48),
		Text = icon,
		StrokeThickness = 0,
		Parent = frame,
	})
	local titleLabel = Kit.Label({
		Position = UDim2.fromOffset(64, 6),
		Size = UDim2.new(1, -260, 0, 28),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	Kit.Label({
		Position = UDim2.fromOffset(64, 34),
		Size = UDim2.new(1, -260, 0, 22),
		Text = subtitle,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Colors.TextDim,
		Font = Theme.Fonts.Body,
		StrokeThickness = 0,
		Parent = frame,
	})
	local button, label = Kit.Button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(180, 46),
		Parent = frame,
	})
	return frame, button, label, titleLabel
end

function Panel.Create(content: Frame, controllers)
	local data = controllers.ClientData
	local tabs = Widgets.Tabs(content, { "UPGRADES", "GEMS", "STYLE", "ROBUX" })

	local upgradeList = Widgets.Scroll(tabs.Pages.UPGRADES)
	local gemList = Widgets.Scroll(tabs.Pages.GEMS)
	local styleList = Widgets.Scroll(tabs.Pages.STYLE)
	local robuxList = Widgets.Scroll(tabs.Pages.ROBUX)

	-- UPGRADES (coins)
	local _, tapButton, tapLabel, tapTitle = row(upgradeList, 1, "👆", "TAP POWER", "More height from every tap")
	local _, autoButton, autoLabel, autoTitle = row(upgradeList, 2, "🌱", "AUTO GROW", "Grow by yourself, even without tapping")
	tapButton.Activated:Connect(function()
		data:Fire("BuyUpgrade", "TapPower")
	end)
	autoButton.Activated:Connect(function()
		data:Fire("BuyUpgrade", "AutoGrow")
	end)

	-- GEMS (permanent upgrades)
	local gemRows = {}
	for i, id in ShopConfig.GemUpgradeOrder do
		local def = ShopConfig.GemUpgrades[id]
		local frame, button, label, title = row(gemList, i, def.Icon, def.Name, def.Text)
		button.Activated:Connect(function()
			data:Fire("BuyGemUpgrade", id)
		end)
		gemRows[id] = { Frame = frame, Button = button, Label = label, Title = title }
	end

	-- STYLE (trails + auras)
	local styleRows = {}
	local function addStyle(kind: string, list, order0: number)
		local ids = {}
		for id in list do
			table.insert(ids, id)
		end
		table.sort(ids, function(a, b)
			return list[a].Order < list[b].Order
		end)
		for i, id in ids do
			local def = list[id]
			local frame, button, label = row(styleList, order0 + i, if kind == "Trail" then "✨" else "🌟", def.Name .. " " .. kind, "")
			-- colour preview
			local swatch = Kit.New("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				Position = UDim2.fromOffset(12, 14),
				Size = UDim2.fromOffset(40, 36),
				Parent = frame,
			})
			Kit.Corner(swatch, 10)
			local keys = {}
			for k, c in def.Colors do
				table.insert(keys, ColorSequenceKeypoint.new(if #def.Colors == 1 then 0 else (k - 1) / (#def.Colors - 1), c))
			end
			if #keys == 1 then
				table.insert(keys, ColorSequenceKeypoint.new(1, def.Colors[1]))
			end
			Kit.New("UIGradient", { Color = ColorSequence.new(keys), Parent = swatch })
			button.Activated:Connect(function()
				local cosmetics = data:Get("Cosmetics")
				local passes = data:Get("Passes") or {}
				local field = if kind == "Trail" then "Trails" else "Auras"
				local owned = if def.Pass then passes[def.Pass] == true else (cosmetics and cosmetics[field].Owned[id] == true)
				if owned then
					local equipped = cosmetics and cosmetics[field].Equipped == id
					data:Fire("EquipCosmetic", kind, if equipped then "" else id)
				elseif def.Pass then
					Purchase.Pass(controllers, def.Pass)
				else
					data:Fire("BuyCosmetic", kind, id)
				end
			end)
			styleRows[kind .. id] = { Kind = kind, Id = id, Def = def, Frame = frame, Button = button, Label = label }
		end
	end
	addStyle("Trail", CosmeticConfig.Trails, 0)
	addStyle("Aura", CosmeticConfig.Auras, 100)

	-- ROBUX
	local any = false
	for i, key in ShopConfig.PassOrder do
		local pass = ShopConfig.Passes[key]
		if Purchase.Available(pass) then
			any = true
			local _, button, label = row(robuxList, i, pass.Icon, pass.Name, table.concat(pass.Perks, " • "))
			label.Text = "R$ " .. pass.Price
			Kit.SetButtonColor(button, Theme.Colors.Yellow)
			button.Activated:Connect(function()
				local passes = data:Get("Passes") or {}
				if not passes[key] then
					Purchase.Pass(controllers, key)
				end
			end)
			styleRows["Pass" .. key] = { Kind = "Pass", Id = key, Button = button, Label = label, Price = pass.Price }
		end
	end
	for i, key in ShopConfig.ProductOrder do
		local product = ShopConfig.Products[key]
		if Purchase.Available(product) then
			any = true
			local _, button, label = row(robuxList, 100 + i, product.Icon, product.Name, "")
			label.Text = "R$ " .. product.Price
			Kit.SetButtonColor(button, Theme.Colors.Yellow)
			button.Activated:Connect(function()
				Purchase.Product(controllers, key)
			end)
		end
	end
	if not any then
		Kit.Label({ Size = UDim2.new(1, 0, 0, 40), Text = "Coming soon!", Parent = robuxList })
	end

	local api = {}
	function api.Refresh()
		local stats = data:Get("Stats")
		if not stats then
			return
		end
		local tapCost = Formulas.TapCost(stats.TapLevel)
		tapLabel.Text = if tapCost then "🪙 " .. Format.Number(tapCost) else "MAX"
		Kit.SetButtonColor(tapButton, if tapCost and stats.Coins >= tapCost then Theme.Colors.Green else Theme.Colors.GrayDark)
		tapTitle.Text = string.format("TAP POWER  %s ➜ %s", Format.Mult(Formulas.TapPower(stats.TapLevel)), Format.Mult(Formulas.TapPower(stats.TapLevel + 1)))
		local autoCost = Formulas.AutoCost(stats.AutoLevel)
		autoLabel.Text = if autoCost then "🪙 " .. Format.Number(autoCost) else "MAX"
		Kit.SetButtonColor(autoButton, if autoCost and stats.Coins >= autoCost then Theme.Colors.Green else Theme.Colors.GrayDark)
		autoTitle.Text = string.format("AUTO GROW  %s/s ➜ %s/s", Format.Gain(Formulas.AutoRate(stats.AutoLevel)), Format.Gain(Formulas.AutoRate(stats.AutoLevel + 1)))

		for id, entry in gemRows do
			local level = stats.Gem and stats.Gem[id] or 0
			local cost = ShopConfig.GemUpgradeCost(id, level)
			entry.Label.Text = if cost then "💎 " .. Format.Number(cost) else "MAX"
			Kit.SetButtonColor(entry.Button, if cost and stats.Gems >= cost then Theme.Colors.Blue else Theme.Colors.GrayDark)
			entry.Title.Text = string.format("%s  (Lv %d/%d)", ShopConfig.GemUpgrades[id].Name, level, ShopConfig.GemUpgrades[id].MaxLevel)
		end

		local cosmetics = data:Get("Cosmetics")
		local passes = data:Get("Passes") or {}
		for _, entry in styleRows do
			if entry.Kind == "Pass" then
				local owned = passes[entry.Id] == true
				entry.Label.Text = if owned then "✔ OWNED" else "R$ " .. entry.Price
				Kit.SetButtonColor(entry.Button, if owned then Theme.Colors.GrayDark else Theme.Colors.Yellow)
				continue
			end
			local def = entry.Def
			local field = if entry.Kind == "Trail" then "Trails" else "Auras"
			local owned = if def.Pass then passes[def.Pass] == true else (cosmetics ~= nil and cosmetics[field].Owned[entry.Id] == true)
			local equipped = cosmetics ~= nil and cosmetics[field].Equipped == entry.Id
			if equipped then
				entry.Label.Text = "✔ EQUIPPED"
				Kit.SetButtonColor(entry.Button, Theme.Colors.Purple)
			elseif owned then
				entry.Label.Text = "EQUIP"
				Kit.SetButtonColor(entry.Button, Theme.Colors.Green)
			elseif def.Pass then
				entry.Label.Text = "🔒 " .. (ShopConfig.Passes[def.Pass] and ShopConfig.Passes[def.Pass].Name or "PASS")
				Kit.SetButtonColor(entry.Button, Theme.Colors.Yellow)
			else
				local currency = if def.Price.Currency == "Gems" then "💎" else "🪙"
				local have = if def.Price.Currency == "Gems" then stats.Gems else stats.Coins
				entry.Label.Text = currency .. " " .. Format.Number(def.Price.Amount)
				Kit.SetButtonColor(entry.Button, if have >= def.Price.Amount then Theme.Colors.Blue else Theme.Colors.GrayDark)
			end
		end
	end
	return api
end

return Panel
