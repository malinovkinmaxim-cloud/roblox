local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UiStyle = require(Shared:WaitForChild("UiStyle"))
local Modes = require(Shared:WaitForChild("Modes"))

local remotes = ReplicatedStorage:WaitForChild("HubRemotes")
local startNowRemote = remotes:WaitForChild("StartNow")
local setModeRemote = remotes:WaitForChild("SetMode")
local noticeRemote = remotes:WaitForChild("Notice")

local player = Players.LocalPlayer
local C = UiStyle.colors
local F = UiStyle.fonts

local gui = Instance.new("ScreenGui")
gui.Name = "HubUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local function popIn(container)
	local scale = container:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = container
	scale.Scale = 0.4
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

-- Title card
local titleBody = UiStyle.card(gui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.fromOffset(420, 70),
})
local logo = UiStyle.text(titleBody, {
	Position = UDim2.fromOffset(0, 6),
	Size = UDim2.new(1, 0, 0, 34),
	FontFace = F.logo,
	TextSize = 32,
	TextColor3 = Config.PALETTE.lift,
	Text = Config.GAME_TITLE,
})
UiStyle.stroke(logo, 3, C.ink, Enum.ApplyStrokeMode.Contextual)
UiStyle.text(titleBody, {
	Position = UDim2.fromOffset(0, 42),
	Size = UDim2.new(1, 0, 0, 20),
	FontFace = F.bold,
	TextSize = 16,
	TextColor3 = C.muted,
	Text = `Встаньте на платформу комнаты · от {Config.ROOM_MIN_PLAYERS} игроков`,
})

-- Own progress under the title
local progressBody = UiStyle.card(gui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 90),
	Size = UDim2.fromOffset(420, 40),
})
local progressText = UiStyle.text(progressBody, {
	Size = UDim2.fromScale(1, 1),
	FontFace = F.bold,
	TextSize = 15,
})
local function refreshProgress()
	local unlocked = string.split(player:GetAttribute("UnlockedModes") or "", ",")
	local names = {}
	for _, id in Modes.order do
		local info = Modes.get(id)
		if table.find(unlocked, id) then
			table.insert(names, info.name)
		end
	end
	local best = player:GetAttribute("EndlessBest") or 0
	progressText.Text = `Открыто: {table.concat(names, ", ")} · рекорд ∞: {best}`
end
player:GetAttributeChangedSignal("UnlockedModes"):Connect(refreshProgress)
player:GetAttributeChangedSignal("EndlessBest"):Connect(refreshProgress)
refreshProgress()

-- Room panel
local panelBody, panel = UiStyle.card(gui, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -24),
	Size = UDim2.fromOffset(460, 222),
	Visible = false,
})
local roomTitle = UiStyle.text(panelBody, {
	Position = UDim2.fromOffset(0, 12),
	Size = UDim2.new(1, 0, 0, 32),
	TextSize = 28,
})
local roomStatus = UiStyle.text(panelBody, {
	Position = UDim2.fromOffset(12, 46),
	Size = UDim2.new(1, -24, 0, 22),
	FontFace = F.bold,
	TextSize = 17,
	TextColor3 = C.muted,
})
-- Mode selector: the leader picks, everybody sees the choice
local modeRow = Instance.new("Frame")
modeRow.BackgroundTransparency = 1
modeRow.Position = UDim2.fromOffset(12, 76)
modeRow.Size = UDim2.new(1, -24, 0, 40)
local modeLayout = Instance.new("UIListLayout")
modeLayout.FillDirection = Enum.FillDirection.Horizontal
modeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
modeLayout.Padding = UDim.new(0, 6)
modeLayout.Parent = modeRow
modeRow.Parent = panelBody

