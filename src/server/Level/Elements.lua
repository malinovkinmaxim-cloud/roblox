--[[
	Elements
	Turns level element specs (see LevelKit) into Roblox Parts and runtime element objects.
	Runtime behaviour of the created elements lives in InteractionService / ObstacleService.

	Every builder returns an element table:
	  { Id, Type, Kind, Spec, Part, Parts, ... }
	Kind is what InteractionService reacts to when an actor overlaps the element's Part.
]]

local LevelKit = require(script.Parent.LevelKit)

local Colors = LevelKit.Colors

local Elements = {}
Elements.Builders = {}

local ACTIVATOR_COLORS = {
	Any = Colors.Any,
	Player = Colors.Player,
	Doppel = Colors.Doppel,
}
Elements.ActivatorColors = ACTIVATOR_COLORS

local function toCFrame(inst, pos: Vector3, rot: Vector3?): CFrame
	local cf = CFrame.new(inst.OriginPos + pos)
	if rot then
		cf *= CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
	end
	return cf
end

local function newPart(inst, folder: Instance, spec, defaults: { [string]: any }?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.CastShadow = true
	if defaults then
		for key, value in defaults do
			(part :: any)[key] = value
		end
	end
	if spec.Size then
		part.Size = spec.Size
	end
	if spec.Color then
		part.Color = spec.Color
	end
	if spec.Material then
		part.Material = spec.Material
	end
	if spec.Transparency then
		part.Transparency = spec.Transparency
	end
	part.CFrame = toCFrame(inst, spec.Pos, spec.Rot)
	part.Parent = folder
	return part
end

local function billboard(adornee: BasePart, text: string, color: Color3, sizeStuds: Vector2, offsetY: number, maxDistance: number?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.new(sizeStuds.X, 0, sizeStuds.Y, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or 90
	gui.AlwaysOnTop = false
	gui.Adornee = adornee

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.35
	label.TextStrokeColor3 = Color3.fromRGB(20, 22, 30)
	label.Text = text
	label.Parent = gui

	gui.Parent = adornee
	return gui, label
end
Elements.Billboard = billboard

local function makeElement(inst, spec, kind: string?, part: BasePart?)
	return {
		Id = spec.Id,
		Type = spec.Type,
		Kind = kind,
		Spec = spec,
		Part = part,
		Parts = { part },
		Instance = inst,
	}
end

local floorIndex = 0

---------------------------------------------------------------------------
-- Static
---------------------------------------------------------------------------

Elements.Builders.Platform = function(inst, spec)
	floorIndex += 1
	local part = newPart(inst, inst.Geometry, spec, {
		Color = if floorIndex % 2 == 0 then Colors.FloorAlt else Colors.Floor,
	})
	return makeElement(inst, spec, nil, part)
end

Elements.Builders.Decor = function(inst, spec)
	local part = newPart(inst, inst.Decor, spec, {
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Color = Colors.FloorAlt,
	})
	return makeElement(inst, spec, nil, part)
end

Elements.Builders.Start = function(inst, spec)
	local part = newPart(inst, inst.Geometry, {
		Pos = spec.Pos - Vector3.new(0, spec.Size.Y / 2, 0),
		Size = spec.Size,
		Color = spec.Color or Colors.Start,
	}, { Material = Enum.Material.SmoothPlastic })
	part.Name = "Start"
	local top = inst.OriginPos + spec.Pos
	local yaw = math.rad(spec.Yaw or -90) -- default: face +X
	inst.StartCFrame = CFrame.new(top + Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, yaw, 0)
	local doppelOffset = spec.DoppelOffset or Vector3.new(0, 0, -4)
	inst.DoppelStartCFrame = CFrame.new(top + doppelOffset + Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, yaw, 0)
	inst.Checkpoints[0] = {
		Index = 0,
		SpawnCFrame = inst.StartCFrame,
		DoppelCFrame = inst.DoppelStartCFrame,
	}
	return makeElement(inst, spec, nil, part)
end

Elements.Builders.Checkpoint = function(inst, spec)
	local part = newPart(inst, inst.Interactive, {
		Pos = spec.Pos - Vector3.new(0, spec.Size.Y / 2, 0),
		Size = spec.Size,
		Color = Colors.Checkpoint,
	})
	part.Name = "Checkpoint" .. spec.Index

	-- flag pole (decor)
	local pole = newPart(inst, inst.Decor, {
		Pos = spec.Pos + Vector3.new(0, 4, spec.Size.Z / 2 - 0.6),
		Size = Vector3.new(0.4, 8, 0.4),
		Color = Color3.fromRGB(220, 225, 235),
	}, { CanCollide = false, CanQuery = false, CanTouch = false })
	local flag = newPart(inst, inst.Decor, {
		Pos = spec.Pos + Vector3.new(1.4, 7, spec.Size.Z / 2 - 0.6),
		Size = Vector3.new(2.6, 1.6, 0.2),
		Color = Colors.Checkpoint,
	}, { CanCollide = false, CanQuery = false, CanTouch = false, Material = Enum.Material.SmoothPlastic })
	billboard(part, tostring(spec.Index), Color3.new(1, 1, 1), Vector2.new(3, 3), 9.5, 70)

	local top = inst.OriginPos + spec.Pos
	local yaw = math.rad(spec.Yaw or -90)
	local doppelOffset = spec.DoppelOffset or Vector3.new(0, 0, -3.5)
	local element = makeElement(inst, spec, "Checkpoint", part)
	element.Index = spec.Index
	element.Flag = flag
	element.Pole = pole
	inst.Checkpoints[spec.Index] = {
		Index = spec.Index,
		Element = element,
		SpawnCFrame = CFrame.new(top + Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, yaw, 0),
		DoppelCFrame = CFrame.new(top + doppelOffset + Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, yaw, 0),
		SetRole = spec.SetRole,
	}
	return element
end

Elements.Builders.Finish = function(inst, spec)
	local part = newPart(inst, inst.Interactive, {
		Pos = spec.Pos - Vector3.new(0, spec.Size.Y / 2, 0),
		Size = spec.Size,
		Color = Colors.Finish,
	}, { Material = Enum.Material.Neon })
	part.Name = "Finish"
	local half = spec.Size.Z / 2
	for _, side in { -1, 1 } do
		newPart(inst, inst.Decor, {
			Pos = spec.Pos + Vector3.new(0, 5, side * (half + 0.5)),
			Size = Vector3.new(1, 10, 1),
			Color = Color3.fromRGB(40, 44, 60),
		}, { CanCollide = false, CanQuery = false, CanTouch = false })
	end
	local top = newPart(inst, inst.Decor, {
		Pos = spec.Pos + Vector3.new(0, 10.5, 0),
		Size = Vector3.new(1, 1.2, spec.Size.Z + 2),
		Color = Color3.fromRGB(40, 44, 60),
	}, { CanCollide = false, CanQuery = false, CanTouch = false })
	billboard(top, "FINISH", Colors.Finish, Vector2.new(12, 3), 2.2, 160)
	inst.FinishPart = part
	local element = makeElement(inst, spec, "Finish", part)
	inst.FinishElement = element
	return element
end

Elements.Builders.Sign = function(inst, spec)
	local anchor = newPart(inst, inst.Decor, {
		Pos = spec.Pos,
		Size = Vector3.new(0.2, 0.2, 0.2),
	}, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	anchor.Name = "Sign"
	local width = spec.Width or 22
	local height = spec.Height or 4
	local gui, label = billboard(anchor, spec.Text, spec.TextColor or Color3.new(1, 1, 1), Vector2.new(width, height), 0, spec.MaxDistance or 70)
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0.15
	gui.Name = "SignGui"
	local element = makeElement(inst, spec, nil, anchor)
	element.Label = label
	return element
end

---------------------------------------------------------------------------
-- Hazards
---------------------------------------------------------------------------

Elements.Builders.Kill = function(inst, spec)
	local part = newPart(inst, inst.Interactive, spec, {
		Color = Colors.Kill,
		Material = Enum.Material.Neon,
	})
	part.Name = "KillBrick"
	return makeElement(inst, spec, "Kill", part)
end

Elements.Builders.Laser = function(inst, spec)
	local part = newPart(inst, inst.Interactive, spec, {
		Color = Colors.Laser,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	part.Name = "Laser"
	-- emitters at both ends of the longest axis
	local size = spec.Size
	local axis
	if size.X >= size.Y and size.X >= size.Z then
		axis = Vector3.new(size.X / 2 + 0.5, 0, 0)
	elseif size.Z >= size.Y then
		axis = Vector3.new(0, 0, size.Z / 2 + 0.5)
	else
		axis = Vector3.new(0, size.Y / 2 + 0.5, 0)
	end
	for _, sign in { -1, 1 } do
		newPart(inst, inst.Geometry, {
			Pos = spec.Pos + axis * sign,
			Size = Vector3.new(1.2, 1.2, 1.2),
			Color = Color3.fromRGB(45, 48, 62),
		})
	end
	local element = makeElement(inst, spec, "Laser", part)
	element.Trap = spec.Trap == true
	element.On = not element.Trap
	element.LethalAt = 0
	element.Powered = false
	element.Warning = false
	table.insert(inst.Lasers, element)
	return element
end

Elements.Builders.RotatingBeam = function(inst, spec)
	local pos = spec.Pos
	-- pivot post from the floor below up to the beam
	local postHeight = spec.PostHeight or 3
	newPart(inst, inst.Geometry, {
		Pos = pos - Vector3.new(0, postHeight / 2, 0),
		Size = Vector3.new(1.4, postHeight + 1, 1.4),
		Color = Color3.fromRGB(45, 48, 62),
	})
	local thickness = spec.Thickness or 1
	-- The beam's rotation is deterministic: angle = StartAngle + Speed * (serverTime - SpinStart).
	-- Clients animate it locally (smooth, zero network cost), the server checks hits with math
	-- (InteractionService), so the part itself never moves on the server.
	local beam = newPart(inst, inst.Decor, {
		Pos = pos,
		Size = Vector3.new(spec.Length, thickness, thickness),
	}, {
		Color = Color3.fromRGB(255, 90, 60),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	beam.Name = "RotatingBeam"
	local element = makeElement(inst, spec, "Beam", beam)
	element.PivotCFrame = CFrame.new(inst.OriginPos + pos)
	element.Speed = spec.Speed or 1.5
	element.StartAngle = spec.StartAngle or 0
	element.Length = spec.Length
	element.Thickness = thickness
	beam:SetAttribute("PivotCFrame", element.PivotCFrame)
	beam:SetAttribute("Speed", element.Speed)
	beam:SetAttribute("StartAngle", element.StartAngle)
	beam:AddTag("DoppelSpinBeam")
	table.insert(inst.Beams, element)
	return element
end

---------------------------------------------------------------------------
-- Special platforms
---------------------------------------------------------------------------

Elements.Builders.MovingPlatform = function(inst, spec)
	local part = newPart(inst, inst.Geometry, spec, {
		Color = Colors.Mover,
		Anchored = false,
	})
	part.Name = "MovingPlatform"
	part.CollisionGroup = "Movers"
	part.CustomPhysicalProperties = PhysicalProperties.new(20, 1, 0, 1, 1)
	local attachment = Instance.new("Attachment")
	attachment.Name = "MoverAttachment"
	attachment.Parent = part

	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPosition.Attachment0 = attachment
	alignPosition.MaxForce = math.huge
	alignPosition.MaxVelocity = math.huge
	alignPosition.Responsiveness = 60
	alignPosition.Position = part.Position
	alignPosition.Parent = part

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = attachment
	alignOrientation.RigidityEnabled = true
	alignOrientation.CFrame = part.CFrame
	alignOrientation.Parent = part

	local element = makeElement(inst, spec, nil, part)
	element.BaseCFrame = part.CFrame
	element.AlignPosition = alignPosition
	element.Motion = spec.Motion or { Kind = "Linear", Offset = Vector3.new(0, 0, 10), Period = 4 }
	element.Powered = not spec.Powered -- unpowered platforms always move
	element.RequiresPower = spec.Powered == true
	element.Clock = spec.Motion and spec.Motion.Phase or 0
	element.Physics = true
	table.insert(inst.Movers, element)
	return element
end

Elements.Builders.Disappearing = function(inst, spec)
	local part = newPart(inst, inst.Geometry, spec, {
		Color = Colors.Vanish,
	})
	part.Name = "Disappearing"
	local element = makeElement(inst, spec, nil, part)
	element.Cycle = spec.Cycle or { Visible = 2, Hidden = 1.5, Phase = 0 }
	element.Visible = true
	element.Blinking = false
	table.insert(inst.Cyclic, element)
	return element
end

Elements.Builders.Falling = function(inst, spec)
	local part = newPart(inst, inst.Interactive, spec, {
		Color = Colors.Falling,
	})
	part.Name = "FallingPlatform"
	local element = makeElement(inst, spec, "Falling", part)
	element.BaseCFrame = part.CFrame
	element.Triggered = false
	return element
end

Elements.Builders.Fake = function(inst, spec)
	local isFake = true
	if spec.Group then
		isFake = inst.FakeSelection[spec.Id] == true
	end
	floorIndex += 1
	local part = newPart(inst, if isFake then inst.Interactive else inst.Geometry, spec, {
		Color = if floorIndex % 2 == 0 then Colors.FloorAlt else Colors.Floor,
	})
	part.Name = if isFake then "Platform " else "Platform" -- identical look on purpose
	local element = makeElement(inst, spec, if isFake then "Fake" else nil, part)
	element.IsFake = isFake
	element.Revealed = false
	element.Lure = spec.Lure == true
	return element
end

Elements.Builders.LaunchPad = function(inst, spec)
	local part = newPart(inst, inst.Interactive, {
		Pos = spec.Pos + Vector3.new(0, spec.Size.Y / 2, 0),
		Size = spec.Size,
		Color = Colors.Launch,
	}, { Material = Enum.Material.Neon })
	part.Name = "LaunchPad"
	billboard(part, "^", Colors.Launch, Vector2.new(2.5, 2.5), 2, 50)
	local element = makeElement(inst, spec, "Launch", part)
	element.Velocity = spec.Velocity
	return element
end

Elements.Builders.TeleportPad = function(inst, spec)
	local part = newPart(inst, inst.Interactive, {
		Pos = spec.Pos + Vector3.new(0, spec.Size.Y / 2, 0),
		Size = spec.Size,
		Color = Colors.Teleport,
	}, { Material = Enum.Material.Neon })
	part.Name = "TeleportPad"
	local element = makeElement(inst, spec, "Teleport", part)
	element.TargetPos = inst.OriginPos + spec.Target
	return element
end

---------------------------------------------------------------------------
-- Interaction sources and targets
---------------------------------------------------------------------------

Elements.Builders.Button = function(inst, spec)
	local color = ACTIVATOR_COLORS[spec.Activator] or Colors.Any
	local isPlate = spec.Mode == "Hold"
	local part: BasePart
	local base: BasePart? = nil
	if isPlate then
		part = newPart(inst, inst.Interactive, {
			Pos = spec.Pos + Vector3.new(0, spec.Size.Y / 2, 0),
			Size = spec.Size,
			Color = color,
		})
		-- dark frame so plates read as "a thing you stand on"
		base = newPart(inst, inst.Geometry, {
			Pos = spec.Pos + Vector3.new(0, 0.1, 0),
			Size = spec.Size + Vector3.new(1, -spec.Size.Y + 0.2, 1),
			Color = Color3.fromRGB(40, 44, 60),
		})
	else
		base = newPart(inst, inst.Geometry, {
			Pos = spec.Pos + Vector3.new(0, 0.15, 0),
			Size = Vector3.new(spec.Size.X + 1, 0.3, spec.Size.Z + 1),
			Color = Color3.fromRGB(40, 44, 60),
		})
		part = newPart(inst, inst.Interactive, {
			Pos = spec.Pos + Vector3.new(0, 0.55, 0),
			Size = Vector3.new(0.5, spec.Size.X, spec.Size.Z),
			Rot = Vector3.new(0, 0, 90),
			Color = color,
		}, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	end
	part.Name = if isPlate then "PressurePlate" else "Button"
	part:SetAttribute("DoppelgangerInteraction", spec.Activator ~= "Player")

	if spec.Activator == "Doppel" then
		billboard(part, spec.Label or "DOPPEL", Colors.Doppel, Vector2.new(5, 1.4), 2.4, 45)
	elseif spec.Activator == "Player" then
		billboard(part, spec.Label or "YOU", Colors.Player, Vector2.new(4, 1.4), 2.4, 45)
	elseif spec.Label then
		billboard(part, spec.Label, Colors.Any, Vector2.new(4, 1.4), 2.4, 45)
	end

	local click = Instance.new("Sound")
	click.Name = "Click"
	click.SoundId = "rbxasset://sounds/button.wav"
	click.Volume = 0.6
	click.RollOffMaxDistance = 80
	click.Parent = part

	local element = makeElement(inst, spec, "Source", part)
	element.Base = base
	element.BaseColor = color
	element.PartCFrame = part.CFrame
	element.Mode = spec.Mode or "Timed"
	element.Activator = spec.Activator or "Any"
	element.Duration = spec.Duration or 6
	element.ReleaseDelay = spec.ReleaseDelay or 0
	element.Targets = table.clone(spec.Targets or {})
	element.Active = false
	element.Occupied = false
	element.WasOccupied = false
	element.ActiveUntil = 0
	element.LastOccupied = -math.huge
	element.Bad = spec.Bad == true
	element.AllyTarget = spec.Activator ~= "Player"
	element.Sound = click
	table.insert(inst.Sources, element)
	if element.AllyTarget then
		table.insert(inst.AllyTargets, element)
	end
	return element
end

Elements.Builders.Door = function(inst, spec)
	local isBridge = spec.Bridge == true
	local part = newPart(inst, if isBridge then inst.Geometry else inst.Blockers, spec, {
		Color = if isBridge then Colors.Mover else Colors.Door,
	})
	part.Name = if isBridge then "Bridge" else "Door"
	local element = makeElement(inst, spec, nil, part)
	element.ClosedCFrame = part.CFrame
	element.OpenCFrame = part.CFrame + (spec.OpenOffset or Vector3.new(0, -(spec.Size.Y + 0.2), 0))
	element.IsBridge = isBridge
	element.Logic = spec.Logic or "Any"
	element.Open = false
	element.Powered = false
	if spec.Cycle then
		element.Cycle = spec.Cycle
		table.insert(inst.Cyclic, element)
	end
	table.insert(inst.Doors, element)
	return element
end

return Elements
