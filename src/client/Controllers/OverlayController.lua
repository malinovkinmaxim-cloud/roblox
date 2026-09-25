--[[
	OverlayController
	Short full-screen moments (never long cutscenes - the player keeps control):
	  - level intro card           "LEVEL 05 - SHADOW"
	  - role reveal                "DOPPELGÄNGER ... IS ... THE TROLL."
	  - death screen               "YOU DIED" / "YOUR DOPPELGÄNGER SURVIVED" + respawn bar
	  - results                    time, personal best, rewards, NEXT / REPLAY / LOBBY
	  - duo invites & secret missions
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local RoleConfig = require(ReplicatedStorage.Shared.RoleConfig)

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)

local OverlayController = {}

local C = Theme.Colors

local DEATH_CAUSES = {
	Hazard = "Touched something red.",
	Laser = "Zapped by a laser.",
	Beam = "Hit by the spinning beam.",
	Fell = "Fell into the void.",
	Linked = "Your shadow fell - you are linked!",
	Restart = "Back to the checkpoint.",
	Debug = "Debug kill.",
}

function OverlayController:Init(controllers)
	self.Controllers = controllers
end

function OverlayController:Start()
	local gui = Kit.Screen("OverlayUI", 30)
	self.Gui = gui
	self:_buildReveal()
	self:_buildDeath()
	self:_buildIntro()
	self:_buildResults()
	self:_buildDuoPopups()

	Net.Event("RunStarted").OnClientEvent:Connect(function(info)
		self:HideResults()
		self:HideDeath()
		self:ShowIntro(info)
	end)
	Net.Event("RoleRevealed").OnClientEvent:Connect(function(roleName)
		self:PlayReveal(roleName)
	end)
	Net.Event("PlayerDied").OnClientEvent:Connect(function(info)
		self:ShowDeath(info)
	end)
	Net.Event("PlayerRespawned").OnClientEvent:Connect(function()
		self:HideDeath()
	end)
	Net.Event("RunEnded").OnClientEvent:Connect(function(results)
		self:HideDeath()
		self.SecretPanel.Visible = false
		if results and not results.Aborted then
			self:ShowResults(results)
		else
			self:HideResults()
		end
	end)
	Net.Event("DuoState").OnClientEvent:Connect(function(state)
		self:_onDuoState(state)
	end)
end

---------------------------------------------------------------------------
-- Role reveal
---------------------------------------------------------------------------

function OverlayController:_buildReveal()
	local frame = Kit.New("Frame", {
		Name = "Reveal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = self.Gui,
	})
	self.RevealFrame = frame
	self.RevealLines = {}
	for index = 1, 3 do
		local label = Kit.Text({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, (index - 2) * 70),
			Size = UDim2.fromOffset(900, if index == 3 then 90 else 60),
			Font = Theme.Fonts.Title,
			TextSize = if index == 3 then 76 else 44,
			TextTransparency = 1,
			TextStrokeTransparency = 1,
			Text = "",
			Parent = frame,
		})
		self.RevealLines[index] = label
	end
end

