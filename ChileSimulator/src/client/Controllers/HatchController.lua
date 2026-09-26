--[[
	HatchController - egg shop popup + the hatch animation.

	  * walk up to an egg (ProximityPrompt "Open") -> small popup: chances, HATCH 1 / HATCH 3
	  * server rolls, then the client plays: eggs shake harder and harder -> crack flash ->
	    the pet spins in 3D (ViewportFrame) with its rarity. Legendary+ = confetti + screen
	    flash + big sound; SECRET = everything, twice.
	  * Faster Hatch pass = 3x faster animation; click anywhere to skip
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared.PetConfig)
local ShopConfig = require(Shared.ShopConfig)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local PetIcon = require(UI.PetIcon)
local PetBuilder = require(script.Parent.Parent.Util.PetBuilder)

local LocalPlayer = Players.LocalPlayer

local HatchController = {}

function HatchController:Init(controllers)
	self.Controllers = controllers
	self.Queue = {}
	self.Playing = false
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local eggGui, eggRoot = Kit.ScreenGui("ChileEgg", 8, playerGui)
	self.EggGui = eggGui
	self.EggRoot = eggRoot
	local hatchGui, hatchRoot = Kit.ScreenGui("ChileHatch", 30, playerGui)
	self.HatchGui = hatchGui
	self.HatchRoot = hatchRoot
	hatchGui.Enabled = false
end

---------------------------------------------------------------------------
-- egg popup
---------------------------------------------------------------------------
function HatchController:CloseEgg()
	if self.EggPanel then
		self.EggPanel:Destroy()
		self.EggPanel = nil
		self.OpenEgg = nil
	end
end

function HatchController:OpenEggPanel(eggId: string, prompt: ProximityPrompt)
	local egg = PetConfig.GetEgg(eggId)
	if not egg then
		return
	end
	self:CloseEgg()
	self.OpenEgg = { Id = eggId, Prompt = prompt }
	local data = self.Controllers.ClientData
	local pets = data:Get("Pets") or {}
	local luck = pets.Luck or 1

	local panel = Kit.Panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(470, 420),
		Parent = self.EggRoot,
	})
	Kit.Gradient(panel, egg.Color:Lerp(Theme.Colors.PanelLight, 0.55), Theme.Colors.Panel)
	self.EggPanel = panel
	Kit.Label({
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -80, 0, 40),
		Text = "🥚 " .. string.upper(egg.Name),
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	Kit.Button({
		Text = "X",
		Color = Theme.Colors.Red,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(42, 42),
		Font = Theme.Fonts.Title,
		Parent = panel,
		OnClick = function()
			self:CloseEgg()
		end,
	})
	local list = Kit.New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 58),
		Size = UDim2.new(1, -28, 0, 270),
		Parent = panel,
	})
	Kit.New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	for i, chance in PetConfig.Chances(egg, luck) do
		local def = PetConfig.Pets[chance.Id]
		local rarity = PetConfig.Rarities[def.Rarity]
		local row = Kit.New("Frame", {
			BackgroundColor3 = Theme.Colors.PanelDark,
			BackgroundTransparency = 0.2,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = i,
			Parent = list,
		})
		Kit.Corner(row, 8)
		PetIcon.Create(row, chance.Id, UDim2.fromOffset(34, 34), UDim2.fromOffset(4, 0))
		Kit.Label({
			Position = UDim2.fromOffset(44, 4),
			Size = UDim2.new(0.42, -44, 1, -8),
			Text = def.Name,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		Kit.Label({
			Position = UDim2.new(0.42, 0, 0, 5),
			Size = UDim2.new(0.22, 0, 1, -10),
			Text = def.Rarity,
			TextColor3 = if def.Rarity == "Secret" then Color3.fromRGB(255, 90, 230) else rarity.Color,
			Parent = row,
		})
		local pct = chance.Chance * 100
		Kit.Label({
			Position = UDim2.new(0.64, 0, 0, 5),
			Size = UDim2.new(0.18, 0, 1, -10),
			Text = if pct >= 1 then string.format("%.1f%%", pct) elseif pct >= 0.01 then string.format("%.2f%%", pct) else "1 in " .. Format.Number(math.floor(1 / chance.Chance + 0.5)),
			Parent = row,
		})
		Kit.Label({
			Position = UDim2.new(0.82, 0, 0, 5),
			Size = UDim2.new(0.18, -6, 1, -10),
			Text = Format.Mult(def.Mult),
			TextColor3 = Theme.Colors.Green,
			Parent = row,
		})
	end
	for i, count in { 1, 3 } do
		Kit.Button({
			Text = string.format("HATCH %d  •  🪙 %s", count, Format.Number(egg.Cost * count)),
			Color = if count == 1 then Theme.Colors.Green else Theme.Colors.Orange,
			Position = UDim2.new(if i == 1 then 0 else 0.5, if i == 1 then 14 else 5, 1, -72),
			Size = UDim2.new(0.5, -19, 0, 58),
			Font = Theme.Fonts.Title,
			Parent = panel,
			OnClick = function()
				if not self.Playing then
					data:Fire("Hatch", eggId, count)
				end
			end,
		})
	end
	Kit.Pop(panel, 0.1)
end

---------------------------------------------------------------------------
-- hatch animation
---------------------------------------------------------------------------
-- 3D spinning pet inside a ViewportFrame
local function petViewport(parent: Instance, petId: string, size: UDim2, position: UDim2)
	local viewport = Kit.New("ViewportFrame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = size,
		Position = position,
		Ambient = Color3.fromRGB(200, 200, 210),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-1, -1, -1),
		Parent = parent,
	})
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.4, -4.2), Vector3.new(0, 0.1, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local pet = PetBuilder.Build(petId, viewport)
	pet:SetScale(1)
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if not viewport.Parent then
			connection:Disconnect()
			return
		end
		local t = os.clock()
		pet:Pose(CFrame.Angles(0, t * 1.6, 0) * CFrame.new(0, math.sin(t * 3) * 0.08, 0), t, function(part, cf)
			part.CFrame = cf
		end)
	end)
	return viewport
