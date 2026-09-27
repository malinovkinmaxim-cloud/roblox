--[[
	Looks - the small part accessories that make a survivor recognisable: the character look
	(Sigma shades, Brainrot brain, 67 band...) and the cosmetic hats (shared/SkinData.lua).

	Pure data + one builder, used by
	  * the server (CharacterManager): parts WELDED to the player's real head
	  * the client menus (UI/Previews): ANCHORED parts on a preview head inside a ViewportFrame
	so a hat looks exactly the same in the shop and in the game.

	A piece: { Name, Size, Color, At (CFrame relative to the head centre), Shape?, Material?, Text? }
]]

local Looks = {}

local rgb = Color3.fromRGB
local BALL, CYL = Enum.PartType.Ball, Enum.PartType.Cylinder
local NEON = Enum.Material.Neon
local UP = CFrame.Angles(0, 0, math.rad(90)) -- cylinders stand up

export type Piece = {
	Name: string,
	Size: Vector3,
	Color: Color3,
	At: CFrame,
	Shape: Enum.PartType?,
	Material: Enum.Material?,
	Text: string?,
}

Looks.Characters = {
	Goober = {
		{ Name = "Antenna", Size = Vector3.new(0.15, 0.8, 0.15), Color = rgb(60, 60, 70), At = CFrame.new(0, 0.9, 0) },
		{ Name = "AntennaBall", Size = Vector3.new(0.45, 0.45, 0.45), Color = rgb(120, 220, 90), At = CFrame.new(0, 1.35, 0), Shape = BALL },
	},
	Sigma = {
		{ Name = "Shades", Size = Vector3.new(1.3, 0.3, 0.2), Color = rgb(15, 15, 20), At = CFrame.new(0, 0.15, -0.6) },
		{ Name = "Jaw", Size = Vector3.new(1.1, 0.35, 0.4), Color = rgb(230, 190, 150), At = CFrame.new(0, -0.55, -0.45) },
	},
	SixSeven = {
		{ Name = "Band67", Size = Vector3.new(1.28, 0.28, 1.28), Color = rgb(255, 205, 50), At = CFrame.new(0, 0.4, 0), Material = NEON },
		{ Name = "Tag67", Size = Vector3.new(0.7, 0.34, 0.06), Color = rgb(40, 20, 60), At = CFrame.new(0, 0.4, -0.66), Text = "67" },
	},
	Brainrot = {
		{ Name = "Brain", Size = Vector3.new(1.4, 0.9, 1.3), Color = rgb(255, 150, 190), At = CFrame.new(0, 0.75, 0), Shape = BALL },
		{ Name = "BrainLobe", Size = Vector3.new(0.9, 0.7, 0.9), Color = rgb(255, 130, 175), At = CFrame.new(0.25, 0.95, 0.1), Shape = BALL },
	},
	TheNPC = {
		{ Name = "Cap", Size = Vector3.new(1.3, 0.3, 1.4), Color = rgb(40, 127, 71), At = CFrame.new(0, 0.65, -0.1) },
	},
} :: { [string]: { Piece } }

