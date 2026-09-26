--[[
	TutorialController - the first 5 minutes. A bouncing arrow + one short hint at a time:

	  STEP 1  "TAP TO GROW!"                       -> arrow on the TAP button
	  STEP 2  "Buy TAP POWER!"                     -> arrow on the upgrade (when affordable)
	  STEP 3  "Reach 100 m and REBIRTH!"           -> arrow on the rebirth bar
	          "REBIRTH NOW!"                       -> arrow on the REBIRTH button
	  STEP 4  "x2 GROWTH! Now become MUCH taller"  -> done
	Progress is saved (Stats.Tutorial): steps 1-3 are advanced by the server when you
	actually tap / upgrade / rebirth; the client only marks the very end as seen.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)

local LocalPlayer = Players.LocalPlayer

local TutorialController = {}

function TutorialController:Init(controllers)
	self.Controllers = controllers
	self.Done = false
end

function TutorialController:Build()
	local gui, root = Kit.ScreenGui("ChileTutorial", 4, LocalPlayer:WaitForChild("PlayerGui"))
	self.Gui = gui
	self.Root = root
	self.Arrow = Kit.Label({
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(70, 70),
		Text = "👇",
		StrokeThickness = 0,
		Visible = false,
		Parent = root,
	})
	self.Bubble = Kit.Panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(380, 50),
		BackgroundColor3 = Theme.Colors.Yellow,
		Visible = false,
		Radius = 25,
		Parent = root,
	})
	self.BubbleText = Kit.Label({
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 1, -12),
		Text = "",
		TextColor3 = Theme.Colors.TextDark,
		StrokeThickness = 0,
		Font = Theme.Fonts.Title,
		Parent = self.Bubble,
	})
end

-- point at a HUD element (absolute position -> root space)
function TutorialController:PointAt(target: GuiObject?, text: string)
	if not target or not target.Visible then
		self.Arrow.Visible = false
		self.Bubble.Visible = false
		return
	end
	-- screen pixels -> root design units (the root is scaled by a UIScale)
	local rootPos = self.Root.AbsolutePosition
	local uiScale = self.Root:FindFirstChildOfClass("UIScale")
	local s = if uiScale then uiScale.Scale else 1
	local center = (target.AbsolutePosition + Vector2.new(target.AbsoluteSize.X / 2, 0) - rootPos) / s
	local bounce = math.abs(math.sin(os.clock() * 5)) * 14
	self.Arrow.Position = UDim2.fromOffset(center.X, center.Y - 4 - bounce)
	self.Bubble.Position = UDim2.fromOffset(math.clamp(center.X, 200, self.Root.AbsoluteSize.X / s - 200), center.Y - 74 - bounce)
	self.BubbleText.Text = text
	self.Arrow.Visible = true
	self.Bubble.Visible = true
end

function TutorialController:Hide()
	self.Arrow.Visible = false
	self.Bubble.Visible = false
end

function TutorialController:Step()
	local data = self.Controllers.ClientData
	local stats = data:Get("Stats")
	local hud = self.Controllers.HudController
	if not stats or self.Done or not hud.TapButton then
		self:Hide()
		return
	end
	if self.Controllers.PanelController.Current then
		self:Hide()
		return
	end
	local step = stats.Tutorial or 0
	if step >= 4 then
		self.Done = true
		self:Hide()
		return
	end
	if step <= 1 then
		if stats.Taps < 10 then
			self:PointAt(hud.TapButton, "TAP TO GROW! 👆")
		elseif hud.CanUpgrade then
			self:PointAt(hud.TapUpgrade, "Buy TAP POWER to grow faster!")
		else
			self:PointAt(hud.TapButton, "Keep tapping to earn 🪙 coins!")
		end
	elseif step == 2 then
		if hud.RebirthReady then
			self:PointAt(hud.RebirthButton, "♻️ REBIRTH NOW for x2 GROWTH!")
		else
			self:PointAt(hud.RebirthBar.Frame, "Reach 100 m to REBIRTH!")
		end
	elseif step == 3 then
		if not self.FinalShownAt then
			self.FinalShownAt = os.clock()
		end
		self:PointAt(hud.TapButton, "x2 GROWTH! Now become MUCH taller 🚀")
		if os.clock() - self.FinalShownAt > 7 then
			data:Fire("Tutorial", 4)
			self.Done = true
			self:Hide()
		end
	end
end

function TutorialController:Start()
	self:Build()
	RunService.RenderStepped:Connect(function()
		self:Step()
	end)
end

return TutorialController
