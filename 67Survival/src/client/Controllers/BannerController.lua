--[[
	BannerController - big moments and small messages.

	  Show(title, sub, style)   big centered banner (queued, never overlapping)
	  BossWarning               flashing WARNING -> "A BOSS HAS ARRIVED" -> boss name
	  Event67                   the 67 EVENT sequence: screen dims, "6"... "7"... camera
	                            punch, "67", then the event's name (67 LUCK, 67 MODE...)
	  Secret                    golden banner
	  Toasts (Notify remote)    small stacked messages: achievements, unlocks, rewards, errors
	  Invite (Party remote)     a party invite with JOIN / NO (expires by itself)
]]

local Players = game:GetService("Players")

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)

local BannerController = {}

local C = Theme.Colors

function BannerController:Init(controllers)
	self.C = controllers
	local gui, root = Kit.ScreenGui("S67Banners", 40, Players.LocalPlayer:WaitForChild("PlayerGui"))
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
	self.ToastLayout = Kit.New("UIListLayout", {
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = toasts,
	})
	self.Toasts = toasts
	self.ToastOrder = 0
end

-- in a run (and on its results) toasts sit at the top centre (under the timer); in the hub
-- the logo is there, so they stack on the right under the coins bar
function BannerController:PlaceToasts()
	local inRun = (self.C.RunClient and self.C.RunClient.Active) or self.C.ResultsController:IsOpen()
	if inRun then
		self.Toasts.Position = UDim2.new(0.5, 0, 0, 90)
		self.Toasts.AnchorPoint = Vector2.new(0.5, 0)
		self.ToastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	else
		self.Toasts.Position = UDim2.new(1, -24, 0, 104)
		self.Toasts.AnchorPoint = Vector2.new(1, 0)
		self.ToastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	end
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
	-- the run is paused while the level-up cards are up: banners wait so they never cover the cards
	local levelUp = self.C.LevelUpController
	if levelUp and levelUp:IsOpen() then
		if not self.Waiting and #self.Queue > 0 then
			self.Waiting = true
			task.delay(0.3, function()
				self.Waiting = false
				self:Next()
			end)
		end
		return
	end
	local item = table.remove(self.Queue, 1)
	if not item then
		return
	end
	self.Showing = true
	self.Current = item
	self.ShowId = (self.ShowId or 0) + 1
	local id = self.ShowId
	local colors = Theme.BannerStyles[item.Style] or Theme.BannerStyles.Info
	self.BannerGradient.Color = ColorSequence.new(colors[1], colors[2])
	self.BannerTitle.Text = item.Title
	self.BannerSub.Text = item.Sub
	self.BannerTitle.TextColor3 = if item.Style == "Secret" or item.Style == "Victory" or item.Style == "Event67" then C.Gold
		elseif item.Style == "Evolution" then C.Mythic
		else C.Text
	local banner = self.Banner
	banner.Visible = true
	banner.BackgroundTransparency = 0
	self.BannerScale.Scale = 1.12
	Kit.Tween(self.BannerScale, 0.25, { Scale = 1 })
	self.C.SoundController:Play("Banner")
	task.delay(2.3, function()
		if self.ShowId ~= id then
			return
		end
		Kit.Tween(self.BannerScale, 0.2, { Scale = 0.01 })
		task.delay(0.22, function()
			if self.ShowId ~= id then
				return
			end
			banner.Visible = false
			self.Showing = false
			self.Current = nil
			self:Next()
		end)
	end)
end

-- takes the banner off the screen right away (the level-up cards opened). With requeue it is
-- shown again afterwards, unless it only announced the evolution the cards now offer.
function BannerController:Hide(requeue: boolean?)
	if not self.Showing then
		return
	end
	local item = self.Current
	self.ShowId = (self.ShowId or 0) + 1
	self.Banner.Visible = false
	self.Showing = false
	self.Current = nil
	if requeue and item and item.Style ~= "Evolution" then
		table.insert(self.Queue, 1, item)
	end
	self:Next()