function OverlayController:PlayReveal(roleName: string)
	local info = RoleConfig.Get(roleName)
	if not info then
		return
	end
	self.Controllers.SoundController:Play("Reveal")
	self.RevealToken = (self.RevealToken or 0) + 1
	local token = self.RevealToken
	local frame = self.RevealFrame
	local lines = self.RevealLines
	frame.Visible = true
	frame.BackgroundTransparency = 1
	Kit.Tween(frame, 0.2, { BackgroundTransparency = 0.55 })
	local texts = { "DOPPELGÄNGER...", "IS...", info.RevealText }
	for index, label in lines do
		label.Text = texts[index]
		label.TextColor3 = if index == 3 then info.Color else C.Text
		label.TextTransparency = 1
		label.TextStrokeTransparency = 1
	end
	task.spawn(function()
		for index, label in lines do
			if self.RevealToken ~= token then
				return
			end
			local uiScale = label:FindFirstChildOfClass("UIScale") or Kit.New("UIScale", { Parent = label })
			uiScale.Scale = if index == 3 then 1.6 else 1.2
			Kit.Tween(label, 0.18, { TextTransparency = 0, TextStrokeTransparency = 0.4 })
			Kit.Tween(uiScale, if index == 3 then 0.35 else 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
			task.wait(if index == 3 then 1.1 else 0.42)
		end
		if self.RevealToken ~= token then
			return
		end
		for _, label in lines do
			Kit.Tween(label, 0.25, { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
		Kit.Tween(frame, 0.25, { BackgroundTransparency = 1 })
		task.wait(0.27)
		if self.RevealToken == token then
			frame.Visible = false
		end
	end)
end

---------------------------------------------------------------------------
-- Level intro
---------------------------------------------------------------------------

function OverlayController:_buildIntro()
	local card = Kit.Panel({
		Name = "Intro",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.32),
		Size = UDim2.fromOffset(560, 130),
		Visible = false,
		Parent = self.Gui,
	})
	self.IntroCard = card
	self.IntroLevel = Kit.Text({
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 18,
		TextColor3 = C.Cyan,
		Text = "",
		Parent = card,
	})
	self.IntroName = Kit.Text({
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 0, 50),
		Font = Theme.Fonts.Title,
		TextSize = 44,
		Text = "",
		Parent = card,
	})
	self.IntroSub = Kit.Text({
		Position = UDim2.fromOffset(0, 88),
		Size = UDim2.new(1, 0, 0, 26),
		Font = Theme.Fonts.Body,
		TextSize = 18,
		TextColor3 = C.TextDim,
		Text = "",
		Parent = card,
	})
end

function OverlayController:ShowIntro(info)
	local card = self.IntroCard
	self.IntroLevel.Text = if info.IsPartner then "DUO - YOU ARE THE DOPPELGÄNGER" else "LEVEL " .. Format.LevelNumber(info.LevelId)
	self.IntroName.Text = info.Name
	self.IntroSub.Text = info.Hint or info.Subtitle or ""
	card.Visible = true
	card.Position = UDim2.fromScale(0.5, 0.28)
	card.BackgroundTransparency = 1
	Kit.Tween(card, 0.3, { Position = UDim2.fromScale(0.5, 0.32), BackgroundTransparency = 0.08 }, Enum.EasingStyle.Back)
	self.IntroToken = (self.IntroToken or 0) + 1
	local token = self.IntroToken
	task.delay(2.6, function()
		if self.IntroToken == token then
			Kit.Tween(card, 0.3, { Position = UDim2.fromScale(0.5, 0.26), BackgroundTransparency = 1 })
			task.wait(0.3)
			if self.IntroToken == token then
				card.Visible = false
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Death screen
---------------------------------------------------------------------------

function OverlayController:_buildDeath()
	local frame = Kit.New("Frame", {
		Name = "Death",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(120, 0, 10),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = self.Gui,
	})
	self.DeathFrame = frame
	self.DeathTitle = Kit.Text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(800, 90),
		Font = Theme.Fonts.Title,
		TextSize = 80,
		TextColor3 = C.Red,
		TextStrokeTransparency = 0.3,
		Text = "YOU DIED",
		Parent = frame,
	})
	self.DeathSub = Kit.Text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.4, 70),
		Size = UDim2.fromOffset(800, 40),
		Font = Theme.Fonts.Title,
		TextSize = 30,
		TextStrokeTransparency = 0.4,
		Text = "",
		Parent = frame,
	})
	self.DeathCause = Kit.Text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.4, 110),
		Size = UDim2.fromOffset(800, 28),
		Font = Theme.Fonts.Body,
		TextSize = 20,
		TextColor3 = C.TextDim,
		TextStrokeTransparency = 0.5,
		Text = "",
		Parent = frame,
	})
	local barBack = Kit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.4, 150),
		Size = UDim2.fromOffset(260, 8),
		BackgroundColor3 = Color3.fromRGB(60, 20, 25),
		Parent = frame,
	}, { Kit.Corner(4) })
	self.DeathBar = Kit.New("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.Red,
		Parent = barBack,
	}, { Kit.Corner(4) })
	self.DeathBlur = Kit.New("ColorCorrectionEffect", {
		Name = "DoppelDeathTint",
		Saturation = 0,
		Enabled = false,
		Parent = Lighting,
	})
