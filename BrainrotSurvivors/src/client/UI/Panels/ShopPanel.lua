--[[
	ShopPanel - Robux items. Passes are coins / account XP / cosmetics / convenience; the paid
	revive is sold on the death screen (once per run). Nothing here wins a run by itself.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local MonetizationData = require(Shared.MonetizationData)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)

local C = Theme.Colors

local Panel = {}
Panel.Title = "SHOP"
Panel.Size = Vector2.new(900, 520)

local function item(scroll, order: number, def, kind: string, controllers)
	local row = Kit.Panel({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.PanelLight, LayoutOrder = order, Radius = 14, Parent = scroll })
	Kit.Label({ Text = def.Icon, Size = UDim2.fromOffset(60, 60), Position = UDim2.fromOffset(8, 14), StrokeThickness = 0, Parent = row })
	Kit.Label({ Text = def.Name, Size = UDim2.new(1, -220, 0, 28), Position = UDim2.fromOffset(74, 10), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.Fonts.Title, Parent = row })
	Kit.Label({
		Text = def.Desc,
		Size = UDim2.new(1, -220, 0, 40),
		Position = UDim2.fromOffset(74, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Font = Theme.Fonts.Body,
		TextColor3 = C.TextDim,
		StrokeThickness = 0,
		Parent = row,
	})
	local button, label = Kit.Button({
		Text = "R$ " .. def.Price,
		Size = UDim2.fromOffset(130, 52),
		Position = UDim2.new(1, -10, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = C.Lime,
		OnClick = function()
			controllers.ClientData:Fire("Buy", kind, def.Key)
		end,
		Parent = row,
	})
	return { Button = button, Label = label, Def = def }
end

function Panel.Build(body: Frame, controllers)
	local scroll = Widgets.Scroll(body, Vector2.new(820, 92), 8)
	local state = { Passes = {}, Products = {} }
	local order = 0
	for _, def in MonetizationData.Passes do
		order += 1
		state.Passes[def.Key] = item(scroll, order, def, "Pass", controllers)
	end
	for _, def in MonetizationData.Products do
		if def.Key ~= "Revive" then
			order += 1
			state.Products[def.Key] = item(scroll, order, def, "Product", controllers)
		end
	end
	return state
end

function Panel.Refresh(state, data)
	local passes = data.Passes or {}
	for key, ui in state.Passes do
		if passes[key] then
			ui.Label.Text = "✔ OWNED"
			Kit.SetButtonColor(ui.Button, C.Gold)
		else
			ui.Label.Text = "R$ " .. ui.Def.Price
			Kit.SetButtonColor(ui.Button, C.Lime)
		end
	end
	local rush = state.Products.CoinRush
	if rush then
		rush.Label.Text = if (data.CoinRushLeft or 0) > 0 then string.format("%dm left", math.ceil(data.CoinRushLeft / 60)) else "R$ " .. rush.Def.Price
	end
end

return Panel
