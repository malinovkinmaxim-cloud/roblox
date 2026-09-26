--[[
	NotifyController - toasts (small, stacked) and BIG banners (one at a time, center screen).

	Not spammy by design:
	  * big banners queue up and show one at a time (max 4 waiting, oldest dropped)
	  * the same text is ignored if it was shown in the last 10 seconds
	  * at most 3 toasts on screen; older ones slide out
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)

local LocalPlayer = Players.LocalPlayer

local NotifyController = {}

local MAX_TOASTS = 3
local TOAST_TIME = 3.2
local BANNER_TIME = 2.6
local DEDUPE_SECONDS = 10

function NotifyController:Init(controllers)
	self.Controllers = controllers
	self.Toasts = {}
	self.BannerQueue = {}
	self.BannerBusy = false
	self.Recent = {}
	local gui, root = Kit.ScreenGui("ChileNotify", 15, LocalPlayer:WaitForChild("PlayerGui"))
	self.Gui = gui
	self.Root = root
	self.ToastHolder = Kit.New("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 190),
		Size = UDim2.fromOffset(560, 200),
		Parent = root,
	})
end

local function tween(instance: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?)
	local t = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

function NotifyController:Layout()
	for i, toast in self.Toasts do
		tween(toast, 0.2, { Position = UDim2.new(0.5, 0, 0, (i - 1) * 52) })
	end
end

function NotifyController:Toast(kind: string, text: string)
	local color = Theme.ToastColors[kind] or Theme.Colors.Blue
	local toast = Kit.Panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -60),
		Size = UDim2.fromOffset(540, 46),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.1,
		Radius = 12,
		Parent = self.ToastHolder,
	})
	local bar = Kit.New("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 8, 1, 0),
		Parent = toast,
	})
	Kit.Corner(bar, 12)
	Kit.Label({
		Position = UDim2.fromOffset(18, 6),
		Size = UDim2.new(1, -28, 1, -12),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.new(1, 1, 1),
		Parent = toast,
	})
	table.insert(self.Toasts, 1, toast)
	while #self.Toasts > MAX_TOASTS do
		local old = table.remove(self.Toasts)
		if old then
			old:Destroy()
		end
	end
	self:Layout()
	Kit.Pop(toast, 0.08)
	task.delay(TOAST_TIME, function()
		local index = table.find(self.Toasts, toast)
		if index then
			table.remove(self.Toasts, index)
			tween(toast, 0.25, { BackgroundTransparency = 1 })
			for _, d in toast:GetDescendants() do
				if d:IsA("TextLabel") then
					tween(d, 0.25, { TextTransparency = 1 })
				elseif d:IsA("Frame") then
					tween(d, 0.25, { BackgroundTransparency = 1 })
				elseif d:IsA("UIStroke") then
					tween(d, 0.25, { Transparency = 1 })
				end
			end
			task.delay(0.3, function()
				toast:Destroy()
			end)
			self:Layout()
		end
	end)
end

function NotifyController:ShowBanner(item)
	self.BannerBusy = true
	local color = Theme.Colors.Pink
	if item.Event then
		color = Theme.Colors.Green
	end
	local holder = Kit.New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.33),
		Size = UDim2.fromOffset(900, 90),
		Parent = self.Root,
	})
	local label = Kit.Label({
		Size = UDim2.fromScale(1, 1),
		Text = item.Text,
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.new(1, 1, 1),
		StrokeThickness = 4,
		Parent = holder,
	})
	Kit.Gradient(label, Color3.new(1, 1, 1), color:Lerp(Color3.new(1, 1, 1), 0.2))
	local scale = Kit.New("UIScale", { Scale = 0.3, Parent = holder })
	tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	if item.Sound then
		self.Controllers.SoundController:Play(item.Sound)
	end
	if item.Milestone then
		self.Controllers.EffectsController:Celebrate(2)
		self.Controllers.CameraController:Shake(0.9, 0.7)
	end
	-- a little wobble so it reads as an ALERT
	task.spawn(function()
		for i = 1, 6 do
			if not holder.Parent then
				return
			end
			holder.Rotation = if i % 2 == 0 then 2 else -2
			task.wait(0.06)
		end
		holder.Rotation = 0
	end)
	task.delay(BANNER_TIME, function()
		tween(scale, 0.25, { Scale = 1.25 })
		tween(label, 0.25, { TextTransparency = 1 })
		task.delay(0.3, function()
			holder:Destroy()
			self.BannerBusy = false
			self:NextBanner()
		end)
	end)
end

function NotifyController:NextBanner()
	if self.BannerBusy then
		return
	end
	local item = table.remove(self.BannerQueue, 1)
	if item then
		self:ShowBanner(item)
	end
end

function NotifyController:Notify(payload)
	if type(payload) ~= "table" or type(payload.Text) ~= "string" then
		return
	end
	local now = os.clock()
	local last = self.Recent[payload.Text]
	if last and now - last < DEDUPE_SECONDS then
		return
	end
	self.Recent[payload.Text] = now

	local function show()
		if payload.Kind == "Big" then
			table.insert(self.BannerQueue, payload)
			while #self.BannerQueue > 4 do
				table.remove(self.BannerQueue, 1)
			end
			self:NextBanner()
		else
			self:Toast(payload.Kind or "Info", payload.Text)
			local sound = payload.Sound or (if payload.Kind == "Error" then "Error" elseif payload.Kind == "Success" or payload.Kind == "Reward" then "Reward" else nil)
			if sound then
				self.Controllers.SoundController:Play(sound)
			end
		end
	end
	-- e.g. "X hatched a LEGENDARY" waits until the egg animation has revealed it
	if type(payload.Delay) == "number" and payload.Delay > 0 then
		task.delay(math.min(payload.Delay, 6), show)
	else
		show()
	end
end

function NotifyController:Start()
	Net.Event("Notify").OnClientEvent:Connect(function(payload)
		self:Notify(payload)
	end)
end

return NotifyController
