--[[
	Pets (logic) - hatching (server-side RNG), equipping, deleting, multiplier.

	Hatch validation: egg exists, egg zone unlocked, count 1..MaxHatchCount, enough coins,
	enough storage. The client only says "hatch Basic x3".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared.PetConfig)
local ZoneConfig = require(Shared.ZoneConfig)
local ShopConfig = require(Shared.ShopConfig)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Num = require(Shared.Util.Num)

local Session = require(script.Parent.Session)

local Pets = {}

function Pets.Count(session): number
	local n = 0
	for _ in session.Data.Pets do
		n += 1
	end
	return n
end

function Pets.Capacity(session): number
	local cap = PetConfig.BaseStorage + session.Data.Gem.Storage * PetConfig.StoragePerGemLevel
	if session.Passes.ExtraStorage then
		cap += ShopConfig.ExtraStorageCount
	end
	return cap
end

function Pets.EquipLimit(session): number
	local limit = PetConfig.BaseEquip
	if session.Passes.ExtraEquip then
		limit += ShopConfig.ExtraEquipCount
	end
	return limit
end

function Pets.EquippedList(session): { string }
	local list = {}
	for uid, pet in session.Data.Pets do
		if pet.E then
			table.insert(list, uid)
		end
	end
	return list
end

local function mult(pet): number
	local def = PetConfig.Pets[pet.Id]
	return def and def.Mult or 1
end

function Pets.Multiplier(session): number
	if session.PetMultCache then
		return session.PetMultCache
	end
	local mults = {}
	local limit = Pets.EquipLimit(session)
	for _, pet in session.Data.Pets do
		if pet.E and #mults < limit then
			table.insert(mults, mult(pet))
		end
	end
	local value = Formulas.PetMultiplier(mults)
	session.PetMultCache = value
	return value
end

local function changed(session)
	session.PetMultCache = nil
	session.AttrDirty = true
	Session.MarkDirty(session, "Pets", "Rates")
end

-- Makes sure no more than the equip limit is equipped (e.g. a pass expired in Studio)
function Pets.Validate(session)
	local equipped = Pets.EquippedList(session)
	local limit = Pets.EquipLimit(session)
	if #equipped > limit then
		table.sort(equipped, function(a, b)
			return mult(session.Data.Pets[a]) > mult(session.Data.Pets[b])
		end)
		for i = limit + 1, #equipped do
			session.Data.Pets[equipped[i]].E = false
		end
		changed(session)
	end
end

function Pets.Equip(session, uid: string, equip: boolean): (boolean, string?)
	local pet = session.Data.Pets[uid]
	if not pet then
		return false, "Pet not found"
	end
	if pet.E == equip then
		return true
	end
	if equip and #Pets.EquippedList(session) >= Pets.EquipLimit(session) then
		return false, "Unequip a pet first (max " .. Pets.EquipLimit(session) .. ")"
	end
	pet.E = equip
	changed(session)
	return true
end

function Pets.EquipBest(session)
	local all = {}
	for uid, pet in session.Data.Pets do
		pet.E = false
		table.insert(all, uid)
	end
	table.sort(all, function(a, b)
		local ma, mb = mult(session.Data.Pets[a]), mult(session.Data.Pets[b])
		if ma == mb then
			return a < b
		end
		return ma > mb
	end)
	for i = 1, math.min(#all, Pets.EquipLimit(session)) do
		session.Data.Pets[all[i]].E = true
	end
	changed(session)
end

function Pets.Delete(session, uid: string): (boolean, string?)
	local pet = session.Data.Pets[uid]
	if not pet then
		return false, "Pet not found"
	end
	session.Data.Pets[uid] = nil
	changed(session)
	return true
end

-- Adds a pet; auto-equips it when a slot is free or it beats the weakest equipped pet.
function Pets.Give(session, petId: string): string?
	if not PetConfig.Pets[petId] then
		return nil
	end
	if Pets.Count(session) >= Pets.Capacity(session) then
		return nil
	end
	local data = session.Data
	local uid = tostring(data.NextPetUid)
	data.NextPetUid += 1
	data.Pets[uid] = { Id = petId, E = false }

	local equipped = Pets.EquippedList(session)
	if #equipped < Pets.EquipLimit(session) then
		data.Pets[uid].E = true
	else
		local weakestUid, weakest = nil, math.huge
		for _, e in equipped do
			local m = mult(data.Pets[e])
			if m < weakest then
				weakest, weakestUid = m, e
			end
		end
		if weakestUid and PetConfig.Pets[petId].Mult > weakest then
			data.Pets[weakestUid].E = false
			data.Pets[uid].E = true
		end
	end

	local rarity = PetConfig.Pets[petId].Rarity
	data.Stats.Hatched += 1
	if rarity == "Legendary" or rarity == "Mythic" or rarity == "Secret" then
		data.Stats.Legendaries += 1
	end
	if rarity == "Secret" then
		data.Stats.Secrets += 1
	end
	changed(session)
	return uid
end

function Pets.LuckMultiplier(session): number
	return 1 + session.Data.Gem.Luck * PetConfig.LuckPerGemLevel
end

function Pets.EggUnlocked(session, egg): boolean
	return ZoneConfig.HighestUnlocked(session.Data.BestHeight) >= egg.Zone
end

-- Best egg the player can open (for "random pet" rewards)
function Pets.BestEgg(session)
	local best = PetConfig.Eggs[1]
	for _, egg in PetConfig.Eggs do
		if Pets.EggUnlocked(session, egg) then
			best = egg
		end
	end
	return best
end

--[[
	Hatch `count` pets from egg. `rng` must provide NextNumber() in [0,1).
	Returns list of { Uid, Id } or nil + error message.
]]
function Pets.Hatch(session, eggId: any, count: any, rng): ({ any }?, string?)
	local egg = type(eggId) == "string" and PetConfig.GetEgg(eggId) or nil
	if not egg then
		return nil, "Unknown egg"
	end
	if not Pets.EggUnlocked(session, egg) then
		return nil, "Reach " .. ZoneConfig.Zones[egg.Zone].Name .. " first!"
	end
	local validCount = Num.ValidInt(count, 1, PetConfig.MaxHatchCount)
	if not validCount then
		return nil, "Bad count"
	end
	count = validCount
	local cost = egg.Cost * count
	if session.Data.Coins < cost then
		return nil, "Not enough coins (" .. Format.Number(cost) .. ")"
	end
	if Pets.Count(session) + count > Pets.Capacity(session) then
		return nil, "Pet storage full! Delete some pets."
	end
	session.Data.Coins -= cost
	local luck = Pets.LuckMultiplier(session)
	local results = {}
	for _ = 1, count do
		local petId = PetConfig.Roll(egg, rng:NextNumber(), luck)
		local uid = Pets.Give(session, petId)
		table.insert(results, { Uid = uid, Id = petId })
	end
	Session.MarkDirty(session, "Stats")
	return results
end

-- Reward pet: a pet of `rarity` (or a normal roll) from the best unlocked egg.
function Pets.GrantReward(session, rarity: string?, rng): string?
	local egg = Pets.BestEgg(session)
	local petId
	if rarity then
		for _, entry in egg.Pets do
			if PetConfig.Pets[entry.Id].Rarity == rarity then
				petId = entry.Id
				break
			end
		end
	end
	petId = petId or PetConfig.Roll(egg, rng:NextNumber(), Pets.LuckMultiplier(session))
	local uid = Pets.Give(session, petId)
	if uid then
		return petId
	end
	return nil
end

return Pets