Looks.Hats = {
	None = {},
	Cone = {
		{ Name = "Cone0", Size = Vector3.new(0.55, 1.3, 1.3), Color = rgb(255, 120, 30), At = CFrame.new(0, 0.85, 0) * UP, Shape = CYL },
		{ Name = "Cone1", Size = Vector3.new(0.55, 0.95, 0.95), Color = rgb(255, 255, 255), At = CFrame.new(0, 1.35, 0) * UP, Shape = CYL },
		{ Name = "Cone2", Size = Vector3.new(0.55, 0.6, 0.6), Color = rgb(255, 120, 30), At = CFrame.new(0, 1.85, 0) * UP, Shape = CYL },
	},
	BrainHat = {
		{ Name = "HatBrain", Size = Vector3.new(1.5, 1, 1.4), Color = rgb(255, 150, 190), At = CFrame.new(0, 0.8, 0), Shape = BALL },
		{ Name = "HatLobe", Size = Vector3.new(0.9, 0.8, 1), Color = rgb(255, 125, 170), At = CFrame.new(0.3, 1.05, 0.1), Shape = BALL },
	},
	Shades = {
		{ Name = "HatShades", Size = Vector3.new(1.35, 0.32, 0.2), Color = rgb(10, 10, 15), At = CFrame.new(0, 0.15, -0.62) },
		{ Name = "HatShadesBridge", Size = Vector3.new(1.45, 0.08, 0.1), Color = rgb(255, 205, 60), At = CFrame.new(0, 0.3, -0.66) },
	},
	Propeller = {
		{ Name = "CapTop", Size = Vector3.new(0.5, 1.35, 1.35), Color = rgb(60, 140, 255), At = CFrame.new(0, 0.72, 0) * UP, Shape = CYL },
		{ Name = "CapStick", Size = Vector3.new(0.1, 0.4, 0.1), Color = rgb(40, 40, 40), At = CFrame.new(0, 1.15, 0) },
		{ Name = "Blade", Size = Vector3.new(1.6, 0.06, 0.25), Color = rgb(255, 60, 70), At = CFrame.new(0, 1.35, 0) },
		{ Name = "Blade2", Size = Vector3.new(0.25, 0.06, 1.6), Color = rgb(255, 215, 60), At = CFrame.new(0, 1.35, 0) },
	},
	Headband67 = {
		{ Name = "Headband", Size = Vector3.new(1.3, 0.3, 1.3), Color = rgb(255, 205, 50), At = CFrame.new(0, 0.35, 0), Material = NEON },
		{ Name = "Tag67", Size = Vector3.new(0.6, 0.3, 0.05), Color = rgb(40, 20, 60), At = CFrame.new(0, 0.35, -0.68), Text = "67" },
	},
	Halo = {
		{ Name = "Halo", Size = Vector3.new(0.15, 1.5, 1.5), Color = rgb(255, 245, 170), At = CFrame.new(0, 1.2, 0) * UP, Shape = CYL, Material = NEON },
	},
	GoldAntenna = {
		{ Name = "GoldStick", Size = Vector3.new(0.15, 0.9, 0.15), Color = rgb(220, 170, 30), At = CFrame.new(0, 0.95, 0) },
		{ Name = "GoldBall", Size = Vector3.new(0.55, 0.55, 0.55), Color = rgb(255, 215, 50), At = CFrame.new(0, 1.45, 0), Shape = BALL, Material = NEON },
	},
	Crown = {
		{ Name = "CrownBand", Size = Vector3.new(1.3, 0.35, 1.3), Color = rgb(255, 205, 50), At = CFrame.new(0, 0.8, 0), Material = NEON },
		{ Name = "CrownSpikeL", Size = Vector3.new(0.3, 0.45, 0.3), Color = rgb(255, 215, 60), At = CFrame.new(-0.45, 1.15, -0.5), Material = NEON },
		{ Name = "CrownSpikeM", Size = Vector3.new(0.3, 0.45, 0.3), Color = rgb(255, 215, 60), At = CFrame.new(0, 1.15, -0.5), Material = NEON },
		{ Name = "CrownSpikeR", Size = Vector3.new(0.3, 0.45, 0.3), Color = rgb(255, 215, 60), At = CFrame.new(0.45, 1.15, -0.5), Material = NEON },
		{ Name = "CrownGem", Size = Vector3.new(0.25, 0.25, 0.1), Color = rgb(255, 60, 120), At = CFrame.new(0, 0.8, -0.68), Shape = BALL },
	},
} :: { [string]: { Piece } }

--[[
	Builds pieces around `head` into `container`.
	weld = true  -> unanchored, massless, welded to the head (a real character)
	weld = false -> anchored (a static preview)
]]
function Looks.Build(pieces: { Piece }, head: BasePart, container: Instance, weld: boolean)
	for _, piece in pieces do
		local p = Instance.new("Part")
		p.Name = piece.Name
		p.Size = piece.Size
		p.Color = piece.Color
		p.Material = piece.Material or Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		if piece.Shape then
			p.Shape = piece.Shape
		end
		p.CFrame = head.CFrame * piece.At
		if weld then
			p.Anchored = false
			p.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = p
			w.Part1 = head
			w.Parent = p
		else
			p.Anchored = true
		end
		if piece.Text then
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Front
			gui.LightInfluence = 0
			gui.CanvasSize = Vector2.new(120, 60)
			gui.Parent = p
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Text = piece.Text
			label.TextScaled = true
			label.Font = Enum.Font.LuckiestGuy
			label.TextColor3 = rgb(255, 215, 50)
			label.Parent = gui
		end
		p.Parent = container
	end
end

return Looks
