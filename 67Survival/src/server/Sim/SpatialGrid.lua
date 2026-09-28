--[[
	SpatialGrid - uniform hash grid for "who is near this point" queries.

	Rebuilt every simulation step (Clear + Insert all enemies). Cell arrays are reused
	between steps, so a rebuild allocates nothing once warm.
	Query() returns candidates from the overlapping cells; callers do the exact distance test.
]]

local SpatialGrid = {}
SpatialGrid.__index = SpatialGrid

export type Grid = {
	Size: number,
	Cells: { [number]: { N: number, [number]: any } },
	Used: { number },
}

local OFFSET = 2048 -- keeps keys positive for coordinates down to -OFFSET * Size

local function key(cx: number, cz: number): number
	return (cx + OFFSET) * 8192 + (cz + OFFSET)
end

function SpatialGrid.new(cellSize: number): Grid
	return setmetatable({ Size = cellSize, Cells = {}, Used = {} }, SpatialGrid) :: any
end

function SpatialGrid.Clear(self: Grid)
	local cells = self.Cells
	for _, k in self.Used do
		local cell = cells[k]
		for i = 1, cell.N do
			cell[i] = nil
		end
		cell.N = 0
	end
	table.clear(self.Used)
end

function SpatialGrid.Insert(self: Grid, item: any, x: number, z: number)
	local size = self.Size
	local k = key(math.floor(x / size), math.floor(z / size))
	local cell = self.Cells[k]
	if not cell then
		cell = { N = 0 }
		self.Cells[k] = cell
	end
	if cell.N == 0 then
		table.insert(self.Used, k)
	end
	cell.N += 1
	cell[cell.N] = item
end

-- Fills out[1..n] with candidates around (x, z) within radius r and returns n.
-- Entries after n are stale leftovers of earlier queries: always loop to n, never #out.
function SpatialGrid.Query(self: Grid, x: number, z: number, r: number, out: { any }): number
	local size = self.Size
	local cells = self.Cells
	local x0, x1 = math.floor((x - r) / size), math.floor((x + r) / size)
	local z0, z1 = math.floor((z - r) / size), math.floor((z + r) / size)
	local n = 0
	for cx = x0, x1 do
		for cz = z0, z1 do
			local cell = cells[key(cx, cz)]
			if cell then
				for i = 1, cell.N do
					n += 1
					out[n] = cell[i]
				end
			end
		end
	end
	return n
end

return SpatialGrid