end

local function drawEgg(parent: Instance, egg, position: UDim2): Frame
	local shell = Kit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = egg.Color,
		Size = UDim2.fromOffset(150, 190),
		Position = position,
		Parent = parent,
	})
	Kit.New("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = shell })
	Kit.Stroke(shell, 4)
	for i, spot in { { 0.3, 0.3, 0.2 }, { 0.68, 0.45, 0.16 }, { 0.4, 0.7, 0.18 }, { 0.72, 0.78, 0.12 } } do
		local s = Kit.New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = egg.Spots,
			Size = UDim2.fromScale(spot[3], spot[3] * 0.8),
			Position = UDim2.fromScale(spot[1], spot[2]),
			LayoutOrder = i,
			Parent = shell,
		})
		Kit.New("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = s })
	end
	return shell
end

function HatchController:Reveal(holder: Instance, petId: string, position: UDim2, speed: number)
	local def = PetConfig.Pets[petId]
	local rarity = PetConfig.Rarities[def.Rarity]
	local secret = def.Rarity == "Secret"
	petViewport(holder, petId, UDim2.fromOffset(190, 190), position)
	local name = Kit.Label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = position + UDim2.fromOffset(0, 95),
		Size = UDim2.fromOffset(240, 36),
		Text = def.Name,
		Font = Theme.Fonts.Title,
		Parent = holder,
	})
	local rarityLabel = Kit.Label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = position + UDim2.fromOffset(0, 130),
		Size = UDim2.fromOffset(240, 30),
		Text = if secret then "??? SECRET ???" else string.upper(def.Rarity),
		Font = Theme.Fonts.Title,
		TextColor3 = if secret then Color3.new(1, 1, 1) else rarity.Color,
		Parent = holder,
	})
	if secret or def.Rarity == "Mythic" then
		local gradient = Kit.New("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 70)),
				ColorSequenceKeypoint.new(0.66, Color3.fromRGB(70, 220, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(230, 80, 255)),
			}),
			Parent = rarityLabel,
		})
		local c
		c = RunService.RenderStepped:Connect(function()
			if not gradient.Parent then
				c:Disconnect()
				return
			end
			gradient.Offset = Vector2.new(math.sin(os.clock() * 3) * 0.5, 0)
		end)
	end
	Kit.Label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = position + UDim2.fromOffset(0, 160),
		Size = UDim2.fromOffset(240, 26),
		Text = Format.Mult(def.Mult) .. " growth & coins",
		TextColor3 = Theme.Colors.Green,
		Parent = holder,
	})
	Kit.Pop(name, 0.4)
	return rarity.Order
