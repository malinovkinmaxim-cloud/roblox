local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local remotes = ReplicatedStorage:WaitForChild("HubRemotes")
local startNowRemote = remotes:WaitForChild("StartNow")
local noticeRemote = remotes:WaitForChild("Notice")

local player = Players.LocalPlayer
local TEXT = Config.PALETTE.text

local gui = Instance.new("ScreenGui")
gui.Name = "HubUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = TEXT
	for k, v in props do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function rounded(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = instance
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = TEXT
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance
end

label(gui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.new(0.6, 0, 0, 30),
	Text = `{Config.GAME_TITLE} · выберите комнату`,
	TextStrokeColor3 = Color3.new(1, 1, 1),
	TextStrokeTransparency = 0,
})

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -24)
panel.Size = UDim2.fromOffset(380, 130)
panel.BackgroundColor3 = Color3.new(1, 1, 1)
panel.BackgroundTransparency = 0.1
panel.Visible = false
rounded(panel, UDim.new(0, 16))
panel.Parent = gui

local roomTitle = label(panel, {
	Position = UDim2.fromOffset(12, 8),
	Size = UDim2.new(1, -24, 0, 32),
})
local roomStatus = label(panel, {
	Position = UDim2.fromOffset(12, 42),
	Size = UDim2.new(1, -24, 0, 24),
	Font = Enum.Font.GothamMedium,
})

local startButton = Instance.new("TextButton")
startButton.AnchorPoint = Vector2.new(0.5, 1)
startButton.Position = UDim2.new(0.5, 0, 1, -10)
startButton.Size = UDim2.fromOffset(220, 42)
startButton.BackgroundColor3 = Config.PALETTE.buttonPressed
startButton.Font = Enum.Font.FredokaOne
startButton.TextScaled = true
startButton.TextColor3 = Color3.new(1, 1, 1)
startButton.Text = "Начать сейчас"
rounded(startButton, UDim.new(0.5, 0))
startButton.Parent = panel
startButton.Activated:Connect(function()
	startNowRemote:FireServer()
end)

local toast = label(gui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 50),
	Size = UDim2.new(0.7, 0, 0, 30),
	TextStrokeColor3 = Color3.new(1, 1, 1),
	TextStrokeTransparency = 1,
	TextTransparency = 1,
})

local function refresh()
	local capacity = player:GetAttribute("RoomCapacity") or 0
	if capacity == 0 then
		panel.Visible = false
		return
	end
	local count = player:GetAttribute("RoomCount") or 0
	local secondsLeft = player:GetAttribute("RoomSecondsLeft") or -1
	local state = player:GetAttribute("RoomState")

	panel.Visible = true
	roomTitle.Text = `Комната на {capacity} · {count}/{capacity}`
	if state == "teleporting" then
		roomStatus.Text = "Переходим в игру…"
	elseif secondsLeft >= 0 then
		roomStatus.Text = `Старт через {secondsLeft} с · сойдите с платформы, чтобы выйти`
	else
		roomStatus.Text = `Ждём ещё {Config.ROOM_MIN_PLAYERS - count} игрока (минимум {Config.ROOM_MIN_PLAYERS})`
	end
	startButton.Visible = state ~= "teleporting" and count >= Config.ROOM_MIN_PLAYERS
end

for _, name in { "RoomCapacity", "RoomCount", "RoomSecondsLeft", "RoomState" } do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end
refresh()

local toastId = 0
noticeRemote.OnClientEvent:Connect(function(text)
	toastId += 1
	local id = toastId
	toast.Text = text
	toast.TextTransparency = 0
	toast.TextStrokeTransparency = 0
	task.delay(3, function()
		if id == toastId then
			TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end)

gui.Parent = player:WaitForChild("PlayerGui")
