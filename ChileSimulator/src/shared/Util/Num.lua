--[[
	Num - safe number helpers.

	All game values (Height, Coins, Gems...) are plain Luau doubles. Doubles are exact up to
	2^53 and keep ~15 significant digits beyond that, which is exactly what a simulator needs
	for display ("1.25Qa"). The only danger is overflow to inf and NaN, so every value that is
	stored, replicated or saved goes through Num.Sanitize: NaN -> fallback, clamp to +-Num.MAX.
	Num.MAX (1e300) leaves headroom so a multiplication of two clamped values never reaches inf
	before it is clamped again.
]]

local Num = {}

Num.MAX = 1e300

function Num.IsFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Returns a finite number in [-MAX, MAX]. NaN / non-numbers become `fallback` (default 0).
function Num.Sanitize(x: any, fallback: number?): number
	if type(x) ~= "number" or x ~= x then
		return fallback or 0
	end
	if x > Num.MAX then
		return Num.MAX
	elseif x < -Num.MAX then
		return -Num.MAX
	end
	return x
end

-- Same as Sanitize but never negative.
function Num.NonNeg(x: any, fallback: number?): number
	local v = Num.Sanitize(x, fallback)
	if v < 0 then
		return 0
	end
	return v
end

function Num.Add(a: number, b: number): number
	return Num.Sanitize(a + b)
end

function Num.Sub(a: number, b: number): number
	return Num.Sanitize(a - b)
end

function Num.Mul(a: number, b: number): number
	-- 0 * inf would be NaN; sanitize inputs first
	return Num.Sanitize(Num.Sanitize(a) * Num.Sanitize(b))
end

-- Product of a list of multipliers, clamped after every step.
function Num.Product(list: { number }): number
	local result = 1
	for _, v in list do
		result = Num.Sanitize(result * Num.Sanitize(v, 1))
	end
	return result
end

function Num.Clamp(x: number, lo: number, hi: number): number
	x = Num.Sanitize(x, lo)
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end

-- Integer check that is safe for huge values.
function Num.IsInteger(x: any): boolean
	return Num.IsFinite(x) and math.floor(x) == x
end

-- Strict validation for values coming from the network: a finite integer in [min, max]
-- (NaN, inf, fractions, strings, tables -> nil). Use for every client-supplied number.
function Num.ValidInt(x: any, min: number, max: number): number?
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return nil
	end
	if math.floor(x) ~= x or x < min or x > max then
		return nil
	end
	return x
end

-- log10 that never errors (log of <= 0 -> -inf is replaced by `floor`).
function Num.Log10(x: number, floor: number?): number
	if not Num.IsFinite(x) or x <= 0 then
		return floor or -2
	end
	return math.log10(x)
end

return Num
