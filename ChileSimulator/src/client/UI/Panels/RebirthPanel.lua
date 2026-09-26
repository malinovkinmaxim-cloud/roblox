--[[
	RebirthPanel - the main long-term progress: reset height, get a bigger multiplier + gems.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)
local ShopConfig = require(Shared.ShopConfig)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Widgets = require(UI.Widgets)
local Purchase = require(UI.Purchase)

local Panel = { Title = "REBIRTH", Icon = "♻️", Color = Theme.Colors.Purple }

function Panel.Create(content: Frame, controllers)
	local data = controllers.ClientData

	local count = Kit.Label({
		Size = UDim2.new(1, 0, 0, 40),
		Text = "",
		Font = Theme.Fonts.Title,
		Parent = content,
	})
	local mults = Kit.Label({
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, 52),
		Text = "",
		RichText = true,
		Font = Theme.Fonts.Title,
		Parent = content,
	})
	Kit.Label({
		Position = UDim2.fromOffset(20, 100),
		Size = UDim2.new(1, -40, 0, 46),
		Text = "Rebirth resets your HEIGHT - you keep coins, upgrades and pets.\nYou get a BIGGER multiplier and 💎 gems. Then you grow MUCH faster!",
		TextColor3 = Theme.Colors.TextDim,
		Font = Theme.Fonts.Body,
		StrokeThickness = 0,
		Parent = content,
	})
	local bar = Widgets.ProgressBar(content, UDim2.new(1, -60, 0, 40), UDim2.fromOffset(30, 156), Theme.Colors.Green)
	local reward = Kit.Label({
		Position = UDim2.fromOffset(0, 202),
		Size = UDim2.new(1, 0, 0, 30),
		Text = "",
		TextColor3 = Theme.Colors.Gem,
		Parent = content,
	})
	local button, label = Kit.Button({
		Text = "REBIRTH",
		Color = Theme.Colors.Green,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 240),
		Size = UDim2.fromOffset(320, 70),
		Font = Theme.Fonts.Title,
		Parent = content,
		OnClick = function()
			local stats = data:Get("Stats")
			if stats and stats.Height >= stats.RebirthCost then
				data:Fire("Rebirth")
				controllers.PanelController:Close(true) -- watch the shrink + BOOM
			else
				controllers.SoundController:Play("Error")
			end
		end,
	})
	local instant = ShopConfig.Products.InstantRebirth
	local instantButton = Kit.Button({
		Text = string.format("♻️ +1 INSTANT REBIRTH  (R$ %d)", instant.Price),
		Color = Theme.Colors.Yellow,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(360, 40),
		Parent = content,
		OnClick = function()
			Purchase.Product(controllers, "InstantRebirth")
		end,
	})
	instantButton.Visible = Purchase.Available(instant)

	local api = {}
	function api.Refresh()
		local stats = data:Get("Stats")
		if not stats then
			return
		end
		local r = stats.Rebirths
		count.Text = "REBIRTHS: " .. Format.Number(r)
		mults.Text = string.format(
			'<font color="#FFFFFF">%s GROWTH</font>  ➜  <font color="#5CFF7A">%s GROWTH</font>',
			Format.Mult(Formulas.RebirthMultiplier(r)),
			Format.Mult(Formulas.RebirthMultiplier(r + 1))
		)
		local cost = stats.RebirthCost
		bar.Set(stats.Height / cost, string.format("%s / %s", Format.Length(stats.Height), Format.Length(cost)))
		reward.Text = "Reward: +" .. Format.Number(Formulas.RebirthGems(r + 1)) .. " 💎"
		local ready = stats.Height >= cost
		label.Text = if ready then "♻️ REBIRTH!" else "🔒 NEED " .. Format.Length(cost)
		Kit.SetButtonColor(button, if ready then Theme.Colors.Green else Theme.Colors.GrayDark)
	end
	return api
end

return Panel