end

function OverlayController:ShowDeath(info)
	self.Controllers.SoundController:Play("Death")
	local frame = self.DeathFrame
	frame.Visible = true
	frame.BackgroundTransparency = 1
	Kit.Tween(frame, 0.25, { BackgroundTransparency = 0.72 })
	self.DeathTitle.Text = if info.IsPartner then "YOU FELL" else "YOU DIED"
	if info.DoppelAlive then
		self.DeathSub.Text = "YOUR DOPPELGÄNGER SURVIVED"
		self.DeathSub.TextColor3 = C.Cyan
	else
		self.DeathSub.Text = "YOUR DOPPELGÄNGER FAILED"
		self.DeathSub.TextColor3 = C.Orange
	end
	self.DeathCause.Text = DEATH_CAUSES[info.Cause] or ""
	local scale = self.DeathTitle:FindFirstChildOfClass("UIScale") or Kit.New("UIScale", { Parent = self.DeathTitle })
	scale.Scale = 1.4
	Kit.Tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	self.DeathBar.Size = UDim2.fromScale(0, 1)
	Kit.Tween(self.DeathBar, info.RespawnDelay or 1.6, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Linear)
	self.DeathBlur.Enabled = true
	self.DeathBlur.Saturation = -0.6
end

function OverlayController:HideDeath()
	if not self.DeathFrame or not self.DeathFrame.Visible then
		return
	end
	self.DeathBlur.Enabled = false
	Kit.Tween(self.DeathFrame, 0.2, { BackgroundTransparency = 1 })
	task.delay(0.2, function()
		self.DeathFrame.Visible = false
	end)
end

---------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------

function OverlayController:_buildResults()
	local panel = Kit.Panel({
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(520, 520),
		Visible = false,
		Parent = self.Gui,
	})
	self.ResultsPanel = panel
	self.ResultsTitle = Kit.Text({
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 44),
		Font = Theme.Fonts.Title,
		TextSize = 38,
		TextColor3 = C.Yellow,
		Text = "LEVEL COMPLETE",
		Parent = panel,
	})
	self.ResultsLevel = Kit.Text({
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 18,
		TextColor3 = C.TextDim,
		Text = "",
		Parent = panel,
	})
	self.ResultsTime = Kit.Text({
		Position = UDim2.fromOffset(0, 90),
		Size = UDim2.new(1, 0, 0, 54),
		Font = Theme.Fonts.Title,
		TextSize = 50,
		Text = "",
		Parent = panel,
	})
	self.ResultsBest = Kit.Text({
		Position = UDim2.fromOffset(0, 144),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 17,
		TextColor3 = C.TextDim,
		Text = "",
		Parent = panel,
	})
	self.ResultsExtra = Kit.Text({
		Position = UDim2.fromOffset(20, 170),
		Size = UDim2.new(1, -40, 0, 44),
		TextSize = 17,
		Text = "",
		Parent = panel,
	})
	self.ResultsLines = Kit.New("Frame", {
		Position = UDim2.fromOffset(30, 218),
		Size = UDim2.new(1, -60, 0, 200),
		BackgroundTransparency = 1,
		Parent = panel,
	}, { Kit.List(Enum.FillDirection.Vertical, 4) })

	local buttons = Kit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.new(1, -40, 0, 54),
		BackgroundTransparency = 1,
		Parent = panel,
	}, { Kit.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center) })
	self.NextButton = Kit.Button({ Text = "NEXT", Size = UDim2.fromOffset(150, 52), Color = C.Green, TextColor = C.Background, LayoutOrder = 1, Parent = buttons }, function()
		if self.NextLevelId then
			self:_requestLevel(self.NextLevelId)
		end
	end)
	self.ReplayButton = Kit.Button({ Text = "REPLAY", Size = UDim2.fromOffset(150, 52), Color = C.Cyan, TextColor = C.Background, LayoutOrder = 2, Parent = buttons }, function()
		if self.ResultLevelId then
			self:_requestLevel(self.ResultLevelId)
		end
	end)
	Kit.Button({ Text = "LOBBY", Size = UDim2.fromOffset(150, 52), Color = C.PanelLight, LayoutOrder = 3, Parent = buttons }, function()
		self:HideResults()
		Net.Event("RequestLeave"):FireServer()
	end)
