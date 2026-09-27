--[[
	BannerController - big moments and small messages.

	  Show(title, sub, style)   big centered banner (queued, never overlapping)
	  BossWarning               flashing WARNING -> "THE BRAINROT HAS ARRIVED" -> boss name
	  RandomEvent               event banners; the 67 EVENT gets its own sequence:
	                            screen dims, "6"... "7"... absurd camera zoom, "67", variant
	  Secret                    golden banner
	  Toasts (Notify remote)    small stacked messages: achievements, unlocks, rewards, errors
]]

local Players = game:GetService("Players")

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)

local BannerController = {}

local C = Theme.Colors

function BannerController:Init(controllers)
	self.C = controllers
	local gui, root = Kit.ScreenGui("BrainrotBanners", 40, Players.LocalPlayer:WaitForChild("PlayerGui"))
	self.Gui = gui
	self.Root = root
	self.Queue = {}
	self.Showing = false

	local banner = Kit.New("Frame", {
		Name = "Banner",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, 0, 0, 100),
		Position = UDim2.new(0.5, 0, 0.3, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
		Visible = false,
		Parent = root,
	})
	self.BannerGradient = Kit.New("UIGradient", {
		Color = ColorSequence.new(C.Neutral, C.SurfaceDark),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 0.25),
			NumberSequenceKeypoint.new(0.75, 0.25),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = banner,
	})
	self.BannerTitle = Kit.Label({
		Text = "",
		Size = UDim2.new(0.9, 0, 0, 50),
		Position = UDim2.new(0.5, 0, 0, 12),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = Theme.Fonts.Title,
		MaxTextSize = 44,
		StrokeThickness = 1.5,
		StrokeTransparency = 0.5,
		Parent = banner,
	})
	self.BannerSub = Kit.Label({
		Text = "",
		Size = UDim2.new(0.8, 0, 0, 22),
		Position = UDim2.new(0.5, 0, 0, 66),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = Theme.Fonts.Medium,
		MaxTextSize = 18,
		TextColor3 = C.TextDim,
		Parent = banner,
	})
	self.BannerScale = Kit.New("UIScale", { Parent = banner })
	self.Banner = banner

	-- full screen dim + giant text (67 / WARNING)
	self.Dim = Kit.New("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = root,
	})
	self.Giant = Kit.Label({
		Name = "Giant",
		Text = "",
		Size = UDim2.fromOffset(900, 320),
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Font = Theme.Fonts.Title,
		TextColor3 = C.Gold,
		StrokeThickness = 3,
		StrokeTransparency = 0.4,
		Visible = false,
		Parent = root,
	})
	self.GiantScale = Kit.New("UIScale", { Parent = self.Giant })

	-- toasts
	local toasts = Kit.New("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(460, 300),
		Position = UDim2.new(0.5, 0, 0, 90),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = root,
	})
	Kit.New("UIListLayout", {
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = toasts,
	})
	self.Toasts = toasts
	self.ToastOrder = 0
end

---------------------------------------------------------------------------
-- banners
---------------------------------------------------------------------------
function BannerController:Show(title: string, sub: string?, style: string?)
	table.insert(self.Queue, { Title = title, Sub = sub or "", Style = style or "Info" })
	while #self.Queue > 3 do
		table.remove(self.Queue, 1)
	end
	self:Next()
end

function BannerController:Next()
	if self.Showing then
		return
	end
	local item = table.remove(self.Queue, 1)
	if not item then
		return
	end
	self.Showing = true
	local colors = Theme.BannerStyles[item.Style] or Theme.BannerStyles.Info
	self.BannerGradient.Color = ColorSequence.new(colors[1], colors[2])
	self.BannerTitle.Text = item.Title
	self.BannerSub.Text = item.Sub
	self.BannerTitle.TextColor3 = if item.Style == "Secret" or item.Style == "Victory" or item.Style == "Sigma" then C.Gold else C.Text
	local banner = self.Banner
	banner.Visible = true
	banner.BackgroundTransparency = 0
	self.BannerScale.Scale = 1.12
	Kit.Tween(self.BannerScale, 0.25, { Scale = 1 })
	self.C.SoundController:Play("Banner")
	task.delay(2.3, function()
		Kit.Tween(self.BannerScale, 0.2, { Scale = 0.01 })
		task.delay(0.22, function()
			banner.Visible = false
			self.Showing = false
			self:Next()
		end)
	end)
end

-- the meme font is only used for the 67 moment
function BannerController:GiantText(text: string, color: Color3, hold: number, meme: boolean?)
	local giant = self.Giant
	giant.Font = if meme then Theme.Fonts.Meme else Theme.Fonts.Title
	giant.Text = text
	giant.TextColor3 = color
	giant.Visible = true
	giant.TextTransparency = 0
	self.GiantScale.Scale = if meme then 2 else 1.3
	Kit.Tween(self.GiantScale, 0.25, { Scale = 1 }, if meme then Enum.EasingStyle.Back else Enum.EasingStyle.Quad)
	task.delay(hold, function()
		if giant.Text == text then
			Kit.Tween(giant, 0.2, { TextTransparency = 1 })
			task.delay(0.2, function()
				if giant.Text == text then
					giant.Visible = false
				end
			end)
		end
	end)
