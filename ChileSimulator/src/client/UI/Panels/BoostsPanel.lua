--[[
	BoostsPanel - your boost inventory. USE to activate (same boost again = more time).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BoostConfig = require(Shared.BoostConfig)
local ShopConfig = require(Shared.ShopConfig)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Widgets = require(UI.Widgets)
local Purchase = require(UI.Purchase)

local Panel = { Title = "BOOSTS", Icon = "⚡", Color = Theme.Colors.Blue }

-- boost id -> developer product that sells it
local PRODUCT_FOR = {
	Height2x = "BoostHeight2x",
	Height4x = "BoostHeight4x",
	SuperGrowth = "BoostSuper",
	AutoTap = "BoostAutoTap",
}

function Panel.Create(content: Frame, controllers)
	local data = controllers.ClientData
	local list = Widgets.Scroll(content)
	local rows = {}
	for i, id in BoostConfig.Order do
		local def = BoostConfig.Boosts[id]
		local frame = Widgets.Row(list, 70, i)
		local stripe = Kit.New("Frame", { BackgroundColor3 = def.Color, Size = UDim2.new(0, 8, 1, 0), Parent = frame })
		Kit.Corner(stripe, 8)
		Kit.Label({ Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(50, 50), Text = def.Icon, StrokeThickness = 0, Parent = frame })
		Kit.Label({
			Position = UDim2.fromOffset(74, 6),
			Size = UDim2.new(1, -330, 0, 30),
			Text = string.format("%s  (%s)", def.Name, Format.Duration(def.Duration)),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		local status = Kit.Label({
			Position = UDim2.fromOffset(74, 38),
			Size = UDim2.new(1, -330, 0, 24),
			Text = def.Description,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Colors.TextDim,
			Font = Theme.Fonts.Body,
			StrokeThickness = 0,
			Parent = frame,
		})
		local useButton, useLabel = Kit.Button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(130, 48),
			Parent = frame,
			OnClick = function()
				data:Fire("ActivateBoost", id)
			end,
		})
		local productKey = PRODUCT_FOR[id]
		local product = productKey and ShopConfig.Products[productKey]
		local buyButton
		if product and Purchase.Available(product) then
			buyButton = Kit.Button({
				Text = "R$ " .. product.Price,
				Color = Theme.Colors.Yellow,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -150, 0.5, 0),
				Size = UDim2.fromOffset(100, 40),
				Parent = frame,
				OnClick = function()
					Purchase.Product(controllers, productKey)
				end,
			})
		end
		rows[id] = { Status = status, Use = useButton, UseLabel = useLabel, Def = def, Buy = buyButton }
	end
	Kit.Label({
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = 99,
		Text = "Get free boosts from 📅 Daily, 🎁 Free gifts, chests, quests and events!",
		TextColor3 = Theme.Colors.TextDim,
		Font = Theme.Fonts.Body,
		StrokeThickness = 0,
		Parent = list,
	})

	local api = {}
	function api.Refresh()
		local boosts = data:Get("Boosts")
		if not boosts then
			return
		end
		for id, entry in rows do
			local count = boosts.Inventory[id] or 0
			local left = data:BoostLeft(id)
			entry.UseLabel.Text = if count > 0 then string.format("USE (x%d)", count) else "x0"
			Kit.SetButtonColor(entry.Use, if count > 0 then Theme.Colors.Green else Theme.Colors.GrayDark)
			if left > 0 then
				entry.Status.Text = "🔥 ACTIVE  " .. Format.Time(left)
				entry.Status.TextColor3 = Theme.Colors.Green
			else
				entry.Status.Text = entry.Def.Description
				entry.Status.TextColor3 = Theme.Colors.TextDim
			end
		end
	end
	api.Tick = api.Refresh
	return api
end

return Panel
