--[[
	Tiny Signal implementation (no BindableEvents, no leaks).
]]

local Signal = {}
Signal.__index = Signal

export type Connection = { Connected: boolean, Disconnect: (self: Connection) -> () }

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	local handlers = self._handlers
	local connection
	connection = {
		Connected = true,
		Disconnect = function(conn)
			if not conn.Connected then
				return
			end
			conn.Connected = false
			local index = table.find(handlers, fn)
			if index then
				table.remove(handlers, index)
			end
		end,
	}
	table.insert(handlers, fn)
	return connection
end

function Signal:Fire(...)
	-- copy so handlers may disconnect while firing
	local snapshot = table.clone(self._handlers)
	for _, fn in snapshot do
		task.spawn(fn, ...)
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	table.clear(self._handlers)
end

return Signal
