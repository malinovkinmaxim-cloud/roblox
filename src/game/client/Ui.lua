local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UiStyle = require(Shared:WaitForChild("UiStyle"))

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

function Ui.new(player, gameState, onRestart, onHub)
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
	restart.Activated:Connect(onRestart)
	if gameState:GetAttribute("HubAvailable") then
		local hub = UiStyle.button(gui, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -84, 0, 12),
			Size = UDim2.fromOffset(96, 56),
		}, "Хаб", C.info, C.white)
		hub.Activated:Connect(onHub)
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

	-- State bindings
	local shownIndex = nil
	local function refreshLevel()
		local index = gameState:GetAttribute("LevelIndex")
		if not index then
			return
		end
		local count = gameState:GetAttribute("LevelCount") or 1
		local name = gameState:GetAttribute("LevelName") or ""
		badgeNumber.Text = tostring(index)
		levelCounter.Text = `УРОВЕНЬ {index} ИЗ {count}`
		levelName.Text = name
		hintText.Text = gameState:GetAttribute("LevelHint") or ""

		if index ~= shownIndex then
			shownIndex = index
			introCounter.Text = `УРОВЕНЬ {index}`
			introName.Text = name
			pop(intro, introScale, 2.4)

			hintCard.Position = hintHidden
			tween(hintCard, 0.5, { Position = hintHome }, Enum.EasingStyle.Back)
			task.delay(10, function()
				if shownIndex == index then
					tween(hintCard, 0.4, { Position = hintHidden }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				end
			end)
		end
	end
	for _, name in { "LevelIndex", "LevelName", "LevelHint" } do
		gameState:GetAttributeChangedSignal(name):Connect(refreshLevel)
	end
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
