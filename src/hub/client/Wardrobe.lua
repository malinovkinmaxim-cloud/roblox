-- Wardrobe panel: pick a buddy (class) and a colour skin. Buddies cost Paws only;
-- skins cost Paws and some can also be bought for Robux if a product ID is configured.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Buddies = require(Shared:WaitForChild("Buddies"))
local Config = require(Shared:WaitForChild("Config"))
local UiStyle = require(Shared:WaitForChild("UiStyle"))

local C = UiStyle.colors
local F = UiStyle.fonts

local Wardrobe = {}

local function split(value)
	return string.split(value or "", ",")
end

function Wardrobe.new(gui, player, shopRemote)
	local bodyFrame, panel = UiStyle.card(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(600, 530),
		Visible = false,
	})
	local scale = Instance.new("UIScale")
	scale.Parent = panel

	UiStyle.text(bodyFrame, {
		Position = UDim2.fromOffset(20, 12),
		Size = UDim2.fromOffset(300, 40),
		TextSize = 32,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Wardrobe",
	})
	local starsLabel = UiStyle.text(bodyFrame, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -76, 0, 16),
		Size = UDim2.fromOffset(160, 32),
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local close = UiStyle.button(bodyFrame, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 12),
		Size = UDim2.fromOffset(46, 46),
	}, "✕")
	close.Activated:Connect(function()
		panel.Visible = false
	end)

	local function sectionTitle(text, y)
		UiStyle.text(bodyFrame, {
			Position = UDim2.fromOffset(20, y),
			Size = UDim2.new(1, -40, 0, 24),
			FontFace = F.bold,
			TextSize = 18,
			TextColor3 = C.muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = text,
		})
	end

	local function row(y, height)
		local frame = Instance.new("Frame")
		frame.BackgroundTransparency = 1
		frame.Position = UDim2.fromOffset(16, y)
		frame.Size = UDim2.new(1, -32, 0, height)
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.Padding = UDim.new(0, 8)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = frame
		frame.Parent = bodyFrame
		return frame
	end

	local entries = {}

	local function itemCard(parent, order, width, kind, item, visual)
		local card = Instance.new("Frame")
		card.LayoutOrder = order
		card.Size = UDim2.new(0, width, 1, 0)
		card.BackgroundColor3 = C.paper
		UiStyle.corner(card, UDim.new(0, 12))
		local stroke = UiStyle.stroke(card, 2.5)
		card.Parent = parent
		visual(card)
		UiStyle.text(card, {
			Position = UDim2.new(0, 4, 0, 62),
			Size = UDim2.new(1, -8, 0, 22),
			TextSize = 17,
			Text = item.name,
		})
		local action = UiStyle.button(card, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -16, 0, 34),
		}, "")
		action.Activated:Connect(function()
			local owned = table.find(split(player:GetAttribute(if kind == "class" then "OwnedClasses" else "OwnedSkins")), item.id)
			shopRemote:FireServer(if owned then "select" else "buy", kind, item.id)
		end)
		local robux = nil
		local productId = if kind == "skin" then Config.SKIN_PRODUCTS[item.id] else nil
		if productId and productId ~= 0 then
			robux = UiStyle.button(card, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -6, 0, 6),
				Size = UDim2.fromOffset(40, 26),
			}, "R$", C.success, C.white)
			robux.Activated:Connect(function()
				shopRemote:FireServer("robux", kind, item.id)
			end)
		end
		table.insert(entries, { kind = kind, item = item, stroke = stroke, action = action, robux = robux })
	end

	sectionTitle("BUDDIES - they help the team, bought with Paws", 64)
	local classRow = row(92, 190)
	for i, id in Buddies.classOrder do
		local buddy = Buddies.classes[id]
		itemCard(classRow, i, 132, "class", buddy, function(card)
			UiStyle.text(card, {
				Position = UDim2.fromOffset(0, 8),
				Size = UDim2.new(1, 0, 0, 52),
				TextSize = 44,
				Text = buddy.emoji,
			})
			local description = UiStyle.text(card, {
				Position = UDim2.fromOffset(6, 86),
				Size = UDim2.new(1, -12, 0, 54),
				FontFace = F.bold,
				TextScaled = true,
				TextWrapped = true,
				TextColor3 = C.muted,
				Text = buddy.description,
			})
			local limit = Instance.new("UITextSizeConstraint")
			limit.MaxTextSize = 13
			limit.Parent = description
		end)
	end

	sectionTitle("COLOURS - just for looks", 294)
	local skinRow = row(322, 132)
	for i, id in Buddies.skinOrder do
		local skin = Buddies.skins[id]
		itemCard(skinRow, i, 84, "skin", skin, function(card)
			local swatch = Instance.new("Frame")
			swatch.AnchorPoint = Vector2.new(0.5, 0)
			swatch.Position = UDim2.new(0.5, 0, 0, 10)
			swatch.Size = UDim2.fromOffset(46, 46)
			swatch.BackgroundColor3 = skin.color or C.white
			UiStyle.corner(swatch, UDim.new(0.35, 0))
			UiStyle.stroke(swatch, 2.5)
			swatch.Parent = card
			if not skin.color then
				local gradient = Instance.new("UIGradient")
				local colors = {}
				for k, color in Config.PLAYER_COLORS do
					table.insert(colors, ColorSequenceKeypoint.new((k - 1) / (#Config.PLAYER_COLORS - 1), color))
				end
				gradient.Color = ColorSequence.new(colors)
				gradient.Parent = swatch
			end
		end)
	end

	if Config.PAW_PACK.productId ~= 0 then
		local pack = UiStyle.button(bodyFrame, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Size = UDim2.fromOffset(300, 40),
		}, `🐾 {Config.PAW_PACK.paws} Paws for Robux`, C.gold)
		pack.Activated:Connect(function()
			shopRemote:FireServer("robux", "skin", "pawPack")
		end)
	end

	local function refresh()
		local paws = player:GetAttribute("Paws") or 0
		starsLabel.Text = `🐾 {paws}`
		local ownedClasses = split(player:GetAttribute("OwnedClasses"))
		local ownedSkins = split(player:GetAttribute("OwnedSkins"))
		for _, entry in entries do
			local owned = table.find(if entry.kind == "class" then ownedClasses else ownedSkins, entry.item.id) ~= nil
			local selected = player:GetAttribute(if entry.kind == "class" then "Class" else "Skin") == entry.item.id
			if selected then
				entry.action.Text = "Selected"
				entry.action.BackgroundColor3 = C.success
				entry.action.TextColor3 = C.white
			elseif owned then
				entry.action.Text = "Select"
				entry.action.BackgroundColor3 = C.paper
				entry.action.TextColor3 = C.ink
			else
				entry.action.Text = `🐾 {entry.item.cost}`
				entry.action.BackgroundColor3 = if paws >= entry.item.cost then C.gold else C.paper
				entry.action.TextColor3 = if paws >= entry.item.cost then C.ink else C.muted
			end
			entry.stroke.Thickness = if selected then 4 else 2.5
			entry.stroke.Color = if selected then C.success else C.ink
			if entry.robux then
				entry.robux.Parent.Visible = not owned
			end
		end
	end
	for _, name in { "Paws", "OwnedClasses", "OwnedSkins", "Class", "Skin" } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	refresh()

	return {
		toggle = function()
			panel.Visible = not panel.Visible
			if panel.Visible then
				scale.Scale = 0.4
				TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end
		end,
	}
end

return Wardrobe
