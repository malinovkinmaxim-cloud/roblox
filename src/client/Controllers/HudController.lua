--[[
	HudController
	  - LevelUI: LEVEL 05 | TIME 01:24 | CHECKPOINT 3/5 | DOPPELGÄNGER: SHADOW / ???
	  - status banner (DOPPELGÄNGER IS AHEAD!)
	  - ability hints + touch buttons (ABILITY / INTERACT) + freeze timer
	  - respawn / restart / lobby buttons
	  - profile chip (level, XP bar, coins) - always visible
	  - toasts
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local RoleConfig = require(ReplicatedStorage.Shared.RoleConfig)

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)

local HudController = {}

local C = Theme.Colors

function HudController:Init(controllers)
	self.Controllers = controllers
end

function HudController:Start()
	self:_buildProfileChip()
	self:_buildLevelUI()
	self:_buildToasts()

	local state = self.Controllers.ClientState
	state.Changed:Connect(function(key)
		if key == "Profile" then
			self:_refreshProfile()
		elseif key == "Run" then
			self:_refreshRun()
		elseif key == "RoleState" then
			self:_refreshRole()
		elseif key == "CheckpointIndex" then
			self:_refreshCheckpoint()
		end
	end)

	Net.Event("Toast").OnClientEvent:Connect(function(text, kind)
		if type(text) == "string" then
			self:Toast(text, kind)
		end
	end)
	Net.Event("DoppelStatus").OnClientEvent:Connect(function(key, text)
		self:_setStatus(key, text)
	end)
	Net.Event("AbilityState").OnClientEvent:Connect(function(abilityState)
		self.FrozenUntil = if abilityState and abilityState.Frozen then abilityState.FrozenUntil else nil
		self:_refreshAbilityButtons()
		if abilityState and abilityState.Frozen then
			self.Controllers.SoundController:Play("Freeze")
		end
	end)
	Net.Event("CheckpointReached").OnClientEvent:Connect(function(index, total)
		self.Controllers.SoundController:Play("Checkpoint")
		self:Toast(string.format("CHECKPOINT %d/%d", index, total), "Success")
	end)
	Net.Event("RunEnded").OnClientEvent:Connect(function()
		self:_setStatus(nil, nil)
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		self:_refreshAbilityButtons()
	end)

	RunService.RenderStepped:Connect(function()
		self:_updateTimer()
	end)

	-- in case the bootstrap arrived before we subscribed
	state:WhenReady(function()
		self:_refreshProfile()
		self:_refreshRun()
	end)
end

---------------------------------------------------------------------------
-- Profile chip (top right)
---------------------------------------------------------------------------

function HudController:_buildProfileChip()
	local gui = Kit.Screen("ProfileUI", 5)
	local chip = Kit.Panel({
		Name = "Chip",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(250, 56),
		Parent = gui,
	})
	local levelBadge = Kit.New("Frame", {
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = C.Cyan,
		Parent = chip,
	}, { Kit.Corner(22) })
	local levelText = Kit.Text({
		Size = UDim2.fromScale(1, 1),
		Font = Theme.Fonts.Title,
		TextSize = 20,
		TextColor3 = C.Background,
		Text = "1",
		Parent = levelBadge,
	})
	local xpBack = Kit.New("Frame", {
		Position = UDim2.fromOffset(58, 34),
		Size = UDim2.fromOffset(88, 8),
		BackgroundColor3 = C.PanelLight,
		Parent = chip,
	}, { Kit.Corner(4) })
	local xpFill = Kit.New("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.Cyan,
		Parent = xpBack,
	}, { Kit.Corner(4) })
	Kit.Text({
		Position = UDim2.fromOffset(58, 8),
		Size = UDim2.fromOffset(88, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		TextColor3 = C.TextDim,
		Text = "LEVEL",
		Parent = chip,
	})
	local coin = Kit.CoinIcon(22)
	coin.Position = UDim2.fromOffset(156, 17)
	coin.Parent = chip
	local coinText = Kit.Text({
		Position = UDim2.fromOffset(184, 13),
		Size = UDim2.fromOffset(62, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.Title,
		TextSize = 18,
		TextScaled = true,
		Text = "0",
		Parent = chip,
	})
	Kit.New("UITextSizeConstraint", { MaxTextSize = 20, Parent = coinText })
	self.ProfileChip = { Level = levelText, XP = xpFill, Coins = coinText }
end

function HudController:_refreshProfile()
	local profile = self.Controllers.ClientState.Profile
	if not profile or not self.ProfileChip then
		return
	end
	local level, into, need = Progression.FromXP(profile.XP or 0)
	local chip = self.ProfileChip
	local previousCoins = self.LastCoins
	chip.Level.Text = tostring(level)
	Kit.Tween(chip.XP, 0.4, { Size = UDim2.fromScale(math.clamp(into / need, 0, 1), 1) })
	chip.Coins.Text = Format.Commas(profile.Coins or 0)
	if previousCoins and profile.Coins > previousCoins then
		self.Controllers.SoundController:Play("Coin")
	end
	self.LastCoins = profile.Coins
end

---------------------------------------------------------------------------
-- Level UI
---------------------------------------------------------------------------

function HudController:_buildLevelUI()
	local gui = Kit.Screen("LevelUI", 10)
	gui.Enabled = false
	self.LevelGui = gui

	-- top center: LEVEL | TIME | CHECKPOINT
	local bar = Kit.Panel({
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(460, 64),
		Parent = gui,
	})
	local function cell(x: number, width: number, title: string)
		Kit.Text({
			Position = UDim2.fromOffset(x, 6),
			Size = UDim2.fromOffset(width, 16),
			TextSize = 13,
			TextColor3 = C.TextDim,
			Text = title,
			Parent = bar,
		})
		return Kit.Text({
			Position = UDim2.fromOffset(x, 22),
			Size = UDim2.fromOffset(width, 34),
			Font = Theme.Fonts.Title,
			TextSize = 28,
			Text = "",
			Parent = bar,
		})
	end
	self.LevelText = cell(10, 120, "LEVEL")
	self.TimeText = cell(140, 180, "TIME")
	self.TimeText.Font = Theme.Fonts.Title
	self.CheckpointText = cell(330, 120, "CHECKPOINT")
	self.BestText = Kit.Text({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 4),
		Size = UDim2.fromOffset(300, 18),
		TextSize = 14,
		TextColor3 = C.TextDim,
		Text = "",
		Parent = bar,
	})

	-- top left: doppelgänger card (under the Roblox top bar)
	local card = Kit.Panel({
		Name = "DoppelCard",
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.fromOffset(250, 78),
		Parent = gui,
	})
	Kit.Text({
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.fromOffset(220, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 13,
		TextColor3 = C.TextDim,
		Text = "DOPPELGÄNGER:",
		Parent = card,
	})
	self.RoleText = Kit.Text({
		Position = UDim2.fromOffset(14, 24),
		Size = UDim2.fromOffset(220, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.Title,
		TextSize = 26,
		Text = "???",
		TextColor3 = RoleConfig.HiddenColor,
		Parent = card,
	})
	self.RoleDescription = Kit.Text({
		Position = UDim2.fromOffset(14, 54),
		Size = UDim2.fromOffset(226, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.Body,
		TextSize = 13,
		TextColor3 = C.TextDim,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		Parent = card,
	})
	self.RoleAccent = Kit.New("Frame", {
		Size = UDim2.new(0, 5, 1, -20),
		Position = UDim2.fromOffset(4, 10),
		BackgroundColor3 = RoleConfig.HiddenColor,
		BorderSizePixel = 0,
		Parent = card,
	}, { Kit.Corner(3) })

	-- status banner
	self.StatusBanner = Kit.Panel({
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 104),
		Size = UDim2.fromOffset(420, 44),
		Visible = false,
		Parent = gui,
	})
	self.StatusText = Kit.Text({
		Size = UDim2.fromScale(1, 1),
		Font = Theme.Fonts.Title,
		TextSize = 22,
		Text = "",
		Parent = self.StatusBanner,
	})

	-- top right: respawn / restart / lobby (below the profile chip)
	local actions = Kit.New("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 74),
		Size = UDim2.fromOffset(250, 40),
		BackgroundTransparency = 1,
		Parent = gui,
	}, { Kit.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right) })
	Kit.Button({ Text = "RESPAWN", Size = UDim2.fromOffset(84, 36), TextSize = 14, Color = C.PanelLight, LayoutOrder = 1, Parent = actions }, function()
		Net.Event("RequestRestart"):FireServer("Checkpoint")
	end)
	Kit.Button({ Text = "RESTART", Size = UDim2.fromOffset(78, 36), TextSize = 14, Color = C.PanelLight, LayoutOrder = 2, Parent = actions }, function()
		Net.Event("RequestRestart"):FireServer("Level")
	end)
	Kit.Button({ Text = "LOBBY", Size = UDim2.fromOffset(70, 36), TextSize = 14, Color = Color3.fromRGB(120, 40, 50), LayoutOrder = 3, Parent = actions }, function()
		Net.Event("RequestLeave"):FireServer()
	end)

	-- ability hint (keyboard / gamepad)
	self.AbilityHint = Kit.Text({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(520, 30),
		Font = Theme.Fonts.Title,
		TextSize = 20,
		TextStrokeTransparency = 0.4,
		Text = "",
		Parent = gui,
	})

	-- touch buttons (left of the Roblox jump button)
	local function touchButton(name: string, size: number, position: UDim2, color: Color3, fn: () -> ())
		local button = Kit.Button({
			Name = name,
			Text = name,
			Size = UDim2.fromOffset(size, size),
			AnchorPoint = Vector2.new(1, 1),
			Position = position,
			Color = color,
			TextColor = C.Background,
			TextSize = 16,
			Radius = size,
			Parent = gui,
		}, fn)
		button.Font = Theme.Fonts.Title
		button.BackgroundTransparency = 0.1
		return button
	end
	self.TouchAbility = touchButton("ABILITY", 92, UDim2.new(1, -200, 1, -40), C.Cyan, function()
		self.Controllers.InputController:Ability()
	end)
	self.TouchInteract = touchButton("INTERACT", 72, UDim2.new(1, -210, 1, -150), C.Yellow, function()
		self.Controllers.InputController:Interact()
	end)
	self.TouchInteract.TextSize = 12
end

function HudController:_refreshRun()
	local run = self.Controllers.ClientState.Run
	self.LevelGui.Enabled = run ~= nil
	if not run then
		self:_setStatus(nil, nil)
		return
	end
	self.FinalTime = nil
	self.FrozenUntil = nil
	self.LevelText.Text = Format.LevelNumber(run.LevelId)
	local best = run.BestTime
	self.BestText.Text = (if best then "PERSONAL BEST " .. Format.Time(best, true) else "NO PERSONAL BEST YET") .. "   ·   PAR " .. Format.Time(run.ParTime)
	self:_refreshCheckpoint()
	self:_refreshRole()
	self:_setStatus(nil, nil)
end

function HudController:_refreshCheckpoint()
	local state = self.Controllers.ClientState
	local run = state.Run
	if not run then
		return
	end
	self.CheckpointText.Text = string.format("%d/%d", state.CheckpointIndex or 0, run.CheckpointCount or 0)
end

function HudController:_refreshRole()
	local roleState = self.Controllers.ClientState.RoleState
	if not roleState then
		self.RoleText.Text = RoleConfig.HiddenName
		self.RoleText.TextColor3 = RoleConfig.HiddenColor
		self.RoleAccent.BackgroundColor3 = RoleConfig.HiddenColor
		self.RoleDescription.Text = ""
	else
		self.RoleText.Text = roleState.Display
		self.RoleText.TextColor3 = roleState.Color
		self.RoleAccent.BackgroundColor3 = roleState.Color
		self.RoleDescription.Text = roleState.Description or ""
	end
	self:_refreshAbilityButtons()
end

function HudController:_refreshAbilityButtons()
	if not self.TouchAbility then
		return
	end
	local roleState = self.Controllers.ClientState.RoleState
	local ability = roleState and roleState.Ability
	local interact = roleState and roleState.Interact
	local mode = self.Controllers.InputController:GetInputMode()
	local touch = mode == "Touch"
	self.TouchAbility.Visible = touch and ability ~= nil
	self.TouchInteract.Visible = touch and interact ~= nil
	if ability then
		self.TouchAbility.Text = if self.FrozenUntil then "RELEASE" else ability
	end
	if interact then
		self.TouchInteract.Text = interact
	end
	if touch or not ability then
		self.AbilityHint.Text = ""
	else
		local abilityKey = if mode == "Gamepad" then "(Y)" else "[Q]"
		local interactKey = if mode == "Gamepad" then "(X)" else "[E]"
		local text = abilityKey .. " " .. ability
		if interact then
			text ..= "     " .. interactKey .. " " .. interact
		end
		self.AbilityHint.Text = text
	end
end

function HudController:_updateTimer()
	local run = self.Controllers.ClientState.Run
	if not run or not self.LevelGui.Enabled then
		return
	end
	local elapsed = self.FinalTime or (Workspace:GetServerTimeNow() - run.StartServerTime)
	self.TimeText.Text = Format.Time(elapsed, true)
	if self.FrozenUntil then
		local left = self.FrozenUntil - Workspace:GetServerTimeNow()
		if left <= 0 then
			self.FrozenUntil = nil
			self:_refreshAbilityButtons()
		elseif self.TouchAbility.Visible then
			self.TouchAbility.Text = string.format("RELEASE\n%d", math.ceil(left))
		else
			self.AbilityHint.Text = string.format("SHADOW FROZEN %ds   ·   [E] RELEASE", math.ceil(left))
		end
	end
end

function HudController:SetFinalTime(seconds: number)
	self.FinalTime = seconds
end

---------------------------------------------------------------------------
-- Status banner
---------------------------------------------------------------------------

local STATUS_COLORS = {
	Ahead = Theme.Colors.Orange,
	Behind = Theme.Colors.Green,
	Won = Theme.Colors.Red,
	Died = Theme.Colors.Red,
	Back = Theme.Colors.Cyan,
}

function HudController:_setStatus(key: string?, text: string?)
	local banner = self.StatusBanner
	if not banner then
		return
	end
	self.StatusToken = (self.StatusToken or 0) + 1
	local token = self.StatusToken
	if not key or not text then
		banner.Visible = false
		return
	end
	banner.Visible = true
	self.StatusText.Text = text
	self.StatusText.TextColor3 = STATUS_COLORS[key] or C.Text
	local stroke = banner:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = STATUS_COLORS[key] or C.Stroke
		stroke.Transparency = 0
	end
	banner.Size = UDim2.fromOffset(460, 50)
	Kit.Tween(banner, 0.25, { Size = UDim2.fromOffset(420, 44) }, Enum.EasingStyle.Back)
	-- transient statuses fade out; race statuses stay
	if key == "Died" or key == "Back" or key == "Won" then
		task.delay(if key == "Won" then 4 else 2.2, function()
			if self.StatusToken == token then
				banner.Visible = false
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Toasts
---------------------------------------------------------------------------

function HudController:_buildToasts()
	local gui = Kit.Screen("ToastUI", 50)
	self.ToastHolder = Kit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -64),
		Size = UDim2.fromOffset(560, 240),
		BackgroundTransparency = 1,
		Parent = gui,
	}, { Kit.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom) })
end

function HudController:Toast(text: string, kind: string?)
	local holder = self.ToastHolder
	if not holder then
		return
	end
	local color = Theme.ToastColors[kind or "Info"] or C.Cyan
	local toast = Kit.Panel({
		Size = UDim2.fromOffset(520, 40),
		BackgroundTransparency = 0.05,
		LayoutOrder = math.floor(os.clock() * 100) % 1e8,
		Parent = holder,
	})
	local stroke = toast:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Transparency = 0.1
	end
	local label = Kit.Text({
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		TextSize = 17,
		TextColor3 = color,
		Text = text,
		Parent = toast,
	})
	if kind ~= "Debug" then
		self.Controllers.SoundController:Play("Toast")
	end
	-- keep at most 4 toasts
	local toasts = {}
	for _, child in holder:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #toasts > 4 do
		local oldest = table.remove(toasts, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	task.delay(3.2, function()
		if toast.Parent then
			Kit.Tween(toast, 0.3, { BackgroundTransparency = 1 })
			Kit.Tween(label, 0.3, { TextTransparency = 1 })
			if stroke then
				Kit.Tween(stroke, 0.3, { Transparency = 1 })
			end
			task.wait(0.32)
			toast:Destroy()
		end
	end)
end

return HudController
