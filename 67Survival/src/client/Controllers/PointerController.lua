--[[
	PointerController - arrows on the screen edge towards things worth walking to when they are
	off screen: the BOSSES ("BOSS 2 · 140" with the boss number, THE FINAL ONE "67"), elites,
	items on the ground, an awake 67 VAULT, treasure chests, fragments and rare specials
	(67 Goblin, THE 67, Golden Goober).
	Each arrow carries a small monogram badge. Also the one-time "how to play" hint of the very
	first run.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Widgets = require(script.Parent.Parent.UI.Widgets)
local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local GameConfig = require(Modules.GameConfig)
local ArenaData = require(Modules.ArenaData)
local Rarity = require(Modules.Rarity)

local PointerController = {}

local C = Theme.Colors
local MAX_ARROWS = 6
local ELITE = Color3.fromRGB(190, 110, 255)
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
		-- "BOSS 2 · 120" under the badge (only for the big things)
		local tag = Kit.Label({
			Name = "Tag",
			Text = "",
			Size = UDim2.fromOffset(110, 16),
			Position = UDim2.new(0.5, 0, 0.5, 26),
			AnchorPoint = Vector2.new(0.5, 0),
			Font = Theme.Fonts.Title,
			MaxTextSize = 13,
			TextColor3 = C.Text,
			StrokeThickness = 1.5,
			StrokeTransparency = 0.2,
			Visible = false,
			Parent = holder,
		})
		self.Arrows[i] = { Frame = holder, Arrow = arrow, Icon = icon, IconText = icon:FindFirstChild("Text") :: TextLabel, IconStroke = icon:FindFirstChildOfClass("UIStroke") :: UIStroke, Tag = tag }
	end

	-- first run: a short "how to play" card (GameConfig.Tutorial)
	local hint = Kit.Panel({
		Name = "Hint",
		Size = UDim2.fromOffset(460, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0.5, 0, 0.2, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = Theme.GlassStrong,
		Visible = false,
		Radius = 18,
		Parent = root,
	})
	Kit.Padding(hint, 20, 14)
	Kit.New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = hint })
	Kit.Label({
		Name = "Title",
		Text = "HOW TO SURVIVE",
		Size = UDim2.new(1, 0, 0, 20),
		Font = Theme.Fonts.Title,
		TextScaled = false,
		TextSize = 17,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 0,
		Parent = hint,
	})
	self.HintLines = {}
	for i = 1, 4 do
		self.HintLines[i] = Kit.Label({
			Name = "Line" .. i,
			Text = "",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Font = Theme.Fonts.Bold,
			TextScaled = false,
			TextSize = 16,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = i,
			Parent = hint,
		})
	end
	self.Hint = hint
	self.HintUntil = -1
end

-- how far something is from you (studs, rounded)
local function distance(run, x: number, z: number): number
	local px, pz = run:LocalXZ()
	if not px or not pz then
		return 0
	end
	return math.floor(math.sqrt((x - px) ^ 2 + (z - pz) ^ 2) + 0.5)
end

-- targets: { Pos: Vector3, Icon: string, Color: Color3, Tag: string? }
function PointerController:Targets()
	local run = self.C.RunClient
	local out = {}
	-- bosses: the reason to go somewhere (THE FINAL ONE first)
	local encounters = {}
	for _, enc in run.Encounters do
		table.insert(encounters, enc)
	end
	table.sort(encounters, function(a, b)
		return (a.Slot or 0) > (b.Slot or 0)
	end)
	for _, enc in encounters do
		local x, z = enc.X, enc.Z
		for _, id in enc.Ids do
			local e = run.Enemies[id]
			if e then
				x, z = e.RX or e.X1, e.RZ or e.Z1
				break
			end
		end
		if #out < MAX_ARROWS then
			local label = if enc.Main then "THE FINAL ONE " else "BOSS " .. tostring(enc.Slot or "") .. " · "
			table.insert(out, { Pos = run:World(x, z, 3), Icon = if enc.Main then "67" else tostring(enc.Slot or "!"), Color = if enc.Crowned then C.Gold else C.Danger, Tag = label .. distance(run, x, z) })
		end
	end
	-- elites nearby (they are worth it)
	for id in run.Elites do
		local e = run.Enemies[id]
		if e and #out < MAX_ARROWS then
			local x, z = e.RX or e.X1, e.RZ or e.Z1
			if distance(run, x, z) < 120 then
				table.insert(out, { Pos = run:World(x, z, 3), Icon = "E", Color = ELITE, Tag = "ELITE " .. distance(run, x, z) })
			end
		end
	end
	-- items on the ground and an awake vault
	for _, item in self.C.LootRenderer.Items do
		if #out < MAX_ARROWS and not item.Soul then
			table.insert(out, { Pos = run:World(item.X, item.Z, 2), Icon = "◆", Color = Rarity.Colors[item.Def.Rarity] or C.Gold })
		end
	end
	for i, v in run.Map.Vaults do
		if v.State == 1 and #out < MAX_ARROWS then
			local def = ArenaData.Vaults[i]
			table.insert(out, { Pos = run:World(def.X, def.Z, 2), Icon = "67", Color = C.Gold, Tag = "VAULT " .. distance(run, def.X, def.Z) })
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
					a.Tag.Visible = t.Tag ~= nil
					if t.Tag then
						a.Tag.Text = t.Tag
						a.Tag.TextColor3 = t.Color
						-- the tag sits on the inner side of the arrow (never off the screen)
						a.Tag.Position = UDim2.new(0.5, -dx * 40, 0.5, if dy > 0.5 then -44 else 26)
					end
					shown = true
				end
			end
		end
		a.Frame.Visible = shown
	end
end

-- the lines of the first-run card: keyboard or touch
function PointerController.HintText(touch: boolean): { string }
	if touch then
		return {
			"Move with the joystick (left thumb)",
			"Your weapons attack on their own",
			"Grab the XP crystals to level up",
			"Level up: tap a card to pick an upgrade",
		}
	end
	return {
		"WASD - move",
		"Your weapons attack on their own",
		"Grab the XP crystals to level up",
		"Level up: pick an upgrade with keys 1-3",
	}
end

-- shown in the first seconds of your very first run only (never to players who have played)
function PointerController:ShowFirstRunHint()
	local data = self.C.ClientData.Data
	if not data or not data.Stats or data.Stats.Runs > 0 then
		return
	end
	for i, text in PointerController.HintText(Kit.IsTouch()) do
		self.HintLines[i].Text = text
	end
	-- run time, so pauses and level-up choices do not eat it
	self.HintUntil = GameConfig.Tutorial.HintSeconds
	self.Hint.Visible = true
	Kit.Appear(self.Hint)
end

-- the card hides while a level-up choice is open and goes away after HintSeconds of run time
function PointerController:UpdateHint()
	if self.HintUntil < 0 then
		return
	end
	local run = self.C.RunClient
	if not run.Active or run.Time >= self.HintUntil then
		self.HintUntil = -1
		self.Hint.Visible = false
		return
	end
	self.Hint.Visible = not self.C.LevelUpController:IsOpen()
end

function PointerController:Start()
	self.C.RunClient.Started:Connect(function()
		self:ShowFirstRunHint()
	end)
	RunService.RenderStepped:Connect(function()
		self:Update()
		self:UpdateHint()
	end)
end

return PointerController
