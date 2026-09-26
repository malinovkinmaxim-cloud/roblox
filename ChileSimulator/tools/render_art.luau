--[[
	Renders store / docs art as SVG from the GAME'S OWN BodyShape module, so the pictures show
	exactly the proportions the game uses.
	Run from ChileSimulator/:   lune run tools/render_art.luau
	Output: docs/growth.svg, docs/icon.svg, docs/thumbnail.svg (convert to PNG with any browser)
]]

local fs = require("@lune/fs")
local H = require("../tests/harness")

local BodyShape = H.Require("ReplicatedStorage.Shared.BodyShape")
local Format = H.Require("ReplicatedStorage.Shared.Util.Format")

local SKIN = "#F5CD30"
local SHIRT = "#D52B1E" -- Chile red
local PANTS = "#0039A6" -- Chile blue
local SHOES = "#23232b"
local OUTLINE = "#1b1530"

local function r(x: number): string
	return string.format("%.1f", x)
end

local function rect(x, y, w, h, fill, rx, stroke)
	return string.format(
		'<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="%s" stroke="%s" stroke-width="%s"/>',
		r(x), r(y), r(math.max(w, 1)), r(math.max(h, 1)), r(rx or 0), fill, OUTLINE, r(stroke or 0)
	)
end

-- A stretched character standing on groundY, centred on cx, `s` pixels per stud.
local function figure(shape, cx: number, groundY: number, s: number, outline: number?): string
	local out = {}
	local o = outline or math.clamp(shape.Width * s * 0.04, 0.6, 4)
	local W, LW = shape.Width * s, shape.LimbWidth * s
	local legs, torso = shape.Legs * s, shape.Torso * s
	local shoeH = math.clamp(shape.Legs * 0.1, 0.06, 4) * s
	-- legs + shoes
	for _, side in { -1, 1 } do
		local lx = cx + side * W / 4 - LW / 2
		table.insert(out, rect(lx, groundY - legs, LW * 0.98, legs, PANTS, LW * 0.1, o))
		table.insert(out, rect(lx - LW * 0.05, groundY - shoeH, LW * 1.1, shoeH, SHOES, shoeH * 0.3, o))
	end
	-- torso (with a white stripe + star: Chile flag vibes)
	local torsoTop = groundY - legs - torso
	table.insert(out, rect(cx - W / 2, torsoTop, W, torso, SHIRT, W * 0.08, o))
	if W > 14 and torso > 14 then
		local star = math.min(W, torso) * 0.18
		table.insert(out, string.format('<text x="%s" y="%s" font-size="%s" text-anchor="middle" fill="#ffffff" font-family="Arial">★</text>', r(cx), r(torsoTop + star * 1.6), r(star * 1.6)))
	end
	-- arms: sleeve + skin
	local armLen = shape.ArmLength * s
	local AW = shape.ArmWidth * s
	local upper, lower = armLen * 0.45, armLen * 0.55
	for _, side in { -1, 1 } do
		local ax = cx + side * (W / 2 + AW * 0.45) - AW / 2
		local shoulder = groundY - legs - torso + AW * 0.35
		table.insert(out, rect(ax, shoulder, AW * 1.02, upper, SHIRT, AW * 0.15, o))
		table.insert(out, rect(ax + AW * 0.05, shoulder + upper, AW * 0.9, lower, SKIN, AW * 0.2, o))
	end
	-- head with a face
	local hs = shape.Head * s
	local hx, hy = cx - hs / 2, torsoTop - hs
	table.insert(out, rect(hx, hy, hs, hs, SKIN, hs * 0.28, math.max(o, hs * 0.03)))
	local eye = math.max(0.8, hs * 0.08)
	table.insert(out, string.format('<circle cx="%s" cy="%s" r="%s" fill="%s"/>', r(cx - hs * 0.17), r(hy + hs * 0.42), r(eye), OUTLINE))
	table.insert(out, string.format('<circle cx="%s" cy="%s" r="%s" fill="%s"/>', r(cx + hs * 0.17), r(hy + hs * 0.42), r(eye), OUTLINE))
	table.insert(out, string.format(
		'<path d="M %s %s Q %s %s %s %s" stroke="%s" stroke-width="%s" fill="none" stroke-linecap="round"/>',
		r(cx - hs * 0.2), r(hy + hs * 0.64), r(cx), r(hy + hs * 0.8), r(cx + hs * 0.2), r(hy + hs * 0.64), OUTLINE, r(math.max(0.8, hs * 0.05))
	))
	return table.concat(out, "\n")