end

function OverlayController:_requestLevel(levelId: number)
	self:HideResults()
	local duo = self.Controllers.ClientState.Duo
	if duo and duo.IsHost then
		Net.Event("DuoAction"):FireServer("Start", levelId)
	else
		Net.Event("RequestPlay"):FireServer(levelId)
	end
end

local function rewardLine(label: string, coins: number, xp: number)
	local row = Kit.New("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
	})
	Kit.Text({
		Size = UDim2.new(0.6, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 18,
		Text = label,
		Parent = row,
	})
	Kit.Text({
		Position = UDim2.fromScale(0.6, 0),
		Size = UDim2.new(0.2, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 18,
		TextColor3 = Theme.Colors.Coin,
		Text = "+" .. coins,
		Parent = row,
	})
	Kit.Text({
		Position = UDim2.fromScale(0.8, 0),
		Size = UDim2.new(0.2, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 18,
		TextColor3 = Theme.Colors.Cyan,
		Text = "+" .. xp .. " XP",
		Parent = row,
	})
	return row
end

function OverlayController:ShowResults(results)
	self.Controllers.SoundController:Play("Finish")
	self.Controllers.HudController:SetFinalTime(results.Time or 0)
	self.ResultLevelId = results.LevelId
	self.NextLevelId = results.NextLevelId
	local duo = self.Controllers.ClientState.Duo
	local canChoose = not results.IsPartner and (not duo or duo.IsHost)
	self.NextButton.Visible = canChoose and results.NextLevelId ~= nil
	self.ReplayButton.Visible = canChoose

	self.ResultsTitle.Text = if results.Perfect then "PERFECT!" else "LEVEL COMPLETE"
	self.ResultsTitle.TextColor3 = if results.Perfect then C.Cyan else C.Yellow
	self.ResultsLevel.Text = string.format("LEVEL %s  ·  %s", Format.LevelNumber(results.LevelId), results.Name or "")
	self.ResultsTime.Text = Format.Time(results.Time, true)
	local bestLine
	if results.IsPartner then
		bestLine = "DUO CLEAR"
	elseif results.NewBest then
		bestLine = "NEW PERSONAL BEST!"
	else
		bestLine = "PERSONAL BEST " .. Format.Time(results.BestTime, true)
	end
	if results.GlobalBest then
		bestLine ..= string.format("   ·   WORLD BEST %s (%s)", Format.Time(results.GlobalBest.Time, true), results.GlobalBest.Name or "?")
	end
	self.ResultsBest.Text = bestLine
	self.ResultsBest.TextColor3 = if results.NewBest then C.Green else C.TextDim

	local extra = {}
	if results.RivalResult == "Won" then
		table.insert(extra, "YOU BEAT YOUR DOPPELGÄNGER!")
	elseif results.RivalResult == "Lost" then
		table.insert(extra, "YOUR DOPPELGÄNGER WON THE RACE...")
	end
	if results.Betrayal then
		local betrayal = results.Betrayal
		if betrayal.IsTraitor then
			table.insert(extra, string.format("YOUR DOPPELGÄNGER WAS A TRAITOR! (%d/%d deaths)", betrayal.Deaths, betrayal.Goal))
		else
			table.insert(extra, "YOUR DOPPELGÄNGER WAS LOYAL.")
		end
	end
	table.insert(extra, string.format("DEATHS: %d", results.Deaths or 0))
	self.ResultsExtra.Text = table.concat(extra, "\n")
	self.ResultsExtra.TextColor3 = if results.RivalResult == "Lost" then C.Orange else C.Text

	for _, child in self.ResultsLines:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index, line in results.Lines or {} do
		local row = rewardLine(line.Label, line.Coins, line.XP)
		row.LayoutOrder = index
		row.Parent = self.ResultsLines
	end
	if (results.LevelsGained or 0) > 0 then
		local row = Kit.Text({ Size = UDim2.new(1, 0, 0, 26), TextSize = 20, Font = Theme.Fonts.Title, TextColor3 = C.Green, Text = "LEVEL UP!", LayoutOrder = 99 })
		row.Parent = self.ResultsLines
	end

	local panel = self.ResultsPanel
	panel.Visible = true
	local scale = panel:FindFirstChildOfClass("UIScale") or Kit.New("UIScale", { Parent = panel })
	scale.Scale = 0.85
	Kit.Tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
end

function OverlayController:HideResults()
	if self.ResultsPanel then
		self.ResultsPanel.Visible = false
	end
end

---------------------------------------------------------------------------
-- Duo popups
---------------------------------------------------------------------------

function OverlayController:_buildDuoPopups()
	local invite = Kit.Panel({
		Name = "DuoInvite",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.fromOffset(440, 120),
		Visible = false,
		Parent = self.Gui,
	})
	self.InvitePanel = invite
	self.InviteText = Kit.Text({
		Position = UDim2.fromOffset(10, 12),
		Size = UDim2.new(1, -20, 0, 48),
		TextSize = 19,
		Text = "",
		Parent = invite,
	})
	local row = Kit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -20, 0, 44),
		BackgroundTransparency = 1,
		Parent = invite,
	}, { Kit.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center) })
	Kit.Button({ Text = "ACCEPT", Size = UDim2.fromOffset(150, 42), Color = C.Green, TextColor = C.Background, Parent = row }, function()
		invite.Visible = false
		if self.InviteFrom then
			Net.Event("DuoAction"):FireServer("Accept", self.InviteFrom)
		end
	end)
	Kit.Button({ Text = "DECLINE", Size = UDim2.fromOffset(150, 42), Color = C.PanelLight, Parent = row }, function()
		invite.Visible = false
		Net.Event("DuoAction"):FireServer("Decline")
	end)

	self.SecretPanel = Kit.Panel({
		Name = "DuoSecret",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.fromOffset(330, 76),
		Visible = false,
		Parent = self.Gui,
	})
	self.SecretText = Kit.Text({
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 1, -12),
		TextSize = 16,
		Text = "",
		Parent = self.SecretPanel,
	})
