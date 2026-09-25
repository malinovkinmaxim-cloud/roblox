-- Tiny pixel-art sprites built from parts. A sprite is a list of rows (top to bottom), one
-- character per pixel; "." is empty. Palette maps characters to colours. Runs of the same colour in
-- a row become one part, so a sign stays cheap.
local PixelArt = {}

PixelArt.INK = Color3.fromRGB(45, 45, 70)

-- 9x8 bunny; "A" = body colour
PixelArt.BUNNY = {
	"..A...A..",
	"..A...A..",
	"..A...A..",
	".AAAAAAA.",
	".AAAAKAA.",
	".AAAAAAP.",
	".AAAAAAA.",
	"..F...F..",
}

-- 5x6 bunny for crowded signs
PixelArt.BUNNY_SMALL = {
	"A...A",
	"A...A",
	"AAAAA",
	"AAAKA",
	"AAAAP",
	".F.F.",
}

PixelArt.ENVELOPE = {
	"KKKKKKKKKKKKK",
	"KOKOOOOOOOKOK",
	"KOOKOOOOOKOOK",
	"KOOOKOOOKOOOK",
	"KOOOORRRROOOK",
	"KOOOORRRROOOK",
	"KOOOOORROOOOK",
	"KKKKKKKKKKKKK",
}

PixelArt.TROPHY = {
	"YYYYYYYYY",
	"Y.YYYYY.Y",
	"Y.YYYYY.Y",
	".YYYWYYY.",
	"..YYYYY..",
	"...YYY...",
	"....Y....",
	"...YYY...",
	"..KKKKK..",
}

local BASE_PALETTE = {
	K = PixelArt.INK,
	P = Color3.fromRGB(255, 150, 170),
	O = Color3.fromRGB(255, 252, 245),
	W = Color3.new(1, 1, 1),
	R = Color3.fromRGB(235, 80, 100),
	Y = Color3.fromRGB(255, 205, 60),
}

-- Layers: { rows = sprite, colors = { A = Color3, ... }, x = 0, y = 0 } in pixel units from the top-left.
-- The sprite is drawn in the XY plane of `cframe`, centred on it, readable from its -Z side
-- (build with CFrame.lookAt(position, position + directionAwayFromViewer)).
function PixelArt.build(layers, pixel, cframe, parent)
	local model = Instance.new("Model")
	model.Name = "PixelSprite"

	local width, height = 0, 0
	for _, layer in layers do
		width = math.max(width, (layer.x or 0) + #layer.rows[1])
		height = math.max(height, (layer.y or 0) + #layer.rows)
	end

	for _, layer in layers do
		for r, row in layer.rows do
			local c = 1
			while c <= #row do
				local ch = string.sub(row, c, c)
				local color = layer.colors and layer.colors[ch] or BASE_PALETTE[ch]
				if ch ~= "." and color then
					local first = c
					while c + 1 <= #row and string.sub(row, c + 1, c + 1) == ch do
						c += 1
					end
					local runLength = c - first + 1
					local px = (layer.x or 0) + first - 1 + runLength / 2 - width / 2
					local py = height / 2 - ((layer.y or 0) + r - 0.5)
					local part = Instance.new("Part")
					part.Name = "Pixel"
					part.Anchored = true
					part.CanCollide = false
					part.CanQuery = false
					part.CanTouch = false
					part.CastShadow = false
					part.Material = Enum.Material.SmoothPlastic
					part.Color = color
					part.Size = Vector3.new(runLength * pixel, pixel, pixel)
					part.CFrame = cframe * CFrame.new(px * pixel, py * pixel, 0)
					part.Parent = model
				end
				c += 1
			end
		end
	end

	model.Parent = parent
	return model, Vector2.new(width * pixel, height * pixel)
end

return PixelArt
