--[[
	Widgets - reusable UI pieces built on Kit:
	  Bar, Scroll, Clear, Row, Tag (chip), Mono (monogram badge icon), Coin / Gear / Lock / Pause
	  (icons drawn from frames: no image assets), Card, Tabs,
	  Screen (full-screen menu: one screen = one purpose), Window (compact modal).
]]

local TextService = game:GetService("TextService")

local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Widgets = {}

local C = Theme.Colors
local F = Theme.Fonts

export type Bar = { Frame: Frame, Fill: Frame, Label: TextLabel, Set: (self: Bar, fraction: number, text: string?) -> () }

-- Progress bar: dark track, solid fill, optional small text inside
function Widgets.Bar(parent: Instance, size: UDim2, position: UDim2, color: Color3, props: { [string]: any }?): Bar
	local frame = Kit.New("Frame", {
		Name = "Bar",
		Size = size,
		Position = position,
		BackgroundColor3 = C.SurfaceDark,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = parent,
	})
	if props then
		for k, v in props do
			(frame :: any)[k] = v
		end
	end
	Kit.Corner(frame, 8)
	Kit.Stroke(frame)
	local fill = Kit.New("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = frame,
	})
	Kit.Corner(fill, 8)
	Kit.New("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(215, 215, 215)),
		Rotation = 90,
		Parent = fill,
	})
	local label = Kit.Label({
		Name = "Label",
		Size = UDim2.new(1, -12, 1, -4),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Font = F.Bold,
		MaxTextSize = 16,
		StrokeThickness = 1,
		ZIndex = 3,
		Parent = frame,
	})
	local bar = { Frame = frame, Fill = fill, Label = label, Last = -1 }
	function bar.Set(self, fraction: number, text: string?)
		fraction = math.clamp(if fraction == fraction then fraction else 0, 0, 1)
		if math.abs(fraction - self.Last) > 0.001 then
			self.Last = fraction
			Kit.Tween(self.Fill, 0.15, { Size = UDim2.fromScale(math.max(fraction, 0.001), 1) })
		end
		if text then
			self.Label.Text = text
		end
	end
	return bar :: any
end

-- Vertical list or grid that grows its canvas automatically
function Widgets.Scroll(parent: Instance, grid: Vector2?, padding: number?): ScrollingFrame
	local scroll = Kit.New("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.TextMuted,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	})
	local pad = padding or 10
	if grid then
		Kit.New("UIGridLayout", {
			CellSize = UDim2.fromOffset(grid.X, grid.Y),
			CellPadding = UDim2.fromOffset(pad, pad),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Left, -- lines up with the tabs above
			Parent = scroll,
		})
	else
		Kit.New("UIListLayout", {
			Padding = UDim.new(0, pad),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Parent = scroll,
		})
	end
	Kit.New("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 10),
		Parent = scroll,
	})
	return scroll
end

-- Removes every GuiObject child (keeps layouts / paddings)
function Widgets.Clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function Widgets.Row(parent: Instance, height: number, order: number?, color: Color3?): Frame
	return Kit.Panel({
		Size = UDim2.new(1, -8, 0, height),
		BackgroundColor3 = color or C.SurfaceLight,
		LayoutOrder = order or 0,
		Radius = 12,
		Parent = parent,
	})
end

