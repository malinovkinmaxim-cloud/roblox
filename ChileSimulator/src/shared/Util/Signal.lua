--[[
	Signal - minimal synchronous signal (no BindableEvent, no instance allocations).
]]

local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (self: Connection) -> () }

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	local handlers = self._handlers
	local entry = { Fn = fn, Connected = true }
	table.insert(handlers, entry)
	return {
		Disconnect = function()
			entry.Connected = false
			local index = table.find(handlers, entry)
			if index then
				table.remove(handlers, index)
			end
		end,
	}
end

function Signal:Fire(...: any)
	-- iterate over a copy so handlers can disconnect while firing
	for _, entry in table.clone(self._handlers) do
		if entry.Connected then
			local ok, err = pcall(entry.Fn, ...)
			if not ok then
				warn("[Signal] handler error: " .. tostring(err))
			end
		end
	end
end

return Signal
