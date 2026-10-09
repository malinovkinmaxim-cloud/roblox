--!nocheck
--[[
	Prints the power table of the premium abilities against the best free ability of their
	Category (tests/power.luau):   lune run tools/power.luau
	Every free ability's numbers:  lune run tools/power.luau -- free
]]
local process = require("@lune/process")
local Power = require("../tests/power")
local Harness = require("../tests/harness")
local WeaponData = Harness.Require("ReplicatedStorage.Modules.WeaponData")

if process.args[1] == "free" then
	for _, cat in WeaponData.Categories do
		for _, key in Power.FreeOf(cat) do
			local def = WeaponData.ByKey[key]
			local m = def.MaxLevel
			print(string.format("%-10s %-15s L1 crowd %8.0f single %6.0f | L%d crowd %8.0f single %6.0f", cat, key, Power.Measure(key, 1, "Crowd"), Power.Measure(key, 1, "Single"), m, Power.Measure(key, m, "Crowd"), Power.Measure(key, m, "Single")))
		end
	end
	return
end

print(string.format("%-16s %3s %-6s %10s %10s %-15s %6s", "ability", "lvl", "scene", "premium", "best free", "(which)", "ratio"))
for _, row in Power.Table() do
	print(string.format("%-16s %3d %-6s %10.0f %10.0f %-15s %6.2f", row.Key, row.Level, row.Scene, row.Premium, row.Best, row.BestKey or "-", row.Ratio))
end
