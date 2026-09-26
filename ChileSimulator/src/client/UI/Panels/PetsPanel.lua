--[[
	PetsPanel - simple on purpose: tap a pet to equip / unequip, EQUIP BEST, delete mode.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared.PetConfig)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Widgets = require(UI.Widgets)
local PetIcon = require(UI.PetIcon)

local Panel = { Title = "PETS", Icon = "🐾", Color = Theme.Colors.Orange }

function Panel.Create(content: Frame, controllers)
	local data = controllers.ClientData
	local deleteMode = false
	local armed: string? = nil

	local info = Kit.Label({
		Size = UDim2.new(1, -330, 0, 40),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	})
	Kit.Button({
		Text = "⭐ EQUIP BEST",
		Color = Theme.Colors.Green,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -170, 0, 0),
		Size = UDim2.fromOffset(160, 40),
		Parent = content,
		OnClick = function()
			data:Fire("EquipBest")
		end,
	})
	local deleteButton, deleteLabel = Kit.Button({
		Text = "🗑️ DELETE",
		Color = Theme.Colors.GrayDark,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(160, 40),
		Parent = content,
	})
	local holder = Kit.New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 1, -50),
		Parent = content,
	})
	local grid = Widgets.Scroll(holder, nil, Vector2.new(100, 124), 8)
	local empty = Kit.Label({
		Position = UDim2.fromOffset(0, 120),
		Size = UDim2.new(1, 0, 0, 40),
		Text = "Walk to an egg 🥚 and hatch your first pet!",
		TextColor3 = Theme.Colors.TextDim,
		Visible = false,
		Parent = holder,
	})

	local api = {}
	function api.Refresh()
		local pets = data:Get("Pets")
		if not pets then
			return
		end
		Widgets.Clear(grid)
		local list = {}
		local equipped = 0
		for uid, pet in pets.List do
			local def = PetConfig.Pets[pet.Id]
			if def then
				table.insert(list, { Uid = uid, Id = pet.Id, E = pet.E, Def = def })
				if pet.E then
					equipped += 1
				end
			end
		end
		table.sort(list, function(a, b)
			if a.E ~= b.E then
				return a.E
			end
			if a.Def.Mult ~= b.Def.Mult then
				return a.Def.Mult > b.Def.Mult
			end
			return a.Uid < b.Uid
		end)
		info.Text = string.format("Equipped %d/%d  •  Storage %d/%d  •  Bonus %s", equipped, pets.EquipLimit, #list, pets.Capacity, Format.Mult(pets.Multiplier))
		empty.Visible = #list == 0
		deleteLabel.Text = if deleteMode then "✔ DONE" else "🗑️ DELETE"
		Kit.SetButtonColor(deleteButton, if deleteMode then Theme.Colors.Red else Theme.Colors.GrayDark)

		for i, pet in list do
			local rarity = PetConfig.Rarities[pet.Def.Rarity]
			local card = Kit.New("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = if pet.E then Color3.fromRGB(50, 110, 60) else Theme.Colors.PanelDark,
				LayoutOrder = i,
				Parent = grid,
			})
			Kit.Corner(card, 12)
			Kit.Stroke(card, 3, if pet.Def.Rarity == "Secret" then Color3.fromRGB(255, 90, 230) else rarity.Color)
			PetIcon.Create(card, pet.Id, UDim2.fromOffset(64, 64), UDim2.fromOffset(18, 4))
			Kit.Label({
				Position = UDim2.fromOffset(4, 68),
				Size = UDim2.new(1, -8, 0, 20),
				Text = pet.Def.Name,
				Parent = card,
			})
			Kit.Label({
				Position = UDim2.fromOffset(4, 88),
				Size = UDim2.new(1, -8, 0, 18),
				Text = Format.Mult(pet.Def.Mult),
				TextColor3 = Theme.Colors.Green,
				Parent = card,
			})
			local status = Kit.Label({
				Position = UDim2.fromOffset(4, 105),
				Size = UDim2.new(1, -8, 0, 16),
				Text = if deleteMode and armed == pet.Uid then "TAP AGAIN!" elseif pet.E then "✔ EQUIPPED" else "",
				TextColor3 = if deleteMode then Theme.Colors.Red else Color3.fromRGB(180, 255, 180),
				Parent = card,
			})
			card.Activated:Connect(function()
				controllers.SoundController:Play("Click")
				if deleteMode then
					if armed == pet.Uid then
						armed = nil
						data:Fire("DeletePet", pet.Uid)
					else
						armed = pet.Uid
						status.Text = "TAP AGAIN!"
					end
				else
					data:Fire("EquipPet", pet.Uid, not pet.E)
				end
			end)
		end
	end
	deleteButton.Activated:Connect(function()
		deleteMode = not deleteMode
		armed = nil
		api.Refresh()
	end)
	function api.OnClose()
		deleteMode = false
		armed = nil
	end
	return api
end

return Panel
