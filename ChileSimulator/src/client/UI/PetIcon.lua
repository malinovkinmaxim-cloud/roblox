--[[
	PetIcon - lightweight 2D pet portrait for lists (no ViewportFrame per card, so a pet
	inventory with 100+ pets stays cheap on phones). Body circle + ears + eyes in the pet's
	colours, rarity ring around it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PetConfig = require(ReplicatedStorage:WaitForChild("Shared").PetConfig)

local Kit = require(script.Parent.Kit)

local PetIcon = {}

local function circle(parent: Instance, color: Color3, size: UDim2, position: UDim2, z: number): Frame
	local f = Kit.New("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = size,
		Position = position,
		ZIndex = z,
		Parent = parent,
	})
	Kit.New("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = f })
	return f
end

function PetIcon.Create(parent: Instance, petId: string, size: UDim2, position: UDim2?): Frame
	local def = PetConfig.Pets[petId] or PetConfig.Pets.Doggy
	local look = def.Look
	local rarity = PetConfig.Rarities[def.Rarity]
	local holder = Kit.New("Frame", {
		Name = "PetIcon",
		BackgroundTransparency = 1,
		Size = size,
		Position = position or UDim2.new(),
		Parent = parent,
	})
	local tall = look.Tall == true
	local body = circle(holder, look.Body, UDim2.fromScale(if tall then 0.55 else 0.7, if tall then 0.85 else 0.7), UDim2.fromScale(0.5, 0.56), 3)
	Kit.New("UIStroke", { Thickness = 2, Color = rarity.Color, Parent = body })
	if look.Rainbow then
		Kit.New("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 255, 140)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 150, 255)),
			}),
			Parent = body,
		})
	end
	local ears = look.Ears or "None"
	if ears ~= "None" then
		for _, side in { -1, 1 } do
			local earSize = if ears == "Long" then UDim2.fromScale(0.14, 0.4) else UDim2.fromScale(0.22, 0.22)
			local earY = if ears == "Long" then 0.18 elseif ears == "Floppy" then 0.45 else 0.26
			local earX = if ears == "Floppy" then 0.5 + side * 0.36 else 0.5 + side * 0.22
			local ear = circle(holder, look.Accent, earSize, UDim2.fromScale(earX, earY), 2)
			if ears == "Pointy" then
				ear.Rotation = 45
				ear:FindFirstChildOfClass("UICorner"):Destroy()
			end
		end
	end
	for _, side in { -1, 1 } do
		circle(body, Color3.fromRGB(25, 20, 30), UDim2.fromScale(0.16, 0.16), UDim2.fromScale(0.5 + side * 0.17, 0.42), 4)
	end
	if look.Extra == "Halo" then
		local halo = circle(holder, look.Accent, UDim2.fromScale(0.5, 0.12), UDim2.fromScale(0.5, 0.1), 5)
		halo.BackgroundTransparency = 0.2
	elseif look.Extra == "Horn" then
		local horn = circle(holder, look.Accent, UDim2.fromScale(0.08, 0.3), UDim2.fromScale(0.5, 0.2), 5)
		horn.Rotation = 10
	end
	return holder
end

return PetIcon