end

-- the run is over: queued run banners would only cover the results
function BannerController:ClearRun()
	table.clear(self.Queue)
	self:Hide(false)
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

function BannerController:BossWarning(title: string, delay: number, final: boolean?)
	local S = self.C.SoundController
	S:Play("Siren")
	self.C.EffectsController:Flash(C.Danger, 0.3)
	self:GiantText("WARNING", C.Danger, 1.1)
	task.delay(1.2, function()
		self:Show(if final then "THE END IS HERE" else "A BOSS HAS ARRIVED", title, "Boss")
		self.C.CameraController:Shake(1)
	end)
	task.delay(math.max(0.5, delay - 0.3), function()
		self.C.EffectsController:Flash(C.Danger, 0.4)
	end)
end

-- a 67 EVENT: "6"... "7"... "67" -> the event
function BannerController:Event67(p)
	local S = self.C.SoundController
	local Cam = self.C.CameraController
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
		Cam:ZoomPunch(0.35, 1.6)
		Cam:Shake(1.5)
		self.C.EffectsController:Flash(C.Gold, 0.5)
	end)
	task.delay(2.9, function()
		Kit.Tween(self.Dim, 0.3, { BackgroundTransparency = 1 })
		local title = p.Title or p.Event or "67"
		local sub = p.Sub or ""
		if p.Variant and p.Event then
			sub = p.Event .. ": " .. sub
		end
		self:Show(title, sub, "Event67")
		S:Play("Event")
	end)
end

function BannerController:Secret(p)
	self.C.SoundController:Play("Secret")
	self.C.EffectsController:Flash(C.Gold, 0.45)
	if p.Key == "SigmaStare" or p.Key == "GoldenGoober" then
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
	self:PlaceToasts()
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
	if kind == "Achievement" or kind == "Unlock" or kind == "Cosmetic" then
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

-- a party invite: JOIN / NO, gone after a few seconds
function BannerController:Invite(p)
	if type(p.From) ~= "string" or type(p.FromId) ~= "number" then
		return
	end
	local old = self.Root:FindFirstChild("Invite")
	if old then
		old:Destroy()
	end
	local card = Kit.Panel({
		Name = "Invite",
		Size = UDim2.fromOffset(360, 64),
		Position = UDim2.new(0.5, 0, 1, -110),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = Theme.GlassStrong,
		Radius = 16,
		Parent = self.Root,
	})
	Kit.Label({
		Text = string.sub(p.From, 1, 20) .. " invited you to a party",
		Size = UDim2.new(1, -170, 0, 20),
		Position = UDim2.new(0, 16, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = Theme.Fonts.Bold,
		MaxTextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	local function answer(accept: boolean)
		self.C.ClientData:Fire(if accept then "PartyAccept" else "PartyDecline", p.FromId)
		card:Destroy()
	end
	Kit.Button({
		Name = "Join",
		Text = "JOIN",
		Size = UDim2.fromOffset(76, 40),
		Position = UDim2.new(1, -94, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = C.Success,
		TextSize = 16,
		OnClick = function()
			answer(true)
		end,
		Parent = card,
	})
	Kit.Button({
		Name = "No",
		Text = "NO",
		Size = UDim2.fromOffset(64, 40),
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = C.Neutral,
		TextSize = 16,
		OnClick = function()
			answer(false)
		end,
		Parent = card,
	})
	Kit.Appear(card)
	self.C.SoundController:Play("Pick")
	task.delay(math.clamp(p.Seconds or 20, 3, 30), function()
		if card.Parent then
			card:Destroy()
		end
	end)
end

function BannerController:Start()
	self.C.ClientData:Remote("Notify").OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.Text) == "string" then
			self:Toast(payload.Text, payload.Kind)
		end
	end)
	self.C.ClientData:Remote("Party").OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.Kind == "Invite" then
			self:Invite(payload)
		end
	end)
end

return BannerController
