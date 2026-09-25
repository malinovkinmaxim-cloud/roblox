--[[
	Kit - tiny declarative helpers to build UI from code (no Studio-built GUIs needed).
	All sizes are designed for a 1280x720 reference screen; ScreenGuis get a UIScale
	that adapts to phones, tablets and big monitors.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)

local Kit = {}

local player = Players.LocalPlayer

-- Kit.New("Frame", { Size = ..., Parent = ... }, { children })
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

function Kit.Corner(radius: number?): UICorner
	return Kit.New("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

function Kit.Stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Kit.New("UIStroke", {
		Color = color or Theme.Colors.Stroke,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0.3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Kit.Padding(all: number): UIPadding
	local u = UDim.new(0, all)
	return Kit.New("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

function Kit.List(direction: Enum.FillDirection?, padding: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return Kit.New("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function Kit.Text(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Bold,
		TextColor3 = Theme.Colors.Text,
		TextScaled = false,
		TextSize = 18,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 24),
	}
	for key, value in props do
		defaults[key] = value
	end
	return Kit.New("TextLabel", defaults)
end

function Kit.Panel(props: { [string]: any }, children: { Instance }?): Frame
	local defaults = {
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
	}
	for key, value in props do
		defaults[key] = value
	end
	local frame = Kit.New("Frame", defaults, children)
	Kit.Corner(16).Parent = frame
	Kit.Stroke().Parent = frame
	return frame
end

local clickSound: Sound? = nil
function Kit.SetClickSound(sound: Sound)
	clickSound = sound
end

--[[
	Kit.Button({ Text, Color, Size, Position, ... }, onClick)
	Hover / press animation, gamepad-selectable.
]]
function Kit.Button(props: { [string]: any }, onClick: (() -> ())?): TextButton
	local color = props.Color or Theme.Colors.PanelLight
	local button = Kit.New("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Font = props.Font or Theme.Fonts.Bold,
		Text = props.Text or "",
		TextColor3 = props.TextColor or Theme.Colors.Text,
		TextSize = props.TextSize or 20,
		TextWrapped = true,
		Size = props.Size or UDim2.new(0, 200, 0, 48),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Name = props.Name or "Button",
		Selectable = true,
		Parent = props.Parent,
	})
	Kit.Corner(props.Radius or 12).Parent = button
	if props.Stroke ~= false then
		Kit.Stroke(props.StrokeColor or Color3.new(1, 1, 1), 1.5, 0.75).Parent = button
	end
	local scale = Kit.New("UIScale", { Scale = 1, Parent = button })
	local hover = color:Lerp(Color3.new(1, 1, 1), 0.12)
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = hover }):Play()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.03 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = color }):Play()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.96 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	if onClick then
		button.Activated:Connect(function()
			if clickSound then
				clickSound:Play()
			end
			onClick()
		end)
	end
	return button
end

-- Recolour a Kit button (keeps hover working)
function Kit.SetButtonColor(button: TextButton, color: Color3)
	button.BackgroundColor3 = color
end

--[[
	New ScreenGui with a UIScale that follows the viewport size.
	Reference 1280x720; clamped so text stays readable on phones.
]]
function Kit.Screen(name: string, displayOrder: number?): (ScreenGui, UIScale)
	local gui = Kit.New("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 0,
		Parent = player:WaitForChild("PlayerGui"),
	})
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
	local scale = Kit.New("UIScale", { Parent = gui })
	local function update()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local size = camera.ViewportSize
		local s = math.min(size.X / 1280, size.Y / 720)
		scale.Scale = math.clamp(s, 0.55, 1.5)
	end
	update()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return gui, scale
end

-- Fade helpers
function Kit.Tween(instance: Instance, time: number, goals: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local tween = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goals)
	tween:Play()
	return tween
end

-- A coin icon (yellow circle with a darker ring)
function Kit.CoinIcon(size: number): Frame
	local icon = Kit.New("Frame", {
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Theme.Colors.Coin,
		BorderSizePixel = 0,
	})
	Kit.Corner(size).Parent = icon
	Kit.Stroke(Color3.fromRGB(200, 140, 20), 2, 0).Parent = icon
	return icon
end

return Kit
