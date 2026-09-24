local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UiStyle = require(Shared:WaitForChild("UiStyle"))
local Modes = require(Shared:WaitForChild("Modes"))

local C = UiStyle.colors
local F = UiStyle.fonts

local BANNER_COLORS = {
	success = C.success,
	fail = C.danger,
	info = C.info,
}

local Ui = {}
Ui.__index = Ui

local function tween(instance, time, props, style, direction)
	local t = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- Pops a container in, keeps it for `hold` seconds (forever if nil), then pops it out.
-- A newer pop on the same container cancels the older one's hide.
local popTokens = {}
local function pop(container, scale, hold)
	popTokens[container] = (popTokens[container] or 0) + 1
	local token = popTokens[container]
	container.Visible = true
	scale.Scale = 0.3
	tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	if hold then
		task.delay(hold, function()
			if popTokens[container] ~= token then
				return
			end
			tween(scale, 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In).Completed:Wait()
			if popTokens[container] == token then
				container.Visible = false
			end
		end)
	end
end

local function withScale(container)
	local scale = Instance.new("UIScale")
	scale.Parent = container
	return scale
end

local function bunnyIcon(parent, color, size)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size, size)
	for _, x in { 0.18, 0.56 } do
		local ear = Instance.new("Frame")
		ear.BackgroundColor3 = color
		ear.Position = UDim2.fromScale(x, -0.3)
		ear.Size = UDim2.fromScale(0.26, 0.6)
		UiStyle.corner(ear, UDim.new(0.5, 0))
		UiStyle.stroke(ear, 2)
		ear.Parent = holder
	end
	local head = Instance.new("Frame")
	head.BackgroundColor3 = color
	head.Size = UDim2.fromScale(1, 1)
	UiStyle.corner(head, UDim.new(0.35, 0))
	UiStyle.stroke(head, 2)
	head.Parent = holder
	local eye = Instance.new("Frame")
	eye.BackgroundColor3 = C.ink
	eye.Position = UDim2.fromScale(0.62, 0.3)
	eye.Size = UDim2.fromScale(0.14, 0.26)
	UiStyle.corner(eye, UDim.new(0.5, 0))
	eye.Parent = head
	holder.Parent = parent
	return holder
end

local function keycap(parent, key, order)
	local cap = Instance.new("Frame")
	cap.BackgroundColor3 = C.paper
	cap.Size = UDim2.fromOffset(0, 26)
	cap.AutomaticSize = Enum.AutomaticSize.X
	cap.LayoutOrder = order
	UiStyle.corner(cap, UDim.new(0, 7))
	UiStyle.stroke(cap, 2)
	local label = UiStyle.text(cap, {
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 15,
		Text = key,
	})
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = label
	cap.Parent = parent
end

local function caption(parent, text, order)
	UiStyle.outlinedText(parent, {
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = F.bold,
		TextSize = 16,
		Text = text,
		LayoutOrder = order,
	}, 2)
end

