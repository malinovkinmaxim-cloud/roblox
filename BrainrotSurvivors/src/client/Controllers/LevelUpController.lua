--[[
	LevelUpController - LEVEL UP! (and TREASURE! chests): the game is paused by the server,
	3 (or 4) cards fly in, the player taps one. Cards tilt and grow under the mouse, rarity
	shows as colour, NEW / LV tags explain what the card does. Reroll and Skip buttons,
	keys 1-4 and R. The client only sends the index; the server validates it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Shared.GameConfig)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Widgets = require(script.Parent.Parent.UI.Widgets)

local LevelUpController = {}

local C = Theme.Colors
local CARD_W, CARD_H = 230, 310

function LevelUpController:Init(controllers)
	self.C = controllers
	local gui, root = Kit.ScreenGui("BrainrotLevelUp", 30, Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.Enabled = false
	self.Gui = gui
	self.Offer = nil
	self.Busy = false

	Kit.New("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Overlay,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Parent = root,
	})
	self.Title = Kit.Label({
		Text = "LEVEL UP!",
		Size = UDim2.fromOffset(700, 80),
		Position = UDim2.new(0.5, 0, 0, 40),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = Theme.Fonts.Title,
		TextColor3 = C.Gold,
		StrokeThickness = 4,
		Parent = root,
	})
	self.Sub = Kit.Label({
		Text = "Choose one",
		Size = UDim2.fromOffset(600, 30),
		Position = UDim2.new(0.5, 0, 0, 118),
		AnchorPoint = Vector2.new(0.5, 0),
		TextColor3 = C.TextDim,
		Parent = root,
	})
	self.Cards = Kit.New("Frame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(1000, CARD_H + 20),
		Position = UDim2.new(0.5, 0, 0.5, 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = root,
	})
	Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 18),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = self.Cards,
	})
	local _, rerollLabel = Kit.Button({
		Name = "Reroll",
		Text = "🔄 REROLL",
		Size = UDim2.fromOffset(200, 52),
		Position = UDim2.new(0.5, -110, 1, -30),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = C.Purple,
		OnClick = function()
			self:Reroll()
		end,
		Parent = root,
	})
	self.RerollLabel = rerollLabel
	self.RerollButton = rerollLabel.Parent
	Kit.Button({
		Name = "Skip",
		Text = "SKIP +" .. GameConfig.LevelUp.SkipCoins .. "🪙",
		Size = UDim2.fromOffset(200, 52),
		Position = UDim2.new(0.5, 110, 1, -30),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = C.Gray,
		OnClick = function()
			if not self.Busy then
				self:Lock()
				self.C.ClientData:Fire("Skip")
			end
		end,
		Parent = root,
	})
end

-- blocks double clicks until the server answers; never stays blocked if no answer comes
function LevelUpController:Lock()
	self.Busy = true
	local offer = self.Offer
	task.delay(2, function()
		if self.Offer == offer then
			self.Busy = false
		end
	end)
end

function LevelUpController:IsOpen(): boolean
	return self.Gui.Enabled
end

local function tagFor(card): (string, Color3)
	if card.Type == "Rare" then
		return if card.Rarity == "Legendary" then "LEGENDARY" else "RARE", Theme.Rarity[card.Rarity] or C.Purple
	elseif card.New then
		return "NEW!", C.Lime
	elseif card.Level then
		return "LV " .. card.Level, C.Blue
	end
	return "", C.Gray
end

