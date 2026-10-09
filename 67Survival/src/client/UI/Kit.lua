--[[
	Kit - UI is built from code (no manual StarterGui work). Small helpers for a clean,
	modern look: flat surfaces, soft borders, semi-transparent "glass" panels, light hover /
	press animations, blur behind full-screen menus.

	Everything is laid out in design units (Theme.DesignSize) inside a root frame that is
	scaled with UIScale to fit any screen (phone, tablet, PC). Positions use Scale +
	AnchorPoint so elements stick to their screen region.
]]

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local Theme = require(script.Parent.Theme)

local Kit = {}

local C = Theme.Colors

Kit.ClickSound = nil :: (() -> ())?
Kit.HoverSound = nil :: (() -> ())?

function Kit.New(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Kit.Corner(parent: Instance, radius: number?): UICorner
	return Kit.New("UICorner", { CornerRadius = UDim.new(0, radius or 12), Parent = parent })
end

-- thin, soft border (white at high transparency by default)
function Kit.Stroke(parent: Instance, thickness: number?, color: Color3?, transparency: number?): UIStroke
	return Kit.New("UIStroke", {
		Thickness = thickness or 1.5,
		Color = color or C.Border,
		Transparency = transparency or (if color then 0 else Theme.BorderTransparency),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Kit.Gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	return Kit.New("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
		Parent = parent,
	})
end

function Kit.Padding(parent: Instance, px: number, py: number?)
	return Kit.New("UIPadding", {
		PaddingTop = UDim.new(0, py or px),
		PaddingBottom = UDim.new(0, py or px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		Parent = parent,
	})
end

--[[
	Text label. Extra props:
	  MaxTextSize     cap for scaled text (keeps text from getting huge)
	  StrokeThickness text outline (default none; HUD text over the world uses a soft one)
	  StrokeColor, StrokeTransparency
]]
function Kit.Label(props: { [string]: any }): TextLabel
	local label = Kit.New("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Bold,
		TextColor3 = C.Text,
		TextScaled = true,
		Text = "",
	})
	local extra = { MaxTextSize = true, StrokeThickness = true, StrokeColor = true, StrokeTransparency = true }
	for key, value in props do
		if not extra[key] then
			(label :: any)[key] = value
		end
	end
	if props.MaxTextSize then
		Kit.New("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize, Parent = label })
	end
	local stroke = props.StrokeThickness
	if stroke and stroke > 0 then
		Kit.New("UIStroke", {
			Thickness = stroke,
			Color = props.StrokeColor or C.SurfaceDark,
			Transparency = props.StrokeTransparency or 0.35,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			Parent = label,
		})
	end
	return label
end

function Kit.Tween(instance: Instance, duration: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(instance, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

-- A small bounce through the object's UIScale
function Kit.Pop(guiObject: GuiObject, amount: number?)
	local scale = guiObject:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Kit.New("UIScale", { Name = "PopScale", Parent = guiObject })
	end
	assert(scale)
	scale.Scale = 1 + (amount or 0.08)
	Kit.Tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- Fades a whole panel in (it and everything inside it, from invisible to how it was built)
local FADE_PROPS = {
	Frame = { "BackgroundTransparency" },
	TextLabel = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	TextButton = { "BackgroundTransparency", "TextTransparency" },
	ImageLabel = { "BackgroundTransparency", "ImageTransparency" },
	UIStroke = { "Transparency" },
}
function Kit.FadeIn(root: Instance, duration: number)
	local list = root:GetDescendants()
	table.insert(list, root)
	for _, obj in list do
		local props = FADE_PROPS[obj.ClassName]
		if props then
			local goal = {}
			for _, prop in props do
				local key = "Fade" .. prop
				local base = obj:GetAttribute(key)
				if base == nil then
					base = (obj :: any)[prop]
					obj:SetAttribute(key, base)
				end
				(obj :: any)[prop] = 1
				goal[prop] = base
			end
			Kit.Tween(obj, duration, goal, Enum.EasingStyle.Sine)
		end
	end
end

-- Soft appear: fade + slight grow
function Kit.Appear(guiObject: GuiObject)
	local scale = guiObject:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Kit.New("UIScale", { Name = "AppearScale", Parent = guiObject })
	end
	assert(scale)
	scale.Scale = 0.94
	Kit.Tween(scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Quad)
end

--[[
	Hover / press feedback on any GuiButton: grows a little under the mouse, dips when
	pressed. Uses one UIScale named "PressScale". calm = no bounce when released.
]]
function Kit.Interactive(button: GuiButton, hoverScale: number?, calm: boolean?)
	local scale = button:FindFirstChild("PressScale") :: UIScale?
	if not scale then
		scale = Kit.New("UIScale", { Name = "PressScale", Parent = button })
	end
	assert(scale)
	local hovered = false
	local up = hoverScale or 1.04
	button.MouseEnter:Connect(function()
		hovered = true
		Kit.Tween(scale, 0.12, { Scale = up })
		if Kit.HoverSound then
			Kit.HoverSound()
		end
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		Kit.Tween(scale, 0.15, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		Kit.Tween(scale, 0.07, { Scale = 0.96 })
	end)
	button.MouseButton1Up:Connect(function()
		-- calm: no bounce past the hover size (big cards in a grid must not touch their neighbours)
		Kit.Tween(scale, 0.15, { Scale = if hovered then up else 1 }, if calm then Enum.EasingStyle.Quad else Enum.EasingStyle.Back)
	end)
	return scale
end

export type ButtonOptions = {
	Text: string?,
	Color: Color3?,
	Dark: Color3?,
	TextColor: Color3?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Parent: Instance?,
	TextSize: number?,
	Font: Enum.Font?,
	Radius: number?,
	Name: string?,
	OnClick: (() -> ())?,
	LayoutOrder: number?,
}

-- Flat button: solid fill with a soft vertical sheen, thin border, bold label
function Kit.Button(options: ButtonOptions): (TextButton, TextLabel)
	local color = options.Color or C.Neutral
	local button = Kit.New("TextButton", {
		Name = options.Name or "Button",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = options.Size or UDim2.fromOffset(160, 48),
		Position = options.Position or UDim2.new(),
		AnchorPoint = options.AnchorPoint or Vector2.zero,
		Text = "",
		LayoutOrder = options.LayoutOrder or 0,
		Parent = options.Parent,
	})
	Kit.Corner(button, options.Radius or 12)
	Kit.Stroke(button, 1.5, Color3.new(1, 1, 1), 0.82)
	local gradient = Kit.Gradient(button, color:Lerp(Color3.new(1, 1, 1), 0.08), options.Dark or color:Lerp(Color3.new(0, 0, 0), 0.18))
	gradient.Name = "BodyGradient"
	local label = Kit.Label({
		Name = "Label",
		Size = UDim2.new(1, -20, 1, -12),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = options.Text or "",
		Font = options.Font or Theme.Fonts.Bold,
		TextColor3 = options.TextColor or C.Text,
		MaxTextSize = options.TextSize or Theme.Text.Button,
		Parent = button,
	})
	Kit.Interactive(button)
	if options.OnClick then
		local onClick = options.OnClick
		button.Activated:Connect(function()
			if Kit.ClickSound then
				Kit.ClickSound()
			end
			onClick()
		end)
	end
	return button, label
end

-- Recolour a Kit.Button (e.g. accent when affordable, neutral when not)
function Kit.SetButtonColor(button: GuiObject, color: Color3, dark: Color3?)
	local gradient = button:FindFirstChild("BodyGradient") :: UIGradient?
	if gradient then
		gradient.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.08), dark or color:Lerp(Color3.new(0, 0, 0), 0.18))
	end
end

-- Glass panel: dark, semi-transparent, soft border, rounded
function Kit.Panel(props: { [string]: any }): Frame
	local frame = Kit.New("Frame", {
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = Theme.Glass,
		BorderSizePixel = 0,
	})
	local parent = nil
	for key, value in props do
		if key == "Parent" then
			parent = value
		elseif key ~= "Radius" then
			(frame :: any)[key] = value
		end
	end
	Kit.Corner(frame, props.Radius or 14)
	Kit.Stroke(frame)
	frame.Parent = parent
	return frame
end

function Kit.ScreenGui(name: string, displayOrder: number, parent: Instance): (ScreenGui, Frame)
	local gui = Kit.New("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Parent = parent,
	})
	local root = Kit.New("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	Kit.Responsive(root)
	return gui, root
end

function Kit.IsTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- phones in landscape: a smaller design canvas, so text and buttons come out bigger
function Kit.Compact(viewport: Vector2): boolean
	return Kit.IsTouch() and viewport.Y < 500
end

-- UI scale for the current screen
function Kit.ScaleFor(viewport: Vector2, compact: boolean?): number
	local design = if compact then Theme.CompactDesignSize else Theme.DesignSize
	local scale = math.min(viewport.X / design.X, viewport.Y / design.Y)
	return math.clamp(scale, 0.55, 1.5)
end

-- the visible area in design units (updated by Kit.Responsive)
Kit.View = Theme.DesignSize

-- scale that makes something `height` design units tall fit on the screen with a margin
function Kit.FitScale(height: number): number
	return math.min(1, (Kit.View.Y - 32) / height)
end

-- Scales `root` so design units map to the screen; the root keeps covering the whole screen.
function Kit.Responsive(root: Frame)
	local uiScale = Kit.New("UIScale", { Parent = root })
	local function update()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local viewport = camera.ViewportSize
		local scale = Kit.ScaleFor(viewport, Kit.Compact(viewport))
		uiScale.Scale = scale
		root.Size = UDim2.fromScale(1 / scale, 1 / scale)
		Kit.View = Vector2.new(viewport.X / scale, viewport.Y / scale)
	end
	update()
	local function hook()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
		end
		update()
	end
	hook()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hook)
end

-- Background blur (full-screen menus). Counted, so nested menus do not fight.
local blurUsers = {}
local blurEffect: BlurEffect? = nil

function Kit.Blur(owner: string, size: number)
	if size > 0 then
		blurUsers[owner] = size
	else
		blurUsers[owner] = nil
	end
	local target = 0
	for _, s in blurUsers do
		target = math.max(target, s)
	end
	if not blurEffect then
		blurEffect = Kit.New("BlurEffect", { Name = "S67MenuBlur", Size = 0, Parent = Lighting })
	end
	Kit.Tween(blurEffect :: BlurEffect, 0.25, { Size = target })
end

return Kit
