--!nocheck
-- Builds the map with the real MapBuilder (offline engine) and writes docs/map.json:
-- every part as { n, x, y, z, sx, sy, sz, r, g, b, shape, ... } for tools/render_map.py
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Engine = require("../tests/engine")

local server = Engine.StartServer()
local map = server.Game:GetService("Workspace"):FindFirstChild("Map")
local out = {}
for _, d in rawget(map, "__real"):GetDescendants() do
	if d:IsA("BasePart") then
		local cf, s = d.CFrame, d.Size
		local right = cf.RightVector
		table.insert(out, {
			n = d.Name,
			x = cf.Position.X,
			y = cf.Position.Y,
			z = cf.Position.Z,
			-- world-space extents on X / Z (handles 90 degree rotations)
			ex = math.abs(right.X) * s.X + math.abs(cf.UpVector.X) * s.Y + math.abs(cf.LookVector.X) * s.Z,
			ez = math.abs(right.Z) * s.X + math.abs(cf.UpVector.Z) * s.Y + math.abs(cf.LookVector.Z) * s.Z,
			top = cf.Position.Y + (math.abs(right.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z) / 2,
			r = d.Color.R,
			g = d.Color.G,
			b = d.Color.B,
			round = d:IsA("Part") and (d.Shape.Name == "Ball" or d.Shape.Name == "Cylinder"),
			t = d.Transparency,
			blocker = d:GetAttribute("EnemyBlocker") == true,
		})
	end
end
fs.writeFile("docs/map.json", serde.encode("json", out))
print("parts:", #out)