function LevelUpController:BuildCard(card, index: number, count: number)
	local rarity = Theme.Rarity[card.Rarity] or Theme.Rarity.Common
	local button = Kit.New("TextButton", {
		Name = "Card" .. index,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = index,
		Parent = self.Cards,
	})
	Kit.Corner(button, 18)
	local stroke = Kit.Stroke(button, 4, rarity)
	Kit.Gradient(button, rarity:Lerp(C.Panel, 0.55), C.PanelDark)
	local scale = Kit.New("UIScale", { Parent = button })

	Kit.Label({
		Text = tostring(index),
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.fromOffset(10, 8),
		TextColor3 = C.TextDim,
		Parent = button,
	})
	local tagText, tagColor = tagFor(card)
	if tagText ~= "" then
		Widgets.Tag(button, tagText, tagColor, UDim2.new(1, -10, 0, 10), UDim2.fromOffset(if #tagText > 5 then 110 else 70, 26)).AnchorPoint = Vector2.new(1, 0)
	end
	Kit.Label({
		Name = "Icon",
		Text = card.Icon or "?",
		Size = UDim2.fromOffset(110, 110),
		Position = UDim2.new(0.5, 0, 0, 40),
		AnchorPoint = Vector2.new(0.5, 0),
		StrokeThickness = 0,
		Parent = button,
	})
	Kit.Label({
		Name = "CardTitle",
		Text = card.Title,
		Size = UDim2.new(1, -20, 0, 38),
		Position = UDim2.fromOffset(10, 160),
		Font = Theme.Fonts.Title,
		TextColor3 = if card.Type == "Rare" then rarity else C.Text,
		Parent = button,
	})
	Kit.Label({
		Name = "Desc",
		Text = card.Desc,
		Size = UDim2.new(1, -24, 0, 92),
		Position = UDim2.fromOffset(12, 204),
		Font = Theme.Fonts.Body,
		TextColor3 = C.TextDim,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		StrokeThickness = 0,
		Parent = button,
	})

	-- hover: grow + tilt (alternating), glow
	button.MouseEnter:Connect(function()
		Kit.Tween(scale, 0.15, { Scale = 1.07 }, Enum.EasingStyle.Back)
		Kit.Tween(button, 0.15, { Rotation = if index % 2 == 0 then 2 else -2 })
		stroke.Color = rarity:Lerp(Color3.new(1, 1, 1), 0.5)
		self.C.SoundController:Play("CardHover")
	end)
	button.MouseLeave:Connect(function()
		Kit.Tween(scale, 0.15, { Scale = 1 })
		Kit.Tween(button, 0.15, { Rotation = 0 })
		stroke.Color = rarity
	end)
	button.Activated:Connect(function()
		self:Pick(index)
	end)

	-- fly in from below, staggered
	scale.Scale = 0.6
	button.Rotation = (index - (count + 1) / 2) * 8
	task.delay(0.06 * index, function()
		Kit.Tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		Kit.Tween(button, 0.35, { Rotation = 0 }, Enum.EasingStyle.Back)
	end)
	if card.Type == "Rare" then
		task.delay(0.06 * index + 0.2, function()
			self.C.SoundController:Play("Rare")
		end)
	end
end

function LevelUpController:Show(offer)
	self.Offer = offer
	self.Busy = false
	Widgets.Clear(self.Cards)
	local chest = offer.Kind == "Chest"
	self.Title.Text = if chest then "TREASURE!" else "LEVEL UP!"
	self.Title.TextColor3 = if chest then C.Gold else C.Lime
	self.Sub.Text = if chest then "A chest! Pick your reward" else "Level " .. tostring(offer.Level) .. " - choose one"
	for i, card in offer.Cards do
		self:BuildCard(card, i, #offer.Cards)
	end
	self.RerollLabel.Text = "🔄 REROLL (" .. tostring(offer.Rerolls or 0) .. ")"
	Kit.SetButtonColor(self.RerollButton, if (offer.Rerolls or 0) > 0 then C.Purple else C.Gray)
	local wasOpen = self.Gui.Enabled
	self.Gui.Enabled = true
	if not wasOpen then
		Kit.Pop(self.Title, 0.5)
		self.C.SoundController:Play(if chest then "Chest" else "LevelUp")
	end
	self.C.HudController:TogglePauseMenuOff()
end

function LevelUpController:Hide()
	self.Gui.Enabled = false
	self.Offer = nil
end

function LevelUpController:Pick(index: number)
	local offer = self.Offer
	if not offer or self.Busy or not offer.Cards[index] then
		return
	end
	self:Lock()
	local card = self.Cards:FindFirstChild("Card" .. index)
	if card then
		Kit.Pop(card :: GuiObject, 0.15)
	end
	self.C.ClientData:Fire("Choose", index)
end

function LevelUpController:Reroll()
	local offer = self.Offer
	if not offer or self.Busy or (offer.Rerolls or 0) <= 0 then
		self.C.SoundController:Play("Error")
		return
	end
	self:Lock()
	self.C.SoundController:Play("Reroll")
	self.C.ClientData:Fire("Reroll")
end

function LevelUpController:Start() end

return LevelUpController