local modeButtons = {}
for i, id in Modes.order do
	local modeInfo = Modes.get(id)
	local button = Instance.new("TextButton")
	button.LayoutOrder = i
	button.Size = UDim2.new(1 / #Modes.order, -6, 1, 0)
	button.BackgroundColor3 = modeInfo.color
	button.AutoButtonColor = false
	button.FontFace = F.heavy
	button.TextScaled = true
	button.TextColor3 = C.white
	button.Text = modeInfo.name
	UiStyle.corner(button, UDim.new(0.5, 0))
	local stroke = UiStyle.stroke(button, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.22, 0)
	pad.PaddingBottom = UDim.new(0.22, 0)
	pad.PaddingLeft = UDim.new(0.08, 0)
	pad.PaddingRight = UDim.new(0.08, 0)
	pad.Parent = button
	button.Parent = modeRow
	button.Activated:Connect(function()
		setModeRemote:FireServer(id)
	end)
	modeButtons[id] = { button = button, stroke = stroke }
end

local modeHint = UiStyle.text(panelBody, {
	Position = UDim2.fromOffset(12, 118),
	Size = UDim2.new(1, -24, 0, 20),
	FontFace = F.bold,
	TextSize = 14,
	TextColor3 = C.muted,
})

local startButton, startContainer = UiStyle.button(panelBody, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.fromOffset(230, 50),
}, "Начать сейчас", C.success, C.white)
startButton.Activated:Connect(function()
	startNowRemote:FireServer()
end)

-- Toast
local toastBody, toast = UiStyle.card(gui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 140),
	Size = UDim2.fromOffset(460, 48),
	Visible = false,
}, C.danger)
local toastText = UiStyle.outlinedText(toastBody, {
	Position = UDim2.fromOffset(12, 6),
	Size = UDim2.new(1, -24, 1, -12),
	TextScaled = true,
	TextWrapped = true,
}, 2)
local toastLimit = Instance.new("UITextSizeConstraint")
toastLimit.MaxTextSize = 20
toastLimit.Parent = toastText

local function refresh()
	local capacity = player:GetAttribute("RoomCapacity") or 0
	if capacity == 0 then
		panel.Visible = false
		return
	end
	local count = player:GetAttribute("RoomCount") or 0
	local secondsLeft = player:GetAttribute("RoomSecondsLeft") or -1
	local state = player:GetAttribute("RoomState")

	if not panel.Visible then
		panel.Visible = true
		popIn(panel)
	end
	roomTitle.Text = `Комната на {capacity} · {count}/{capacity}`
	if state == "teleporting" then
		roomStatus.Text = "Переходим в игру…"
	elseif secondsLeft >= 0 then
		roomStatus.Text = `Старт через {secondsLeft} с · сойдите с платформы, чтобы выйти`
	else
		roomStatus.Text = `Ждём ещё игроков: минимум {Config.ROOM_MIN_PLAYERS}`
	end
	startContainer.Visible = state ~= "teleporting" and count >= Config.ROOM_MIN_PLAYERS

	local selected = player:GetAttribute("RoomMode")
	local isLeader = player:GetAttribute("RoomLeader") == true
	local unlocked = string.split(player:GetAttribute("RoomUnlocked") or "", ",")
	for id, entry in modeButtons do
		local on = id == selected
		local open = table.find(unlocked, id) ~= nil
		entry.button.Text = if open then Modes.get(id).name else "🔒"
		entry.button.BackgroundTransparency = if on then 0 elseif open then 0.45 else 0.8
		entry.stroke.Thickness = if on then 3.5 else 1.5
		entry.button.Active = isLeader and open
	end
	local selectedInfo = Modes.get(selected)
	local description = if selectedInfo then selectedInfo.description else ""
	modeHint.Text = if isLeader
		then `Вы лидер — выберите режим. {description}`
		else `Режим выбирает лидер. {description}`
end

for _, name in { "RoomCapacity", "RoomCount", "RoomSecondsLeft", "RoomState", "RoomMode", "RoomLeader", "RoomUnlocked" } do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end
refresh()

local toastId = 0
noticeRemote.OnClientEvent:Connect(function(text)
	toastId += 1
	local id = toastId
	toastText.Text = text
	toast.Visible = true
	popIn(toast)
	task.delay(3.5, function()
		if id == toastId then
			toast.Visible = false
		end
	end)
end)

gui.Parent = player:WaitForChild("PlayerGui")
