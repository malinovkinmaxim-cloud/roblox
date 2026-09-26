--[[
	Widgets - reusable pieces for panels: scrolling lists / grids, tabs, progress bars,
	toggles, notification badges, icon buttons.
]]

local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Widgets = {}

-- Vertical list or grid that grows its canvas automatically
function Widgets.Scroll(parent: Instance, props: { [string]: any }?, grid: Vector2?, padding: number?): ScrollingFrame
	local scroll = Kit.New("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Colors.TextDim,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	})
	if props then
		for k, v in props do
			(scroll :: any)[k] = v
		end
	end
	local pad = padding or 8
	if grid then
		Kit.New("UIGridLayout", {
			CellSize = UDim2.fromOffset(grid.X, grid.Y),
			CellPadding = UDim2.fromOffset(pad, pad),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
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
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 8),
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

-- Row card used by most lists
function Widgets.Row(parent: Instance, height: number, order: number?, color: Color3?): Frame
	return Kit.Panel({
		Size = UDim2.new(1, -6, 0, height),
		BackgroundColor3 = color or Theme.Colors.PanelLight,
		LayoutOrder = order or 0,
		Radius = 12,
		Parent = parent,
	})
end

export type Tabs = {
	Buttons: { [string]: TextButton },
	Pages: { [string]: Frame },
	Select: (name: string) -> (),
	Current: string,
}

function Widgets.Tabs(parent: Instance, names: { string }, onSelect: ((string) -> ())?): Tabs
	local bar = Kit.New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
		Parent = parent,
	})
	Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = bar,
	})
	local tabs: Tabs = {
		Buttons = {},
		Pages = {},
		Current = names[1],
		Select = function() end,
	}
	local width = math.floor((640 - (#names - 1) * 8) / #names)
	for i, name in names do
		local button = Kit.Button({
			Text = name,
			Size = UDim2.fromOffset(width, 38),
			Color = Theme.Colors.PanelLight,
			LayoutOrder = i,
			Parent = bar,
			Radius = 10,
		})
		tabs.Buttons[name] = button
		tabs.Pages[name] = Kit.New("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 48),
			Size = UDim2.new(1, 0, 1, -48),
			Visible = i == 1,
			Parent = parent,
		})
		button.Activated:Connect(function()
			tabs.Select(name)
		end)
	end
	tabs.Select = function(name: string)
		tabs.Current = name
		for n, page in tabs.Pages do
			page.Visible = n == name
			Kit.SetButtonColor(tabs.Buttons[n], if n == name then Theme.Colors.Blue else Theme.Colors.PanelLight)
		end
		if onSelect then
			onSelect(name)
		end
	end
	tabs.Select(names[1])
	return tabs
end

export type Bar = { Frame: Frame, Fill: Frame, Label: TextLabel, Set: (fraction: number, text: string?) -> () }

function Widgets.ProgressBar(parent: Instance, size: UDim2, position: UDim2, color: Color3?): Bar
	local frame = Kit.New("Frame", {
		BackgroundColor3 = Theme.Colors.PanelDark,
		Size = size,
		Position = position,
		Parent = parent,
	})
	Kit.Corner(frame, 10)
	Kit.Stroke(frame, 2)
	local fill = Kit.New("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(0, 1),
		Parent = frame,
	})
	Kit.Corner(fill, 10)
	local c = color or Theme.Colors.Green
	Kit.Gradient(fill, c:Lerp(Color3.new(1, 1, 1), 0.25), c:Lerp(Color3.new(0, 0, 0), 0.2))
	local label = Kit.Label({
		Size = UDim2.new(1, -8, 1, -4),
		Position = UDim2.fromOffset(4, 2),
		Text = "",
		ZIndex = 2,
		Parent = frame,
	})
	local bar: Bar = {
		Frame = frame,
		Fill = fill,
		Label = label,
		Set = function() end,
	}
	bar.Set = function(fraction: number, text: string?)
		fraction = math.clamp(if fraction == fraction then fraction else 0, 0, 1)
		fill.Size = UDim2.fromScale(math.max(fraction, 0.001), 1)
		fill.Visible = fraction > 0.001
		if text then
			label.Text = text
		end
	end
	return bar
end

-- On/off switch with a caption
function Widgets.Toggle(parent: Instance, caption: string, order: number, getValue: () -> boolean, onChange: (boolean) -> ())
	local row = Widgets.Row(parent, 52, order)
	Kit.Label({
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -140, 1, -16),
		Text = caption,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	local button, label = Kit.Button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(100, 38),
		Parent = row,
		Radius = 19,
	})
	local function refresh()
		local on = getValue()
		label.Text = if on then "ON" else "OFF"
		Kit.SetButtonColor(button, if on then Theme.Colors.Green else Theme.Colors.GrayDark)
	end
	button.Activated:Connect(function()
		onChange(not getValue())
		refresh()
	end)
	refresh()
	return row, refresh
end

-- Red "!" / number badge in a corner of a button
function Widgets.Badge(parent: GuiObject): (TextLabel, (number | boolean) -> ())
	local badge = Kit.Label({
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(26, 26),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.Red,
		Text = "!",
		ZIndex = 5,
		Visible = false,
		Parent = parent,
	})
	Kit.Corner(badge, 13)
	local function set(value: number | boolean)
		if value == true then
			badge.Text = "!"
			badge.Visible = true
		elseif type(value) == "number" and value > 0 then
			badge.Text = if value > 9 then "9+" else tostring(value)
			badge.Visible = true
		else
			badge.Visible = false
		end
	end
	return badge, set
end

-- Square HUD button: big emoji + caption
function Widgets.IconButton(parent: Instance, icon: string, caption: string, color: Color3, size: number, order: number, onClick: () -> ()): TextButton
	local button = Kit.Button({
		Size = UDim2.fromOffset(size, size),
		Color = color,
		LayoutOrder = order,
		Parent = parent,
		Radius = 16,
		OnClick = onClick,
	})
	local label = button:FindFirstChild("Label") :: TextLabel
	label.Text = icon
	label.Size = UDim2.new(1, -10, 0.62, 0)
	label.Position = UDim2.fromOffset(5, 3)
	Kit.Label({
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -4, 0.3, 0),
		Text = caption,
		Font = Theme.Fonts.Title,
		Parent = button,
	})
	return button
end

return Widgets
