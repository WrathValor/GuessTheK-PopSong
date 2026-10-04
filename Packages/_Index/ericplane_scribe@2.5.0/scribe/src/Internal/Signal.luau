--!strict
-- Signal: the batched, yield-safe Roblox signal (GoodSignal), vendored so Scribe carries
-- no external Signal dependency. Handlers run on a cached runner thread (cheap yielding),
-- connections form a linked list so a listener can disconnect another mid-fire, and a
-- throwing handler is surfaced by the scheduler rather than swallowed.
--
-- Adapted from GoodSignal by stravant (2021) and sleitnick's typed copy; both
-- MIT-licensed. Trimmed to new / Connect / Once / Fire / Wait / DisconnectAll / Destroy.

export type Connection = {
	Disconnect: (self: Connection) -> (),
	Connected: boolean,
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
	Destroy: (self: Signal<T...>) -> (),
}

-- The currently idle runner thread, reused across handlers. A handler that yields
-- takes it over, and Fire makes a new one for the next handler.
local freeRunnerThread: thread? = nil

local function acquireRunnerThreadAndCallEventHandler(fn: (...any) -> (), ...)
	local acquired = freeRunnerThread
	freeRunnerThread = nil
	fn(...)
	freeRunnerThread = acquired
end

-- Primed to its first yield: a runner started with the handler's arguments keeps
-- them on its stack for life.
local function runEventHandlerInFreeThread()
	while true do
		acquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

-- Connection ------------------------------------------------------------------

local Connection = {}
Connection.__index = Connection

-- Detaches this handler; repeated calls do nothing.
function Connection.Disconnect(self: any)
	if not self.Connected then
		return
	end
	self.Connected = false
	-- Unhook the node without clearing it, so a Fire currently iterating on it
	-- can still move forward; the node is GCed once no Fire references it.
	local signal = self._signal
	if signal._head == self then
		signal._head = self._next
	else
		local prev = signal._head
		while prev and prev._next ~= self do
			prev = prev._next
		end
		if prev then
			prev._next = self._next
		end
	end
end

-- Signal ----------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

function Signal.new(): any
	return setmetatable({ _head = false }, Signal)
end

-- Registers a handler and returns its disconnectable connection.
function Signal.Connect(self: any, fn: (...any) -> ()): any
	local connection = setmetatable({
		Connected = true,
		_signal = self,
		_fn = fn,
		_next = self._head,
	}, Connection)
	self._head = connection
	return connection
end

-- `_head` is false when empty and a connection otherwise; Disconnect unlinks, so
-- the chain only ever holds live connections.
function Signal.HasListeners(self: any): boolean
	return not not self._head
end

-- Disconnects before the handler's first call.
function Signal.Once(self: any, fn: (...any) -> ()): any
	local connection
	connection = Signal.Connect(self, function(...)
		if connection.Connected then
			connection:Disconnect()
		end
		fn(...)
	end)
	return connection
end

function Signal.Fire(self: any, ...: any)
	local item = self._head
	while item do
		if item.Connected then
			if not freeRunnerThread then
				freeRunnerThread = coroutine.create(runEventHandlerInFreeThread)
				coroutine.resume(freeRunnerThread :: thread)
			end
			task.spawn(freeRunnerThread :: thread, item._fn, ...)
		end
		item = item._next
	end
end

-- Fires like Fire does, one isolated thread per handler, then hands
-- `onSettled(ran, ok, err)` the outcome once the last handler has returned or raised.
-- Fire alone cannot say whether a handler ran, finished or blew up, and the cross-server
-- message drain has to know: retiring a message whose handler never observed it destroys
-- it. Not on the exported Signal type, like HasListeners.
--
-- `ran` is how many connections were live at the call, `ok` is false if any raised,
-- `err` is the first error. onSettled runs synchronously when no handler yielded,
-- otherwise on the last handler's thread. A handler that yields and never returns never
-- settles, so the caller is never told to acknowledge.
function Signal.FireTracked(self: any, onSettled: (number, boolean, any) -> (), ...: any)
	local ran, settled = 0, 0
	local failed, firstError = false, nil
	-- False while the list is still being walked, so a handler that completes
	-- synchronously cannot settle the fire before its siblings are spawned.
	local dispatched = false
	local function finish(ok: boolean, err: any)
		settled += 1
		if not ok and not failed then
			failed = true
			firstError = err
		end
		if dispatched and settled == ran then
			onSettled(ran, not failed, firstError)
		end
	end
	local item = self._head
	while item do
		if item.Connected then
			ran += 1
			local fn = item._fn
			-- A fresh thread per handler rather than Fire's cached runner, which cannot
			-- report when a handler ended. Message delivery is not a hot path.
			task.spawn(function(...)
				finish(pcall(fn, ...))
			end, ...)
		end
		item = item._next
	end
	dispatched = true
	if settled == ran then
		onSettled(ran, not failed, firstError)
	end
end

-- Yields until the next fire and returns its arguments.
function Signal.Wait(self: any): ...any
	local waiting = coroutine.running()
	local connection
	connection = Signal.Connect(self, function(...)
		connection:Disconnect()
		task.spawn(waiting, ...)
	end)
	return coroutine.yield()
end

-- Detaches every handler and marks its connection disconnected.
function Signal.DisconnectAll(self: any)
	local item = self._head
	while item do
		item.Connected = false
		item = item._next
	end
	self._head = false
end

-- Disconnects handlers; the signal can still be reused.
Signal.Destroy = Signal.DisconnectAll

--------------------------------------------------------------------------------

local SignalModule = {}

function SignalModule.new(): any
	return Signal.new()
end

return SignalModule