end

local function label(x, y, text, size, fill, anchor, weight)
	return string.format(
		'<text x="%s" y="%s" font-size="%s" fill="%s" text-anchor="%s" font-family="Arial Black, Arial, sans-serif" font-weight="%s" stroke="%s" stroke-width="%s" paint-order="stroke">%s</text>',
		r(x), r(y), r(size), fill or "#ffffff", anchor or "middle", weight or "900", OUTLINE, r(size * 0.12), text
	)
end

local function svg(w, h, body)
	return string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">\n%s\n</svg>\n', w, h, w, h, body)
end

---------------------------------------------------------------------------
-- growth chart
---------------------------------------------------------------------------
do
	local parts = {}
	table.insert(parts, [[<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1d1f5c"/><stop offset="0.55" stop-color="#4a7fe0"/><stop offset="1" stop-color="#a8e0ff"/></linearGradient></defs>]])
	table.insert(parts, '<rect width="1600" height="900" fill="url(#sky)"/>')
	table.insert(parts, '<rect y="820" width="1600" height="80" fill="#57c24a"/>')
	table.insert(parts, label(800, 58, "CHILE SIMULATOR  •  TAP → GET TALLER", 44, "#ffffff"))
	table.insert(parts, label(800, 92, "rendered from the game's BodyShape module: taller = thinner, the head stays small", 20, "#d8e6ff", "middle", "700"))

	-- panel A: the first minutes, one scale
	table.insert(parts, '<rect x="30" y="120" width="690" height="700" rx="18" fill="#ffffff" fill-opacity="0.08"/>')
	table.insert(parts, label(375, 160, "FIRST MINUTES (same scale)", 26, "#ffe066"))
	local early = { 0.01, 0.1, 1, 3, 10 }
	local sA = 26
	local x = 50
	for _, meters in early do
		local shape = BodyShape.FromHeight(meters * 100)
		local half = (shape.Width / 2 + shape.LimbWidth) * sA
		x += half
		table.insert(parts, figure(shape, x, 820, sA))
		table.insert(parts, label(x, 862, Format.Length(meters * 100), 20, "#ffffff"))
		x += half + 22
	end

	-- panel B: later, one (much smaller) scale
	table.insert(parts, '<rect x="740" y="120" width="830" height="700" rx="18" fill="#ffffff" fill-opacity="0.08"/>')
	table.insert(parts, label(1155, 160, "LATER (same scale, 17x smaller)", 26, "#ffe066"))
	local late = { 10, 1e3, 1e5, 4.3e6, 1e9, 1e12, 1e15 }
	local sB = 2.0
	for i, meters in late do
		local x = 800 + (i - 1) * 118
		local shape = BodyShape.FromHeight(meters * 100)
		table.insert(parts, figure(shape, x, 820, sB, 0.8))
		table.insert(parts, label(x, 862, Format.Length(meters * 100), 20, "#ffffff"))
		if meters == 4.3e6 then
			table.insert(parts, label(x, 884, "length of Chile!", 13, "#ffe066"))
		end
	end
	fs.writeFile("docs/growth.svg", svg(1600, 900, table.concat(parts, "\n")))
end

---------------------------------------------------------------------------
-- icon 512x512: tall stretched guy next to a flat cutlet, ruler behind, GET TALL!
---------------------------------------------------------------------------
do
	local parts = {}
	table.insert(parts, [[<defs><radialGradient id="bg" cx="0.5" cy="0.35" r="0.8"><stop offset="0" stop-color="#8fe3ff"/><stop offset="0.6" stop-color="#3b8cff"/><stop offset="1" stop-color="#2a3fb8"/></radialGradient></defs>]])
	table.insert(parts, '<rect width="512" height="512" rx="0" fill="url(#bg)"/>')
	-- ruler
	table.insert(parts, '<rect x="440" y="20" width="30" height="410" rx="6" fill="#ffffff" stroke="' .. OUTLINE .. '" stroke-width="4"/>')
	for i = 0, 10 do
		local y = 430 - i * 40
		table.insert(parts, string.format('<rect x="440" y="%d" width="%d" height="4" fill="%s"/>', y - 2, if i % 2 == 0 then 22 else 12, OUTLINE))
	end
	table.insert(parts, '<rect y="430" width="512" height="82" fill="#4cc93f" stroke="' .. OUTLINE .. '" stroke-width="4"/>')
	table.insert(parts, figure(BodyShape.FromHeight(1e8), 330, 432, 5.0, 3))
	table.insert(parts, figure(BodyShape.FromHeight(1), 140, 432, 30, 3))
	table.insert(parts, label(256, 500, "GET TALL!", 76, "#ffe23d"))
	fs.writeFile("docs/icon.svg", svg(512, 512, table.concat(parts, "\n")))
end

---------------------------------------------------------------------------
-- thumbnail 1920x1080: flat guy -> absurdly tall guy leaving the frame
---------------------------------------------------------------------------
do
	local parts = {}
	table.insert(parts, [[<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3a64ff"/><stop offset="1" stop-color="#bfe9ff"/></linearGradient></defs>]])
	table.insert(parts, '<rect width="1920" height="1080" fill="url(#sky)"/>')
	-- skyline + clouds for scale
	local skyline = { { 980, 180, 90 }, { 1080, 260, 80 }, { 1170, 150, 100 }, { 1290, 320, 90 }, { 1400, 210, 120 }, { 1540, 280, 90 }, { 1650, 170, 110 }, { 1780, 240, 100 } }
	for _, b in skyline do
		table.insert(parts, string.format('<rect x="%d" y="%d" width="%d" height="%d" fill="#5a6a90" stroke="%s" stroke-width="4"/>', b[1], 960 - b[2], b[3], b[2], OUTLINE))
	end
	for _, c in { { 1200, 380 }, { 1650, 300 }, { 300, 250 }, { 700, 160 } } do
		table.insert(parts, string.format('<ellipse cx="%d" cy="%d" rx="130" ry="42" fill="#ffffff" fill-opacity="0.9"/>', c[1], c[2]))
	end
	table.insert(parts, '<rect y="960" width="1920" height="120" fill="#4cc93f" stroke="' .. OUTLINE .. '" stroke-width="6"/>')
	-- left: the flat little guy
	table.insert(parts, figure(BodyShape.FromHeight(1), 360, 962, 62, 4))
	table.insert(parts, label(360, 760, "1 TAP", 110, "#ffffff"))
	-- middle arrow
	table.insert(parts, '<path d="M 640 700 L 880 700 L 880 650 L 990 740 L 880 830 L 880 780 L 640 780 Z" fill="#ffe23d" stroke="' .. OUTLINE .. '" stroke-width="8" stroke-linejoin="round"/>')
	-- right: head far above the top edge
	table.insert(parts, figure(BodyShape.FromHeight(1e11), 1420, 962, 7.2, 5))
	table.insert(parts, label(1880, 560, "HUGE", 150, "#ffe23d", "end"))
	fs.writeFile("docs/thumbnail.svg", svg(1920, 1080, table.concat(parts, "\n")))
end

print("wrote docs/growth.svg, docs/icon.svg, docs/thumbnail.svg")