-- width of one line of text in pixels (TextService; a close estimate where it is missing)
function Widgets.TextWidth(text: string, size: number, font: Enum.Font): number
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(text, size, font, Vector2.new(4096, 1024))
	end)
	if ok and typeof(bounds) == "Vector2" then
		return bounds.X
	end
	return (utf8.len(text) or #text) * size * 0.62
end

local TAG_PAD = 9

-- a chip is as wide as its text + padding (never narrower than its minimum width)
local function fitTag(tag: TextLabel)
	local width = Widgets.TextWidth(tag.Text, tag.TextSize, tag.Font) + TAG_PAD * 2 + 4
	local minWidth = tonumber(tag:GetAttribute("MinWidth")) or 0
	tag.Size = UDim2.fromOffset(math.max(minWidth, math.ceil(width)), tag.Size.Y.Offset)
end

--[[
	Small rounded chip ("NEW", "LV 3", "RARE", "OWNED"): one line that is never cut or wrapped.
	Fixed text size (no TextScaled), no wrapping, the width follows the text (re-fitted when
	the text changes); AutomaticSize X stays on as a safety net.
	size: minimum width + height (default 0 x 22); textSize: default 12 (13 when taller).
]]
function Widgets.Tag(parent: Instance, text: string, color: Color3, position: UDim2, size: UDim2?, textSize: number?): TextLabel
	local height = if size then size.Y.Offset else 22
	local tag = Kit.New("TextLabel", {
		Name = "Tag",
		Text = text,
		Size = UDim2.fromOffset(0, height),
		Position = position,
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0.8,
		BackgroundColor3 = color,
		TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35),
		Font = F.Bold,
		TextSize = textSize or (if height >= 22 then 13 else 12),
		TextScaled = false,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = 5,
		Parent = parent,
	})
	tag:SetAttribute("MinWidth", if size then size.X.Offset else 0)
	Kit.Corner(tag, math.floor(height / 2))
	Kit.Stroke(tag, 1, color, 0.4)
	Kit.New("UIPadding", { PaddingLeft = UDim.new(0, TAG_PAD), PaddingRight = UDim.new(0, TAG_PAD), Parent = tag })
	fitTag(tag)
	tag:GetPropertyChangedSignal("Text"):Connect(function()
		fitTag(tag)
	end)
	tag:GetPropertyChangedSignal("TextSize"):Connect(function()
		fitTag(tag)
	end)
	return tag
end

-- Monogram badge icon: tinted rounded square with a short label ("DMG", "XP", "67%")
function Widgets.Mono(parent: Instance, text: string, color: Color3, size: number, props: { [string]: any }?): Frame
	local frame = Kit.New("Frame", {
		Name = "Mono",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Parent = parent,
	})
	if props then
		for k, v in props do
			(frame :: any)[k] = v
		end
	end
	Kit.Corner(frame, math.floor(size * 0.28))
	Kit.Stroke(frame, 1.5, color, 0.25)
	Kit.Label({
		Name = "Text",
		Text = text,
		Size = UDim2.fromScale(0.8, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Font = F.Title,
		MaxTextSize = math.max(8, math.floor(size * 0.4)),
		TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.3),
		Parent = frame,
	})
	return frame
end

-- simple drawn icons (frames only, no image assets) for the menu tiles
local function bar(parent: Instance, x: number, w: number, h: number, bottom: number, color: Color3)
	local f = Kit.New("Frame", {
		Size = UDim2.fromScale(w, h),
		Position = UDim2.fromScale(x, bottom),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = parent,
	})
	Kit.Corner(f, 2)
	return f
end

