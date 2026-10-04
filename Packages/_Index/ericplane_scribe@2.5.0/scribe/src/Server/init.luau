--!strict
-- Server assembly: builds the shared context, wires the layers together, and
-- exposes the public server `Data` API.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Internal = script.Parent.Internal
local Types = require(script.Parent.Types)
local Template = require(Internal.Template)
local TransportModule = require(Internal.Transport)
local Version = require(Internal.Version)
local Node = require(Internal.Node)
local Log = require(Internal.Log)
local Metrics = require(Internal.Metrics)
local Health = require(Internal.Health)
local Signal = require(Internal.Signal)
local Failure = require(Internal.Failure)
local Addons = require(Internal.Addons)

local Persistence = require(script.Persistence)
local Replication = require(script.Replication)
local Commands = require(script.Commands)
local Timed = require(script.Timed)
local Analytics = require(script.Analytics)
local Leaderboards = require(script.Leaderboards)
local Exchanges = require(script.Exchanges)
local ServerStore = require(script.ServerStore)
local Monetization = require(script.Monetization)

local Server = {}

-- Builds the server context and public Data API without the engine-level wiring
-- (PlayerAdded/Removing, BindToClose). The test harness calls this directly to drive
-- the player lifecycle by hand against stub transports. Returns (Data, ctx).
function Server.build(options: any, compiled: Template.Compiled): (any, any)
	local ctx = {} :: any
	ctx.Options = options
	Addons.SetProfileKeyPrefix(
		if type(options.ProfileKeyPrefix) == "string" then options.ProfileKeyPrefix else "PLAYER_"
	)
	ctx.Compiled = compiled
	-- Studio by default. Overridable because patching RunService is illegal on a real
	-- service Instance, so a spec needing DevMode could not otherwise run in Studio.
	ctx.DevMode = if options.DevMode ~= nil then options.DevMode == true else RunService:IsStudio()
	-- Coarse per-player ceiling on raw inbound frames, spent before a frame is read at
	-- all. Resolved here because Persistence seeds each entry's bucket and Replication
	-- enforces it, and a default derived in two places drifts.
	--
	-- Well above CommandRateLimit on purpose: this tier drops silently, and a silently
	-- dropped Command strands the client until its RequestTimeout, so a merely chatty
	-- client should hit the command token bucket instead. The floor keeps a tiny
	-- CommandRateLimit from throttling handshake and status traffic.
	ctx.InboundFrameRate = options.MaxInboundFrameRate or math.max(60, (options.CommandRateLimit or 20) * 4)
	ctx.Signals = {
		OnSave = Signal.new(), -- { Player, Ok, Duration, At }
		SessionEnded = Signal.new(), -- (player, reason)
		OnAnomaly = Signal.new(), -- { Player, Path, Value, Reason }
		OnGiftReceived = Signal.new(), -- (player, { FromUserId, Product, GiftId })
		OnGiftCredit = Signal.new(), -- (player, productName)
		OnMessage = Signal.new(), -- (player, message)
		OnOwnershipChanged = Signal.new(), -- (player, key, owned)
		OnCooldownEnded = Signal.new(), -- (player, key)
		OnLeaderboard = Signal.new(), -- (boardName, entries)
	}

	if options.LogLevel then
		Log.SetLevel(options.LogLevel)
	end
	if options.LogRingLevel then
		Log.SetRingLevel(options.LogRingLevel)
	end
	if options.LogRingSize ~= nil then
		Log.SetRingSize(options.LogRingSize)
	end
	Health.Configure(options.StatusThresholds)

	ctx.Transport = TransportModule.Resolve(options.Transport, options.TransportChannel)
	-- Did we claim the built-in channel? Only the claiming scope may release it, or a
	-- bundle on a custom transport would take Default away from whoever holds it. Read
	-- the option, not ctx.Transport.Name: a custom adapter may call itself "Default".
	local ownsDefaultChannel = options.Transport == nil or options.Transport == "Default"

	-- Build order matters only for construction-time dependencies; runtime calls flow
	-- through ctx. Pcalled, and the unwind releases what was already built: Replication.new
	-- installs process-global listeners and the constructors after it throw on bad config,
	-- and a failed build leaves no Data object for anyone to call Stop() on. Same list and
	-- reverse order as Data.Stop, each Stop pcalled so one failing teardown cannot replace
	-- the config error the developer is here to read.
	local constructed, constructErr = pcall(function()
		ctx.Analytics = Analytics.new(ctx)
		ctx.Timed = Timed.new(ctx)
		ctx.Persistence = Persistence.new(ctx)
		ctx.Replication = Replication.new(ctx)
		-- After Replication: its OnOp pushes onto Replication's store queue.
		ctx.ServerStore = ServerStore.new(ctx)
		ctx.Commands = Commands.new(ctx)
		ctx.Leaderboards = Leaderboards.new(ctx)
		ctx.Monetization = Monetization.new(ctx)
		-- After Persistence: it reads the resolved mode to decide whether the verdict
		-- key is real or mocked.
		ctx.Exchanges = Exchanges.new(ctx)
	end)
	if not constructed then
		for _, subsystem in
			{
				ctx.Exchanges,
				ctx.Leaderboards,
				ctx.Timed,
				ctx.Monetization,
				ctx.ServerStore,
				ctx.Replication,
				ctx.Persistence,
			}
		do
			if subsystem ~= nil and type(subsystem.Stop) == "function" then
				pcall(subsystem.Stop)
			end
		end
		-- The same release Stop performs: the channel claim and the inbound listener are
		-- both taken above this pcall, so leaving them held turns a config error into
		-- "channel already in use" on the corrected retry. After the subsystems, so
		-- nothing is still sending when the listener goes.
		if ownsDefaultChannel then
			pcall(TransportModule.ReleaseChannel, options.TransportChannel)
		end
		-- Level 0: the message carries its own origin, and re-pointing it at this
		-- line would blame the library for the caller's config.
		error(constructErr, 0)
	end

	-- Background loops start only after every subsystem exists: a constructor throwing
	-- partway must never leave an orphaned loop running against a half-built ctx.
	ctx.Monetization.Start()
	ctx.Timed.Start()
	ctx.Leaderboards.Start()
	ctx.Exchanges.Start()

	-- Public API --------------------------------------------------------------------

	local Data = {} :: any

	-- Luau does not flag an unknown key in an inline table literal passed to an optional
	-- table parameter, only in one bound to a local first, so a typo like
	-- `{ Forcce = true }` type-checks clean and silently does nothing. This is the only
	-- layer that catches it.
	local function checkOptions(given: any, what: string, allowed: { [string]: true })
		if given == nil then
			return
		end
		if type(given) ~= "table" then
			error(`Scribe: {what} options must be a table`, 3)
		end
		local names = {}
		for name in allowed do
			table.insert(names, name)
		end
		table.sort(names)
		for name in given do
			if not allowed[name] then
				error(`Scribe: {what}: unknown option "{tostring(name)}" (expected {table.concat(names, ", ")})`, 3)
			end
		end
	end

	local function entryOrError(player: Player, what: string): any
		local entry = ctx.Persistence.EntryFor(player)
		if not entry then
			error(`Scribe: {what}: no data session for {player.Name}`, 3)
		end
		if entry.State ~= "Ready" then
			error(`Scribe: {what}: data for {player.Name} is {entry.State}: use Data.WaitForData(player)`, 3)
		end
		return entry
	end

	-- Waits for a Ready profile, returning nil and a reason on failure.
	function Data.WaitForData(player: Player, timeout: number?)
		return ctx.Persistence.WaitForData(player, timeout)
	end
	-- Reads session state and loading phase without yielding.
	function Data.GetState(player: Player)
		return ctx.Persistence.GetState(player)
	end
	-- Returns the player's accessor tree; errors unless the profile is Ready.
	function Data.Get(player: Player)
		return entryOrError(player, "Data.Get").Tree.Accessor
	end

	-- Groups writes into one replication flush and container notification pass.
	function Data.Batch(player: Player, fn: () -> ())
		local entry = entryOrError(player, "Data.Batch")
		entry.Tree:RunBatch(fn)
	end
	-- Rolls back all writes if the callback throws or yields.
	function Data.Transaction(player: Player, fn: () -> ()): (boolean, string?)
		local entry = entryOrError(player, "Data.Transaction")
		return entry.Tree:RunTransaction(fn)
	end

	-- Waits for pending changes to save; requires a Ready profile.
	function Data.Flush(player: Player, opts: { Force: boolean?, Timeout: number? }?)
		checkOptions(opts, "Data.Flush", { Force = true, Timeout = true })
		return ctx.Persistence.Flush(player, opts)
	end
	-- Reads the player's last save result and pending-change state.
	function Data.GetSaveInfo(player: Player)
		return ctx.Persistence.GetSaveInfo(player)
	end
	-- Clones local Ready data or reads the last persisted snapshot.
	function Data.GetOffline(userId: number)
		return ctx.Persistence.GetOffline(userId)
	end
	-- Updates an offline profile, with optional template validation.
	function Data.UpdateOffline(userId: number, fn: (data: any) -> (), opts: { Validate: boolean? }?)
		checkOptions(opts, "Data.UpdateOffline", { Validate = true })
		return ctx.Persistence.UpdateOffline(userId, fn, opts)
	end
	-- Lists saved profile versions for support tools.
	function Data.ListVersions(userId: number, limit: number?)
		return ctx.Persistence.ListVersions(userId, limit)
	end
	-- Reads a specific historical profile snapshot.
	function Data.GetVersion(userId: number, versionId: string)
		return ctx.Persistence.GetVersion(userId, versionId)
	end
	-- Restores an existing offline profile while preserving reserved data by default.
	function Data.RestoreVersion(userId: number, versionId: string, opts: { RollBackReserved: boolean? }?)
		checkOptions(opts, "Data.RestoreVersion", { RollBackReserved = true })
		return ctx.Persistence.RestoreVersion(userId, versionId, opts)
	end
	-- Deletes the profile and leaderboard records while blocking this user's joins.
	function Data.Erase(userId: number)
		return ctx.Persistence.Erase(userId)
	end
	-- Serializes a profile to JSON, or returns nil when absent.
	function Data.Export(userId: number)
		return ctx.Persistence.Export(userId)
	end

	-- Registers a validated, rate-limited command for Ready players.
	function Data.Command(name: string, specOrHandler: any, handler: any?)
		ctx.Commands.Register(name, specOrHandler, handler)
	end

	Data.Exchange = {
		-- Trades both baskets between players loaded on this server.
		Attempt = function(playerA: Player, basketA: { any }, playerB: Player, basketB: { any })
			return ctx.Exchanges.Attempt(playerA, basketA, playerB, basketB)
		end,
		-- Lists the player's unfinished exchanges and held value.
		Open = function(player: Player)
			return ctx.Exchanges.Open(player)
		end,
		-- Drops an unstaked claim only when no verdict exists.
		Discard = function(exchangeId: string)
			return ctx.Exchanges.Discard(exchangeId)
		end,
		-- Applies an explicit recovery verdict to a stalled exchange.
		Settle = function(exchangeId: string, verdict: string)
			return ctx.Exchanges.Settle(exchangeId, verdict)
		end,
		-- Moves a parked delivery to another key in the same container.
		Redirect = function(exchangeId: string, userId: number, newKey: string)
			return ctx.Exchanges.Redirect(exchangeId, userId, newKey)
		end,
	}

	-- Reads cached board results without a live DataStore request.
	function Data.GetLeaderboard(name: string, limit: number?, offset: number?)
		return ctx.Leaderboards.GetLeaderboard(name, limit, offset)
	end
	-- Reads the player's rank from the leaderboard cache.
	function Data.GetMyRank(player: Player, name: string)
		return ctx.Leaderboards.GetMyRank(player, name)
	end
	-- Reads the next scheduled refresh delay; nil until scheduled.
	function Data.GetLeaderboardRefreshIn(name: string): number?
		return ctx.Leaderboards.GetRefreshIn(name)
	end
	-- Reads board health without a DataStore request.
	function Data.GetLeaderboardStatus(name: string): Types.LeaderboardStatusInfo?
		return ctx.Leaderboards.GetStatus(name)
	end
	-- Reads the time remaining in a periodic board's current period.
	function Data.GetLeaderboardResetIn(name: string): number?
		return ctx.Leaderboards.GetResetIn(name)
	end

	-- Validates a named product or pass before opening its purchase prompt.
	function Data.PromptPurchase(player: Player, name: string)
		return ctx.Monetization.PromptPurchase(player, name)
	end
	-- Reads the ownership and policy state used by purchase prompts.
	function Data.GetProductState(player: Player, name: string): string
		return ctx.Monetization.GetProductState(player, name)
	end
	-- Uses a gift credit or saves the recipient before opening a paid prompt.
	function Data.PromptGift(buyer: Player, productName: string, recipientUserId: number)
		return ctx.Monetization.PromptGift(buyer, productName, recipientUserId)
	end
	-- Reads the player's unassigned gift credits.
	function Data.GetGiftCredits(player: Player)
		return ctx.Monetization.GetGiftCredits(player)
	end
	-- Processes a Scribe receipt with persisted deduplication.
	function Data.HandleReceipt(receiptInfo: any)
		return ctx.Monetization.HandleReceipt(receiptInfo)
	end

	-- Processes known products and returns nil for another receipt handler.
	function Data.TryHandleReceipt(receiptInfo: any)
		return ctx.Monetization.TryHandleReceipt(receiptInfo)
	end
	-- Reads cached pass, perk, or Roblox Plus ownership without yielding.
	function Data.Owns(player: Player, key: string)
		return ctx.Monetization.Owns(player, key)
	end
	-- Verifies uncached pass ownership with Roblox before returning.
	function Data.OwnsAsync(player: Player, key: string, timeout: number?)
		return ctx.Monetization.OwnsAsync(player, key, timeout)
	end
	-- Reports current ownership and later changes; returns a disconnect.
	function Data.ObserveOwned(player: Player, key: string, callback: (owned: boolean) -> ())
		return ctx.Monetization.ObserveOwned(player, key, callback)
	end
	-- Grants a perk through Scribe's ownership state.
	function Data.GrantPerk(player: Player, key: string)
		return ctx.Monetization.GrantPerk(player, key)
	end
	-- Removes a granted perk from Scribe's ownership state.
	function Data.RevokePerk(player: Player, key: string)
		return ctx.Monetization.RevokePerk(player, key)
	end
	-- Debits, grants, and logs atomically; failures roll back the purchase.
	function Data.Purchase(player: Player, spec: any)
		return ctx.Monetization.Purchase(player, spec)
	end
	-- Adds a game-defined entry to the in-game purchase log.
	function Data.RecordPurchase(player: Player, entry: any)
		return ctx.Monetization.RecordPurchase(player, entry)
	end
	-- Reads filtered purchase history, newest first.
	function Data.GetPurchases(player: Player, filter: any?)
		checkOptions(filter, "Data.GetPurchases", {
			Kind = true,
			Category = true,
			ItemId = true,
			Since = true,
			Limit = true,
		})
		return ctx.Monetization.GetPurchases(player, filter)
	end

	-- Checks the cooldown and arms it only when inactive.
	function Data.OnCooldown(
		player: Player,
		key: string,
		seconds: number,
		opts: { IncludeOfflineTime: boolean? }?
	): (boolean, number)
		local entry = entryOrError(player, "Data.OnCooldown")
		checkOptions(opts, "Data.OnCooldown", { IncludeOfflineTime = true })
		return ctx.Timed.OnCooldown(entry, key, seconds, opts)
	end

	-- Reads cooldown state without starting or extending it.
	function Data.PeekCooldown(player: Player, key: string): (boolean, number)
		local entry = entryOrError(player, "Data.PeekCooldown")
		return ctx.Timed.PeekCooldown(entry, key)
	end

	-- Clears a stored cooldown.
	function Data.ClearCooldown(player: Player, key: string)
		local entry = entryOrError(player, "Data.ClearCooldown")
		ctx.Timed.ClearCooldown(entry, key)
	end

	-- Fires after each save attempt, including failures.
	Data.OnSave = ctx.Signals.OnSave
	-- Fires when a player's session ends.
	Data.SessionEnded = ctx.Signals.SessionEnded
	-- Fires when data validation or integrity checks detect an anomaly.
	Data.OnAnomaly = ctx.Signals.OnAnomaly
	-- Fires when effective ownership changes after load.
	Data.OnOwnershipChanged = ctx.Signals.OnOwnershipChanged
	-- Fires when cached board contents change.
	Data.OnLeaderboard = ctx.Signals.OnLeaderboard
	-- Fires when a cooldown expires during an active session.
	Data.OnCooldownEnded = ctx.Signals.OnCooldownEnded
	-- Fires when a player receives a gift.
	Data.OnGiftReceived = ctx.Signals.OnGiftReceived
	-- Fires when a player receives an unassigned gift credit.
	Data.OnGiftCredit = ctx.Signals.OnGiftCredit
	-- Delivers durable messages; handlers must be idempotent.
	Data.OnMessage = ctx.Signals.OnMessage

	-- Queues a durable message; receiving handlers must tolerate repeats.
	function Data.SendMessage(userId: number, message: any): boolean
		if ctx.Persistence.Mode == "NoSave" then
			ctx.Persistence.RefuseNoSave("SendMessage")
			return false
		end
		-- `provablyClean` is MessageAsync's third return: true only where no attempt in
		-- its own retry loop could have written. Read for the log line alone; the boolean
		-- this function returns is unchanged.
		local ok, delivered, reason, provablyClean = pcall(function()
			return ctx.Persistence.Store:MessageAsync(ctx.Persistence.KeyFor(userId), {
				ScribeMessage = true,
				Data = message,
			})
		end)
		if ok and delivered == true then
			Health.ReportSuccess("SendMessage")
			return true
		end
		if ok and reason == "QueueFull" then
			-- Deliberately not Failure.Report: that calls Health.ReportFailure, and a full
			-- inbox is one player's profile rather than a DataStore fault, so a single
			-- jammed queue would degrade the whole server to Outage and refuse every Robux
			-- grant. An earlier attempt of the same call may also have committed and lost
			-- only its answer, so this can be reported for a message already in the inbox.
			Metrics.Add("MessageQueueFull")
			if provablyClean ~= true then
				Metrics.Add("MessageQueueFullAmbiguous")
			end
			Log.Warn(
				"Persistence",
				"MESSAGE_QUEUE_FULL",
				if provablyClean == true
					then "the recipient's message queue is at its cap and no attempt in this call reached "
						.. "storage; nothing was written"
					else "the recipient's message queue is at its cap, but an earlier attempt in the same "
						.. "call may already have queued this message; it may yet be delivered",
				{ UserId = userId, ProvablyClean = provablyClean == true }
			)
			return false
		end
		-- Keyed by recipient, so a shutdown that fails to deliver for one player counts as
		-- one problem instead of one per attempt. Past this point the send threw,
		-- MessageAsync gave up retrying, or it refused at its IsClosing door without
		-- attempting anything; `provablyClean` separates them. The return is `false` either
		-- way, because at-least-once is this channel's contract.
		Failure.Report({
			Subsystem = "SendMessage",
			Key = tostring(userId),
			Error = if ok then nil else delivered,
			Category = "Persistence",
			Code = "MESSAGE_SEND_FAIL",
			Message = if ok and provablyClean == true
				then "MessageAsync failed; nothing reached storage, so the message was not delivered"
				else "MessageAsync failed; the message may or may not have been delivered, so treat it as retryable",
			Context = {
				UserId = userId,
				Threw = not ok,
				ProvablyClean = ok and provablyClean == true,
				Error = if ok then nil else tostring(delivered),
			},
		})
		return false
	end

	-- Exposes the underlying store, bypassing Scribe's data guarantees.
	Data.ProfileStore = ctx.Persistence.Store

	-- Dev-mode misuse guard: a template key shadowed by an accessor method, at any depth,
	-- needs explicit Child(name) lookup. The root-level half runs at the very
	-- end of build; see the comment on it for why.
	if ctx.DevMode then
		local function warnCollision(node: any)
			local name = node.Name
			if
				name
				and Node.METHOD_NAMES[name]
				and node.Path[1] ~= Template.RESERVED_ROOT
				and node.Path[1] ~= Template.SESSION_ROOT
			then
				Log.Warn(
					"Lifecycle",
					"API_NAME_COLLISION",
					`template field "{name}" collides with an accessor method; use Child("{name}") to reach it`,
					{ Path = table.concat(node.Path :: { any }, ".") }
				)
			end
		end
		-- ById covers static fields; element subtrees are id-less and hang off
		-- AnyChild, so they have to be walked explicitly.
		local function walkElements(node: any)
			local anyChild = node.AnyChild
			if anyChild and anyChild.IsElement then
				local function walkSubtree(n: any)
					warnCollision(n)
					if n.Children then
						for _, child in n.Children do
							walkSubtree(child)
						end
					end
					if n.AnyChild and n.AnyChild.IsElement then
						walkSubtree(n.AnyChild)
					end
				end
				walkSubtree(anyChild)
			end
			if node.Children then
				for _, child in node.Children do
					walkElements(child)
				end
			end
		end
		for _, node in compiled.ById do
			warnCollision(node)
		end
		walkElements(compiled.Root)
	end

	-- Data[player] -> typed accessor tree.
	setmetatable(Data :: any, {
		__index = function(_, key: unknown)
			if typeof(key) == "Instance" and key:IsA("Player") then
				return entryOrError(key, "Data[player]").Tree.Accessor
			end
			return nil
		end,
	})

	-- Exposes the same API without template-aware types.
	Data.Raw = Data

	Metrics.Set("SchemaNodes", compiled.NodeCount)
	Log.Info("Lifecycle", "SERVER_STARTED", "Scribe server initialized", {
		Fields = compiled.NodeCount,
		Transport = ctx.Transport.Name,
	})

	-- Hoisted above the doc block below: docgen resolves a @within block from the
	-- next line of code, so a declaration between the two orphans the member.
	local stopped = false

	-- Stops this bundle's workers and releases its listeners.
	function Data.Stop()
		if stopped then
			return
		end
		stopped = true
		-- Reverse of the Start order: stop producing work before releasing what consumes it.
		for _, subsystem in
			{
				ctx.Exchanges,
				ctx.Leaderboards,
				ctx.Timed,
				ctx.Monetization,
				ctx.ServerStore,
				ctx.Replication,
				ctx.Persistence,
			}
		do
			if subsystem ~= nil and type(subsystem.Stop) == "function" then
				local ok, err = pcall(subsystem.Stop)
				if not ok then
					Log.Warn("Lifecycle", "SUBSYSTEM_HOOK_ERROR", `Stop failed: {tostring(err)}`, {})
				end
			end
		end
		-- After the subsystems, so nothing is still sending when the channel's listener
		-- goes. The claim is a module global that outlives this bundle, so leaving it set
		-- means the channel can never be rebound.
		if ownsDefaultChannel then
			pcall(TransportModule.ReleaseChannel, options.TransportChannel)
		end
	end

	-- Per store root, not the store's root accessor: the client holds one tree over both
	-- halves, so this keeps the surface identical on both realms.
	-- Exposes server-owned roots without a player argument.
	if ctx.ServerStore ~= nil then
		local proxy = {}
		for _, key in compiled.Views.Store.RootOrder do
			proxy[key] = ctx.ServerStore.Accessor.Child(key)
		end
		Data.ServerStore = table.freeze(proxy)
	end

	-- A root field named like a Data API name is silently shadowed by that real key (a
	-- real key always wins over __index), so it is unreachable as `Data.<name>`.
	--
	-- Keep this last, after every Data key is assigned: `for key in Data` sees only the
	-- keys that exist when it runs, so a guard placed higher exempts everything below it.
	-- Server.new redefines Data.Stop after this but adds no new key, so this still sees
	-- the whole public surface.
	-- Raw iteration, so the metatable installed above is not consulted.
	if ctx.DevMode then
		local rootChildren = compiled.Root.Children :: { [string]: any }
		for key in Data do
			if type(key) == "string" and rootChildren[key] then
				-- In the context as well as the message, so a sink need not parse prose.
				Log.Warn(
					"Lifecycle",
					"API_NAME_COLLISION",
					`template root field "{key}" collides with a Data API name`,
					{ Field = key }
				)
			end
		end
	end

	return Data, ctx
