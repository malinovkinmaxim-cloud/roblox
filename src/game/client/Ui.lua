local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))

local TEXT = Config.PALETTE.text

local Ui = {}
Ui.__index = Ui

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextColor3 = TEXT
	l.TextScaled = true
	for k, v in props do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function roundButton(parent, text, position, size)
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = position
	b.Size = size
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.BackgroundTransparency = 0.25
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.TextColor3 = TEXT
	b.Text = text
	b.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = TEXT
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	b.Parent = parent
	return b
end

local function bindHold(button, touch, key)
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			touch[key] = true
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			touch[key] = false
		end
	end)
end

function Ui.new(player, gameState, onRestart, onHub)
	local self = setmetatable({}, Ui)
	self.touch = { left = false, right = false, jump = false }

	local gui = Instance.new("ScreenGui")
	gui.Name = "HopPalsUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local title = label(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 44),
		Size = UDim2.new(0.8, 0, 0, 40),
		TextStrokeColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0,
	})
	local hint = label(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 88),
		Size = UDim2.new(0.8, 0, 0, 24),
		Font = Enum.Font.GothamMedium,
		TextStrokeColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.3,
	})
	local message = label(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.7, 0.12),
		TextStrokeColor3 = Color3.new(1, 1, 1),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	local restart = roundButton(gui, "↻", UDim2.new(1, -40, 0, 70), UDim2.fromOffset(52, 52))
	restart.Activated:Connect(onRestart)

	if gameState:GetAttribute("HubAvailable") then
		local hub = roundButton(gui, "В хаб", UDim2.new(1, -120, 0, 70), UDim2.fromOffset(90, 44))
		hub.Activated:Connect(onHub)
	end

	if UserInputService.TouchEnabled then
		local left = roundButton(gui, "◀", UDim2.new(0, 70, 1, -80), UDim2.fromOffset(96, 96))
		local right = roundButton(gui, "▶", UDim2.new(0, 180, 1, -80), UDim2.fromOffset(96, 96))
		local jump = roundButton(gui, "⤒", UDim2.new(1, -90, 1, -90), UDim2.fromOffset(120, 120))
		bindHold(left, self.touch, "left")
		bindHold(right, self.touch, "right")
		bindHold(jump, self.touch, "jump")
	else
		label(gui, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(0.9, 0, 0, 20),
			Font = Enum.Font.GothamMedium,
			TextTransparency = 0.3,
			Text = "A / D или ← → — ходить   ·   Пробел / W — прыжок   ·   R — заново",
		})
	end

	local function refreshTitle()
		local waiting = gameState:GetAttribute("Waiting")
		if waiting and waiting ~= "" then
			title.Text = `{Config.GAME_TITLE}  ·  {waiting}`
			hint.Text = "Остальные игроки ещё загружаются"
			return
		end
		local index = gameState:GetAttribute("LevelIndex") or 1
		local count = gameState:GetAttribute("LevelCount") or 1
		local name = gameState:GetAttribute("LevelName") or ""
		title.Text = `{Config.GAME_TITLE}  ·  УРОВЕНЬ {index}/{count}  ·  {name}`
		hint.Text = gameState:GetAttribute("LevelHint") or ""
	end
	gameState:GetAttributeChangedSignal("LevelIndex"):Connect(refreshTitle)
	gameState:GetAttributeChangedSignal("LevelName"):Connect(refreshTitle)
	gameState:GetAttributeChangedSignal("LevelHint"):Connect(refreshTitle)
	gameState:GetAttributeChangedSignal("Waiting"):Connect(refreshTitle)
	refreshTitle()

	local shownId = gameState:GetAttribute("MessageId")
	gameState:GetAttributeChangedSignal("MessageId"):Connect(function()
		local id = gameState:GetAttribute("MessageId")
		if id == shownId then
			return
		end
		shownId = id
		message.Text = gameState:GetAttribute("Message") or ""
		message.TextTransparency = 0
		message.TextStrokeTransparency = 0
		message.Size = UDim2.fromScale(0.5, 0.08)
		TweenService:Create(message, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.fromScale(0.7, 0.12) }):Play()
		task.delay(2, function()
			if shownId == id then
				TweenService:Create(message, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end)
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	return self
end

return Ui