end

function HatchController:Play(petIds: { string }, egg, fast: boolean)
	self.Playing = true
	self:CloseEgg()
	local speed = if fast then ShopConfig.FasterHatchSpeed else 1
	local sounds = self.Controllers.SoundController
	local effects = self.Controllers.EffectsController
	local gui = self.HatchGui
	gui.Enabled = true
	local dim = Kit.New("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		Parent = self.HatchRoot,
	})
	local skip = false
	dim.Activated:Connect(function()
		skip = true
	end)
	local positions = {}
	for i = 1, #petIds do
		positions[i] = UDim2.new(0.5, (i - (#petIds + 1) / 2) * 260, 0.45, 0)
	end

	-- shake
	local eggs = {}
	if egg then
		for i = 1, #petIds do
			eggs[i] = drawEgg(dim, egg, positions[i])
		end
		local shakeTime = 1.7 / speed
		local started = os.clock()
		local nextTick = 0
		while os.clock() - started < shakeTime and not skip do
			local k = (os.clock() - started) / shakeTime
			for i, shell in eggs do
				shell.Rotation = math.sin(os.clock() * (18 + k * 30) + i) * (6 + k * 22)
				shell.Size = UDim2.fromOffset(150 * (1 + k * 0.15), 190 * (1 + k * 0.15))
			end
			if os.clock() >= nextTick then
				sounds:Play("EggShake", 1 + k * 0.6)
				nextTick = os.clock() + (0.3 - k * 0.2) / speed
			end
			RunService.RenderStepped:Wait()
		end
		sounds:Play("EggCrack")
		effects:ScreenFlash(Color3.new(1, 1, 1), 0.9, 0.5)
		for _, shell in eggs do
			shell:Destroy()
		end
	end

	-- reveal
	local best = 1
	for i, petId in petIds do
		best = math.max(best, self:Reveal(dim, petId, positions[i], speed))
	end
	local bestRarity = PetConfig.RarityOrder[best]
	sounds:Play(PetConfig.Rarities[bestRarity].Sound)
	if best >= PetConfig.Rarities.Legendary.Order then
		effects:Celebrate(2)
		self.Controllers.CameraController:Shake(if bestRarity == "Secret" then 2 else 1, 0.8)
		effects:ScreenFlash(PetConfig.Rarities[bestRarity].Color, 0.6, 0.8)
		if bestRarity == "Secret" then
			task.delay(0.6, function()
				effects:ScreenFlash(Color3.new(1, 1, 1), 0.8, 0.8)
				effects:Celebrate(3)
			end)
		end
	end
	local holdTime = (if best >= 4 then 2.6 else 1.6) / speed
	local started = os.clock()
	skip = false
	while os.clock() - started < holdTime and not skip do
		task.wait(0.05)
	end
	dim:Destroy()
	gui.Enabled = false
	self.Playing = false
	local nextItem = table.remove(self.Queue, 1)
	if nextItem then
		task.spawn(self.Play, self, nextItem.Pets, nextItem.Egg, nextItem.Fast)
	end
end

function HatchController:Enqueue(pets: { string }, egg, fast: boolean)
	if self.Playing then
		if #self.Queue < 5 then
			table.insert(self.Queue, { Pets = pets, Egg = egg, Fast = fast })
		end
		return
	end
	task.spawn(self.Play, self, pets, egg, fast)
end

function HatchController:PlayHatch(payload)
	local egg = PetConfig.GetEgg(payload.Egg)
	local pets = {}
	for _, r in payload.Results or {} do
		if type(r) == "table" and PetConfig.Pets[r.Id] then
			table.insert(pets, r.Id)
		end
	end
	if #pets == 0 then
		return
	end
	if payload.Auto then
		-- one-button mode: never block the screen (you keep tapping), a card slides in instead
		for _, id in pets do
			self:QuickReveal(id)
		end
	else
		self:Enqueue(pets, egg, payload.Fast == true)
	end
end

-- Non-blocking "NEW PET!" card on the right side of the screen
function HatchController:QuickReveal(petId: string)
	local def = PetConfig.Pets[petId]
	local rarity = PetConfig.Rarities[def.Rarity]
	self.Cards = self.Cards or {}
	local card = Kit.Panel({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 200 + #self.Cards * 128),
		Size = UDim2.fromOffset(290, 118),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = self.EggRoot,
	})
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if def.Rarity == "Secret" then Color3.fromRGB(255, 90, 230) else rarity.Color
	end
	table.insert(self.Cards, card)
	petViewport(card, petId, UDim2.fromOffset(106, 106), UDim2.fromOffset(58, 59))
	Kit.Label({ Position = UDim2.fromOffset(112, 8), Size = UDim2.new(1, -120, 0, 24), Text = "🐾 NEW PET!", TextColor3 = Theme.Colors.Yellow, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	Kit.Label({ Position = UDim2.fromOffset(112, 34), Size = UDim2.new(1, -120, 0, 28), Text = def.Name, Font = Theme.Fonts.Title, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	Kit.Label({
		Position = UDim2.fromOffset(112, 64),
		Size = UDim2.new(1, -120, 0, 22),
		Text = string.upper(def.Rarity) .. "  " .. Format.Mult(def.Mult),
		TextColor3 = if def.Rarity == "Secret" then Color3.fromRGB(255, 90, 230) else rarity.Color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	Kit.Pop(card, 0.2)
	self.Controllers.SoundController:Play(rarity.Sound)
	if rarity.Order >= PetConfig.Rarities.Legendary.Order then
		self.Controllers.EffectsController:Celebrate(2)
		self.Controllers.CameraController:Shake(if def.Rarity == "Secret" then 1.5 else 0.8, 0.6)
	end
	task.delay(if rarity.Order >= PetConfig.Rarities.Legendary.Order then 4 else 2.6, function()
		local index = table.find(self.Cards, card)
		if index then
			table.remove(self.Cards, index)
		end
		card:Destroy()
	end)
end

-- a pet from a reward (daily, playtime gift, chest): reveal without an egg
function HatchController:ShowReward(petId: string)
	if PetConfig.Pets[petId] then
		if self.Controllers.ClientData:Setting("OneButton") then
			self:QuickReveal(petId)
		else
			self:Enqueue({ petId }, nil, false)
		end
	end
end

function HatchController:Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local eggId = prompt:GetAttribute("EggId")
		if type(eggId) == "string" then
			self:OpenEggPanel(eggId, prompt)
		end
	end)
	-- close the egg popup when walking away or opening a menu
	task.spawn(function()
		while true do
			task.wait(0.3)
			local open = self.OpenEgg
			if open then
				local character = LocalPlayer.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local part = open.Prompt.Parent
				if not root or not root:IsA("BasePart") or not part or not part:IsA("BasePart") or (root.Position - part.Position).Magnitude > 35 then
					self:CloseEgg()
				elseif self.Controllers.PanelController.Current then
					self:CloseEgg()
				end
			end
		end
	end)
end

return HatchController
