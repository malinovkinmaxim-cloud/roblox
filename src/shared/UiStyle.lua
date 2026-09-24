-- Shared look for all UI: rounded cards with a thick ink outline and a soft drop shadow.
-- Nunito is used for text because it has Cyrillic glyphs (Fredoka One does not, and Roblox
-- would silently fall back to a plain default font for Russian text).
local TweenService = game:GetService("TweenService")

local UiStyle = {}

local NUNITO = Font.fromEnum(Enum.Font.Nunito).Family

UiStyle.fonts = {
	heavy = Font.new(NUNITO, Enum.FontWeight.Heavy),
	bold = Font.new(NUNITO, Enum.FontWeight.Bold),
	logo = Font.fromEnum(Enum.Font.FredokaOne), -- Latin-only, used for the game title and digits
}

UiStyle.colors = {
	ink = Color3.fromRGB(45, 45, 70),
	paper = Color3.fromRGB(255, 252, 245),
	white = Color3.new(1, 1, 1),
	muted = Color3.fromRGB(120, 118, 140),
	success = Color3.fromRGB(80, 195, 110),
	danger = Color3.fromRGB(240, 95, 95),
	info = Color3.fromRGB(95, 155, 240),
	gold = Color3.fromRGB(255, 200, 60),
}

local C = UiStyle.colors

function UiStyle.apply(instance, props)
	for key, value in props do
		instance[key] = value
	end
	return instance
end

function UiStyle.corner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0, 14)
	corner.Parent = parent
	return corner
end

function UiStyle.stroke(parent, thickness, color, mode)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or 3
	stroke.Color = color or C.ink
	stroke.ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent
	return stroke
end

function UiStyle.padding(parent, px)
	local padding = Instance.new("UIPadding")
	local u = UDim.new(0, px)
	padding.PaddingLeft, padding.PaddingRight, padding.PaddingTop, padding.PaddingBottom = u, u, u, u
	padding.Parent = parent
	return padding
end

function UiStyle.text(parent, props)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = UiStyle.fonts.heavy
	label.TextColor3 = C.ink
	label.TextSize = 20
	label.RichText = false
	UiStyle.apply(label, props or {})
	label.Parent = parent
	return label
end

-- White text with a thick ink outline, readable over any background
function UiStyle.outlinedText(parent, props, outline)
	local label = UiStyle.text(parent, props)
	label.TextColor3 = props.TextColor3 or C.white
	UiStyle.stroke(label, outline or 3, C.ink, Enum.ApplyStrokeMode.Contextual)
	return label
end

-- A rounded card with shadow. Layout props (Position, Size, AnchorPoint...) go on the returned
-- container; content goes into the returned body.
function UiStyle.card(parent, props, color)
	local container = Instance.new("Frame")
	container.BackgroundTransparency = 1
	UiStyle.apply(container, props or {})

	local radius = UDim.new(0, 16)
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BackgroundColor3 = C.ink
	shadow.BackgroundTransparency = 0.75
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Position = UDim2.fromOffset(0, 5)
	shadow.ZIndex = 0
	UiStyle.corner(shadow, radius)
	shadow.Parent = container

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundColor3 = color or C.paper
	body.Size = UDim2.fromScale(1, 1)
	body.ZIndex = 1
	UiStyle.corner(body, radius)
	UiStyle.stroke(body, 3)
	body.Parent = container

	container.Parent = parent
	return body, container
end

-- A chunky button that dips down while pressed
function UiStyle.button(parent, props, text, color, textColor)
	local container = Instance.new("Frame")
	container.BackgroundTransparency = 1
	UiStyle.apply(container, props or {})

	local radius = UDim.new(0.5, 0)
	local shadow = Instance.new("Frame")
	shadow.BackgroundColor3 = C.ink
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Position = UDim2.fromOffset(0, 5)
	shadow.ZIndex = 1
	UiStyle.corner(shadow, radius)
	shadow.Parent = container

	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.BackgroundColor3 = color or C.paper
	button.Size = UDim2.fromScale(1, 1)
	button.FontFace = UiStyle.fonts.heavy
	button.TextColor3 = textColor or C.ink
	button.TextScaled = true
	button.Text = text
	button.ZIndex = 2
	UiStyle.corner(button, radius)
	UiStyle.stroke(button, 3)
	local sizeLimit = Instance.new("UITextSizeConstraint")
	sizeLimit.MaxTextSize = 30
	sizeLimit.Parent = button
	local inner = Instance.new("UIPadding")
	inner.PaddingTop = UDim.new(0.18, 0)
	inner.PaddingBottom = UDim.new(0.18, 0)
	inner.PaddingLeft = UDim.new(0.12, 0)
	inner.PaddingRight = UDim.new(0.12, 0)
	inner.Parent = button
	button.Parent = container

	local tweenInfo = TweenInfo.new(0.08)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(button, tweenInfo, { Position = UDim2.fromOffset(0, 4) }):Play()
	end)
	local function release()
		TweenService:Create(button, tweenInfo, { Position = UDim2.fromOffset(0, 0) }):Play()
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)

	container.Parent = parent
	return button, container
end

-- A small rounded tag floating above something in the world
function UiStyle.worldTag(adornee, offset, text, color, textColor)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(84, 34)
	gui.StudsOffset = offset
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0

	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.BackgroundColor3 = color or C.paper
	pill.Size = UDim2.new(1, -6, 1, -6)
	pill.Position = UDim2.fromOffset(3, 3)
	UiStyle.corner(pill, UDim.new(0.5, 0))
	UiStyle.stroke(pill, 2.5)
	pill.Parent = gui

	local label = UiStyle.text(pill, {
		Size = UDim2.fromScale(1, 1),
		TextScaled = true,
		TextColor3 = textColor or C.ink,
		Text = text,
	})
	local inner = Instance.new("UIPadding")
	inner.PaddingTop = UDim.new(0.14, 0)
	inner.PaddingBottom = UDim.new(0.14, 0)
	inner.PaddingLeft = UDim.new(0.1, 0)
	inner.PaddingRight = UDim.new(0.1, 0)
	inner.Parent = label

	gui.Parent = adornee
	return label, gui
end

return UiStyle