end

function BannerController:BossWarning(title: string, delay: number)
	local S = self.C.SoundController
	S:Play("Siren")
	self.C.EffectsController:Flash(C.Danger, 0.3)
	self:GiantText("WARNING", C.Danger, 1.1)
	task.delay(1.2, function()
		self:Show("THE BRAINROT HAS ARRIVED", title, "Boss")
		self.C.CameraController:Shake(1)
	end)
	task.delay(math.max(0.5, delay - 0.3), function()
		self.C.EffectsController:Flash(C.Danger, 0.4)
	end)
end

function BannerController:RandomEvent(p)
	local S = self.C.SoundController
	local Cam = self.C.CameraController
	if p.Key == "Event67" then
		-- the 67 sequence
		Kit.Tween(self.Dim, 0.2, { BackgroundTransparency = 0.45 })
		self:GiantText("6", C.Gold, 0.5, true)
		S:Play("Six")
		task.delay(0.67, function()
			self:GiantText("7", C.Accent, 0.5, true)
			S:Play("Seven")
		end)
		task.delay(1.34, function()
			self:GiantText("67", C.Gold, 1.3, true)
			S:Play("SixSeven")
			Cam:ZoomPunch(0.3, 1.8) -- absurd zoom
			Cam:Shake(1.5)
			self.C.EffectsController:Flash(C.Gold, 0.5)
		end)
		task.delay(2.9, function()
			Kit.Tween(self.Dim, 0.3, { BackgroundTransparency = 1 })
			self:Show(p.VariantTitle or "67", "67 EVENT", "Secret")
		end)
		return
	end
	S:Play("Event")
	self:Show(p.Title, p.Sub, if p.Key == "SigmaMoment" then "Sigma" else "Event")
	if p.Key == "SigmaMoment" then
		Cam:ZoomPunch(0.55, 1.2)
	elseif p.Key == "WhyRunning" then
		S:Play("Goofy")
	elseif p.Key == "BrainrotStorm" then
		self.C.EffectsController:Flash(C.Rare, 0.4)
	end
end

function BannerController:Secret(p)
	self.C.SoundController:Play("Secret")
	self.C.EffectsController:Flash(C.Gold, 0.45)
	if p.Key == "SigmaStare" then
		self.C.CameraController:ZoomPunch(0.35, 2.2)
	end
	self:Show(p.Title, p.Sub, "Secret")
end

---------------------------------------------------------------------------
-- toasts
---------------------------------------------------------------------------
function BannerController:Toast(text: string, kind: string?)
	if (kind == "Achievement" or kind == "Unlock") and self.C.ResultsController:IsOpen() then
		return -- the results screen already lists them
	end
	local color = Theme.ToastColors[kind or "Info"] or Theme.ToastColors.Info
	self.ToastOrder += 1
	local frame = Kit.Panel({
		Size = UDim2.fromOffset(400, 40),
		BackgroundTransparency = Theme.GlassStrong,
		LayoutOrder = self.ToastOrder,
		Radius = 12,
		Parent = self.Toasts,
	})
	frame:SetAttribute("Kind", kind or "Info")
	-- a small coloured dot says what kind of message it is
	local dot = Kit.New("Frame", {
		Size = UDim2.fromOffset(8, 8),
		Position = UDim2.new(0, 16, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = color,
		Parent = frame,
	})
	Kit.Corner(dot, 4)
	Kit.Label({
		Text = text,
		Size = UDim2.new(1, -52, 0, 20),
		Position = UDim2.new(0, 34, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = Theme.Fonts.Bold,
		MaxTextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	Kit.Appear(frame)
	local count = 0
	for _, child in self.Toasts:GetChildren() do
		if child:IsA("Frame") then
			count += 1
		end
	end
	if count > 3 then
		local oldest, order = nil, math.huge
		for _, child in self.Toasts:GetChildren() do
			if child:IsA("Frame") and child.LayoutOrder < order then
				oldest, order = child, child.LayoutOrder
			end
		end
		if oldest then
			oldest:Destroy()
		end
	end
	if kind == "Achievement" or kind == "Unlock" then
		self.C.SoundController:Play("Rare")
	elseif kind == "Error" then
		self.C.SoundController:Play("Error")
	end
	task.delay(3.2, function()
		if frame.Parent then
			frame:Destroy()
		end
	end)
end

-- removes the achievement / unlock toasts (the results screen lists them itself)
function BannerController:ClearRewardToasts()
	for _, child in self.Toasts:GetChildren() do
		local kind = child:GetAttribute("Kind")
		if kind == "Achievement" or kind == "Unlock" then
			child:Destroy()
		end
	end
end

function BannerController:Start()
	self.C.ClientData:Remote("Notify").OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.Text) == "string" then
			self:Toast(payload.Text, payload.Kind)
		end
	end)
end

return BannerController