end

function OverlayController:_onDuoState(state)
	local hud = self.Controllers.HudController
	if state.Type == "Invite" then
		self.InviteFrom = state.FromUserId
		self.InviteText.Text = string.format("%s wants YOU to be their DOPPELGÄNGER!", state.From)
		self.InvitePanel.Visible = true
		task.delay(28, function()
			self.InvitePanel.Visible = false
		end)
	elseif state.Type == "InviteSent" then
		hud:Toast("Invite sent to " .. state.To, "Info")
	elseif state.Type == "Paired" then
		hud:Toast(if state.IsHost then state.Partner .. " is your doppelgänger now!" else "You are " .. state.Host .. "'s doppelgänger!", "Success")
	elseif state.Type == "Dissolved" then
		self.SecretPanel.Visible = false
		if state.Text then
			hud:Toast(state.Text, "Info")
		end
	elseif state.Type == "Error" then
		hud:Toast(state.Text or "Duo error", "Error")
	elseif state.Type == "Secret" then
		self.SecretPanel.Visible = true
		self.SecretText.Text = state.Goal
		self.SecretText.TextColor3 = if state.Traitor then C.Red else C.Cyan
		local stroke = self.SecretPanel:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if state.Traitor then C.Red else C.Cyan
		end
	elseif state.Type == "SecretProgress" then
		self.SecretText.Text = string.format("SECRET MISSION: %d / %d", state.Count, state.Goal)
	end
end

return OverlayController
