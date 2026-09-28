--[[
	PointerController - arrows on the screen edge towards things worth walking to when they are
	off screen: the boss, treasure chests, fragments and rare specials (67 Goblin, THE 67,
	Golden Goober). Each arrow carries a small monogram badge. Also the one-time "how to play" hint
	of the very first run.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Widgets = require(script.Parent.Parent.UI.Widgets)

local PointerController = {}

local C = Theme.Colors
local MAX_ARROWS = 5
local MARGIN = 0.07 -- fraction of the screen kept free at the edges
local RARE_ICONS = { Goblin67 = "67", The67 = "67", GoldenGoober = "GG" }

function PointerController:Init(controllers)
	self.C = controllers
	local gui, root = Kit.ScreenGui("S67Pointers", 11, Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.Enabled = false
	self.Gui = gui
	self.Arrows = {}
	for i = 1, MAX_ARROWS do
		local holder = Kit.New("Frame", {
			Name = "Pointer" .. i,
			Size = UDim2.fromOffset(64, 64),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = root,
		})
		local arrow = Kit.Label({
			Name = "Arrow",
			Text = "▲",
			Size = UDim2.fromOffset(22, 22),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Font = Theme.Fonts.Title,
			TextColor3 = C.Gold,
			StrokeThickness = 1.5,
			StrokeTransparency = 0.4,
			Parent = holder,
		})
		local icon = Widgets.Mono(holder, "", C.Gold, 34, { Name = "Icon", Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
		icon.BackgroundColor3 = C.SurfaceDark
		icon.BackgroundTransparency = Theme.Glass
		self.Arrows[i] = { Frame = holder, Arrow = arrow, Icon = icon, IconText = icon:FindFirstChild("Text") :: TextLabel, IconStroke = icon:FindFirstChildOfClass("UIStroke") :: UIStroke }
	end

	self.Hint = Kit.Label({
		Name = "Hint",
		Text = "",
		Size = UDim2.fromOffset(520, 44),
		Position = UDim2.new(0.5, 0, 0.72, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Font = Theme.Fonts.Bold,
		MaxTextSize = 18,
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = Theme.Glass,
		Visible = false,
		Parent = root,
	})
	Kit.Corner(self.Hint, 22)
	Kit.Stroke(self.Hint)
	Kit.Padding(self.Hint, 18, 10)
end

-- targets: { Pos: Vector3, Icon: string, Color: Color3 }
function PointerController:Targets()
	local run = self.C.RunClient
	local out = {}
	local boss = run.Boss
	if boss then
		local e = run.Enemies[boss.Id]
		if e then
			table.insert(out, { Pos = run:World(e.RX or e.X1, e.RZ or e.Z1, 3), Icon = "BOSS", Color = C.Danger })
		end
	end
	for _, item in self.C.PickupRenderer.Items do
		if (item.Kind == "Chest" or item.Kind == "Chest67") and #out < MAX_ARROWS then
			table.insert(out, { Pos = run:World(item.X, item.Z, 2), Icon = if item.Kind == "Chest67" then "67" else "LOOT", Color = C.Gold })
		elseif item.Kind == "Fragment" and #out < MAX_ARROWS then
			table.insert(out, { Pos = run:World(item.X, item.Z, 2), Icon = "F", Color = C.Fragment })
		end
	end
	for _, e in run.Enemies do
		local icon = RARE_ICONS[e.Def.Key]
		if icon and #out < MAX_ARROWS then
			table.insert(out, { Pos = run:World(e.RX or e.X1, e.RZ or e.Z1, 2), Icon = icon, Color = C.Gold })
		end
	end
	return out
end

function PointerController:Update()
	local run = self.C.RunClient
	local active = run.Active
	self.Gui.Enabled = active
	if not active then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local targets = self:Targets()
	for i, a in self.Arrows do
		local t = targets[i]
		local shown = false
		if t then
			local p, onScreen = camera:WorldToViewportPoint(t.Pos)
			local sx, sy = p.X / viewport.X, p.Y / viewport.Y
			local inside = onScreen and p.Z > 0 and sx > MARGIN and sx < 1 - MARGIN and sy > MARGIN and sy < 1 - MARGIN
			if not inside then
				-- direction from the screen centre (flipped when the point is behind the camera)
				local dx, dy = sx - 0.5, sy - 0.5
				if p.Z < 0 then
					dx, dy = -dx, -dy
				end
				local len = math.sqrt(dx * dx + dy * dy)
				if len > 1e-4 then
					dx, dy = dx / len, dy / len
					local k = math.min((0.5 - MARGIN) / math.max(math.abs(dx), 1e-4), (0.5 - MARGIN) / math.max(math.abs(dy), 1e-4))
					a.Frame.Position = UDim2.fromScale(0.5 + dx * k, 0.5 + dy * k)
					a.Arrow.Rotation = math.deg(math.atan2(dx, -dy))
					a.Arrow.Position = UDim2.new(0.5, dx * 28, 0.5, dy * 28)
					a.Arrow.TextColor3 = t.Color
					a.IconText.Text = t.Icon
					a.IconText.TextColor3 = t.Color
					a.IconStroke.Color = t.Color
					shown = true
				end
			end
		end
		a.Frame.Visible = shown
	end
end

function PointerController:ShowFirstRunHint()
	local data = self.C.ClientData.Data
	if not data or not data.Stats or data.Stats.Runs > 0 then
		return
	end
	local hint = self.Hint
	hint.Text = if Kit.IsTouch() then "Move with the joystick. Attacks are automatic." else "Move with WASD. Attacks are automatic."
	hint.Visible = true
	hint.TextTransparency = 0
	hint.BackgroundTransparency = Theme.Glass
	Kit.Appear(hint)
	task.delay(6, function()
		Kit.Tween(hint, 0.6, { TextTransparency = 1, BackgroundTransparency = 1 })
		task.delay(0.6, function()
			hint.Visible = false
		end)
	end)
end

function PointerController:Start()
	self.C.RunClient.Started:Connect(function()
		self:ShowFirstRunHint()
	end)
	RunService.RenderStepped:Connect(function()
		self:Update()
	end)
end

return PointerController