-- callbacks: restart(), hub(), chooseMode(modeId)
function Ui.new(player, gameState, callbacks)
	local self = setmetatable({}, Ui)
	self.touch = { left = false, right = false, jump = false }

	local gui = Instance.new("ScreenGui")
	gui.Name = "HopPalsUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Level card (top-left)
	local levelBody = UiStyle.card(gui, {
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.fromOffset(340, 64),
	})
	local badge = Instance.new("Frame")
	badge.BackgroundColor3 = C.ink
	badge.Position = UDim2.fromOffset(8, 8)
	badge.Size = UDim2.fromOffset(48, 48)
	UiStyle.corner(badge, UDim.new(0.5, 0))
	badge.Parent = levelBody
	local badgeNumber = UiStyle.text(badge, {
		Size = UDim2.fromScale(1, 1),
		FontFace = F.logo,
		TextColor3 = C.gold,
		TextSize = 26,
	})
	local levelCounter = UiStyle.text(levelBody, {
		Position = UDim2.fromOffset(66, 8),
		Size = UDim2.new(1, -76, 0, 18),
		FontFace = F.bold,
		TextSize = 14,
		TextColor3 = C.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local levelName = UiStyle.text(levelBody, {
		Position = UDim2.fromOffset(66, 26),
		Size = UDim2.new(1, -76, 0, 30),
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	-- Hint card (slides away after a while)
	local hintHome = UDim2.fromOffset(16, 86)
	local hintHidden = UDim2.fromOffset(-380, 86)
	local hintBody, hintCard = UiStyle.card(gui, {
		Position = hintHidden,
		Size = UDim2.fromOffset(340, 56),
	}, Color3.fromRGB(255, 246, 214))
	local hintText = UiStyle.text(hintBody, {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 1, -12),
		FontFace = F.bold,
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local hintLimit = Instance.new("UITextSizeConstraint")
	hintLimit.MaxTextSize = 17
	hintLimit.Parent = hintText

	-- Top-right buttons
	local restart = UiStyle.button(gui, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12),
		Size = UDim2.fromOffset(56, 56),
	}, "↻")
	restart.Activated:Connect(function()
		self.requestRestart()
	end)
	if gameState:GetAttribute("HubAvailable") then
		local hub = UiStyle.button(gui, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -84, 0, 12),
			Size = UDim2.fromOffset(96, 56),
		}, "Хаб", C.info, C.white)
		hub.Activated:Connect(callbacks.hub)
	end

	-- Team list (right side)
	local roster = Instance.new("Frame")
	roster.BackgroundTransparency = 1
	roster.AnchorPoint = Vector2.new(1, 0)
	roster.Position = UDim2.new(1, -16, 0, 86)
	roster.Size = UDim2.fromOffset(190, 330)
	local rosterLayout = Instance.new("UIListLayout")
	rosterLayout.Padding = UDim.new(0, 8)
	rosterLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rosterLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rosterLayout.Parent = roster
	roster.Parent = gui

	local chips = {}
	local function refreshRoster()
		local seen = {}
		for _, p in Players:GetPlayers() do
			seen[p] = true
			local slot = p:GetAttribute("Slot") or 1
			local chip = chips[p]
			if not chip or chip.slot ~= slot then
				if chip then
					chip.frame:Destroy()
				end
				local frame = Instance.new("Frame")
				frame.BackgroundColor3 = C.paper
				frame.Size = UDim2.fromOffset(180, 34)
				UiStyle.corner(frame, UDim.new(0.5, 0))
				UiStyle.stroke(frame, 2.5)
				local icon = bunnyIcon(frame, Config.PLAYER_COLORS[slot] or C.info, 20)
				icon.Position = UDim2.fromOffset(10, 8)
				UiStyle.text(frame, {
					Position = UDim2.fromOffset(38, 0),
					Size = UDim2.new(1, -72, 1, 0),
					FontFace = F.bold,
					TextSize = 15,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Text = p.DisplayName,
				})
				local status = UiStyle.text(frame, {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -8, 0.5, 0),
					Size = UDim2.fromOffset(24, 24),
					TextSize = 18,
					TextColor3 = C.success,
				})
				frame.Parent = roster
				chip = { frame = frame, status = status, slot = slot }
				chips[p] = chip
			end
			chip.frame.LayoutOrder = slot
			chip.status.Text = if p:GetAttribute("InDoor") == true then "✔" else ""
		end
		for p, chip in chips do
			if not seen[p] then
				chip.frame:Destroy()
				chips[p] = nil
			end
		end
	end
	task.spawn(function()
		while true do
			refreshRoster()
			task.wait(0.5)
		end
	end)

	-- Centre banner for "level complete" / "oops"
	local bannerBody, banner = UiStyle.card(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(520, 96),
		Visible = false,
	})
	local bannerScale = withScale(banner)
	local bannerText = UiStyle.outlinedText(bannerBody, {
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -32, 1, -24),
		TextScaled = true,
	}, 4)
	local bannerLimit = Instance.new("UITextSizeConstraint")
	bannerLimit.MaxTextSize = 46
	bannerLimit.Parent = bannerText

	-- Level intro card
	local introBody, intro = UiStyle.card(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(460, 128),
		Visible = false,
	})
	local introScale = withScale(intro)
	local introCounter = UiStyle.text(introBody, {
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 26),
		FontFace = F.bold,
		TextSize = 20,
		TextColor3 = C.muted,
	})
	local introName = UiStyle.text(introBody, {
		Position = UDim2.fromOffset(16, 44),
		Size = UDim2.new(1, -32, 0, 64),
		TextScaled = true,
	})
	local introLimit = Instance.new("UITextSizeConstraint")
	introLimit.MaxTextSize = 44
	introLimit.Parent = introName

	-- Waiting-for-team card
	local waitBody, waitCard = UiStyle.card(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(420, 110),
		Visible = false,
	})
	local waitScale = withScale(waitCard)
	local waitTitle = UiStyle.text(waitBody, {
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = 34,
	})
	UiStyle.text(waitBody, {
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 0, 24),
		FontFace = F.bold,
		TextSize = 17,
		TextColor3 = C.muted,
		Text = "Остальные игроки ещё загружаются",
	})

	-- Controls
	if UserInputService.TouchEnabled then
		local function holdButton(text, props, key)
			local button = UiStyle.button(gui, props, text)
			button.BackgroundTransparency = 0.15
			button.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
					self.touch[key] = true
				end
			end)
			button.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
					self.touch[key] = false
				end
			end)
		end
		holdButton("◀", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 70, 1, -80), Size = UDim2.fromOffset(92, 92) }, "left")
		holdButton("▶", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 180, 1, -80), Size = UDim2.fromOffset(92, 92) }, "right")
		holdButton("▲", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -90, 1, -90), Size = UDim2.fromOffset(116, 116) }, "jump")
	else
		local bar = Instance.new("Frame")
		bar.BackgroundTransparency = 1
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.Position = UDim2.new(0.5, 0, 1, -14)
		bar.Size = UDim2.fromOffset(0, 26)
		bar.AutomaticSize = Enum.AutomaticSize.X
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 6)
		layout.Parent = bar
		keycap(bar, "A", 1)
		keycap(bar, "D", 2)
		caption(bar, "ходить     ", 3)
		keycap(bar, "Пробел", 4)
		caption(bar, "прыжок     ", 5)
		keycap(bar, "R", 6)
		caption(bar, "заново", 7)
		bar.Parent = gui
	end

	-- Timer and stop/go signal (top centre)
	local timerBody, timerCard = UiStyle.card(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(130, 52),
		Visible = false,
	})
	local timerText = UiStyle.text(timerBody, {
		Size = UDim2.fromScale(1, 1),
		FontFace = F.logo,
		TextSize = 30,
	})

	local signalBody, signalCard = UiStyle.card(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 72),
		Size = UDim2.fromOffset(300, 56),
		Visible = false,
	})
	local signalText = UiStyle.outlinedText(signalBody, {
		Size = UDim2.fromScale(1, 1),
		TextSize = 28,
	}, 3)
	local edge = Instance.new("Frame")
	edge.BackgroundTransparency = 1
	-- A Border stroke is drawn outside the frame, so inset the frame by the stroke thickness
	edge.Position = UDim2.fromOffset(14, 14)
	edge.Size = UDim2.new(1, -28, 1, -28)
	edge.Visible = false
	local edgeStroke = UiStyle.stroke(edge, 14, C.danger)
	edgeStroke.Transparency = 0.25
	edge.Parent = gui

	local SIGNALS = {
		go = { text = "ИДИТЕ", color = C.success },
		warn = { text = "ВНИМАНИЕ…", color = C.gold },
		stop = { text = "СТОП! ЗАМРИТЕ", color = C.danger },
	}
	local function refreshSignal()
		local signal = SIGNALS[gameState:GetAttribute("Signal")]
		signalCard.Visible = signal ~= nil
		edge.Visible = signal ~= nil and signal ~= SIGNALS.go
		if signal then
			signalText.Text = signal.text
			signalBody.BackgroundColor3 = signal.color
			edgeStroke.Color = signal.color
		end
	end
	gameState:GetAttributeChangedSignal("Signal"):Connect(refreshSignal)
	refreshSignal()

	local function refreshTimer()
		local left = gameState:GetAttribute("TimeLeft") or -1
		timerCard.Visible = left >= 0
		timerText.Text = `{left}`
		timerText.TextColor3 = if left <= 10 then C.danger else C.ink
	end
	gameState:GetAttributeChangedSignal("TimeLeft"):Connect(refreshTimer)
	refreshTimer()

	-- Mode picker (only when the server was started without a hub room, e.g. in Studio)
	local pickerBody, picker = UiStyle.card(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, 76 + #Modes.order * 66),
		Visible = false,
	})
	local pickerScale = withScale(picker)
	UiStyle.text(pickerBody, {
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = 32,
		Text = "Выберите режим",
	})
	for i, id in Modes.order do
		local modeInfo = Modes.get(id)
		local button = UiStyle.button(pickerBody, {
			Position = UDim2.fromOffset(20, 62 + (i - 1) * 66),
			Size = UDim2.new(1, -40, 0, 54),
		}, "", modeInfo.color, C.white)
		button:FindFirstChildOfClass("UIPadding"):Destroy()
		UiStyle.outlinedText(button, {
			Position = UDim2.fromOffset(18, 4),
			Size = UDim2.new(1, -36, 0.55, 0),
			TextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = modeInfo.name,
			ZIndex = 3,
		}, 2)
		UiStyle.text(button, {
			Position = UDim2.new(0, 18, 0.55, 0),
			Size = UDim2.new(1, -36, 0.4, 0),
			FontFace = F.bold,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = C.white,
			Text = modeInfo.description,
			ZIndex = 3,
		})
		button.Activated:Connect(function()
			callbacks.chooseMode(id)
		end)
	end
	local function refreshPicker()
		local choosing = gameState:GetAttribute("ChoosingMode") == true
		if choosing and not picker.Visible then
			pop(picker, pickerScale)
		elseif not choosing then
			picker.Visible = false
		end
	end
	gameState:GetAttributeChangedSignal("ChoosingMode"):Connect(refreshPicker)
	refreshPicker()

	-- Game over (hardcore)
	local overBody, over = UiStyle.card(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(480, 190),
		Visible = false,
	}, C.danger)
	local overScale = withScale(over)
	UiStyle.outlinedText(overBody, {
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 50),
		TextSize = 44,
		Text = "ИГРА ОКОНЧЕНА",
	}, 4)
	local overReason = UiStyle.outlinedText(overBody, {
		Position = UDim2.fromOffset(12, 78),
		Size = UDim2.new(1, -24, 0, 30),
		TextSize = 22,
	}, 2)
	local overStats = UiStyle.outlinedText(overBody, {
		Position = UDim2.fromOffset(12, 116),
		Size = UDim2.new(1, -24, 0, 26),
		FontFace = F.bold,
		TextSize = 19,
	}, 2)
	local function refreshGameOver()
		if gameState:GetAttribute("GameOver") == true then
			local reached = gameState:GetAttribute("GameOverLevel") or 1
			overReason.Text = gameState:GetAttribute("GameOverReason") or ""
			overStats.Text = `Пройдено уровней: {reached - 1}. Хардкор прощает только идеальную игру.`
			pop(over, overScale)
		else
			over.Visible = false
		end
	end
	gameState:GetAttributeChangedSignal("GameOver"):Connect(refreshGameOver)
	refreshGameOver()

	-- Restart; in hardcore it means giving up, so it needs a second press
	local giveUpArmedUntil = 0
	function self.requestRestart()
		local modeInfo = Modes.get(gameState:GetAttribute("ModeId"))
		if modeInfo and modeInfo.oneLife and os.clock() > giveUpArmedUntil then
			giveUpArmedUntil = os.clock() + 3
			bannerBody.BackgroundColor3 = C.danger
			bannerText.Text = "Нажмите ещё раз, чтобы сдаться"
			pop(banner, bannerScale, 2)
			return
		end
		giveUpArmedUntil = 0
		callbacks.restart()
	end

	-- State bindings
	local shownKey = nil
	local function refreshLevel()
		local index = gameState:GetAttribute("LevelIndex")
		local modeInfo = Modes.get(gameState:GetAttribute("ModeId"))
		if not index or not modeInfo then
			return
		end
		local count = gameState:GetAttribute("LevelCount") or 0
		local name = gameState:GetAttribute("LevelName") or ""
		badge.BackgroundColor3 = modeInfo.color
		badgeNumber.TextColor3 = C.white
		badgeNumber.Text = tostring(index)
		local counter = if count > 0 then `УРОВЕНЬ {index} ИЗ {count}` else `УРОВЕНЬ {index} · ∞`
		levelCounter.Text = `{string.upper(modeInfo.name)} · {counter}` .. (if modeInfo.oneLife then " · ❤ 1" else "")
		levelName.Text = name
		hintText.Text = gameState:GetAttribute("LevelHint") or ""

		local key = `{modeInfo.id}:{index}`
		if key ~= shownKey then
			shownKey = key
			introCounter.Text = `{string.upper(modeInfo.name)} · УРОВЕНЬ {index}`
			introName.Text = name
			pop(intro, introScale, 2.4)

			hintCard.Position = hintHidden
			tween(hintCard, 0.5, { Position = hintHome }, Enum.EasingStyle.Back)
			task.delay(10, function()
				if shownKey == key then
					tween(hintCard, 0.4, { Position = hintHidden }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				end
			end)
		end
	end
	for _, name in { "LevelIndex", "LevelName", "LevelHint", "ModeId" } do
		gameState:GetAttributeChangedSignal(name):Connect(refreshLevel)
	end
	gameState:GetAttributeChangedSignal("ChoosingMode"):Connect(function()
		shownKey = nil
	end)
	refreshLevel()

	local function refreshWaiting()
		local waiting = gameState:GetAttribute("Waiting")
		if waiting and waiting ~= "" then
			waitTitle.Text = waiting
			if not waitCard.Visible then
				pop(waitCard, waitScale)
			end
		else
			popTokens[waitCard] = (popTokens[waitCard] or 0) + 1
			waitCard.Visible = false
		end
	end
	gameState:GetAttributeChangedSignal("Waiting"):Connect(refreshWaiting)
	refreshWaiting()

	local shownMessage = gameState:GetAttribute("MessageId")
	gameState:GetAttributeChangedSignal("MessageId"):Connect(function()
		local id = gameState:GetAttribute("MessageId")
		if id == shownMessage then
			return
		end
		shownMessage = id
		bannerBody.BackgroundColor3 = BANNER_COLORS[gameState:GetAttribute("MessageKind")] or C.info
		bannerText.Text = gameState:GetAttribute("Message") or ""
		pop(banner, bannerScale, 1.8)
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	return self
end

return Ui
