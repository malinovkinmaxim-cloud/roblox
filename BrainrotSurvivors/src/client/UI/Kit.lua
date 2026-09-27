--[[
	Kit - UI is built from code (no manual StarterGui work). Small helpers for the
	"modern simulator" look: rounded corners, thick outlines, gradients, bouncy buttons.

	Everything is laid out in design units (Theme.DesignSize) inside a root frame that is
	scaled with UIScale to fit any screen (phone, tablet, PC).
]]

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)

local Kit = {}

Kit.ClickSound = nil :: (() -> ())?

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
	return Kit.New("UICorner", { CornerRadius = UDim.new(0, radius or 14), Parent = parent })
end

function Kit.Stroke(parent: Instance, thickness: number?, color: Color3?, transparency: number?): UIStroke
	return Kit.New("UIStroke", {
		Thickness = thickness or 3,
		Color = color or Theme.Colors.Outline,
		Transparency = transparency or 0,
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

function Kit.Padding(parent: Instance, px: number)
	return Kit.New("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		Parent = parent,
	})
end

-- Text label with outline stroke (readable over any background)
function Kit.Label(props: { [string]: any }): TextLabel
	local label = Kit.New("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Bold,
		TextColor3 = Theme.Colors.Text,
		TextScaled = true,
		Text = "",
	})
	local strokeThickness = props.StrokeThickness
	local strokeColor = props.StrokeColor
	for key, value in props do
		if key ~= "StrokeThickness" and key ~= "StrokeColor" then
			(label :: any)[key] = value
		end
	end
	if strokeThickness ~= 0 then
		Kit.New("UIStroke", {
			Thickness = strokeThickness or 2,
			Color = strokeColor or Theme.Colors.Outline,
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

-- Bounce a GuiObject through its UIScale (one UIScale per object: reuse the existing one)
function Kit.Pop(guiObject: GuiObject, amount: number?)
	local scale = guiObject:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Kit.New("UIScale", { Name = "PopScale", Parent = guiObject })
	end
	assert(scale)
	scale.Scale = 1 + (amount or 0.12)
	Kit.Tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

export type ButtonOptions = {
	Text: string?,
	Color: Color3?,
	Dark: Color3?,
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

-- Chunky simulator button: gradient body, dark outline, bounces when pressed
function Kit.Button(options: ButtonOptions): (TextButton, TextLabel)
	local color = options.Color or Theme.Colors.Green
	local dark = options.Dark or color:Lerp(Color3.new(0, 0, 0), 0.35)
	local button = Kit.New("TextButton", {
		Name = options.Name or "Button",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = options.Size or UDim2.fromOffset(160, 56),
		Position = options.Position or UDim2.new(),
		AnchorPoint = options.AnchorPoint or Vector2.zero,
		Text = "",
		LayoutOrder = options.LayoutOrder or 0,
		Parent = options.Parent,
	})
	Kit.Corner(button, options.Radius or 14)
	Kit.Stroke(button, 3)
	local gradient = Kit.Gradient(button, color:Lerp(Color3.new(1, 1, 1), 0.15), dark)
	local label = Kit.Label({
		Name = "Label",
		Size = UDim2.new(1, -12, 1, -8),
		Position = UDim2.fromOffset(6, 4),
		Text = options.Text or "",
		Font = options.Font or Theme.Fonts.Bold,
		Parent = button,
	})
	local scale = Kit.New("UIScale", { Name = "PressScale", Parent = button })
	button.MouseButton1Down:Connect(function()
		Kit.Tween(scale, 0.08, { Scale = 0.93 })
	end)
	local function release()
		Kit.Tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	if options.OnClick then
		local onClick = options.OnClick
		button.Activated:Connect(function()
			if Kit.ClickSound then
				Kit.ClickSound()
			end
			onClick()
		end)
	end
	gradient.Name = "BodyGradient"
	return button, label
end

-- Recolour a Kit.Button (e.g. green when affordable, gray when not)
function Kit.SetButtonColor(button: GuiObject, color: Color3, dark: Color3?)
	local gradient = button:FindFirstChild("BodyGradient") :: UIGradient?
	if gradient then
		gradient.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.15), dark or color:Lerp(Color3.new(0, 0, 0), 0.35))
	end
end

-- Rounded panel background
function Kit.Panel(props: { [string]: any }): Frame
	local frame = Kit.New("Frame", {
		BackgroundColor3 = Theme.Colors.Panel,
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
	Kit.Corner(frame, props.Radius or 16)
	Kit.Stroke(frame, 3)
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

-- UI scale for the current screen
function Kit.ScaleFor(viewport: Vector2): number
	local design = Theme.DesignSize
	local scale = math.min(viewport.X / design.X, viewport.Y / design.Y)
	return math.clamp(scale, 0.55, 1.5)
end

-- Scales `root` so design units map to the screen; the root keeps covering the whole screen.
function Kit.Responsive(root: Frame)
	local uiScale = Kit.New("UIScale", { Parent = root })
	local function update()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local scale = Kit.ScaleFor(camera.ViewportSize)
		uiScale.Scale = scale
		root.Size = UDim2.fromScale(1 / scale, 1 / scale)
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

return Kit
