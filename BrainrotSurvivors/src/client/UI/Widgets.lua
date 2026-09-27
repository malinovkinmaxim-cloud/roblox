--[[
	Widgets - reusable UI pieces: bars, scrolling lists / grids, modal panels, icon slots,
	small tags. Built on Kit.
]]

local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Widgets = {}

export type Bar = { Frame: Frame, Fill: Frame, Label: TextLabel, Set: (self: Bar, fraction: number, text: string?) -> () }

-- Horizontal progress bar with a text label on top
function Widgets.Bar(parent: Instance, size: UDim2, position: UDim2, color: Color3, props: { [string]: any }?): Bar
	local frame = Kit.New("Frame", {
		Size = size,
		Position = position,
		BackgroundColor3 = Theme.Colors.PanelDark,
		BorderSizePixel = 0,
		Parent = parent,
	})
	if props then
		for k, v in props do
			(frame :: any)[k] = v
		end
	end
	Kit.Corner(frame, 8)
	Kit.Stroke(frame, 2.5)
	local fill = Kit.New("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = frame,
	})
	Kit.Corner(fill, 8)
	Kit.Gradient(fill, color:Lerp(Color3.new(1, 1, 1), 0.25), color:Lerp(Color3.new(0, 0, 0), 0.2))
	local label = Kit.Label({
		Name = "Label",
		Size = UDim2.new(1, -8, 1, -2),
		Position = UDim2.fromOffset(4, 1),
		Text = "",
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
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Colors.TextDim,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	})
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

function Widgets.Row(parent: Instance, height: number, order: number?, color: Color3?): Frame
	return Kit.Panel({
		Size = UDim2.new(1, -6, 0, height),
		BackgroundColor3 = color or Theme.Colors.PanelLight,
		LayoutOrder = order or 0,
		Radius = 12,
		Parent = parent,
	})
end

-- Small rounded text tag ("NEW!", "LV 3", "MAX")
function Widgets.Tag(parent: Instance, text: string, color: Color3, position: UDim2, size: UDim2?): TextLabel
	local tag = Kit.Label({
		Text = text,
		Size = size or UDim2.fromOffset(56, 22),
		Position = position,
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
		Font = Theme.Fonts.Bold,
		StrokeThickness = 1.5,
		ZIndex = 5,
		Parent = parent,
	})
	Kit.Corner(tag, 8)
	Kit.Stroke(tag, 2)
	return tag
end

-- Square icon slot (emoji icon + small level text)
function Widgets.Slot(parent: Instance, size: number, order: number?): (Frame, TextLabel, TextLabel)
	local frame = Kit.Panel({
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Theme.Colors.PanelLight,
		LayoutOrder = order or 0,
		Radius = 10,
		Parent = parent,
	})
	local icon = Kit.Label({
		Name = "Icon",
		Size = UDim2.fromScale(0.78, 0.78),
		Position = UDim2.fromScale(0.11, 0.06),
		Text = "",
		StrokeThickness = 0,
		Parent = frame,
	})
	local level = Kit.Label({
		Name = "Level",
		Size = UDim2.new(1, 0, 0.36, 0),
		Position = UDim2.fromScale(0, 0.68),
		Text = "",
		Font = Theme.Fonts.Bold,
		ZIndex = 3,
		Parent = frame,
	})
	return frame, icon, level
end

export type Modal = { Frame: Frame, Body: Frame, Title: TextLabel, Close: TextButton }

-- Centered panel with a title bar and a close button
function Widgets.Modal(parent: Instance, title: string, size: Vector2, onClose: () -> ()): Modal
	local frame = Kit.Panel({
		Name = title,
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Colors.Panel,
		Radius = 20,
		Visible = false,
		ZIndex = 2,
		Parent = parent,
	})
	Kit.Gradient(frame, Theme.Colors.PanelLight, Theme.Colors.PanelDark)
	local header = Kit.Label({
		Name = "Title",
		Text = title,
		Size = UDim2.new(1, -120, 0, 44),
		Position = UDim2.fromOffset(20, 8),
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		StrokeThickness = 3,
		Parent = frame,
	})
	local close = Kit.Button({
		Name = "Close",
		Text = "X",
		Size = UDim2.fromOffset(46, 46),
		Position = UDim2.new(1, -56, 0, 8),
		Color = Theme.Colors.Red,
		OnClick = onClose,
		Parent = frame,
	})
	local body = Kit.New("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -32, 1, -72),
		Position = UDim2.fromOffset(16, 62),
		Parent = frame,
	})
	return { Frame = frame, Body = body, Title = header, Close = close }
end

-- Coin amount pill (🪙 1,234)
function Widgets.CoinText(n: number): string
	local s = tostring(math.floor(n))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	return "🪙 " .. string.gsub(out, "^,", "")
end

return Widgets