end

function Server.new(options: any, compiled: Template.Compiled): any
	local Data, ctx = Server.build(options, compiled)

	-- Studio-only debug hook for the Scribe Studio plugin, opt-in because it records from
	-- the moment it attaches, plugin or not. The remover Attach hands back is kept: it
	-- releases a Log sink and a Health.OnStatusChanged listener, both library-level
	-- singletons that outlive the bundle, and ends the digest pump. Nil on the refusal
	-- and pcall failure paths, and Stop below tolerates both.
	local detachDebugHook: (() -> ())? = nil
	if options.StudioHook == true and RunService:IsStudio() then
		local ok, err = pcall(function()
			detachDebugHook = (require(script.DebugHook) :: any).Attach(Data, ctx)
		end)
		if not ok then
			Log.Warn("Lifecycle", "DEBUG_HOOK_FAIL", tostring(err), {})
		end
	end

	ctx.Persistence.BindShutdown()

	local playerConnections = {
		Players.PlayerAdded:Connect(function(player)
			ctx.Persistence.OnPlayerAdded(player)
		end),
		Players.PlayerRemoving:Connect(function(player)
			ctx.Persistence.OnPlayerRemoving(player)
		end),
	}
	for _, player in Players:GetPlayers() do
		ctx.Persistence.OnPlayerAdded(player)
	end

	-- Extend build's Stop with the engine wiring only Server.new installs, so each
	-- scope releases exactly what it created.
	local stopSubsystems = Data.Stop
	function Data.Stop()
		for _, connection in playerConnections do
			pcall(function()
				connection:Disconnect()
			end)
		end
		table.clear(playerConnections)
		-- Before the subsystems, and cleared so a second Stop cannot call it twice: the
		-- digest pump reads Persistence.Entries once a tick, so the hook lets go before
		-- what it watches is dismantled. pcalled: a debug facility must not fail teardown.
		local detach = detachDebugHook
		detachDebugHook = nil
		if detach ~= nil then
			local ok, err = pcall(detach)
			if not ok then
				Log.Warn("Lifecycle", "DEBUG_HOOK_FAIL", tostring(err), {})
			end
		end
		stopSubsystems()
	end

	if options.Banner ~= false then
		print(`Running Scribe v{Version} by ericplane. Server is now initialized`)
	end

	return Data
end

return Server
