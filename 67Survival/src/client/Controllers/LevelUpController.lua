--[[
	LevelUpController - LEVEL UP! (and TREASURE / 67 CHEST): the game is paused by the server,
	3 (or 4) cards fade in, the player taps one. Rarity shows as the border colour and a
	tag (7 tiers); an EVOLUTION card is Mythic, glows and shows its recipe. NEW / LV tags and
	"completes an evolution" hints explain the card. Reroll (out of rerolls: +1 reroll can
	be bought, never forced) and Skip, keys 1-4 and R. The client only sends the index.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Shared.GameConfig)
local WeaponData = require(Shared.WeaponData)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Widgets = require(script.Parent.Parent.UI.Widgets)
local Icons = require(script.Parent.Parent.UI.Icons)
local Cards = require(script.Parent.Parent.UI.Cards)

local LevelUpController = {}

local C = Theme.Colors
local F = Theme.Fonts
local CARD_W, CARD_H = 220, 272

function LevelUpController:Init(controllers)
	self.C = controllers
	local gui, root = Kit.ScreenGui("S67LevelUp", 30, Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.Enabled = false
	self.Gui = gui
	self.Offer = nil
	self.Busy = false

	Kit.New("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Overlay,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Parent = root,
	})
	self.Title = Kit.Label({
		Text = "LEVEL UP",
		Size = UDim2.fromOffset(600, 48),
		Position = UDim2.new(0.5, 0, 0.5, -(CARD_H / 2 + 86)),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = F.Title,
		MaxTextSize = 44,
		Parent = root,
	})
	self.Sub = Kit.Label({
		Text = "Choose one",
		Size = UDim2.fromOffset(600, 22),
		Position = UDim2.new(0.5, 0, 0.5, -(CARD_H / 2 + 36)),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = F.Medium,
		MaxTextSize = 17,
		TextColor3 = C.TextDim,
		Parent = root,
	})
	self.Cards = Kit.New("Frame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(1000, CARD_H + 20),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = root,
	})
	Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 16),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = self.Cards,
	})
	local buttons = Kit.New("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(372, 44),
		Position = UDim2.new(0.5, 0, 0.5, CARD_H / 2 + 34),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = root,
	})
	local reroll, rerollLabel = Kit.Button({
		Name = "Reroll",
		Text = "REROLL",
		Size = UDim2.fromOffset(180, 44),
		Color = C.Neutral,
		TextSize = 16,
		OnClick = function()
			self:Reroll()
		end,
		Parent = buttons,
	})
	self.RerollLabel = rerollLabel
	self.RerollButton = reroll
	Kit.Button({
		Name = "Skip",
		Text = "SKIP  +" .. GameConfig.LevelUp.SkipCoins .. " COINS",
		Size = UDim2.fromOffset(180, 44),
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Color = C.Neutral,
		TextSize = 16,
		OnClick = function()
			if not self.Busy then
				self:Lock()
				self.C.ClientData:Fire("Skip")
			end
		end,
		Parent = buttons,
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
	if card.Type == "Evolution" then
		return "EVOLUTION", C.Mythic
	elseif card.New then
		return "NEW", C.Accent
	elseif card.Level then
		return "LV " .. card.Level, C.TextDim
	end
	return "", C.TextDim
end

local function iconFor(parent: Instance, card, size: number)
	local props = { Position = UDim2.new(0.5, 0, 0, 44), AnchorPoint = Vector2.new(0.5, 0) }
	if card.Type == "Weapon" or card.Type == "WeaponLevel" then
		return Icons.Make(parent, "Weapon", card.Key, size, props)
	elseif card.Type == "Evolution" then
		return Icons.Make(parent, "Weapon", string.sub(card.Id, 3), size, props)
	elseif card.Type == "Passive" then
		return Icons.Make(parent, "Stat", card.Key, math.floor(size * 0.8), props)
	end
	return Icons.Make(parent, "Filler", card.Key or "", math.floor(size * 0.8), props)
end

local RARE_TIERS = { Rare = true, Epic = true, Legendary = true, Mythic = true, Secret = true }

function LevelUpController:BuildCard(card, index: number, _count: number)
	local rare = RARE_TIERS[card.Rarity] == true
	local rarity = Theme.Rarity[card.Rarity] or Theme.Rarity.Common
	local button = Kit.New("TextButton", {
		Name = "Card" .. index,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundColor3 = if rare then rarity:Lerp(C.Surface, 0.82) else C.Surface,
		BackgroundTransparency = Theme.GlassStrong,
		LayoutOrder = index,
		Parent = self.Cards,
	})
	Kit.Corner(button, 16)
	local stroke = Kit.Stroke(button, if rare then 2.5 else 1.5, rarity, if rare then 0.1 else 0.55)
	local scale = Kit.New("UIScale", { Parent = button })

	if not Kit.IsTouch() then
		Kit.Label({
			Name = "Key",
			Text = tostring(index),
			Size = UDim2.fromOffset(22, 22),
			Position = UDim2.fromOffset(12, 12),
			Font = F.Bold,
			MaxTextSize = 13,
			TextColor3 = C.TextMuted,
			BackgroundTransparency = 0.6,
			BackgroundColor3 = C.SurfaceDark,
			Parent = button,
		})
	end
	local tagText, tagColor = tagFor(card)
	if tagText ~= "" then
		local tag = Widgets.Tag(button, tagText, tagColor, UDim2.new(1, -12, 0, 12), UDim2.fromOffset(0, 22), 12)
		tag.AnchorPoint = Vector2.new(1, 0)
	end
	iconFor(button, card, 96)
	-- rarity word under the icon (colour + word: readable for colour blind players too)
	Kit.Label({
		Name = "Rarity",
		Text = string.upper(if card.Type == "Evolution" then "Mythic" else card.Rarity or "Common"),
		Size = UDim2.new(1, -24, 0, 14),
		Position = UDim2.fromOffset(12, 142),
		Font = F.Bold,
		TextScaled = false,
		TextSize = 12,
		TextColor3 = rarity,
		Parent = button,
	})
	Kit.Label({
		Name = "CardTitle",
		Text = card.Title,
		Size = UDim2.new(1, -24, 0, 26),
		Position = UDim2.fromOffset(12, 160),
		Font = F.Title,
		MaxTextSize = 21,
		TextColor3 = if rare then rarity:Lerp(Color3.new(1, 1, 1), 0.3) else C.Text,
		Parent = button,
	})
	local hint = if card.Type == "Evolution" then card.Evolves elseif card.Evolves then "Completes: " .. card.Evolves else nil
	if hint then
		Kit.Label({
			Name = "Hint",
			Text = hint,
			Size = UDim2.new(1, -24, 0, 16),
			Position = UDim2.new(0, 12, 1, -26),
			Font = F.Bold,
			TextScaled = false,
			TextSize = 13,
			TextColor3 = C.Mythic,
			Parent = button,
		})
	end
	-- one line of numbers under the text: the ability's stats, its level, the passive's stack
	local info = ""
	if card.Type == "Weapon" then
		local def = WeaponData.ByKey[card.Key]
		info = if def then Cards.WeaponStats(def) else ""
	elseif (card.Type == "WeaponLevel" or card.Type == "Passive") and card.Level and card.MaxLevel then
		info = string.format("%s %d / %d", if card.Type == "Passive" then "Stack" else "Level", card.Level, card.MaxLevel)
	end
	if info ~= "" and not hint then
		Kit.Label({
			Name = "Info",
			Text = info,
			Size = UDim2.new(1, -24, 0, 16),
			Position = UDim2.new(0, 12, 1, -26),
			Font = F.Bold,
			TextScaled = false,
			TextSize = 13,
			TextColor3 = rarity:Lerp(Color3.new(1, 1, 1), 0.45),
			Parent = button,
		})
	end
	-- (the EVOLUTION tag already says it: the text starts with what it does)
	local desc = if card.Type == "Evolution" then (string.gsub(card.Desc or "", "^Evolution%.%s*", "")) else card.Desc
	Kit.Label({
		Name = "Desc",
		Text = desc,
		Size = UDim2.new(1, -32, 0, if hint or info ~= "" then 46 else 64),
		Position = UDim2.fromOffset(16, 194),
		Font = F.Medium,
		TextScaled = false, -- a fixed 15 px, never shrunk
		TextSize = 15,
		TextColor3 = C.TextDim,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = button,
	})

	-- hover: lift a little, brighter border
	button.MouseEnter:Connect(function()
		Kit.Tween(scale, 0.12, { Scale = 1.05 })
		stroke.Transparency = 0
		self.C.SoundController:Play("CardHover")
	end)
	button.MouseLeave:Connect(function()
		Kit.Tween(scale, 0.15, { Scale = 1 })
		stroke.Transparency = if rare then 0.1 else 0.55
	end)
	button.Activated:Connect(function()
		self:Pick(index)
	end)

	-- soft staggered appear
	scale.Scale = 0.9
	task.delay(0.05 * index, function()
		Kit.Tween(scale, 0.22, { Scale = 1 })
	end)
	if rare then
		task.delay(0.05 * index + 0.15, function()
			self.C.SoundController:Play(if card.Type == "Evolution" then "Evolve" else "Rare")
		end)
	end
end

function LevelUpController:Show(offer)
	self.Offer = offer
	self.Busy = false
	Widgets.Clear(self.Cards)
	local chest = offer.Kind == "Chest" or offer.Kind == "Chest67"
	self.Title.Text = if offer.Kind == "Chest67" then "67 CHEST" elseif chest then "TREASURE" else "LEVEL UP"
	self.Title.TextColor3 = if chest then C.Gold else C.Text
	self.Sub.Text = if offer.Kind == "Chest67" then "Golden chest: rare cards are much more likely"
		elseif chest then "A chest! Pick your reward"
		else "Level " .. tostring(offer.Level) .. "  ·  choose one"
	for i, card in offer.Cards do
		self:BuildCard(card, i, #offer.Cards)
	end
	local rerolls = offer.Rerolls or 0
	self.RerollLabel.Text = if rerolls > 0 then "REROLL (" .. tostring(rerolls) .. ")" else "+1 REROLL"
	self.RerollLabel.TextColor3 = C.Text
	local wasOpen = self.Gui.Enabled
	self.Gui.Enabled = true
	if not wasOpen then
		Kit.Appear(self.Title)
		Kit.Blur("levelup", 10)
		self.C.HudController:SetCovered(true)
		self.C.SoundController:Play(if chest then "Chest" else "LevelUp")
		self.C.BannerController:Hide(true)
	end
	self.C.HudController:TogglePauseMenuOff()
end

function LevelUpController:Hide()
	if self.Gui.Enabled then
		Kit.Blur("levelup", 0)
		self.C.HudController:SetCovered(false)
	end
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
	if not offer or self.Busy then
		return
	end
	if (offer.Rerolls or 0) <= 0 then
		-- out of rerolls: offer one more (Extra Reroll product). Nothing happens unless bought.
		self.C.ClientData:Fire("Buy", "Product", "ExtraReroll")
		return
	end
	self:Lock()
	self.C.SoundController:Play("Reroll")
	self.C.ClientData:Fire("Reroll")
end

function LevelUpController:Start() end

return LevelUpController
