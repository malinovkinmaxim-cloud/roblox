--[[
	Cards - the one card layout shared by the collection menus (characters, weapons, hats,
	upgrades, shop items), so every menu reads the same way:

	  picture (3D preview or monogram)
	  NAME
	  [RARITY] [STATE]
	  short description
	  [ ACTION ]

	Cards.Item(parent, options) -> ItemCard. Size comes from the parent grid cell.
	Cards.Set(card, state, buttonText?, buttonColor?, price?, currency?) updates the chip and the
	button: state "LOCKED" / "OWNED" / "EQUIPPED" / "" ; price -> coin (or fragment) icon +
	amount on the button;
	  buttonText = nil hides the button.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)
local AbilityConfig = require(ReplicatedStorage:WaitForChild("Modules").AbilityConfig)

local Cards = {}

local C = Theme.Colors
local F = Theme.Fonts

export type ItemOptions = {
	Name: string,
	Desc: string?,
	Rarity: string?,
	Order: number?,
	PictureHeight: number?,
	Side: boolean?, -- picture on the left of the name (compact cards)
	ButtonWidth: number?, -- small button bottom-right (the unlock hint sits on its left)
	Width: number?, -- the grid cell width: a long unlock hint under a wide button gets 2 lines
	RarityBorder: boolean?, -- a thin border in the rarity colour (abilities); Mythic: animated + a shine
	OnClick: (() -> ())?,
}

export type ItemCard = {
	Card: TextButton,
	Picture: Frame,
	Name: TextLabel,
	Rarity: TextLabel?,
	State: TextLabel,
	Desc: TextLabel,
	Need: TextLabel,
	Button: TextButton,
	ButtonLabel: TextLabel,
}

local function chip(parent: Instance, name: string, text: string, color: Color3, position: UDim2): TextLabel
	local tag = Widgets.Tag(parent, text, color, position, UDim2.fromOffset(0, 20), 12)
	tag.Name = name
	return tag
end

function Cards.Item(parent: Instance, options: ItemOptions): ItemCard
	local card = Widgets.Card(parent, UDim2.fromScale(1, 1), options.Order, options.Name)
	card.BackgroundColor3 = C.Surface
	card.BackgroundTransparency = Theme.Glass
	local rarityColor = if options.Rarity then Theme.Rarity[options.Rarity] or Theme.Rarity.Common else nil
	if options.RarityBorder and rarityColor then
		Cards.RarityBorder(card, options.Rarity :: string)
	end
	local pad = 12
	local side = options.Side == true
	local ph = options.PictureHeight or 120
	local small = options.ButtonWidth
	local buttonH = if small then 32 else 38

	-- picture well, softly tinted with the rarity colour
	local picture = Kit.New("Frame", {
		Name = "Picture",
		Size = if side then UDim2.fromOffset(ph, ph) else UDim2.new(1, -pad * 2, 0, ph),
		Position = UDim2.fromOffset(pad, pad),
		BackgroundColor3 = rarityColor or C.SurfaceLight,
		BackgroundTransparency = 0.86,
		Parent = card,
	})
	Kit.Corner(picture, 12)
	Kit.New("UIGradient", {
		Transparency = NumberSequence.new(0.2, 0.9),
		Rotation = 90,
		Parent = picture,
	})

	local textX = if side then pad + ph + 12 else pad
	local nameY = if side then pad + 2 else pad + ph + 10
	local name = Kit.Label({
		Name = "Title",
		Text = options.Name,
		Size = UDim2.new(1, -(textX + pad), 0, 22),
		Position = UDim2.fromOffset(textX, nameY),
		Font = F.Title,
		MaxTextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	-- chips: rarity + state. Side cards stack them under the name; cards without a rarity
	-- show the state as a badge on the picture, so the text moves up
	local overlay = not options.Rarity and not side
	local chips = Kit.New("Frame", {
		Name = "Chips",
		BackgroundTransparency = 1,
		Size = if overlay then UDim2.new(1, -16, 0, 20) else UDim2.new(1, -(textX + pad), 0, if side then 44 else 20),
		Position = if overlay then UDim2.new(1, -8, 0, 8) else UDim2.fromOffset(textX, nameY + 28),
		AnchorPoint = if overlay then Vector2.new(1, 0) else Vector2.zero,
		ZIndex = 4,
		Parent = if overlay then picture else card,
	})
	Kit.New("UIListLayout", {
		FillDirection = if side then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal,
		HorizontalAlignment = if overlay then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, if side then 4 else 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = chips,
	})
	local rarity = nil
	if options.Rarity and rarityColor then
		rarity = chip(chips, "Rarity", string.upper(options.Rarity), rarityColor, UDim2.new())
		rarity.LayoutOrder = 1
	end
	local state = chip(chips, "State", "", C.Success, UDim2.new())
	state.LayoutOrder = 2
	state.Visible = false

	local descY = if side then pad + ph + 10 elseif overlay then nameY + 30 else nameY + 56
	local bottom = buttonH + pad + 8 + (if small then 0 else 18)
	local desc = Kit.Label({
		Name = "Desc",
		Text = options.Desc or "",
		Size = UDim2.new(1, -pad * 2, 1, -(descY + bottom)),
		Position = UDim2.fromOffset(pad, descY),
		Font = F.Medium,
		TextScaled = false, -- a fixed 14 px: descriptions never shrink below readable
		TextSize = 14,
		TextWrapped = true,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})

	-- one short line about unlocking ("or achievement: Boss Slayer"): its own line under a
	-- wide button (the button moves up when there is one), or beside a small button
	local need = Kit.Label({
		Name = "Need",
		Text = "",
		Size = if small then UDim2.new(1, -(pad * 2 + small + 8), 0, 32) else UDim2.new(1, -pad * 2, 0, 32),
		Position = if small then UDim2.new(0, pad, 1, -pad) else UDim2.new(0, pad, 1, -5),
		AnchorPoint = Vector2.new(0, 1),
		Font = F.Medium,
		TextScaled = false,
		TextSize = 13,
		TextWrapped = true,
		TextYAlignment = if small then Enum.TextYAlignment.Center else Enum.TextYAlignment.Bottom,
		TextColor3 = C.TextMuted,
		TextXAlignment = if small then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		Parent = card,
	})

	local button, label = Kit.Button({
		Name = "Action",
		Text = "",
		Size = if small then UDim2.fromOffset(small, buttonH) else UDim2.new(1, -pad * 2, 0, buttonH),
		Position = if small then UDim2.new(1, -pad, 1, -pad) else UDim2.new(0, pad, 1, -pad),
		AnchorPoint = if small then Vector2.new(1, 1) else Vector2.new(0, 1),
		Color = C.Neutral,
		TextSize = if small then 14 else 16,
		OnClick = options.OnClick,
		Parent = card,
	})

	if not small then
		-- the button makes room for the hint: one line, or two when it is long
		local function place()
			local lift = 0
			if need.Text ~= "" then
				local long = options.Width ~= nil and Widgets.TextWidth(need.Text, need.TextSize, need.Font) > options.Width - pad * 2 - 4
				lift = if long then 30 else 16
			end
			button.Position = UDim2.new(0, pad, 1, -(pad + lift))
			need.Size = UDim2.new(1, -pad * 2, 0, math.max(16, lift))
			if lift > 16 then
				-- the description gives up the extra line a 2-line hint takes
				desc.Size = UDim2.new(1, -pad * 2, 1, -(descY + bottom + lift - 16))
			end
		end
		need:GetPropertyChangedSignal("Text"):Connect(place)
		place()
	end

	return {
		Card = card,
		Picture = picture,
		Name = name,
		Rarity = rarity,
		State = state,
		Desc = desc,
		Need = need,
		Button = button,
		ButtonLabel = label,
	}
end

-- a thin border in the rarity colour; a Mythic card's border is an animated pink -> cyan -> gold
-- gradient with a shine running round it (shared/AbilityConfig.lua MythicColors)
function Cards.RarityBorder(card: GuiObject, rarity: string)
	local stroke = card:FindFirstChildOfClass("UIStroke") or Kit.Stroke(card)
	if rarity == "Mythic" then
		local colors = AbilityConfig.MythicColors
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Thickness = 2.5
		stroke.Transparency = 0
		local gradient = Kit.New("UIGradient", {
			Name = "MythicShine",
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, colors[1]),
				ColorSequenceKeypoint.new(0.33, colors[2]),
				ColorSequenceKeypoint.new(0.45, Color3.new(1, 1, 1)), -- the shine
				ColorSequenceKeypoint.new(0.55, colors[2]),
				ColorSequenceKeypoint.new(0.75, colors[3]),
				ColorSequenceKeypoint.new(1, colors[1]),
			}),
			Parent = stroke,
		})
		TweenService:Create(gradient, TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 }):Play()
	else
		stroke.Color = Theme.Rarity[rarity] or Theme.Rarity.Common
		stroke.Thickness = 1.5
		stroke.Transparency = 0.3
	end
