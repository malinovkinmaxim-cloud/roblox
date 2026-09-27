--[[
	Pool - reuses client-side models instead of creating / destroying them.

	Pool.new(folder, build) where build(key) -> (model, root, info)
	pool:Acquire(key) returns a parked or new model; pool:Release(item) parks it far below
	the map (a single CFrame write, no reparenting).
]]

local Pool = {}
Pool.__index = Pool

local PARK = CFrame.new(0, -400, 0)

export type Item = { Key: string, Model: Model, Root: BasePart, Info: any }

function Pool.new(folder: Instance, build: (key: string) -> (Model, BasePart, any))
	return setmetatable({ Folder = folder, Build = build, Free = {}, Created = 0, InUse = 0 }, Pool)
end

function Pool:Acquire(key: string): Item
	local free = self.Free[key]
	local item = free and table.remove(free)
	if not item then
		local model, root, info = self.Build(key)
		model.Parent = self.Folder
		item = { Key = key, Model = model, Root = root, Info = info }
		self.Created += 1
	end
	self.InUse += 1
	return item
end

function Pool:Release(item: Item)
	item.Root.CFrame = PARK
	local free = self.Free[item.Key]
	if not free then
		free = {}
		self.Free[item.Key] = free
	end
	table.insert(free, item)
	self.InUse -= 1
end

function Pool:Count(): number
	return self.Created
end

return Pool
