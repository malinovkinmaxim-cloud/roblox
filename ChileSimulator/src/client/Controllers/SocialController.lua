--[[
	SocialController - "who is taller than whom" (the viral part).

	  * a tag over every head:  📏 1.25K m  /  [Giant] Name 👑
	  * the closest other player gets a comparison line on their tag:
	        YOU ARE 87x TALLER        (green)   or   4.2x TALLER THAN YOU   (orange)
	  * 🚨 YOU PASSED <name>!  when you outgrow someone (rate limited, never spammy)
	  * 👑 YOU ARE THE TALLEST IN THIS SERVER!
	All from replicated Height attributes, updated 4x per second.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Config = require(Shared.Config)

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)

local LocalPlayer = Players.LocalPlayer

local SocialController = {}

local PASS_COOLDOWN = 12 -- seconds between "you passed" messages
local PASS_SAME_PLAYER = 180 -- same player at most every 3 minutes
local MIN_PASS_HEIGHT = 100 -- cm: passing someone at 0.3 m is not news

local function heightOf(player: Player): number
	local h = player:GetAttribute("Height")
	return if type(h) == "number" and h > 0 then h else Config.START_HEIGHT
end

function SocialController:Init(controllers)
	self.Controllers = controllers
	self.Tags = {} -- [Player] = tag
	self.WasAbove = {} -- [Player] = boolean (were they taller than me?)
	self.LastPassed = {} -- [Player] = os.clock()
	self.LastPassAny = 0
	self.WasTallest = false
	self.LastTallestNote = 0
end

function SocialController:MakeTag(body)
	local old = self.Tags[body.Player]
	if old then
		old.Gui:Destroy()
	end
	local gui = Kit.New("BillboardGui", {
		Name = "Tag",
		Size = UDim2.fromOffset(240, 86),
		LightInfluence = 0,
		MaxDistance = 2500,
		AlwaysOnTop = false,
		ResetOnSpawn = false,
		Adornee = body.Head.Part,
		Parent = body.Folder,
	})
	local height = Kit.Label({
		Size = UDim2.new(1, 0, 0, 34),
		Text = "",
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.new(1, 1, 1),
		StrokeThickness = 3,
		Parent = gui,
	})
	local name = Kit.Label({
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 24),
		Text = "",
		RichText = true,
		Parent = gui,
	})
	local compare = Kit.Label({
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 0, 26),
		Text = "",
		Font = Theme.Fonts.Title,
		Visible = false,
		StrokeThickness = 3,
		Parent = gui,
	})
	self.Tags[body.Player] = { Gui = gui, Height = height, Name = name, Compare = compare, Body = body }
end

function SocialController:UpdateTags()
	local bodies = self.Controllers.BodyController.Bodies
	local myBody = bodies[LocalPlayer]
	local myHeight = heightOf(LocalPlayer)

	-- the closest other player (in range) gets the comparison line
	local closest, closestDist = nil, math.huge
	if myBody and myBody.FeetCF and myBody.Shape then
		for player, body in bodies do
			if player ~= LocalPlayer and body.FeetCF and body.Shape then
				local d = (body.FeetCF.Position - myBody.FeetCF.Position).Magnitude
				local range = 45 + (body.Shape.Total + myBody.Shape.Total) * 1.2
				if d < range and d < closestDist then
					closest, closestDist = player, d
				end
			end
		end
	end

	for player, tag in self.Tags do
		local body = tag.Body
		if bodies[player] ~= body or not body.Head or not body.Head.Part.Parent then
			tag.Gui:Destroy()
			self.Tags[player] = nil
			continue
		end
		local h = heightOf(player)
		local title = Formulas.Title(h)
		tag.Height.Text = "📏 " .. Format.Length(h)
		local vip = if player:GetAttribute("VIP") == true then " 👑" else ""
		tag.Name.Text = string.format(
			'<font color="#%s">[%s]</font> %s%s',
			title.Color:ToHex(),
			title.Name,
			player.DisplayName,
			vip
		)
		local headSize = body.Head.Part.Size.Y
		tag.Gui.StudsOffsetWorldSpace = Vector3.new(0, headSize * 0.5 + 0.6 + headSize * 0.25, 0)
		tag.Gui.ExtentsOffsetWorldSpace = Vector3.zero

		if player == closest then
			local ratio = myHeight / h
			tag.Compare.Visible = true
			if ratio >= 1.15 then
				tag.Compare.Text = "YOU ARE " .. Format.Mult(ratio):sub(2) .. "× TALLER"
				tag.Compare.TextColor3 = Theme.Colors.Green
			elseif ratio <= 1 / 1.15 then
				tag.Compare.Text = Format.Mult(1 / ratio):sub(2) .. "× TALLER THAN YOU"
				tag.Compare.TextColor3 = Theme.Colors.Orange
			else
				tag.Compare.Text = "SAME HEIGHT!"
				tag.Compare.TextColor3 = Theme.Colors.Yellow
			end
		else
			tag.Compare.Visible = false
		end
	end
end

function SocialController:CheckPassing()
	local myHeight = heightOf(LocalPlayer)
	local now = os.clock()
	local others = 0
	local tallest = true
	for _, player in Players:GetPlayers() do
		if player == LocalPlayer or player:GetAttribute("Loaded") ~= true then
			continue
		end
		others += 1
		local h = heightOf(player)
		local above = h > myHeight
		if above then
			tallest = false
		end
		local was = self.WasAbove[player]
		if was == true and not above and h >= MIN_PASS_HEIGHT then
			local last = self.LastPassed[player] or -math.huge
			if now - self.LastPassAny >= PASS_COOLDOWN and now - last >= PASS_SAME_PLAYER then
				self.LastPassAny = now
				self.LastPassed[player] = now
				self.Controllers.NotifyController:Notify({ Kind = "Big", Text = "🚨 YOU PASSED " .. string.upper(player.DisplayName) .. "!", Sound = "BigGrowth" })
			end
		end
		self.WasAbove[player] = above
	end
	if others >= 1 and tallest and not self.WasTallest and myHeight >= MIN_PASS_HEIGHT and now - self.LastTallestNote > 90 then
		self.LastTallestNote = now
		self.Controllers.NotifyController:Notify({ Kind = "Big", Text = "👑 YOU ARE THE TALLEST IN THIS SERVER!", Sound = "BigGrowth" })
	end
	self.WasTallest = tallest and others >= 1
end

function SocialController:Start()
	local bodies = self.Controllers.BodyController
	bodies.BodyAdded:Connect(function(body)
		self:MakeTag(body)
	end)
	for _, body in bodies.Bodies do
		self:MakeTag(body)
	end
	Players.PlayerRemoving:Connect(function(player)
		self.WasAbove[player] = nil
		self.LastPassed[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			self:UpdateTags()
		end
	end)
	task.spawn(function()
		task.wait(5) -- let everyone's heights arrive first
		while true do
			self:CheckPassing()
			task.wait(0.5)
		end
	end)
end

return SocialController