function Widgets.Glyph(parent: Instance, kind: string, size: number, color: Color3, props: { [string]: any }?): Frame
	local holder = Kit.New("Frame", { Name = "Glyph", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Parent = parent })
	if props then
		for k, v in props do
			(holder :: any)[k] = v
		end
	end
	if kind == "Podium" then
		bar(holder, 0.22, 0.26, 0.45, 0.85, color)
		bar(holder, 0.5, 0.26, 0.7, 0.85, color)
		bar(holder, 0.78, 0.26, 0.3, 0.85, color)
	elseif kind == "Chart" then
		for i, h in { 0.3, 0.5, 0.42, 0.72 } do
			bar(holder, 0.14 + (i - 1) * 0.24, 0.16, h, 0.85, color)
		end
	elseif kind == "Gear" then
		Widgets.Gear(holder, math.floor(size * 0.8), color, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
	elseif kind == "Ticket" then
		local ticket = Kit.New("Frame", {
			Size = UDim2.fromScale(0.86, 0.56),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = holder,
		})
		Kit.Corner(ticket, math.floor(size * 0.1))
		for _, x in { 0, 1 } do
			local notch = Kit.New("Frame", {
				Size = UDim2.fromScale(0.26, 0.26),
				Position = UDim2.fromScale(x, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = C.Surface,
				BorderSizePixel = 0,
				Parent = ticket,
			})
			Kit.Corner(notch, size)
		end
		Kit.Label({
			Text = "CODE",
			Size = UDim2.fromScale(0.62, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Font = F.Title,
			TextColor3 = C.Surface,
			Parent = ticket,
		})
	elseif kind == "Info" then
		local ring = Kit.New("Frame", {
			Size = UDim2.fromScale(0.8, 0.8),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Parent = holder,
		})
		Kit.Corner(ring, size)
		Kit.Stroke(ring, math.max(2, size * 0.08), color, 0)
		Kit.Label({ Text = "i", Size = UDim2.fromScale(0.5, 0.55), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Font = F.Title, TextColor3 = color, Parent = ring })
	elseif kind == "Book" then
		for _, x in { 0.27, 0.73 } do
			local page = Kit.New("Frame", {
				Size = UDim2.fromScale(0.42, 0.66),
				Position = UDim2.fromScale(x, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				Rotation = if x < 0.5 then -6 else 6,
				Parent = holder,
			})
			Kit.Corner(page, math.floor(size * 0.06))
		end
	elseif kind == "Flag" then
		bar(holder, 0.26, 0.08, 0.8, 0.9, color)
		local flag = Kit.New("Frame", {
			Size = UDim2.fromScale(0.5, 0.34),
			Position = UDim2.fromScale(0.3, 0.14),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = holder,
		})
		Kit.Corner(flag, math.floor(size * 0.05))
	elseif kind == "Fire" then
		local flame = Kit.New("Frame", {
			Size = UDim2.fromScale(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.48),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Rotation = 45,
			Parent = holder,
		})
		Kit.Corner(flame, math.floor(size * 0.12))
		bar(holder, 0.5, 0.7, 0.1, 0.9, color)
	elseif kind == "People" then
		for _, x in { 0.32, 0.68 } do
			local head = Kit.New("Frame", {
				Size = UDim2.fromScale(0.26, 0.26),
				Position = UDim2.fromScale(x, 0.3),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				Parent = holder,
			})
			Kit.Corner(head, size)
			local body = Kit.New("Frame", {
				Size = UDim2.fromScale(0.36, 0.34),
				Position = UDim2.fromScale(x, 0.68),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				Parent = holder,
			})
			Kit.Corner(body, math.floor(size * 0.12))
		end
	else -- Star
		Kit.Label({ Text = "★", Size = UDim2.fromScale(0.95, 0.95), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Font = F.Title, TextColor3 = color, Parent = holder })
	end
	return holder
end

-- Coin icon drawn from frames (no image asset needed)
function Widgets.Coin(parent: Instance, size: number, props: { [string]: any }?): Frame
	local coin = Kit.New("Frame", {
		Name = "Coin",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = C.Gold,
		BorderSizePixel = 0,
		Parent = parent,
	})
	if props then
		for k, v in props do
			(coin :: any)[k] = v
		end
	end
	Kit.Corner(coin, size)
	Kit.Stroke(coin, math.max(1, size * 0.1), C.GoldDark, 0)
	local inner = Kit.New("Frame", {
		Size = UDim2.fromScale(0.45, 0.45),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.GoldDark,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Parent = coin,
	})
	Kit.Corner(inner, size)
	return coin
end

-- Fragment icon: a small purple crystal (a rotated square with a shine)
function Widgets.Fragment(parent: Instance, size: number, props: { [string]: any }?): Frame
	local holder = Kit.New("Frame", {
		Name = "Fragment",
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	if props then
		for k, v in props do
			(holder :: any)[k] = v
		end
	end
	local gem = Kit.New("Frame", {
		Name = "Gem",
		Size = UDim2.fromScale(0.68, 0.68),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 45,
		BackgroundColor3 = C.Fragment,
		BorderSizePixel = 0,
		Parent = holder,
	})
	Kit.Corner(gem, math.floor(size * 0.12))
	Kit.Stroke(gem, math.max(1, size * 0.08), C.Fragment:Lerp(Color3.new(0, 0, 0), 0.35), 0)
	Kit.New("Frame", {
		Name = "Shine",
		Size = UDim2.fromScale(0.3, 0.3),
		Position = UDim2.fromScale(0.28, 0.28),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Parent = gem,
	})
	return holder
end

-- CHIPS icon (the currency of premium items / boss relics): a cyan poker chip with a 67 notch
Widgets.ChipColor = Color3.fromRGB(90, 220, 255)
function Widgets.Chip(parent: Instance, size: number, props: { [string]: any }?): Frame
	local chip = Kit.New("Frame", {
		Name = "Chip",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Widgets.ChipColor,
		BorderSizePixel = 0,
		Parent = parent,
	})
	if props then
		for k, v in props do
			(chip :: any)[k] = v
		end
	end
	Kit.Corner(chip, size)
	Kit.Stroke(chip, math.max(1, size * 0.12), Color3.fromRGB(20, 90, 140), 0)
	local ring = Kit.New("Frame", {
		Size = UDim2.fromScale(0.6, 0.6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = chip,
	})
	Kit.Corner(ring, size)
	Kit.Stroke(ring, math.max(1, size * 0.08), Color3.new(1, 1, 1), 0.2)
	return chip
end

-- Price chip for fragment costs (like Widgets.Price for coins)
function Widgets.FragmentPrice(parent: Instance, amount: number, props: { [string]: any }?): Frame
	local chip = Kit.New("Frame", {
		Name = "FragmentPrice",
		Size = UDim2.fromOffset(78, 22),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	if props then
		for k, v in props do
			(chip :: any)[k] = v
		end
	end
	Widgets.Fragment(chip, 18, { Position = UDim2.new(0, 0, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
	Kit.Label({
		Name = "Amount",
		Text = Widgets.Commas(amount),
		Size = UDim2.new(1, -22, 1, 0),
		Position = UDim2.fromOffset(22, 0),
		Font = F.Bold,
		MaxTextSize = 15,
		TextColor3 = C.Fragment,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = chip,
	})
	return chip
end

-- Gear icon: a ring with 8 teeth
function Widgets.Gear(parent: Instance, size: number, color: Color3?, props: { [string]: any }?): Frame
	local holder = Kit.New("Frame", {
		Name = "Gear",
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	if props then
		for k, v in props do
			(holder :: any)[k] = v
		end
	end
	local col = color or C.Text
	for i = 0, 3 do
		local tooth = Kit.New("Frame", {
			Size = UDim2.fromScale(0.22, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = i * 45,
			BackgroundColor3 = col,
			BorderSizePixel = 0,
			Parent = holder,
		})
		Kit.Corner(tooth, 2)
	end
	local ring = Kit.New("Frame", {
		Size = UDim2.fromScale(0.72, 0.72),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = col,
		BorderSizePixel = 0,
		Parent = holder,
	})
	Kit.Corner(ring, size)
	local hole = Kit.New("Frame", {
		Size = UDim2.fromScale(0.36, 0.36),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.SurfaceLight,
		BorderSizePixel = 0,
		Parent = holder,
	})
	Kit.Corner(hole, size)
	return holder
end

-- Padlock icon
function Widgets.Lock(parent: Instance, size: number, color: Color3?, props: { [string]: any }?): Frame
	local holder = Kit.New("Frame", {
		Name = "Lock",
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	if props then
		for k, v in props do
			(holder :: any)[k] = v
		end
	end
	local col = color or C.TextDim
	local shackle = Kit.New("Frame", {
		Size = UDim2.fromScale(0.56, 0.6),
		Position = UDim2.fromScale(0.5, 0.05),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	Kit.Corner(shackle, size)
	Kit.Stroke(shackle, math.max(1.5, size * 0.1), col, 0)
	local body = Kit.New("Frame", {
		Size = UDim2.fromScale(0.8, 0.52),
		Position = UDim2.fromScale(0.5, 1),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = col,
		BorderSizePixel = 0,
		Parent = holder,
	})
	Kit.Corner(body, math.floor(size * 0.12))
	return holder
end

-- Pause icon: two bars
function Widgets.Pause(parent: Instance, size: number, props: { [string]: any }?): Frame
	local holder = Kit.New("Frame", { Name = "PauseIcon", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Parent = parent })
	if props then
		for k, v in props do
			(holder :: any)[k] = v
		end
	end
	for _, x in { 0.3, 0.7 } do
		local bar = Kit.New("Frame", {
			Size = UDim2.fromScale(0.2, 0.8),
			Position = UDim2.fromScale(x, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = C.Text,
			BorderSizePixel = 0,
			Parent = holder,
		})
		Kit.Corner(bar, 3)
	end
	return holder
end

-- Clickable card: glass surface, soft border, lifts under the mouse
function Widgets.Card(parent: Instance, size: UDim2, order: number?, name: string?): TextButton
	local card = Kit.New("TextButton", {
		Name = name or "Card",
		Text = "",
		AutoButtonColor = false,
		Size = size,
		BackgroundColor3 = C.SurfaceLight,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		LayoutOrder = order or 0,
		Parent = parent,
	})
	Kit.Corner(card, 16)
	Kit.Stroke(card)
	-- a small lift (3%), no bounce, and the hovered card is drawn above its neighbours
	Kit.Interactive(card, 1.03, true)
	card.MouseEnter:Connect(function()
		card.ZIndex = 3
	end)
	card.MouseLeave:Connect(function()
		card.ZIndex = 1
	end)
	return card
end

-- Closing "x" button (neutral, square)
function Widgets.CloseButton(parent: Instance, onClick: () -> ()): TextButton
	local button = Kit.Button({
		Name = "Close",
		Text = "×",
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		Color = C.Neutral,
		TextSize = 30,
		OnClick = onClick,
		Parent = parent,
	})
	return button
end

export type Tabs = { Frame: Frame, Buttons: { [string]: TextButton }, Select: (name: string) -> (), Current: string }

-- Pill tabs; onSelect(name) when changed
function Widgets.Tabs(parent: Instance, names: { string }, labels: { [string]: string }?, onSelect: (string) -> ()): Tabs
	local tabW = if #names > 5 then 132 else 150 -- (6 tabs still leave room for a wallet)
	local bar = Kit.New("Frame", {
		Name = "Tabs",
		BackgroundColor3 = C.SurfaceDark,
		BackgroundTransparency = 0.35,
		Size = UDim2.fromOffset(#names * tabW + 8, 44),
		Parent = parent,
	})
	Kit.Corner(bar, 22)
	Kit.Stroke(bar)
	Kit.Padding(bar, 4)
	Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = bar,
	})
	local tabs: Tabs = { Frame = bar, Buttons = {}, Current = names[1], Select = function() end }
	for i, name in names do
		local button = Kit.New("TextButton", {
			Name = name,
			Text = (labels and labels[name]) or name,
			AutoButtonColor = false,
			Font = F.Bold,
			TextSize = 15,
			TextColor3 = C.TextDim,
			BackgroundColor3 = C.Accent,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(tabW, 36),
			LayoutOrder = i,
			Parent = bar,
		})
		Kit.Corner(button, 18)
		tabs.Buttons[name] = button
		button.Activated:Connect(function()
			if Kit.ClickSound then
				Kit.ClickSound()
			end
			tabs.Select(name)
			onSelect(name)
		end)
	end
	function tabs.Select(name: string)
		tabs.Current = name
		for n, b in tabs.Buttons do
			local on = n == name
			b.BackgroundTransparency = if on then 0 else 1
			b.TextColor3 = if on then C.Text else C.TextDim
		end
	end
	tabs.Select(names[1])
	return tabs
end

export type Screen = { Frame: Frame, Body: Frame, Title: TextLabel, Header: Frame }

--[[
	Full-screen menu (Characters, Weapons, Shop...): dark see-through backdrop, title on the
	left, close on the right, content inside safe margins. The caller blurs the world.
]]
function Widgets.Screen(parent: Instance, title: string, onClose: () -> ()): Screen
	local frame = Kit.New("Frame", {
		Name = title,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Overlay,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 2,
		Parent = parent,
	})
	local inner = Kit.New("Frame", {
		Name = "Inner",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
	})
	Kit.New("UIPadding", {
		PaddingTop = UDim.new(0, Theme.Margin),
		PaddingBottom = UDim.new(0, Theme.Margin),
		PaddingLeft = UDim.new(0, Theme.Margin + 12),
		PaddingRight = UDim.new(0, Theme.Margin + 12),
		Parent = inner,
	})
	local header = Kit.New("Frame", { Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), Parent = inner })
	local titleLabel = Kit.Label({
		Name = "Title",
		Text = title,
		Size = UDim2.new(0.6, 0, 0, 40),
		Position = UDim2.fromScale(0, 0.5),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = F.Title,
		MaxTextSize = Theme.Text.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})
	Widgets.CloseButton(header, onClose)
	local body = Kit.New("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -64),
		Position = UDim2.fromOffset(0, 64),
		Parent = inner,
	})
	return { Frame = frame, Body = body, Title = titleLabel, Header = header }
end

export type Window = { Frame: TextButton, Fit: Frame, Panel: Frame, Body: Frame, Title: TextLabel, Height: number }

-- Compact centred window over a dimmed backdrop; clicking the backdrop closes it
function Widgets.Window(parent: Instance, title: string, size: Vector2, onClose: () -> ()): Window
	local backdrop = Kit.New("TextButton", {
		Name = title,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Overlay,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 2,
		Parent = parent,
	})
	backdrop.Activated:Connect(onClose)
	-- the window shrinks as a whole on short screens (see Widgets.Fit)
	local fit = Kit.New("Frame", {
		Name = "Fit",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = backdrop,
	})
	Kit.New("UIScale", { Name = "FitScale", Parent = fit })
	local panel = Kit.New("TextButton", { -- a button so clicks inside do not reach the backdrop
		Name = "Panel",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = Theme.GlassStrong,
		BorderSizePixel = 0,
		Parent = fit,
	})
	Kit.Corner(panel, 20)
	Kit.Stroke(panel)
	local titleLabel = Kit.Label({
		Name = "Title",
		Text = title,
		Size = UDim2.new(1, -120, 0, 34),
		Position = UDim2.fromOffset(24, 18),
		Font = F.Title,
		MaxTextSize = Theme.Text.Heading + 4,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	local close = Widgets.CloseButton(panel, onClose)
	close.Position = UDim2.new(1, -14, 0, 14)
	local body = Kit.New("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -48, 1, -88),
		Position = UDim2.fromOffset(24, 70),
		Parent = panel,
	})
	return { Frame = backdrop, Fit = fit, Panel = panel, Body = body, Title = titleLabel, Height = size.Y }
end

-- shrink a fit frame (a window, the results panel) so it stays on a short screen
function Widgets.Fit(fit: Frame, height: number)
	local scale = fit:FindFirstChild("FitScale") :: UIScale?
	if scale then
		scale.Scale = Kit.FitScale(height)
	end
end

-- A small hint box under `target` while the mouse is over it (right-aligned to the target, so
-- it stays on screen near the right edge). Returns the box.
function Widgets.Tooltip(target: GuiObject, text: string, width: number?): Frame
	local box = Kit.Panel({
		Name = "Tooltip",
		Size = UDim2.fromOffset(width or 260, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(1, 0, 1, 8),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = Theme.GlassStrong,
		Visible = false,
		ZIndex = 20,
		Radius = 12,
		Parent = target,
	})
	Kit.Padding(box, 12, 10)
	Kit.Label({
		Name = "Text",
		Text = text,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextScaled = false,
		TextSize = 14,
		TextWrapped = true,
		Font = F.Medium,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 21,
		Parent = box,
	})
	target.MouseEnter:Connect(function()
		box.Visible = true
	end)
	target.MouseLeave:Connect(function()
		box.Visible = false
	end)
	return box
end

-- Small grey caps caption ("DAILY QUEST", "PERK")
function Widgets.Caption(parent: Instance, text: string, position: UDim2, width: number?): TextLabel
	return Kit.Label({
		Name = "Caption",
		Text = text,
		Size = UDim2.new(0, width or 200, 0, 16),
		Position = position,
		Font = F.Bold,
		TextColor3 = C.TextMuted,
		MaxTextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	})
end

-- Shows "coin icon + amount" (or a fragment icon: currency "Fragment") on a Kit.Button
-- instead of its text; cost = nil shows the text again
function Widgets.Price(button: GuiObject, cost: number?, currency: string?)
	local label = button:FindFirstChild("Label") :: TextLabel?
	local price = button:FindFirstChild("Price") :: Frame?
	local kind = currency or "Coin"
	if price and price:GetAttribute("Currency") ~= kind then
		price:Destroy()
		price = nil
	end
	if not price then
		local frame = Kit.New("Frame", { Name = "Price", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = button })
		frame:SetAttribute("Currency", kind)
		Kit.New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = frame,
		})
		if kind == "Fragment" then
			Widgets.Fragment(frame, 18, { LayoutOrder = 1 })
		elseif kind == "Chip" then
			Widgets.Chip(frame, 18, { LayoutOrder = 1 })
		else
			Widgets.Coin(frame, 18, { LayoutOrder = 1 })
		end
		Kit.New("TextLabel", {
			Name = "Amount",
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			Font = F.Bold,
			TextSize = 17,
			TextColor3 = C.Text,
			Text = "",
			LayoutOrder = 2,
			Parent = frame,
		})
		price = frame
	end
	assert(price)
	price.Visible = cost ~= nil
	if label then
		label.Visible = cost == nil
	end
	if cost then
		(price:FindFirstChild("Amount") :: TextLabel).Text = Widgets.Commas(cost)
	end
end

export type Toggle = { Frame: TextButton, Set: (on: boolean) -> () }

-- On / off switch (pill with a knob); onChange(newValue)
function Widgets.Toggle(parent: Instance, position: UDim2, onChange: (boolean) -> ()): Toggle
	local frame = Kit.New("TextButton", {
		Name = "Toggle",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(58, 32),
		Position = position,
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = C.Neutral,
		Parent = parent,
	})
	Kit.Corner(frame, 16)
	Kit.Stroke(frame)
	local knob = Kit.New("Frame", {
		Name = "Knob",
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.new(0, 4, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = C.Text,
		Parent = frame,
	})
	Kit.Corner(knob, 12)
	local toggle = { Frame = frame, On = false, Set = function(_: boolean) end }
	function toggle.Set(on: boolean)
		toggle.On = on
		Kit.Tween(knob, 0.12, { Position = if on then UDim2.new(1, -28, 0.5, 0) else UDim2.new(0, 4, 0.5, 0) })
		frame.BackgroundColor3 = if on then C.Success else C.Neutral
	end
	frame.Activated:Connect(function()
		if Kit.ClickSound then
			Kit.ClickSound()
		end
		onChange(not toggle.On)
	end)
	return toggle :: any
end

-- Tiny status chip used on cards: LOCKED (red), OWNED (green), EQUIPPED (green, filled)
function Widgets.State(chip: TextLabel, state: string)
	chip.Visible = state ~= ""
	local color = if state == "LOCKED" then C.Danger else C.Success
	chip.Text = state
	chip.BackgroundColor3 = color
	chip.BackgroundTransparency = if state == "EQUIPPED" then 0.15 else 0.8
	chip.TextColor3 = if state == "EQUIPPED" then C.Text else color:Lerp(Color3.new(1, 1, 1), 0.35)
	local stroke = chip:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
	end
end

-- "1,234"
function Widgets.Commas(n: number): string
	local s = tostring(math.floor(n))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	return (string.gsub(out, "^,", ""))
end

-- kept for older call sites
function Widgets.CoinText(n: number): string
	return Widgets.Commas(n)
end

-- Square icon slot used by the HUD (icon holder + small level text underneath)
function Widgets.Slot(parent: Instance, size: number, order: number?): (Frame, TextLabel, TextLabel)
	local frame = Kit.Panel({
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = 0.3,
		LayoutOrder = order or 0,
		Radius = 10,
		Parent = parent,
	})
	local icon = Kit.Label({
		Name = "Icon",
		Size = UDim2.fromScale(0.7, 0.7),
		Position = UDim2.fromScale(0.15, 0.08),
		Text = "",
		Parent = frame,
	})
	local level = Kit.Label({
		Name = "Level",
		Size = UDim2.new(1, 0, 0.3, 0),
		Position = UDim2.fromScale(0, 0.72),
		Text = "",
		Font = F.Bold,
		StrokeThickness = 1,
		ZIndex = 3,
		Parent = frame,
	})
	return frame, icon, level
end

return Widgets