end

-- "12 damage x2 · every 0.85 s": what an ability does in numbers (its level 1 stats)
local function seconds(t: number): string
	local text = string.format("%.2f", t)
	text = string.gsub(text, "0+$", "")
	return (string.gsub(text, "%.$", ""))
end

function Cards.WeaponStats(def): string
	local base = def.Base or {}
	local parts = {}
	if base.Damage and base.Damage > 0 then
		local amount = if (base.Amount or 1) > 1 then string.format(" x%d", base.Amount) else ""
		table.insert(parts, string.format("%d damage%s", base.Damage, amount))
	end
	local every = base.Cooldown or base.HitCooldown
	if every and every > 0 then
		table.insert(parts, "every " .. seconds(every) .. " s")
	end
	return table.concat(parts, " · ")
end

function Cards.Set(card: ItemCard, state: string, buttonText: string?, buttonColor: Color3?, price: number?, currency: string?)
	Widgets.State(card.State, state)
	card.Need.Text = ""
	card.Button.Visible = buttonText ~= nil or price ~= nil
	card.ButtonLabel.Text = buttonText or ""
	Widgets.Price(card.Button, price, currency)
	Kit.SetButtonColor(card.Button, buttonColor or C.Neutral)
	card.Card.BackgroundColor3 = if state == "EQUIPPED" then C.SurfaceLight else C.Surface
	local stroke = card.Card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if state == "EQUIPPED" then C.Success else C.Border
		stroke.Transparency = if state == "EQUIPPED" then 0.3 else Theme.BorderTransparency
	end
end

return Cards
