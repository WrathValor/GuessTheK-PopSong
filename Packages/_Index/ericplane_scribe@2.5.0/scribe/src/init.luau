--!strict
-- Scribe: persistent, fully-typed, automatically-replicated player data for Roblox
-- Luau, built on ProfileStore. One shared module declares the template and options and
-- returns { Server, Client }. The typed accessor tree needs the new Luau type solver;
-- without it the library still runs correctly (use `.Raw` as the untyped escape hatch).

local RunService = game:GetService("RunService")

local Types = require(script.Types)
local Util = require(script.Internal.Util)
local Marker = require(script.Internal.Marker)
local Template = require(script.Internal.Template)
local Log = require(script.Internal.Log)
local Metrics = require(script.Internal.Metrics)
local Health = require(script.Internal.Health)
local Addons = require(script.Internal.Addons)
local Config = require(script.Internal.Config)
local Budget = require(script.Internal.Budget)
local LeaderboardDiagnostics = require(script.Internal.LeaderboardDiagnostics)
-- Named BigMath because `Scribe.Big` is the declarator; this is the arithmetic.
local BigMath = require(script.Internal.Big)
-- Types only. Both are leaf modules with no services, so this is safe on the client.
local Exchange = require(script.Internal.Exchange)
local ExchangeLegType = require(script.Internal.ExchangeLeg)

export type ScribeTransport = Types.ScribeTransport
export type Op = Types.Op
export type LogEntry = Types.LogEntry
export type LogCode = Types.LogCode
export type LogLevel = Types.LogLevel
export type LogSinkOptions = Types.LogSinkOptions
export type LogCategory = Types.LogCategory
export type Status = Types.Status
export type LoadPhase = Types.LoadPhase
export type SaveInfo = Types.SaveInfo
export type BudgetSnapshot = Budget.Snapshot
export type ExchangeLeg = ExchangeLegType.Leg
export type OpenExchange = Exchange.OpenExchange
export type OpenLeg = Exchange.OpenLeg
--- One entry of the `Exchangeable` allowlist. See the Exchange guide for the rules.
export type ExchangeableSpec = {
	Path: { string },
	Kind: "Key" | "Qty" | "Stack",
	Count: string?,
	Identity: { string }?,
	Ignore: { string }?,
}
export type LifecycleReason = Types.LifecycleReason
export type RequestReason = Types.RequestReason
export type PurchaseReason = Types.PurchaseReason
export type GiftReason = Types.GiftReason
export type ProductState = Types.ProductState
export type LeaderboardEntry = Types.LeaderboardEntry
export type LeaderboardStatus = Types.LeaderboardStatus
export type LeaderboardStatusInfo = Types.LeaderboardStatusInfo
export type LeaderboardSnapshotEntry = Types.LeaderboardSnapshotEntry
export type PassConfig = Types.PassConfig
export type PurchaseFilter = Types.PurchaseFilter
export type EconomyMeta = Types.EconomyMeta
export type EconomyConfig = Types.EconomyConfig
export type EconomyCurrencyConfig = Types.EconomyCurrencyConfig
export type EconomyFieldSpec = Types.EconomyFieldSpec
export type EconomyLogFn = Types.EconomyLogFn
-- LeaderboardConfig<T>, ProductConfig<T> and PurchaseSpec<T> are defined after the
-- type functions below, which they need to derive their paths from the template.

--------------------------------------------------------------------------------
-- The type function: walks the template type at type-check time and produces
-- the recursive typed accessor tree.
--------------------------------------------------------------------------------

-- selene: allow(undefined_variable) -- `types` is the type-function runtime library
export type function ValueType(T)
	local ts = types

	local nilType = ts.singleton(nil)

	local function optional(t: type): type
		return ts.unionof(t, nilType)
	end

	local anyType = ts.any
	local optBool = optional(ts.boolean)
	local optNumber = optional(ts.number)

	local function fn(params: { type }, rets: { type }): type
		return ts.newfunction({ head = params }, { head = rets })
	end

	local disconnectType = fn({}, {})

	local function widen(t: type): type
		if t:is("singleton") then
			local value = t:value()
			if type(value) == "boolean" then
				return ts.boolean
			elseif type(value) == "string" then
				return ts.string
			end
		end
		return t
	end

	-- Recursion budget: a self-referential template type would blow the type-function
	-- stack, degrading the whole accessor tree to an error type. One past
	-- Util.MAX_VALUE_DEPTH, so it can never bind before the runtime does and only a
	-- cyclic type is cut off. Matches StatPathsType's cap below.
	local MAX_DEPTH = 25
	local MAX_CHILD_UNION = 12

	-- One shared Scribe.Big type for the whole template. Luau resolves `<` and `<=`
	-- by metatable identity rather than by shape, so a fresh type per field leaves
	-- two big fields in the same template incomparable.
	local bigType: type? = nil
	local function bigValueType(): type
		if bigType ~= nil then
			return bigType
		end
		-- The shape Get returns; arithmetic resolves through the metatable.
		local bigProps: { [type]: type } = {}
		bigProps[ts.singleton("M")] = ts.number
		bigProps[ts.singleton("E")] = ts.number
		bigProps[ts.singleton("Short")] = ts.newfunction(
			{ head = { ts.any, ts.unionof(ts.number, ts.singleton(nil)) } },
			{ head = { ts.string } }
		)
		bigProps[ts.singleton("ToNumber")] = ts.newfunction({ head = { ts.any } }, { head = { ts.number } })
		bigProps[ts.singleton("Log10")] = ts.newfunction({ head = { ts.any } }, { head = { ts.number } })

		-- The metamethods must be typed over this table with its metatable, so the table
		-- is built first and the metatable attached after. Typed over a metatable-less
		-- copy they describe a different type from the one Get returns, and every
		-- operator becomes an error. Operands widen to the union those methods accept,
		-- because BIG_MT resolves both sides through Big.from.
		local big = ts.newtable(bigProps, nil, nil)
		-- Pow returns the big type itself, so it cannot go in bigProps: ts.newtable
		-- snapshots that table. setproperty on the live type object instead.
		big:setproperty(ts.singleton("Pow"), ts.newfunction({ head = { big, ts.number } }, { head = { big } }))
		local operand = ts.unionof(big, ts.number, ts.string)
		local binaryMethod = ts.newfunction({ head = { big, operand } }, { head = { big } })
		for _, name in { "Add", "Subtract", "Multiply", "Divide" } do
			big:setproperty(ts.singleton(name), binaryMethod)
		end
		big:setproperty(ts.singleton("Negate"), ts.newfunction({ head = { big } }, { head = { big } }))
		big:setproperty(ts.singleton("Compare"), ts.newfunction({ head = { big, operand } }, { head = { ts.number } }))
		big:setproperty(ts.singleton("Equals"), ts.newfunction({ head = { big, operand } }, { head = { ts.boolean } }))
		local arith = ts.newfunction({ head = { operand, operand } }, { head = { big } })
		local cmp = ts.newfunction({ head = { operand, operand } }, { head = { ts.boolean } })
		local mtProps: { [type]: type } = {}
		mtProps[ts.singleton("__add")] = arith
		mtProps[ts.singleton("__sub")] = arith
		mtProps[ts.singleton("__mul")] = arith
		mtProps[ts.singleton("__div")] = arith
		mtProps[ts.singleton("__unm")] = ts.newfunction({ head = { big } }, { head = { big } })
		mtProps[ts.singleton("__lt")] = cmp
		mtProps[ts.singleton("__le")] = cmp
		-- __eq only ever runs with two tables, so it stays narrow.
		mtProps[ts.singleton("__eq")] = ts.newfunction({ head = { big, big } }, { head = { ts.boolean } })
		mtProps[ts.singleton("__tostring")] = ts.newfunction({ head = { big } }, { head = { ts.string } })
		big:setmetatable(ts.newtable(mtProps, nil, nil))
		bigType = big
		return big
	end

	-- Big, Flags and SetOf carry their label in the metatable rather than in a field,
	-- so each declarator's own type is already the read shape. See BigValue.
	local function hasMarker(t: type, name: string): boolean
		local mt = t:metatable()
		return mt ~= nil and mt:readproperty(ts.singleton(name)) ~= nil
	end

	local function isBigMarker(t: type): boolean
		return hasMarker(t, "__scribeBig")
	end

	-- Timed and ServerOnly read back as a bare T, which may not be a table, so unlike
	-- the branded declarators their label has to be an ordinary field and a
	-- whole-subtree read strips it here. This only ever removes a wrapper, which is
	-- what keeps it cheap enough to run over every node.
	-- Inputs are read-only so a narrower caller type is accepted; a mutable property is
	-- invariant. Indexers are copied as is, since the runtime cannot make one read-only.
	local readOnlyCache: { [type]: type } = {}
	local function readOnlyDeep(t: type, depth: number): type
		if depth > MAX_DEPTH or not t:is("table") then
			return t
		end
		local cached = readOnlyCache[t]
		if cached ~= nil then
			return cached
		end
		local indexer = t:indexer()
		local spec = if indexer ~= nil
			then { index = indexer.index, readresult = indexer.readresult, writeresult = indexer.writeresult }
			else nil
		local out = ts.newtable(nil, spec, t:metatable())
		readOnlyCache[t] = out
		for key, prop in t:properties() do
			local childType = prop.read or prop.write
			if childType ~= nil then
				out:setreadproperty(key, readOnlyDeep(childType, depth + 1))
			end
		end
		return out
	end

	local unwrapCache: { [type]: type } = {}
	local function unwrapWrappers(t: type, depth: number): type
		if depth > MAX_DEPTH or not t:is("table") then
			return t
		end
		local cached = unwrapCache[t]
		if cached ~= nil then
			return cached
		end
		local function memo(result: type): type
			unwrapCache[t] = result
			return result
		end
		local timed = t:readproperty(ts.singleton("__scribeTimed"))
		if timed ~= nil then
			return memo(unwrapWrappers(widen(timed), depth + 1))
		end
		local serverOnly = t:readproperty(ts.singleton("__scribeServerOnly"))
		if serverOnly ~= nil then
			return memo(unwrapWrappers(widen(serverOnly), depth + 1))
		end
		local derived = t:readproperty(ts.singleton("__scribeDerived"))
		if derived ~= nil then
			return memo(unwrapWrappers(widen(derived), depth + 1))
		end
		-- A marker cannot hide under one of the branded declarators: their metatable
		-- brand means the shape below them is already the read shape.
		if hasMarker(t, "__scribeBig") or hasMarker(t, "__scribeFlags") or hasMarker(t, "__scribeSet") then
			return memo(t)
		end
		local props: { [type]: type } = {}
		local rebuilt = false
		for key, prop in t:properties() do
			local childType = prop.read or prop.write
			if childType ~= nil then
				local mapped = unwrapWrappers(childType, depth + 1)
				props[key] = mapped
				if mapped ~= childType then
					rebuilt = true
				end
			end
		end
		local spec: { index: type, readresult: type, writeresult: type }? = nil
		local indexer = t:indexer()
		if indexer ~= nil then
			local mapped = unwrapWrappers(indexer.readresult, depth + 1)
			spec = { index = indexer.index, readresult = mapped, writeresult = mapped }
			if mapped ~= indexer.readresult then
				rebuilt = true
			end
		end
		if not rebuilt then
			return memo(t)
		end
		return memo(ts.newtable(props, spec, nil))
	end

	-- A canonical key for a subtree, so two identical subtrees are built once. A template
	-- repeats declarators heavily and Luau interns none of them.
	--
	-- Returns nil for anything it cannot describe exactly, and nil means do not cache.
	-- tostring() is not the key: it truncates past roughly 25 fields, so two records
	-- sharing a long prefix would collide. Only `table` and `singleton` are probed,
	-- because an unknown tag fails the whole type function.
	local opaqueIds: { [type]: string } = {}
	local opaqueCount = 0
	local signatureOf: (type, number, { [type]: boolean }) -> string?
	signatureOf = function(t: type, depth: number, seen: { [type]: boolean }): string?
		-- A cut-short walk or a cycle cannot be keyed.
		if depth > MAX_DEPTH + 2 or seen[t] then
			return nil
		end
		if t:is("singleton") then
			local value = t:value()
			return `s<{type(value)}:{tostring(value)}>`
		end
		if t:is("table") then
			seen[t] = true
			local function sub(child: type?): string?
				if child == nil then
					return "-"
				end
				return signatureOf(child, depth + 1, seen)
			end
			local parts: { string } = {}
			for key, prop in t:properties() do
				-- Signed separately: a field can differ in only one.
				local keySig, readSig, writeSig = sub(key), sub(prop.read), sub(prop.write)
				if keySig == nil or readSig == nil or writeSig == nil then
					seen[t] = nil
					return nil
				end
				table.insert(parts, `{keySig}={readSig}|{writeSig}`)
			end
			-- Sorted, because property iteration order is not guaranteed.
			table.sort(parts)
			local indexerSig = "-"
			local indexer = t:indexer()
			if indexer ~= nil then
				local i, r, w = sub(indexer.index), sub(indexer.readresult), sub(indexer.writeresult)
				if i == nil or r == nil or w == nil then
					seen[t] = nil
					return nil
				end
				indexerSig = `{i}=>{r}|{w}`
			end
			-- The metatable carries the declarator brands, which pick the accessor.
			local metaSig = "-"
			local mt = t:metatable()
			if mt ~= nil then
				local m = sub(mt)
				if m == nil then
					seen[t] = nil
					return nil
				end
				metaSig = m
			end
			seen[t] = nil
			return `t<{table.concat(parts, ",")};i:{indexerSig};m:{metaSig}>`
		end
		-- Not a table, so its rendering is its structure and is short enough not to
		-- truncate.
		local rendered = tostring(t)
		if #rendered <= 64 then
			return `p<{rendered}>`
		end
		-- Anything longer falls back to identity: exact, but never shared.
		local id = opaqueIds[t]
		if id == nil then
			opaqueCount += 1
			id = `o<{opaqueCount}>`
			opaqueIds[t] = id
		end
		return id
	end

	local buildUncached: (type, boolean, number) -> type
	local buildCache: { [number]: { [string]: type } } = {}
	local function build(rawType: type, isRoot: boolean, depth: number): type
		-- Roots are never cached: isRoot changes what is emitted.
		if isRoot then
			return buildUncached(rawType, isRoot, depth)
		end
		local key = signatureOf(rawType, 0, {})
		if key == nil then
			return buildUncached(rawType, isRoot, depth)
		end
		-- Keyed by depth too, because MAX_DEPTH truncates.
		local atDepth = buildCache[depth]
		if atDepth == nil then
			atDepth = {}
			buildCache[depth] = atDepth
		end
		local hit = atDepth[key]
		if hit ~= nil then
			return hit
		end
		local built = buildUncached(rawType, isRoot, depth)
		atDepth[key] = built
		return built
	end
	buildUncached = function(rawType: type, isRoot: boolean, depth: number): type
		if depth > MAX_DEPTH then
			return anyType
		end
		local t = widen(rawType)

		-- The Scribe.ServerOnly marker has to come off first: every declarator check below
		-- reads a marker off `t`, so with the wrapper on, ServerOnly(SetOf/Big/Flags/Timed)
		-- matches none of them and the node loses its declarator surface. A second unwrap
		-- after the SetOf block handles the inverse nesting, e.g. Timed(ServerOnly(false)).
		if t:is("table") then
			local inner = t:readproperty(ts.singleton("__scribeServerOnly"))
			if inner ~= nil then
				t = widen(inner)
			end
		end

		-- A Scribe.Derived node reads as V and never writes, so this only records the
		-- flag; the mutator block below is skipped as it is for the root accessor.
		local isDerived = false
		if t:is("table") then
			local inner = t:readproperty(ts.singleton("__scribeDerived"))
			if inner ~= nil then
				isDerived = true
				t = widen(inner)
			end
		end

		local isTimed = false
		if t:is("table") then
			local inner = t:readproperty(ts.singleton("__scribeTimed"))
			if inner ~= nil then
				isTimed = true
				t = widen(inner)
			end
		end

		-- Without the marker a flags field is just { string } and would pick up the
		-- array surface, none of which it supports. `t` is already the { string } a
		-- read returns; the label is on the metatable.
		local isFlags = t:is("table") and hasMarker(t, "__scribeFlags")

		-- A big's value is an object with arithmetic metamethods rather than a number,
		-- so it gets its own method surface and none of the table one.
		local isBig = false
		if t:is("table") and isBigMarker(t) then
			isBig = true
			t = bigValueType()
		end

		-- Without the marker a set is just { T } and would pick up Insert plus
		-- index-based Remove, neither of which a set has. `t` is already the members.
		local isSet = t:is("table") and hasMarker(t, "__scribeSet")

		-- Second ServerOnly unwrap, for a marker nested inside another declarator
		-- rather than wrapped around one. The server reads these normally;
		-- StripServerOnly is what drops them from the client type.
		if t:is("table") then
			local inner = t:readproperty(ts.singleton("__scribeServerOnly"))
			if inner ~= nil then
				t = widen(inner)
			end
		end

		-- Scribe.MapOf carries its key type as a singleton, the only way to tell a sparse
		-- {[number]: V} map from an array: at the type level those are the same indexer.
		-- Last, so a map wrapped in Scribe.ServerOnly is still seen as a map. `t` stays the
		-- whole map; only the element is pulled back out, for the key events and Remove.
		local mapKey: type? = nil
		local mapValue: type? = nil
		local mapElement: type? = nil
		if t:is("table") and hasMarker(t, "__scribeMapKey") then
			local indexer = t:indexer()
			if indexer ~= nil then
				mapKey = indexer.index
				mapValue = indexer.readresult
				mapElement = widen(indexer.readresult)
			end
		end

		-- Insertion ordered, because the properties are applied one at a time below and a
		-- later entry must overwrite an earlier one of the same name. A map keyed by type
		-- cannot do that: two ts.singleton("Remove") calls are distinct objects.
		local props: { { key: type, ty: type } } = {}
		local indexerSpec: { index: type, readresult: type, writeresult: type }? = nil
		local childLookups: { type } = {}

		-- Strips a nested Timed / ServerOnly label, the one thing a read should not show.
		local valueType = unwrapWrappers(t, depth)
		local function add(name: string, ty: type)
			table.insert(props, { key = ts.singleton(name), ty = ty })
		end

		-- Static children and container methods first, so the common node methods below win
		-- on name collisions. Maps are excluded: their own block builds the same surface
		-- with the declared key type, and two ts.singleton("Remove") calls are distinct
		-- keys, so letting a map through here duplicates rather than overrides.
		if t:is("table") and mapKey == nil and not isTimed and not isFlags and not isSet and not isBig then
			for key, prop in t:properties() do
				local childType = prop.read or prop.write
				if childType ~= nil then
					local childNode = build(childType, false, depth + 1)
					table.insert(props, { key = key, ty = childNode })
					table.insert(childLookups, fn({ key }, { childNode }))
				end
			end

			-- OnChildChanged reports an existing child's value moving, once per write
			-- and never coalesced, unlike Changed.
			local childKeys: { type } = {}
			local childValues: { type } = {}
			for key, prop in t:properties() do
				local childType = prop.read or prop.write
				if childType ~= nil then
					table.insert(childKeys, key)
					table.insert(childValues, widen(childType))
				end
			end

			local indexer = t:indexer()
			if indexer ~= nil then
				local elementType = widen(indexer.readresult)
				local elementIn = readOnlyDeep(elementType, depth + 1)
				if indexer.index:is("number") then
					-- Array node: the indexer makes `arr[i]` an accessor node, which is
					-- the only way to reach a Scribe.ArrayOf element field.
					local elemNode = build(indexer.readresult, false, depth + 1)
					table.insert(childLookups, fn({ indexer.index }, { elemNode }))
					indexerSpec = {
						index = indexer.index,
						readresult = elemNode,
						writeresult = elemNode,
					}
					add("Insert", fn({ elementIn, optNumber, optBool }, {}))
					-- Remove returns nil on an empty/missing array (matches RemoveValue).
					add("Remove", fn({ optNumber, optBool }, { optional(elementType) }))
					add("RemoveValue", fn({ elementIn, optBool }, { optional(elementType), optNumber }))
					add("Find", fn({ elementIn }, { optNumber }))
					add("Has", fn({ elementIn }, { ts.boolean }))
					add("OnInsert", fn({ fn({ elementType, ts.number }, {}) }, { disconnectType }))
					add("OnRemove", fn({ fn({ elementType, ts.number }, {}) }, { disconnectType }))
				else
					-- Dictionary node: children are accessor nodes.
					local childNode = build(indexer.readresult, false, depth + 1)
					table.insert(childLookups, fn({ indexer.index }, { childNode }))
					indexerSpec = {
						index = indexer.index,
						readresult = childNode,
						writeresult = childNode,
					}
					add("Remove", fn({ ts.string, optBool }, { optional(elementType) }))
					add("OnKeyAdded", fn({ fn({ indexer.index, elementType }, {}) }, { disconnectType }))
					add("OnKeyRemoved", fn({ fn({ indexer.index, elementType }, {}) }, { disconnectType }))
				end
				add("Clear", fn({ optBool }, {}))
				add("Count", fn({}, { ts.number }))
				-- A dynamic container's children are homogeneous, so the key and value
				-- types here are exact rather than a union over declared fields.
				table.insert(childKeys, indexer.index)
				table.insert(childValues, widen(indexer.readresult))
			end

			if #childKeys > 0 then
				-- (key, new, old), matching Changed's new-first order. Both values are
				-- optional: an added key has no old, a removed key has no new. On a
				-- heterogeneous static table they widen to a union Luau will not narrow from
				-- the key, which is accepted; that node kind has exact per-field listeners.
				-- Past MAX_CHILD_UNION the pair is widened; a growing union is what exceeds the budget.
				local childKey = if #childKeys > MAX_CHILD_UNION then ts.string else ts.unionof(table.unpack(childKeys))
				local childValue = if #childValues > MAX_CHILD_UNION
					then optional(anyType)
					else optional(ts.unionof(table.unpack(childValues)))
				add("OnChildChanged", fn({ fn({ childKey, childValue, childValue }, {}) }, { disconnectType }))
			end
		end

		if mapKey ~= nil then
			-- A map's children are accessor nodes keyed by the declared type; the key
			-- events and Remove carry the element rather than the whole map.
			local element = mapElement :: type
			local childNode = build(mapValue :: type, false, depth + 1)
			table.insert(childLookups, fn({ mapKey }, { childNode }))
			indexerSpec = { index = mapKey, readresult = childNode, writeresult = childNode }
			add("Remove", fn({ mapKey, optBool }, { optional(element) }))
			add("OnKeyAdded", fn({ fn({ mapKey, element }, {}) }, { disconnectType }))
			add("OnKeyRemoved", fn({ fn({ mapKey, element }, {}) }, { disconnectType }))
			add("OnChildChanged", fn({ fn({ mapKey, optional(element), optional(element) }, {}) }, { disconnectType }))
			add("Clear", fn({ optBool }, {}))
			add("Count", fn({}, { ts.number }))
		end

		-- A homogeneous container keeps the exact child type. Static records use
		-- an untyped lookup: overloads duplicate every recursive child node in the
		-- callable surface and push ordinary templates past the Luau solver budget.
		-- Direct property access remains exact; TypeScript can type this lookup too.
		if #childLookups == 1 then
			add("Child", childLookups[1])
		elseif #childLookups > 1 then
			add("Child", fn({ ts.unionof(ts.string, ts.number) }, { anyType }))
		end

		-- Common node methods.
		add("Get", fn({}, { valueType }))
		-- The root accessor cannot be Set or Updated at runtime, so those are left off the
		-- root type. A big field declares its own wider Set and Update below; adding them
		-- here too would duplicate rather than override, as the singletons are distinct keys.
		if not isRoot and not isBig and not isDerived then
			-- Writes take the unbranded shape: a caller writing a plain table literal
			-- has no way to produce a map's metatable brand. Reads still hand back the
			-- branded type, which assigns freely to the plain shape.
			local writeType = if mapKey ~= nil and mapElement ~= nil
				then ts.newtable(nil, { index = mapKey, readresult = mapElement, writeresult = mapElement }, nil)
				else valueType
			local writeIn = if mapKey ~= nil then writeType else readOnlyDeep(writeType, depth + 1)
			add("Set", fn({ writeIn, optBool }, { valueType }))
			add("Update", fn({ fn({ valueType }, { writeIn }), optBool }, { valueType }))
		end
		add("Clone", fn({}, { valueType }))
		add("Default", fn({}, { valueType }))
		-- (new, old) on every node. On a container it reports state, coalesced to one
		-- fire per batch or received frame; which child moved is OnChildChanged's job.
		add("Changed", fn({ fn({ valueType, valueType }, {}) }, { disconnectType }))
		add("Observe", fn({ fn({ valueType }, {}) }, { disconnectType }))

		if t:is("number") then
			-- Min/Max read the declared bounds, so they stay on a derived field; the
			-- two mutators do not.
			if not isDerived then
				add("Increment", fn({ ts.number, anyType }, { ts.number }))
				add("Decrement", fn({ ts.number, anyType }, { ts.number }))
			end
			add("Min", fn({}, { optNumber }))
			add("Max", fn({}, { optNumber }))
		elseif t:is("boolean") and not isDerived then
			add("Toggle", fn({ optBool }, { ts.boolean }))
		end

		if isBig then
			-- Every entry point, Set included, takes a number, a numeric string, or
			-- another big value, so the operand type is the same union everywhere.
			local operand = ts.unionof(ts.number, ts.string, valueType)
			add("Set", fn({ operand, optBool }, { valueType }))
			add("Update", fn({ fn({ valueType }, { operand }), optBool }, { valueType }))
			add("Increment", fn({ operand, anyType }, { valueType }))
			add("Decrement", fn({ operand, anyType }, { valueType }))
			add("Multiply", fn({ operand, optBool }, { valueType }))
			add("Divide", fn({ operand, optBool }, { valueType }))
			-- A big bound past the double range is only expressible as a numeric string,
			-- so these return the same union the declarator accepts.
			local optBound = optional(ts.unionof(ts.number, ts.string))
			add("Min", fn({}, { optBound }))
			add("Max", fn({}, { optBound }))
		end

		if isSet then
			-- Membership surface. Get/Set still take the whole { T }.
			local setIndexer = t:indexer()
			local element = if setIndexer ~= nil then widen(setIndexer.readresult) else anyType
			local elementIn = readOnlyDeep(element, depth + 1)
			add("Add", fn({ elementIn, optBool }, { ts.boolean }))
			add("Remove", fn({ elementIn, optBool }, { ts.boolean }))
			add("Has", fn({ elementIn }, { ts.boolean }))
			add("Count", fn({}, { ts.number }))
			add("Clear", fn({ optBool }, {}))
		end

		if isFlags then
			-- Named-member surface. Get/Set still take the whole { string } set.
			add("Enable", fn({ ts.string, optBool }, {}))
			add("Disable", fn({ ts.string, optBool }, {}))
			add("Has", fn({ ts.string }, { ts.boolean }))
			add("Toggle", fn({ ts.string, optBool }, { ts.boolean }))
			add("Clear", fn({ optBool }, {}))
		end

		if isTimed then
			add("SetTimed", fn({ valueType, ts.number, optBool }, {}))
			add("ExtendTimed", fn({ ts.number, optBool }, {}))
			add("Active", fn({}, { ts.boolean, optNumber }))
		end

		-- Read-only, not read/write. An accessor is never assigned to, and a read/write
		-- property makes comparing two accessor trees invariant: the solver has to prove
		-- each side is exactly the other, which is what exceeds its budget at Scribe().
		local out = ts.newtable(nil, indexerSpec, nil)
		for _, entry in props do
			out:setreadproperty(entry.key, entry.ty)
		end
		return out
	end

	return build(T, true, 0)
end

-- Union of every static rankable leaf path in the template, dot-joined ("Coins",
-- "Stats.Wins"), for leaderboard `Stat` and purchase cost paths. Dynamic segments cannot
-- be enumerated at type level, so those paths must be cast to `any`; falls back to plain
-- `string` when the template has no such leaf. `IncludeBig` is true for leaderboards and
-- false for cost paths, which must be plain numbers.
-- selene: allow(undefined_variable)
export type function StatPathsType(T: type, IncludeBig: type?): type
	local ts = types
	local MAX_STAT_PATHS = 32
	local includeBig = IncludeBig ~= nil and IncludeBig:is("singleton") and IncludeBig:value() == true

	local function hasMarker(t: type, name: string): boolean
		local mt = t:metatable()
		return mt ~= nil and mt:readproperty(ts.singleton(name)) ~= nil
	end

	local function isBigMarker(t: type): boolean
		return hasMarker(t, "__scribeBig")
	end

	local function isMapMarker(t: type): boolean
		return hasMarker(t, "__scribeMapKey")
	end

	local paths: { type } = {}

	local function widen(t: type): type
		if t:is("singleton") then
			local value = t:value()
			if type(value) == "boolean" then
				return ts.boolean
			elseif type(value) == "string" then
				return ts.string
			end
		end
		return t
	end

	local function walk(rawType: type, prefix: string, depth: number)
		if depth > 8 then
			return
		end
		local t = widen(rawType)
		if t:is("table") then
			-- Unwrap the Scribe.Timed marker; its inner value is the leaf.
			local inner = t:readproperty(ts.singleton("__scribeTimed"))
			if inner ~= nil then
				t = widen(inner)
			end
		end
		if t:is("table") then
			-- Same for Scribe.ServerOnly: the server is what reads leaderboard
			-- stats, so a server-only number is still a valid stat path.
			local serverOnly = t:readproperty(ts.singleton("__scribeServerOnly"))
			if serverOnly ~= nil then
				t = widen(serverOnly)
			end
		end
		if t:is("table") then
			-- And Scribe.Derived: a board reads its stat through the accessor tree,
			-- which computes derived fields, so a derived number is a valid stat.
			local derived = t:readproperty(ts.singleton("__scribeDerived"))
			if derived ~= nil then
				t = widen(derived)
			end
		end
		if t:is("table") and isMapMarker(t) then
			-- A map's entries live under dynamic keys, which cannot be enumerated at type
			-- level. Recursing would offer the unaddressable "Field.__scribeMapValue".
			return
		end
		if t:is("table") and isBigMarker(t) then
			-- Always terminal: a big's type is its real shape, so recursing would expose the
			-- object's own M and E and offer "Coins.M" as a stat path. When a big counts, the
			-- field itself is the path, or a template whose only rankable field is big
			-- produces an empty union and collapses the gate to `string`.
			if includeBig and prefix ~= "" then
				table.insert(paths, ts.singleton(prefix))
			end
			return
		end
		if t:is("number") then
			if prefix ~= "" then
				table.insert(paths, ts.singleton(prefix))
			end
			return
		end
		if t:is("table") then
			for key, prop in t:properties() do
				local childType = prop.read or prop.write
				if childType ~= nil and key:is("singleton") then
					local name = key:value()
					if type(name) == "string" then
						walk(childType, if prefix == "" then name else `{prefix}.{name}`, depth + 1)
					end
				end
			end
		end
	end

	walk(T, "", 0)

	if #paths == 0 then
		return ts.string
	end
	if #paths == 1 then
		return paths[1]
	end
	if #paths > MAX_STAT_PATHS then
		-- A union this size is what the solver cannot afford.
		return ts.string
	end
	return ts.unionof(table.unpack(paths))
end

-- T with every Scribe.ServerOnly subtree removed, at any depth, so the client type
-- cannot name a field that reads nil there. Applied to the raw template before
-- ValueType, which unwraps the marker and loses the information.
-- selene: allow(undefined_variable)
type function StripServerOnly(T)
	local ts = types
	local MARKER = ts.singleton("__scribeServerOnly")
	-- Matches ValueType's budget: a cyclic template must not blow the stack.
	local MAX_DEPTH = 25

	local function isServerOnly(t: type): boolean
		return t:is("table") and t:readproperty(MARKER) ~= nil
	end

	local function strip(t: type, depth: number): type
		if depth > MAX_DEPTH or not t:is("table") then
			return t
		end
		local out = ts.copy(t)
		for key, prop in t:properties() do
			local childType = prop.read or prop.write
			if childType ~= nil then
				if isServerOnly(childType) then
					out:setproperty(key, nil) -- the whole subtree leaves the client type
				else
					out:setproperty(key, strip(childType, depth + 1))
				end
			end
		end
		-- Element shapes live behind the indexer, not in properties: without this a
		-- ServerOnly field inside an ArrayOf or DictOf entry stays in the client type.
		local indexer = t:indexer()
		if indexer ~= nil then
			local element = strip(indexer.readresult, depth + 1)
			out:setindexer(indexer.index, element)
		end
		return out
	end

	return strip(T, 0)
end

-- Grant callbacks receive the typed accessor tree when a template type is supplied,
-- and stay `any` for the untyped default so un-annotated configs stay clean.
-- selene: allow(undefined_variable)
export type function GrantDataType(T)
	if T:is("any") or T:is("unknown") then
		return types.any
	end
	return ValueType(T)
end

-- Store proxies expose declared roots, without the root accessor's methods.
-- selene: allow(undefined_variable)
type function StoreDataType(S: type): type
	local ts = types
	if not S:is("table") then
		return ts.any
	end

	local fields = ts.newtable(nil, S:indexer(), nil)
	local names: { [type]: type } = {}
	local index = 0
	for key, prop in S:properties() do
		local fieldType = prop.read or prop.write
		if fieldType ~= nil then
			index += 1
			-- Avoid accessor names such as Get while building each field's type.
			local alias = ts.singleton(`_storeField{index}`)
			fields:setproperty(alias, fieldType)
			names[key] = alias
		end
	end
	local nodes = ValueType(fields)
	local roots = ts.newtable(nil, nodes:indexer(), nil)
	for key, alias in names do
		roots:setproperty(key, nodes:readproperty(alias))
	end
	return roots
end

-- The client `Data` is the accessor tree root plus the client API. A type function
-- rather than `ValueType<T> & { ... }`, because normalizing an intersection over a
-- large accessor tree exceeds the solver's budget at the Scribe() call site.
-- selene: allow(undefined_variable)
type function BuildClientDataType(T, S)
	local ts = types

	local function optional(t: type): type
		return ts.unionof(t, ts.singleton(nil))
	end

	local function fn(params: { type }, rets: { type }): type
		return ts.newfunction({ head = params }, { head = rets })
	end

	local anyTable = ts.newtable(nil, { index = ts.string, readresult = ts.any, writeresult = ts.any }, nil)
	local stringToNumber = ts.newtable(nil, { index = ts.string, readresult = ts.number, writeresult = ts.number }, nil)

	local entryProps: { [type]: type } = {}
	entryProps[ts.singleton("Rank")] = ts.number
	entryProps[ts.singleton("UserId")] = ts.number
	entryProps[ts.singleton("Name")] = ts.string
	-- `number | BigScore`, not `number`: a Scribe.Big board hands back the big itself,
	-- and the board's kind is a runtime property of the name passed in, so the type
	-- cannot pick one and the caller narrows.
	local bigScoreProps: { [type]: type } = {}
	bigScoreProps[ts.singleton("M")] = ts.number
	bigScoreProps[ts.singleton("E")] = ts.number
	bigScoreProps[ts.singleton("Short")] = ts.newfunction(
		{ head = { ts.any, ts.unionof(ts.number, ts.singleton(nil)) } },
		{ head = { ts.string } }
	)
	bigScoreProps[ts.singleton("ToNumber")] = ts.newfunction({ head = { ts.any } }, { head = { ts.number } })
	bigScoreProps[ts.singleton("Log10")] = ts.newfunction({ head = { ts.any } }, { head = { ts.number } })
	entryProps[ts.singleton("Score")] = ts.unionof(ts.number, ts.newtable(bigScoreProps, nil, nil))
	local leaderboardEntry = ts.newtable(entryProps, nil, nil)
	local entryArray =
		ts.newtable(nil, { index = ts.number, readresult = leaderboardEntry, writeresult = leaderboardEntry }, nil)
	local anyArray = ts.newtable(nil, { index = ts.number, readresult = anyTable, writeresult = anyTable }, nil)

	local statusType = ts.unionof(ts.singleton("Healthy"), ts.singleton("Degraded"), ts.singleton("Outage"))

	local saveInfoProps: { [type]: type } = {}
	saveInfoProps[ts.singleton("LastSaveAt")] = optional(ts.number)
	saveInfoProps[ts.singleton("LastResult")] = optional(ts.unionof(ts.singleton("Ok"), ts.singleton("Fail")))
	saveInfoProps[ts.singleton("Dirty")] = ts.boolean
	saveInfoProps[ts.singleton("Size")] = optional(ts.number)
	local saveInfo = ts.newtable(saveInfoProps, nil, nil)

	local out = ts.copy(ValueType(StripServerOnly(T)))
	local function add(name: string, ty: type)
		out:setproperty(ts.singleton(name), ty)
	end

	add("IsReady", fn({}, { ts.boolean }))
	add("Batch", fn({ fn({}, {}) }, {}))
	add("Stop", fn({}, {}))
	add("WaitForData", fn({ optional(ts.number) }, { ts.boolean }))
	add("Request", ts.newfunction({ head = { ts.string }, tail = ts.any }, { tail = ts.any }))
	-- RequestOnce(name, key, ...): the key is a required second string, so a plain
	-- Request argument list fails to type-check rather than silently becoming a key.
	add("RequestOnce", ts.newfunction({ head = { ts.string, ts.string }, tail = ts.any }, { tail = ts.any }))
	add("GetLeaderboard", fn({ ts.string, optional(ts.number) }, { entryArray }))
	add("GetMyRank", fn({ ts.string }, { optional(ts.number) }))
	add("OnLeaderboard", ts.any)
	add("GetServiceStatus", fn({}, { statusType }))
	add("OnServiceStatus", ts.any)
	add("GetShared", fn({ ts.any }, { optional(anyTable) }))
	add("OnSharedChanged", ts.any)
	add("Owns", fn({ ts.string }, { ts.boolean }))
	add("OwnsAsync", fn({ ts.string, optional(ts.number) }, { ts.boolean }))
	add("ObserveOwned", fn({ ts.string, fn({ ts.boolean }, {}) }, { fn({}, {}) }))
	add("OnOwnershipChanged", ts.any)
	add("GetSaveInfo", fn({}, { saveInfo }))
	add("GetGiftCredits", fn({}, { stringToNumber }))
	local purchaseFilterProps: { [type]: type } = {}
	purchaseFilterProps[ts.singleton("Kind")] = optional(ts.unionof(ts.singleton("Robux"), ts.singleton("InGame")))
	purchaseFilterProps[ts.singleton("Category")] = optional(ts.string)
	purchaseFilterProps[ts.singleton("ItemId")] = optional(ts.string)
	purchaseFilterProps[ts.singleton("Since")] = optional(ts.number)
	purchaseFilterProps[ts.singleton("Limit")] = optional(ts.number)
	local purchaseFilter = optional(ts.newtable(purchaseFilterProps, nil, nil))
	add("GetPurchases", fn({ purchaseFilter }, { anyArray }))
	local stringArray = ts.newtable(nil, { index = ts.number, readresult = ts.string, writeresult = ts.string }, nil)
	add("GetProductInfo", fn({ ts.string }, { optional(anyTable) }))
	add("GetPrice", fn({ ts.string }, { optional(ts.number) }))
	add("GetProductInfoAsync", fn({ ts.string, optional(ts.number) }, { optional(anyTable) }))
	add("GetPriceAsync", fn({ ts.string, optional(ts.number) }, { optional(ts.number) }))
	add("ObserveProductInfo", fn({ ts.string, fn({ optional(anyTable) }, {}) }, { fn({}, {}) }))
	add("PromptPurchase", fn({ ts.string }, { ts.boolean, optional(ts.string), optional(ts.newtable(nil, nil, nil)) }))
	add("GetProductState", fn({ ts.string }, { ts.string }))
	add("ObserveProductState", fn({ ts.string, fn({ ts.string }, {}) }, { fn({}, {}) }))
	add("PrefetchProductInfo", fn({ optional(stringArray) }, {}))
	add("RefreshProductInfo", fn({ optional(ts.string) }, {}))
	add("Mock", fn({ optional(anyTable), optional(anyTable) }, {}))
	add(
		"MockCommand",
		ts.newfunction({ head = { ts.string, ts.newfunction({ tail = ts.any }, { tail = ts.any }) } }, { head = {} })
	)
	add("Raw", ts.any)
	add("ServerStore", StoreDataType(StripServerOnly(S)))

	return out
end

-- selene: allow(undefined_variable)
export type function ClientDataType(T)
	return BuildClientDataType(T, types.any)
end

-- The server `Data` API. P is the Player class type, passed in as a type argument
-- because class types are not constructible inside a type function. A type function
-- for the same complexity-budget reason as ClientDataType.
-- selene: allow(undefined_variable)
type function BuildServerDataType(T, P, S)
	local ts = types

	local node = ValueType(T)

	local function optional(t: type): type
		return ts.unionof(t, ts.singleton(nil))
	end

	local function fn(params: { type }, rets: { type }): type
		return ts.newfunction({ head = params }, { head = rets })
	end

	local anyTable = ts.newtable(nil, { index = ts.string, readresult = ts.any, writeresult = ts.any }, nil)
	local stringToNumber = ts.newtable(nil, { index = ts.string, readresult = ts.number, writeresult = ts.number }, nil)
	local optAnyTable = optional(anyTable)
	local anyArray = ts.newtable(nil, { index = ts.number, readresult = anyTable, writeresult = anyTable }, nil)
	local boolAndReason = { ts.boolean, optional(ts.string) }

	local entryProps: { [type]: type } = {}
	entryProps[ts.singleton("Rank")] = ts.number
	entryProps[ts.singleton("UserId")] = ts.number
	entryProps[ts.singleton("Name")] = ts.string
	-- `number | BigScore`: a Scribe.Big board hands back the big itself, as in
	-- ClientDataType above.
	local bigScoreProps: { [type]: type } = {}
	bigScoreProps[ts.singleton("M")] = ts.number
	bigScoreProps[ts.singleton("E")] = ts.number
	bigScoreProps[ts.singleton("Short")] = ts.newfunction(
		{ head = { ts.any, ts.unionof(ts.number, ts.singleton(nil)) } },
		{ head = { ts.string } }
	)
	bigScoreProps[ts.singleton("ToNumber")] = ts.newfunction({ head = { ts.any } }, { head = { ts.number } })
	bigScoreProps[ts.singleton("Log10")] = ts.newfunction({ head = { ts.any } }, { head = { ts.number } })
	entryProps[ts.singleton("Score")] = ts.unionof(ts.number, ts.newtable(bigScoreProps, nil, nil))
	local leaderboardEntry = ts.newtable(entryProps, nil, nil)
	local entryArray =
		ts.newtable(nil, { index = ts.number, readresult = leaderboardEntry, writeresult = leaderboardEntry }, nil)

	local saveInfoProps: { [type]: type } = {}
	saveInfoProps[ts.singleton("LastSaveAt")] = optional(ts.number)
	saveInfoProps[ts.singleton("LastResult")] = optional(ts.unionof(ts.singleton("Ok"), ts.singleton("Fail")))
	saveInfoProps[ts.singleton("Dirty")] = ts.boolean
	saveInfoProps[ts.singleton("Size")] = optional(ts.number)
	local saveInfo = ts.newtable(saveInfoProps, nil, nil)

	local versionProps: { [type]: type } = {}
	versionProps[ts.singleton("VersionId")] = ts.string
	versionProps[ts.singleton("CreatedAt")] = ts.number
	versionProps[ts.singleton("Size")] = optional(ts.number)
	local versionRecord = ts.newtable(versionProps, nil, nil)
	local versionArray =
		ts.newtable(nil, { index = ts.number, readresult = versionRecord, writeresult = versionRecord }, nil)

	local flushOptsProps: { [type]: type } = {}
	flushOptsProps[ts.singleton("Force")] = optional(ts.boolean)
	flushOptsProps[ts.singleton("Timeout")] = optional(ts.number)
	local flushOpts = optional(ts.newtable(flushOptsProps, nil, nil))

	local restoreOptsProps: { [type]: type } = {}
	restoreOptsProps[ts.singleton("RollBackReserved")] = optional(ts.boolean)
	local restoreOpts = optional(ts.newtable(restoreOptsProps, nil, nil))

	-- Keep in sync with Types.LifecycleReason. Spelled out here because a type
	-- function cannot reference an exported type alias.
	local reasonUnion = ts.unionof(
		ts.singleton("load-failed"),
		ts.singleton("migration-failed"),
		ts.singleton("erasing"),
		ts.singleton("session-ended"),
		ts.singleton("player-left"),
		ts.singleton("shutdown"),
		ts.singleton("still-loading"),
		ts.singleton("timeout")
	)

	local props: { [type]: type } = {}
	local function add(name: string, ty: type)
		props[ts.singleton(name)] = ty
	end

	add("Get", fn({ P }, { node }))
	add("WaitForData", fn({ P, optional(ts.number) }, { optional(node), optional(reasonUnion) }))
	add(
		"GetState",
		fn({ P }, {
			ts.unionof(ts.singleton("Loading"), ts.singleton("Ready"), ts.singleton("SessionEnded")),
			optional(
				ts.unionof(
					ts.singleton("WaitingForErase"),
					ts.singleton("AcquiringSession"),
					ts.singleton("ReadingProfile"),
					ts.singleton("Retrying"),
					ts.singleton("Initializing"),
					ts.singleton("Importing"),
					ts.singleton("ImportThrottled")
				)
			),
		})
	)

	add("Batch", fn({ P, fn({}, {}) }, {}))
	add("Transaction", fn({ P, fn({}, {}) }, boolAndReason))

	add("Flush", fn({ P, flushOpts }, { ts.boolean }))
	add("GetSaveInfo", fn({ P }, { saveInfo }))
	add("GetOffline", fn({ ts.number }, { optAnyTable }))
	local updateOfflineOptsProps: { [type]: type } = {}
	updateOfflineOptsProps[ts.singleton("Validate")] = optional(ts.boolean)
	local updateOfflineOpts = optional(ts.newtable(updateOfflineOptsProps, nil, nil))
	add(
		"UpdateOffline",
		fn(
			{ ts.number, fn({ anyTable }, {}), updateOfflineOpts },
			{ ts.boolean, optional(ts.string), optional(anyArray) }
		)
	)
	add("ListVersions", fn({ ts.number, optional(ts.number) }, { versionArray }))
	add("GetVersion", fn({ ts.number, ts.string }, { optAnyTable }))
	add("RestoreVersion", fn({ ts.number, ts.string, restoreOpts }, boolAndReason))

	-- Command(name, spec?, handler): the spec shape and the handler's `player` param are
	-- typed; per-arg types cannot be recovered, since the Args literals widen. Args
	-- elements are `any` rather than `string` because Commands.Register also accepts
	-- declarators and shape tables, and validates the entries itself at register time.
	local commandArgs = ts.newtable(nil, { index = ts.number, readresult = ts.any, writeresult = ts.any }, nil)
	local commandSpecProps: { [type]: type } = {}
	commandSpecProps[ts.singleton("Args")] = optional(commandArgs)
	commandSpecProps[ts.singleton("Idempotent")] = optional(ts.boolean)
	local commandSpec = ts.newtable(commandSpecProps, nil, nil)
	local commandHandler = ts.newfunction({ head = { P }, tail = ts.any }, { tail = ts.any })
	add("Command", fn({ ts.string, ts.unionof(commandSpec, commandHandler), optional(commandHandler) }, {}))

	add("GetLeaderboard", fn({ ts.string, optional(ts.number), optional(ts.number) }, { entryArray }))
	add("GetMyRank", fn({ P, ts.string }, { optional(ts.number) }))
	add("GetLeaderboardRefreshIn", fn({ ts.string }, { optional(ts.number) }))
	local boardStatusProps: { [type]: type } = {}
	boardStatusProps[ts.singleton("Status")] =
		ts.unionof(ts.singleton("Starting"), ts.singleton("Healthy"), ts.singleton("Degraded"))
	for _, key in { "PendingWrites", "RetryingWrites", "RejectedWrites" } do
		boardStatusProps[ts.singleton(key)] = ts.number
	end
	for _, key in { "LastReadAt", "ReadAge", "LastWriteAt" } do
		boardStatusProps[ts.singleton(key)] = optional(ts.number)
	end
	for _, key in { "LastReadError", "LastWriteError" } do
		boardStatusProps[ts.singleton(key)] = optional(ts.string)
	end
	add("GetLeaderboardStatus", fn({ ts.string }, { optional(ts.newtable(boardStatusProps, nil, nil)) }))
	add("GetLeaderboardResetIn", fn({ ts.string }, { optional(ts.number) }))

	add("PromptGift", fn({ P, ts.string, ts.number }, boolAndReason))
	add("PromptPurchase", fn({ P, ts.string }, boolAndReason))
	add("GetProductState", fn({ P, ts.string }, { ts.string }))
	add("GetGiftCredits", fn({ P }, { stringToNumber }))
	add("HandleReceipt", fn({ ts.any }, { ts.any }))
	add("TryHandleReceipt", fn({ ts.any }, { optional(ts.any) }))
	add("Owns", fn({ P, ts.string }, { ts.boolean }))
	add("OwnsAsync", fn({ P, ts.string, optional(ts.number) }, { ts.boolean }))
	add("ObserveOwned", fn({ P, ts.string, fn({ ts.boolean }, {}) }, { fn({}, {}) }))
	add("OnOwnershipChanged", ts.any)
	add("GrantPerk", fn({ P, ts.string }, {}))
	add("RevokePerk", fn({ P, ts.string }, {}))

	-- Purchase spec: Cost.Path is the template's numeric-leaf path union and
	-- Grant receives the typed accessor tree.
	local costProps: { [type]: type } = {}
	-- false: a cost path must be a plain number balance. Monetization refuses a
	-- non-number at runtime, so this rejects a Scribe.Big path at author time.
	costProps[ts.singleton("Path")] = StatPathsType(T, ts.singleton(false))
	costProps[ts.singleton("Amount")] = ts.number
	local purchaseProps: { [type]: type } = {}
	purchaseProps[ts.singleton("Cost")] = ts.newtable(costProps, nil, nil)
	purchaseProps[ts.singleton("Category")] = optional(ts.string)
	purchaseProps[ts.singleton("ItemId")] = ts.string
	purchaseProps[ts.singleton("Grant")] = optional(fn({ node }, {}))
	purchaseProps[ts.singleton("Meta")] = optAnyTable
	add("Purchase", fn({ P, ts.newtable(purchaseProps, nil, nil) }, boolAndReason))
	add("RecordPurchase", fn({ P, anyTable }, {}))
	-- OpenLeg and OpenExchange are rebuilt here: a type function cannot reach an alias.
	local openLegProps: { [type]: type } = {}
	local pathSegment = ts.unionof(ts.string, ts.number)
	openLegProps[ts.singleton("Path")] =
		ts.newtable(nil, { index = ts.number, readresult = pathSegment, writeresult = pathSegment }, nil)
	openLegProps[ts.singleton("Kind")] = ts.string
	openLegProps[ts.singleton("Key")] = optional(ts.any)
	openLegProps[ts.singleton("Amount")] = optional(ts.number)
	local openLeg = ts.newtable(openLegProps, nil, nil)
	local openLegArray = ts.newtable(nil, { index = ts.number, readresult = openLeg, writeresult = openLeg }, nil)
	local openProps: { [type]: type } = {}
	openProps[ts.singleton("Id")] = ts.string
	openProps[ts.singleton("State")] =
		ts.unionof(ts.singleton("Claimed"), ts.unionof(ts.singleton("Staked"), ts.singleton("Delivering")))
	openProps[ts.singleton("Partner")] = optional(ts.number)
	openProps[ts.singleton("Staked")] = openLegArray
	openProps[ts.singleton("Owed")] = openLegArray
	openProps[ts.singleton("Since")] = optional(ts.number)
	local openExchange = ts.newtable(openProps, nil, nil)
	local openArray =
		ts.newtable(nil, { index = ts.number, readresult = openExchange, writeresult = openExchange }, nil)
	local exchangeProps: { [type]: type } = {}
	exchangeProps[ts.singleton("Attempt")] = fn(
		{ P, anyArray, P, anyArray },
		{ optional(ts.string), optional(ts.string) }
	)
	exchangeProps[ts.singleton("Open")] = fn({ P }, { openArray })
	exchangeProps[ts.singleton("Discard")] = fn({ ts.string }, boolAndReason)
	exchangeProps[ts.singleton("Settle")] = fn({ ts.string, ts.string }, boolAndReason)
	exchangeProps[ts.singleton("Redirect")] = fn({ ts.string, ts.number, ts.string }, boolAndReason)
	add("Exchange", ts.newtable(exchangeProps, nil, nil))

	-- Returned by Scribe.Server.
	add("Stop", fn({}, {}))
	local purchaseFilterProps: { [type]: type } = {}
	purchaseFilterProps[ts.singleton("Kind")] = optional(ts.unionof(ts.singleton("Robux"), ts.singleton("InGame")))
	purchaseFilterProps[ts.singleton("Category")] = optional(ts.string)
	purchaseFilterProps[ts.singleton("ItemId")] = optional(ts.string)
	purchaseFilterProps[ts.singleton("Since")] = optional(ts.number)
	purchaseFilterProps[ts.singleton("Limit")] = optional(ts.number)
	local purchaseFilter = optional(ts.newtable(purchaseFilterProps, nil, nil))
	add("GetPurchases", fn({ P, purchaseFilter }, { anyArray }))

	local cooldownOptsProps: { [type]: type } = {}
	cooldownOptsProps[ts.singleton("IncludeOfflineTime")] = optional(ts.boolean)
	local cooldownOpts = optional(ts.newtable(cooldownOptsProps, nil, nil))
	add("OnCooldown", fn({ P, ts.string, ts.number, cooldownOpts }, { ts.boolean, ts.number }))
	add("PeekCooldown", fn({ P, ts.string }, { ts.boolean, ts.number }))
	add("ClearCooldown", fn({ P, ts.string }, {}))

	add("Erase", fn({ ts.number }, boolAndReason))
	add("Export", fn({ ts.number }, { optional(ts.string) }))

	add("OnSave", ts.any)
	add("SessionEnded", ts.any)
	add("OnCooldownEnded", ts.any)
	add("OnLeaderboard", ts.any)
	add("OnAnomaly", ts.any)
	add("OnGiftReceived", ts.any)
	add("OnGiftCredit", ts.any)
	add("OnMessage", ts.any)
	add("SendMessage", fn({ ts.number, ts.any }, { ts.boolean }))
	add("ProfileStore", ts.any)
	add("Raw", ts.any)
	add("ServerStore", StoreDataType(S))

	return ts.newtable(props, { index = P, readresult = node, writeresult = node }, nil)
end

-- selene: allow(undefined_variable)
export type function ServerDataType(T, P)
	return BuildServerDataType(T, P, types.any)
end

--------------------------------------------------------------------------------
-- Typed field declarators
--------------------------------------------------------------------------------

export type Timed<T> = { __scribeTimed: T }
-- What a Scribe.Flags field reads back: the enabled member names. The label sits in
-- the metatable so a whole-table read shows the members rather than the label.
export type Flags = typeof(setmetatable({} :: { string }, {} :: { __scribeFlags: true }))
-- A set reads back as its members. Label in the metatable, as above.
export type SetOf<T> = typeof(setmetatable({} :: { T }, {} :: { __scribeSet: true }))
export type ServerOnly<T> = { __scribeServerOnly: T }
-- A derived field reads back as its output type, which may be a scalar, so the label
-- is an ordinary field stripped by unwrapWrappers rather than a metatable entry.
export type Derived<T> = { __scribeDerived: T }

export type NumberMeta = { Min: number?, Max: number? }
-- Scribe.Number only. `Precision` opts into a narrower wire form; Min and Max alone
-- select nothing. Kept off NumberMeta because a bounded Int already packs from its
-- own bounds, so Precision has nothing to say there.
export type FloatMeta = { Min: number?, Max: number?, Precision: (number | "f32")? }
-- Scribe.Big only. A bound past 1.8e308 must be written as a numeric string, because
-- a larger literal is already math.huge and the template validator rejects it.
export type BigMeta = { Min: (number | string)?, Max: (number | string)? }
export type StringMeta = { MaxLength: number? }
-- Scribe.CFrame only. The same knob as FloatMeta's Precision pointing the other way,
-- since a CFrame defaults to the lossy form. "exact" is the only value: a CFrame has no
-- intermediate widths to name.
export type CFrameMeta = { Precision: "exact"? }
-- Container declarator options. Not generic in the element type on purpose: an
-- element-typed option would let Luau infer the element type from it rather than
-- from `shape`, silently redefining the field.
export type ArrayOpts = { MaxItems: number?, Evict: ("Front" | "Back")? }
export type SetOpts = { MaxItems: number? }
export type CooldownOptions = { IncludeOfflineTime: boolean? }
export type MapKeyType = "integer" | "string"
-- What a Scribe.Big field reads back, which is also what the declarator returns.
-- `__scribeBig` lives in the metatable rather than in the fields: a label field travels
-- into every read, so `Get().Wealth.__scribeBig` would typecheck while being nil.
type BigFields = {
	M: number,
	E: number,
	Short: (self: any, decimals: number?) -> string,
	ToNumber: (self: any) -> number,
	-- Pow returns another big, typed `any` rather than BigValue: spelling the recursion
	-- here tips bundles in test/TypeCheck.luau past the solver's complexity budget. The
	-- accessor tree gets the real self-referential type from ValueType above.
	Pow: (self: any, n: number) -> any,
	Log10: (self: any) -> number,
	-- The marker stays shallow, like Pow; accessor reads gain exact recursive
	-- result types from bigValueType above. BigMath.Big is only the M/E shape.
	Add: (self: any, other: BigMath.Big | number | string) -> any,
	Subtract: (self: any, other: BigMath.Big | number | string) -> any,
	Multiply: (self: any, other: BigMath.Big | number | string) -> any,
	Divide: (self: any, other: BigMath.Big | number | string) -> any,
	Negate: (self: any) -> any,
	Compare: (self: any, other: BigMath.Big | number | string) -> number,
	Equals: (self: any, other: BigMath.Big | number | string) -> boolean,
}
type BigMt = { __scribeBig: true }
export type BigValue = typeof(setmetatable({} :: BigFields, {} :: BigMt))
-- What a Scribe.MapOf field reads back: the whole map. The declared key is a
-- singleton that has to become a real indexer key type, hence the type function; the
-- label and the key ride the metatable, as with Big, Flags and SetOf.
-- selene: allow(undefined_variable)
type function MapShape(K, V)
	local ts = types
	local key = if K:is("singleton") and K:value() == "integer" then ts.number else ts.string
	local out = ts.newtable(nil, { index = key, readresult = V, writeresult = V }, nil)
	local mt: { [type]: type } = {}
	mt[ts.singleton("__scribeMapKey")] = K
	out:setmetatable(ts.newtable(mt, nil, nil))
	return out
end
export type MapOf<K, V> = MapShape<K, V>
export type DictOpts = { MaxKeys: number?, MaxKeyLength: number? }

-- Template-aware config types. Annotate a config local with one and `Stat` / `Cost.Path`
-- become the template's numeric leaf-path union while `Grant` receives the typed accessor
-- tree. The annotation is required: in the same table literal that declares the template,
-- Luau widens the string literals before the template type is known.
export type LeaderboardConfig<T = any> = {
	Stat: StatPathsType<T, true>,
	Limit: number?,
	Scale: number?,
	-- Scribe.Big stats only: significant figures the ranking key carries, 1 to 15
	-- (default 12). Every extra figure costs a factor of ten of exponent range,
	-- because the two halves share one integer under 2^53.
	SigFigs: number?,
	Replicate: boolean?, -- default false: server-only (Data.GetLeaderboard on the server); true streams the board to clients
	RefreshInterval: number?, -- approximate seconds between reads of this board (default 60, floor 60, jittered)
	WriteInterval: number?, -- minimum seconds between changed-score writes per player/store (default 30, minimum 1); ignored for Server scope
	StoreName: string?, -- override the OrderedDataStore name (default "LB_<board>"); a periodic board appends the period
	Period: ("Daily" | "Weekly")?, -- a board that resets; nil is lifetime
	Mode: ("Gain" | "Peak")?, -- with Period: the gain since it began (default) or the peak seen in it
	Scope: ("Global" | "Server")?, -- "Server" ranks the players on this server, with no store behind it
}

export type ProductConfig<T = any> = {
	Id: number,
	Category: string?,
	Grant: ((data: GrantDataType<T>) -> ())?,
	Grants: string?,
}

export type PurchaseSpec<T = any> = {
	Cost: { Path: StatPathsType<T, false>, Amount: number },
	Category: string?,
	ItemId: string,
	Grant: ((data: GrantDataType<T>) -> ())?,
	Meta: { [string]: any }?,
}

-- Loose, read-only option shapes. They deliberately do not depend on T: inside the
-- Scribe({ ... }) literal the template type is still being inferred, so strict fields
-- would widen and reject valid configs. Read-only props keep annotated strict tables
-- assignable.
type LeaderboardConfigLoose = {
	read Stat: string,
	read Limit: number?,
	read Scale: number?,
	read SigFigs: number?,
	read Replicate: boolean?,
	read RefreshInterval: number?,
	read WriteInterval: number?,
	read StoreName: string?,
	read Period: string?,
	read Mode: string?,
	read Scope: string?,
}

type ProductConfigLoose = {
	read Id: number,
	read Category: string?,
	read Grant: ((data: any) -> ())?,
	read Grants: string?,
}

-- Economy is loose for the same reason: a Resolve lambda's parameter would
-- generalize inside the literal and a strict field would reject it. Annotate a
-- config local with the exported `Scribe.EconomyConfig` for strict checking.
type EconomyCurrencyConfigLoose = {
	read Label: string?,
	read Fields: { Types.EconomyFieldSpec }?,
	read Resolve: ((player: any) -> { [string]: any })?,
}

type EconomyConfigLoose = {
	read Resolve: ((player: any) -> { [string]: any })?,
	read Prefix: boolean?,
	read Currencies: { read [string]: EconomyCurrencyConfigLoose }?,
	read LogEconomyEvent: Types.EconomyLogFn?,
}

--- Passed to ImportLegacyData and OnPlayerInit for pacing legacy-store reads.
export type MigrationContext = {
	--- Yields until `count` requests are spare, or `timeout` passes. Returns whether
	--- they were granted, and an optional release to call once they have been issued.
	AwaitBudget: (requestType: string, count: number?, timeout: number?) -> (boolean, () -> ()),
}

export type ScribeOptions<T, S = any> = {
	Template: T,
	-- One unsaved tree per server, replicated to everyone.
	ServerStore: S?,
	Transport: (Types.ScribeTransport | "Default")?,

	Migrations: { [number]: (data: { [string]: any }) -> () }?,
	UserOwnsGamePassAsync: ((userId: number, passId: number) -> boolean)?, -- advanced/test seam
	GetProductInfoAsync: ((assetId: number, infoType: any) -> { [string]: any }?)?, -- advanced/test seam
	GetPolicyInfoAsync: ((player: Player) -> { [string]: any }?)?, -- advanced/test seam
	DevMode: boolean?, -- advanced/test seam: overrides the RunService:IsStudio() default
	IsRunning: boolean?, -- advanced/test seam: overrides the RunService:IsRunning() default (false builds the edit-mode client half)
	MigrationShadow: boolean?, -- audit aid: re-runs migrations against raw pre-Reconcile data and warns on divergence (re-executes your migration bodies)
	-- Adopt data from another library, once, before Scribe has ever saved for this player.
	-- The third argument paces reads on the DataStore budget.
	ImportLegacyData: ((player: Player, userId: number, migration: MigrationContext) -> { [string]: any }?)?,
	MigrationConcurrency: number?, -- imports allowed to run at once; defaults to 2
	-- The fourth argument is the same MigrationContext: ImportLegacyData only fires for a
	-- player who has never saved, so a game already on Scribe finishes moving here.
	OnPlayerInit: ((
		player: Player,
		rawData: { [string]: any },
		isNewProfile: boolean,
		migration: MigrationContext
	) -> ())?,
	OnPlayerLeaving: ((player: Player, data: any, reason: LifecycleReason) -> ())?,

	-- persistence
	ProfileStoreIndex: string, -- REQUIRED: the DataStore name (each game must name its own store)
	ProfileKeyPrefix: string, -- REQUIRED: prefix for per-player keys (e.g. "PLAYER_"); "" means bare user-id keys
	SaveInterval: number?, -- seconds between autosaves per profile (default 300, floor 15)
	ProfileStore: any?, -- explicit ProfileStore module (module table or ModuleScript)
	Mode: ("Live" | "Mock" | "NoSave")?, -- persistence mode (default "Live"); overrides the legacy flags below
	TargetUserId: number?, -- load this user's profile instead of the joining player's
	-- Legacy persistence flags, superseded by Mode. Still honoured when Mode is
	-- absent; ignored (with a startup warning) when it is present.
	UseMock: boolean?,
	ViewedUserId: number?,
	OverriddenUserId: number?,
	DontSave: boolean?,
	ResetData: boolean?,
	LoadFailurePolicy: ("Kick" | "Wait")?,
	LoadTimeout: number?,
	EraseJoinTimeout: number?,
	VersionAheadPolicy: ("Kick" | "Allow")?, -- default "Kick": fail closed when data is from a newer deploy
	KickOnSessionEnd: boolean?,
	LoadFailureMessage: string?,
	-- Per-cause overrides for the kick text. Each falls back to LoadFailureMessage when
	-- that is set, and to its own wording otherwise, so naming one never flattens the rest.
	LegacyImportFailureMessage: string?,
	MigrationFailureMessage: string?,
	VersionAheadMessage: string?,
	SchemaFailureMessage: string?,
	RateLimitedMessage: string?,
	ErasingMessage: string?,
	SessionEndMessage: string?,
	-- Per-cause overrides for the session-end kick, falling back to SessionEndMessage.
	SessionStolenMessage: string?,
	SessionInterruptedMessage: string?,

	-- services
	Leaderboards: { read [string]: LeaderboardConfigLoose }?,
	PeriodReset: { read UtcOffset: number?, read WeekStart: string? }?, -- the clock periodic boards reset on: hours from UTC (-12 to 14, default 0) and the day a week starts (default Monday)
	Products: { read [string]: ProductConfigLoose }?,
	RetiredProducts: { read [string]: ProductConfigLoose }?,
	Passes: { [string]: PassConfig }?,
	Perks: { string }?,
	OwnReceipts: boolean?,

	-- exchanging
	Exchangeable: { [string]: ExchangeableSpec }?,
	PurchaseLog: {
		RobuxCap: number?,
		InGameCap: number?,
		ReplicateRobux: boolean?,
		ReplicateInGame: boolean?,
		PurchaseLogCategories: { string }?,
	}?,

	-- gifting
	GiftCooldown: number?,
	GiftMaxPending: number?,
	GiftIntentTTL: number?,
	PurchaseIdTTL: number?,
	MaxProcessedPurchaseIds: number?,
	MaxReceiptHistoryBytes: number?,
	PurchaseClaimTTL: number?,
	MaxPurchaseClaims: number?,
	AllowDuplicateGifts: boolean?,
	NoGiftIntentPolicy: ("GrantOrCredit" | "Hold")?,

	-- economy analytics
	Economy: EconomyConfigLoose?,

	-- behaviour / limits
	CommandRateLimit: number?,
	RequestTimeout: number?,
	MaxInboundBytes: number?,
	MaxInboundRetainedBytes: number?,
	MaxOutboundBytes: number?,
	MaxInboundFrameRate: number?,
	TransportChannel: string?,

	-- integrity
	BoundsPolicy: ("Clamp" | "Reject")?,
	WipeGuardPolicy: ("Warn" | "Block")?,
	SchemaPolicy: ("Warn" | "Reject")?, -- check stored data against the template at load; off when absent
	BudgetPolicy: "Defer"?, -- burst-drain eligible leaderboard writes and budget-pace erasure; background request pacing is always on
	WipeGuardShrinkRatio: number?,

	-- diagnostics
	LogLevel: ("Debug" | "Info" | "Warn" | "Error" | "Fatal")?,
	LogRingLevel: Types.LogLevel?,
	LogRingSize: number?, -- entries Log.GetRecent retains (default 512)
	StatusThresholds: { FailWindow: number?, FailCount: number?, RecoverStreak: number? }?,
	Banner: boolean?, -- default true: print one "Scribe vX.Y.Z ... ready" line on load
	StudioHook: boolean?, -- default false: the Studio debug hooks the Scribe Studio plugin reads
}

export type ServerData<T, S = any> = BuildServerDataType<T, Player, S>

export type ClientData<T, S = any> = BuildClientDataType<T, S>

-- One player's typed accessor tree: the type of `Data[player]`, `Data.Get(player)` and
-- the client's `Data.Get()`. A plain alias because a type function cannot be invoked
-- across a module boundary: `Scribe.ValueType<T>` silently resolves to `any` rather than
-- erroring, so this is the only way a consumer can name the type.
export type PlayerData<T> = ValueType<T>

export type Bundle<T, S = any> = {
	Server: ServerData<T, S>,
	Client: ClientData<T, S>,
}

--------------------------------------------------------------------------------
-- Exported type reference
--
-- Doc blocks for the exported types, gathered here rather than beside the declarations:
-- @interface/@type blocks are keyed by name, and half of these types are re-exported
-- from Types.luau with nothing here to sit beside. A new exported type needs a block or
-- it renders nowhere.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Runtime
--------------------------------------------------------------------------------

local KNOWN_OPTION_KEYS: { [string]: boolean } = {
	Template = true,
	ServerStore = true,
	Exchangeable = true,
	Transport = true,
	TransportChannel = true,
	Migrations = true,
	UserOwnsGamePassAsync = true,
	GetProductInfoAsync = true,
	GetPolicyInfoAsync = true,
	DevMode = true,
	IsRunning = true,
	MigrationShadow = true,
	ImportLegacyData = true,
	MigrationConcurrency = true,
	OnPlayerInit = true,
	OnPlayerLeaving = true,
	ProfileStoreIndex = true,
	ProfileKeyPrefix = true,
	SaveInterval = true,
	ProfileStore = true,
	Mode = true,
	TargetUserId = true,
	UseMock = true,
	ViewedUserId = true,
	OverriddenUserId = true,
	DontSave = true,
	ResetData = true,
	LoadFailurePolicy = true,
	LoadTimeout = true,
	EraseJoinTimeout = true,
	VersionAheadPolicy = true,
	KickOnSessionEnd = true,
	LoadFailureMessage = true,
	LegacyImportFailureMessage = true,
	MigrationFailureMessage = true,
	VersionAheadMessage = true,
	SchemaFailureMessage = true,
	RateLimitedMessage = true,
	ErasingMessage = true,
	SessionEndMessage = true,
	SessionStolenMessage = true,
	SessionInterruptedMessage = true,
	Leaderboards = true,
	PeriodReset = true,
	Products = true,
	RetiredProducts = true,
	Passes = true,
	Perks = true,
	OwnReceipts = true,
	PurchaseLog = true,
	GiftCooldown = true,
	GiftMaxPending = true,
	GiftIntentTTL = true,
	PurchaseIdTTL = true,
	MaxProcessedPurchaseIds = true,
	MaxReceiptHistoryBytes = true,
	PurchaseClaimTTL = true,
	MaxPurchaseClaims = true,
	AllowDuplicateGifts = true,
	NoGiftIntentPolicy = true,
	Economy = true,
	CommandRateLimit = true,
	RequestTimeout = true,
	MaxInboundBytes = true,
	MaxInboundRetainedBytes = true,
	MaxOutboundBytes = true,
	MaxInboundFrameRate = true,
	BoundsPolicy = true,
	WipeGuardPolicy = true,
	SchemaPolicy = true,
	BudgetPolicy = true,
	WipeGuardShrinkRatio = true,
	LogLevel = true,
	LogRingLevel = true,
	LogRingSize = true,
	StatusThresholds = true,
	Banner = true,
	StudioHook = true,
}

local function buildBundle<T, S>(options: ScribeOptions<T, S>): Bundle<T, S>
	if type(options) ~= "table" then
		error("Scribe: options must be a table", 2)
	end
	if type((options :: any).Template) ~= "table" then
		error("Scribe: options.Template is required and must be a table", 2)
	end
	local anyOpts = options :: any
	-- Server only on purpose: the client reads neither of these. Validating them before
	-- the realm branch would force the live DataStore name and key format into the shared
	-- module every client requires, rather than behind `if RunService:IsServer()`.
	if RunService:IsServer() then
		-- Storage location is intentional, never defaulted: two games (or a test
		-- build) accidentally sharing the "Default" store is a silent data hazard.
		if type(anyOpts.ProfileStoreIndex) ~= "string" or anyOpts.ProfileStoreIndex == "" then
			error("Scribe: options.ProfileStoreIndex is required: name your game's DataStore explicitly", 2)
		end
		-- Required, but "" is legitimate: it means bare user-id keys, which is what a
		-- game adopting an existing store keyed only by user id needs. Absent or
		-- non-string is still an error, so the choice stays explicit.
		if type(anyOpts.ProfileKeyPrefix) ~= "string" then
			error(
				'Scribe: options.ProfileKeyPrefix is required: set a per-player key prefix (e.g. "PLAYER_"), or "" for bare user-id keys',
				2
			)
		end
	end

	-- Scribe.Configure refuses to run past this point, because its process-wide values
	-- are applied during construction. Set after the option guards, so a call that
	-- only fails a guard does not poison the flag for a later Configure.
	Config.BundleConstructed = true

	-- Luau does not reject unknown table keys, so a misspelled option name is silently
	-- ignored. Catch it in Studio with a startup warning.
	if RunService:IsStudio() then
		for key in options :: any do
			if type(key) == "string" and not KNOWN_OPTION_KEYS[key] then
				Log.Warn(
					"Lifecycle",
					"UNKNOWN_OPTION",
					`unknown Scribe option "{key}": check the spelling`,
					{ Option = key }
				)
			end
		end
	end

	local anyOptions = options :: any
	local purchaseLog = anyOptions.PurchaseLog or {}
	-- Purchase logs are server-only unless explicitly opted in: they exist for
	-- auditing/support first, and most games never show them to the client.
	local compiled = Template.Compile(anyOptions.Template, {
		ReplicateRobuxLog = purchaseLog.ReplicateRobux == true,
		ReplicateInGameLog = purchaseLog.ReplicateInGame == true,
		ServerStore = anyOptions.ServerStore,
	})

	-- Template safety: deep-freeze after compilation; any accidental
	-- mutation of the shared template throws at the call site.
	Util.deepFreeze(anyOptions.Template)
	Util.deepFreeze(anyOptions.ServerStore)

	-- A Sandboxed script cannot fire a non-Sandboxed event, so a Sandboxed Scribe
	-- silently never sends a replication frame and nothing syncs. Usually caused by
	-- inserting the package from the toolbox rather than syncing it from source.
	local sandboxOk, sandboxed = pcall(function()
		return (script :: any).Sandboxed
	end)
	if sandboxOk and sandboxed == true then
		Log.Warn(
			"Lifecycle",
			"SANDBOXED",
			"the Scribe package is Sandboxed, so it cannot fire its replication RemoteEvents and nothing will sync. "
				.. "Set Sandboxed = false on the Scribe package (and ProfileStore).",
			{}
		)
	end

	-- Edit mode (a storybook, the command bar, a plugin) has no server, yet
	-- RunService:IsServer() is still true there. Dispatching on that alone builds the
	-- server half, which resolves the transport and leaves RemoteEvents saved into the
	-- place file; the client half understands edit mode. `IsRunning` is also the seam
	-- specs use, since RunService cannot be patched.
	local isRunning = if anyOptions.IsRunning ~= nil then anyOptions.IsRunning == true else RunService:IsRunning()

	local bundle: any
	if RunService:IsServer() and isRunning then
		local Server = require(script.Server) :: any
		local serverData = Server.new(anyOptions, compiled)
		local clientStub = setmetatable({}, {
			__index = function()
				error("Scribe: the Client API is not available on the server", 2)
			end,
		})
		bundle = { Server = serverData, Client = clientStub }
	else
		local Client = require(script.Client) :: any
		local clientData = Client.new(anyOptions, compiled)
		local serverStub = setmetatable({}, {
			__index = function()
				error(
					if isRunning
						then "Scribe: the Server API is not available on the client. Client writes go through Data.Request commands"
						else "Scribe: the Server API is not available in edit mode. Scribe builds only the client half there (storybooks, the command bar)",
					2
				)
			end,
		})
		bundle = { Server = serverStub, Client = clientData }
	end

	-- Studio-only: expose the (frozen) raw template so Scribe Studio's
	-- edit-mode lint can introspect the canonical bundle-returning module.
	if RunService:IsStudio() then
		bundle.__ScribeTemplate = anyOptions.Template
	end

	return bundle :: any
end

-- Shared entry point for bundle creation, declarators, and diagnostics.
local Scribe = {}

Scribe.Version = require(script.Internal.Version)

-- Keeps this field and its subtree off the client.
function Scribe.ServerOnly<T>(value: T): ServerOnly<T>
	return Marker.make("ServerOnly", value) :: any
end

-- Replicates a root field to every client.
function Scribe.Shared<T>(value: T): T
	return Marker.make("Shared", value) :: any
end

-- Keeps a root field unsaved; its visibility wrappers still apply.
function Scribe.Session<T>(value: T): T
	return Marker.make("Session", value) :: any
end

-- Declares integer data with optional bounds.
function Scribe.Int(default: number, meta: NumberMeta?): number
	return Marker.make("Int", default, meta :: any) :: any
end

-- Declares floating-point data with optional bounds and wire precision.
function Scribe.Number(default: number, meta: FloatMeta?): number
	return Marker.make("Number", default, meta :: any) :: any
end

-- Declares large-range numbers; numeric strings are limited to 256 bytes.
function Scribe.Big(default: (number | string)?, meta: BigMeta?): BigValue
	return Marker.make("Big", if default == nil then 0 else default, meta :: any) :: any
end

-- Declares string data with an optional byte limit.
function Scribe.String(default: string, meta: StringMeta?): string
	return Marker.make("String", default, meta :: any) :: any
end

-- Restricts a string field to the declared members.
function Scribe.Enum(default: string, members: { string }): string
	return Marker.make("Enum", default, { Members = members }) :: any
end

-- Stores up to 32 named booleans as one field.
function Scribe.Flags(members: { string }): Flags
	return Marker.make("Flags", {}, { Members = members }) :: any
end

-- Declares a leaf reset to its default after SetTimed expires.
function Scribe.Timed<T>(default: T): Timed<T>
	return Marker.make("Timed", default) :: any
end

-- Seeds missing profile values with a pure factory, also sampled at declaration.
-- `(...any) -> T` (not `() -> T`) so standard-library functions with optional
-- params typecheck when passed directly, e.g. `Scribe.Dynamic(os.time)`.
function Scribe.Dynamic<T>(factory: (...any) -> T): T
	return Marker.make("Dynamic", factory(), { Factory = factory :: any }) :: any
end

-- Declares a read-only value computed from named inputs; compute must be pure.
function Scribe.Derived<T>(output: T, inputs: { string }, compute: (...any) -> T): Derived<T>
	return Marker.make("Derived", output, { Inputs = inputs, Compute = compute :: any }) :: any
end

-- Allows an absent leaf value; the inner default is not seeded.
function Scribe.Optional<T>(inner: T): T?
	return Marker.make("Optional", inner) :: any
end

-- Declares a typed array with optional size and eviction limits.
function Scribe.ArrayOf<T>(shape: T, opts: ArrayOpts?): { T }
	if opts ~= nil then
		for key in opts :: any do
			-- A silently dropped option (MaxKeys on an ArrayOf, say) leaves the
			-- container uncapped while reading as protected; refuse it.
			if key ~= "MaxItems" and key ~= "Evict" then
				error(`Scribe.ArrayOf: unknown option "{tostring(key)}" (ArrayOf takes MaxItems and Evict)`, 2)
			end
		end
	end
	return Marker.make("ArrayOf", nil, {
		Element = shape,
		MaxItems = if opts then opts.MaxItems else nil,
		Evict = if opts then opts.Evict else nil,
	}) :: any
end

-- Declares unique scalar members with an optional size limit.
function Scribe.SetOf<T>(element: T, opts: SetOpts?): SetOf<T>
	if opts ~= nil then
		for key in opts :: any do
			if key ~= "MaxItems" then
				error(`Scribe.SetOf: unknown option "{tostring(key)}" (SetOf takes MaxItems)`, 2)
			end
		end
	end
	-- A set is deduplicated and sorted, neither of which works on a record: table.sort
	-- throws a bare comparison error on the second member. Refuse it here rather than at
	-- the surprising second Add.
	if type(element) == "table" and (element :: any).__scribeMarker == nil then
		error("Scribe.SetOf takes a scalar element (Scribe.String, Scribe.Int, ...), not a record shape", 2)
	end
	return Marker.make("SetOf", nil, {
		Element = element,
		MaxItems = if opts then opts.MaxItems else nil,
		Unique = true,
	}) :: any
end

-- Declares a map with integer or string keys and a value schema.
function Scribe.MapOf<K, V>(keyType: K & MapKeyType, value: V, opts: DictOpts?): MapOf<K, V>
	if keyType ~= "integer" and keyType ~= "string" then
		error(`Scribe.MapOf: keyType must be "integer" or "string", got {tostring(keyType)}`, 2)
	end
	if opts ~= nil then
		for key in opts :: any do
			if key ~= "MaxKeys" and key ~= "MaxKeyLength" then
				error(`Scribe.MapOf: unknown option "{tostring(key)}" (MapOf takes MaxKeys and MaxKeyLength)`, 2)
			end
		end
	end
	if keyType == "integer" and opts ~= nil and (opts :: any).MaxKeyLength ~= nil then
		error("Scribe.MapOf: MaxKeyLength applies to string keys only", 2)
	end
	return Marker.make("MapOf", nil, {
		Element = value,
		KeyType = keyType,
		MaxKeys = if opts then opts.MaxKeys else nil,
		MaxKeyLength = if opts then opts.MaxKeyLength else nil,
	}) :: any
end

-- Declares a string-keyed dictionary with a value schema and optional limits.
function Scribe.DictOf<V>(shape: V, opts: DictOpts?): { [string]: V }
	if opts ~= nil then
		for key in opts :: any do
			if key ~= "MaxKeys" and key ~= "MaxKeyLength" then
				error(`Scribe.DictOf: unknown option "{tostring(key)}" (DictOf takes MaxKeys and MaxKeyLength)`, 2)
			end
		end
	end
	return Marker.make("DictOf", nil, {
		Element = shape,
		MaxKeys = if opts then opts.MaxKeys else nil,
		MaxKeyLength = if opts then opts.MaxKeyLength else nil,
	}) :: any
end

-- Roblox datatype fields (opt-in serialization): stored and replicated as a
-- compact packed buffer; Get/Set/Update/Observe convert at the boundary so
-- callers only ever see the real datatype.
local function datatypeMarker(name: string, default: any, precision: string?): any
	return Marker.make("Datatype", default, { Datatype = name, Precision = precision })
end

-- Declares Vector3 data, packed for storage and replication.
function Scribe.Vector3(default: Vector3): Vector3
	return datatypeMarker("Vector3", default)
end

function Scribe.Vector2(default: Vector2): Vector2
	return datatypeMarker("Vector2", default)
end

function Scribe.Vector3int16(default: Vector3int16): Vector3int16
	return datatypeMarker("Vector3int16", default)
end

function Scribe.Vector2int16(default: Vector2int16): Vector2int16
	return datatypeMarker("Vector2int16", default)
end

-- Declares packed CFrame data; Precision = "exact" preserves its f32 components.
function Scribe.CFrame(default: CFrame, meta: CFrameMeta?): CFrame
	if meta ~= nil then
		for key in meta :: any do
			if key ~= "Precision" then
				error(`Scribe.CFrame: unknown option "{tostring(key)}" (CFrame takes Precision)`, 2)
			end
		end
	end
	return datatypeMarker("CFrame", default, if meta then meta.Precision else nil)
end

function Scribe.Color3(default: Color3): Color3
	return datatypeMarker("Color3", default)
end

function Scribe.BrickColor(default: BrickColor): BrickColor
	return datatypeMarker("BrickColor", default)
end

function Scribe.UDim(default: UDim): UDim
	return datatypeMarker("UDim", default)
end

function Scribe.UDim2(default: UDim2): UDim2
	return datatypeMarker("UDim2", default)
end

function Scribe.Rect(default: Rect): Rect
	return datatypeMarker("Rect", default)
end

function Scribe.NumberRange(default: NumberRange): NumberRange
	return datatypeMarker("NumberRange", default)
end

function Scribe.NumberSequence(default: NumberSequence): NumberSequence
	return datatypeMarker("NumberSequence", default)
end

function Scribe.ColorSequence(default: ColorSequence): ColorSequence
	return datatypeMarker("ColorSequence", default)
end

function Scribe.DateTime(default: DateTime): DateTime
	return datatypeMarker("DateTime", default)
end

function Scribe.EnumItem(default: EnumItem): EnumItem
	return datatypeMarker("EnumItem", default)
end

function Scribe.Font(default: Font): Font
	return datatypeMarker("Font", default)
end

function Scribe.PhysicalProperties(default: PhysicalProperties): PhysicalProperties
	return datatypeMarker("PhysicalProperties", default)
end

-- Codec helpers for packing and unpacking Roblox datatypes.
Scribe.Datatypes = require(script.Internal.Datatypes)

-- Formats a number or Big value with suffixes and rounded decimal places.
function Scribe.Short(value: (number | BigValue)?, decimals: number?): string
	if decimals ~= nil and (type(decimals) ~= "number" or decimals < 0 or decimals % 1 ~= 0) then
		error(`Scribe.Short: decimals must be a non-negative whole number, got {tostring(decimals)}`, 2)
	end
	local big = BigMath.from(value)
	if big == nil then
		error(`Scribe.Short: expected a number or a Scribe.Big value, got {typeof(value)}`, 2)
	end
	return BigMath.toShort(big, decimals)
end

-- Replaces suffixes used by Short; the first suffix must be empty.
function Scribe.SetShortSuffixes(suffixes: { string })
	BigMath.SetSuffixes(suffixes)
end

-- Sets process-wide options before any bundle is built; conflicting calls error.
function Scribe.Configure(config: { AutoSaveInterval: number? })
	if type(config) ~= "table" then
		error("Scribe.Configure: config must be a table", 2)
	end
	for key in config :: { [string]: any } do
		if key ~= "AutoSaveInterval" then
			error(`Scribe.Configure: unknown key "{tostring(key)}" (Configure takes AutoSaveInterval)`, 2)
		end
	end
	if Config.BundleConstructed then
		error("Scribe.Configure must be called before any Scribe bundle is constructed", 2)
	end
	local interval = config.AutoSaveInterval
	if interval ~= nil then
		if type(interval) ~= "number" or interval ~= interval or interval <= 0 then
			error("Scribe.Configure: AutoSaveInterval must be a positive number of seconds", 2)
		end
		if
			Config.AutoSaveSource == "Configure"
			and Config.AutoSaveInterval ~= nil
			and Config.AutoSaveInterval ~= interval
		then
			error(
				`Scribe.Configure: AutoSaveInterval was already set to {Config.AutoSaveInterval}; `
					.. "it is a process-wide setting, so configure it once",
				2
			)
		end
		Config.AutoSaveInterval = interval
		Config.AutoSaveSource = "Configure"
	end
end

Scribe.Reason = table.freeze({
	LoadFailed = "load-failed" :: Types.LifecycleReason,
	MigrationFailed = "migration-failed" :: Types.LifecycleReason,
	Erasing = "erasing" :: Types.LifecycleReason,
	SessionEnded = "session-ended" :: Types.LifecycleReason,
	PlayerLeft = "player-left" :: Types.LifecycleReason,
	Shutdown = "shutdown" :: Types.LifecycleReason,
	StillLoading = "still-loading" :: Types.LifecycleReason,
	Timeout = "timeout" :: Types.LifecycleReason,
})

-- Named framework refusals for Request; handlers may return their own reasons.
Scribe.RequestReason = table.freeze({
	RateLimited = "rate-limited" :: Types.RequestReason,
	NotReady = "not-ready" :: Types.RequestReason,
	UnknownCommand = "unknown-command" :: Types.RequestReason,
	BadArgs = "bad-args" :: Types.RequestReason,
	BadIdempotencyKey = "bad-idempotency-key" :: Types.RequestReason,
	Error = "error" :: Types.RequestReason,
	ReplyEncodeFailed = "reply-encode-failed" :: Types.RequestReason,
	Timeout = "timeout" :: Types.RequestReason,
	SendFailed = "send-failed" :: Types.RequestReason,
	EditMode = "edit-mode" :: Types.RequestReason,
	MockError = "mock-error" :: Types.RequestReason,
})

-- Identity marker distinguishing framework request failures from handler replies.
Scribe.RequestFailed = Types.RequestFailed

-- Fixed soft-currency purchase refusals; grant errors return their own text.
Scribe.PurchaseReason = table.freeze({
	DataNotLoaded = "player data not loaded" :: Types.PurchaseReason,
	InvalidCostSpec = "invalid Cost spec" :: Types.PurchaseReason,
	InvalidCostAmount = "invalid Cost amount" :: Types.PurchaseReason,
	InvalidCostPath = "invalid cost path" :: Types.PurchaseReason,
	CostPathNotSpendable = "cost path is not a spendable number" :: Types.PurchaseReason,
	InsufficientFunds = "insufficient funds" :: Types.PurchaseReason,
	PaidRandomRestricted = "paid random items are not available for this account" :: Types.PurchaseReason,
	PolicyPending = "cannot check account settings right now; try again in a moment" :: Types.PurchaseReason,
})

-- Fixed gift refusals; other failures may return diagnostic text.
Scribe.GiftReason = table.freeze({
	ProductRetired = "product retired" :: Types.GiftReason,
	BuyerDataNotLoaded = "buyer data not loaded" :: Types.GiftReason,
	InvalidRecipient = "invalid recipient" :: Types.GiftReason,
	CannotGiftYourself = "cannot gift yourself" :: Types.GiftReason,
	GiftCooldown = "gift cooldown" :: Types.GiftReason,
	TooManyPending = "too many pending gifts" :: Types.GiftReason,
	DataServicesDown = "data services are experiencing issues; try again later" :: Types.GiftReason,
	RecipientAlreadyOwns = "recipient already owns this" :: Types.GiftReason,
	CreditReserveFailed = "could not reserve gift credit; try again later" :: Types.GiftReason,
	DeliveryFailed = "could not deliver gift; try again later" :: Types.GiftReason,
	DeliveryUnconfirmed = "gift delivery could not be confirmed; do not send it again" :: Types.GiftReason,
	AlreadyPending = "a gift of this item is already pending; try again shortly" :: Types.GiftReason,
	IntentRecordFailed = "could not record gift intent; try again later" :: Types.GiftReason,
	PaidRandomRestricted = "paid random items are not available for this account" :: Types.GiftReason,
	PolicyPending = "cannot check account settings right now; try again in a moment" :: Types.GiftReason,
})

-- Named eligibility states for product queries and purchase prompts.
Scribe.ProductState = table.freeze({
	Purchasable = "purchasable" :: Types.ProductState,
	Owned = "owned" :: Types.ProductState,
	PaidRandomRestricted = "paid-random-restricted" :: Types.ProductState,
	PolicyPending = "policy-pending" :: Types.ProductState,
	NotLoaded = "not-loaded" :: Types.ProductState,
})

-- Named replication operations for diagnostics.
Scribe.OpKind = table.freeze({
	Init = "Init" :: Types.OpKind,
	Set = "Set" :: Types.OpKind,
	Insert = "Insert" :: Types.OpKind,
	Remove = "Remove" :: Types.OpKind,
	Clear = "Clear" :: Types.OpKind,
})

-- Named severity levels for logging and log filters.
Scribe.LogLevel = table.freeze({
	Debug = "Debug" :: Types.LogLevel,
	Info = "Info" :: Types.LogLevel,
	Warn = "Warn" :: Types.LogLevel,
	Error = "Error" :: Types.LogLevel,
	Fatal = "Fatal" :: Types.LogLevel,
})

-- Named subsystem categories for log filters.
Scribe.LogCategory = table.freeze({
	Persistence = "Persistence" :: Types.LogCategory,
	Replication = "Replication" :: Types.LogCategory,
	Transport = "Transport" :: Types.LogCategory,
	Commands = "Commands" :: Types.LogCategory,
	Leaderboards = "Leaderboards" :: Types.LogCategory,
	Monetization = "Monetization" :: Types.LogCategory,
	Gifting = "Gifting" :: Types.LogCategory,
	Integrity = "Integrity" :: Types.LogCategory,
	Lifecycle = "Lifecycle" :: Types.LogCategory,
	Derived = "Derived" :: Types.LogCategory,
	Exchanges = "Exchanges" :: Types.LogCategory,
})

-- Named DataStore health states.
Scribe.Status = table.freeze({
	Healthy = "Healthy" :: Types.Status,
	Degraded = "Degraded" :: Types.Status,
	Outage = "Outage" :: Types.Status,
})

-- Named per-board health states, separate from DataStore health.
Scribe.LeaderboardStatus = table.freeze({
	Starting = "Starting" :: Types.LeaderboardStatus,
	Healthy = "Healthy" :: Types.LeaderboardStatus,
	Degraded = "Degraded" :: Types.LeaderboardStatus,
})

-- Named profile lifecycle states returned by GetState.
Scribe.SessionState = table.freeze({
	Loading = "Loading" :: Types.SessionState,
	Ready = "Ready" :: Types.SessionState,
	SessionEnded = "SessionEnded" :: Types.SessionState,
})

-- Named stages reported while a profile is loading.
Scribe.LoadPhase = table.freeze({
	WaitingForErase = "WaitingForErase" :: Types.LoadPhase,
	AcquiringSession = "AcquiringSession" :: Types.LoadPhase,
	ReadingProfile = "ReadingProfile" :: Types.LoadPhase,
	Retrying = "Retrying" :: Types.LoadPhase,
	Initializing = "Initializing" :: Types.LoadPhase,
	Importing = "Importing" :: Types.LoadPhase,
	ImportThrottled = "ImportThrottled" :: Types.LoadPhase,
})

-- Named replication targets for declared fields.
Scribe.Visibility = table.freeze({
	Replicated = "Replicated" :: Types.Visibility,
	ServerOnly = "ServerOnly" :: Types.Visibility,
	Shared = "Shared" :: Types.Visibility,
})

-- Alias of Reason using the matching exported type name.
Scribe.LifecycleReason = Scribe.Reason

-- Returns the server bundle prefix, or PLAYER_ before setup and on clients.
function Scribe.GetProfileKeyPrefix(): string
	return Addons.ProfileKeyPrefix()
end

-- Returns current DataStore health.
function Scribe.GetStatus(): Status
	return Health.GetStatus()
end

-- Returns cached board health without DataStore requests; empty on clients.
function Scribe.GetLeaderboardSnapshot(): { LeaderboardSnapshotEntry }
	return if RunService:IsServer() then LeaderboardDiagnostics.Snapshot() else {}
end

-- Fires when DataStore health changes.
Scribe.OnStatusChanged = Health.OnStatusChanged

-- Fires for each Error or Fatal log entry.
Scribe.OnIssue = Log.OnIssue

-- Adds a filtered, bounded log sink; returns its disconnect function.
function Scribe.AddLogSink(fn: (entry: LogEntry) -> (), options: LogSinkOptions?): () -> ()
	return Log.AddSink(fn :: any, options)
end

-- Registers plugin actions; returned cleanup removes only this registration.
function Scribe.RegisterAddon(name: string, actions: Addons.Actions): () -> ()
	return Addons.Register(name, actions)
end

-- Returns filtered retained logs, oldest first; Limit keeps the newest entries.
function Scribe.GetRecentLogs(filter: Log.LogFilter?): { LogEntry }
	return Log.GetRecent(filter)
end

-- Returns this context's counters and distribution summaries.
function Scribe.GetMetrics(): { [string]: number | { Count: number, Average: number, Max: number } }
	return Metrics.Get()
end

-- Returns recent distribution percentiles with sample age and window size.
function Scribe.GetPercentiles(): { [string]: Metrics.Percentiles }
	return Metrics.GetPercentiles()
end

-- Reads current DataStore allowances; Available is false if the query fails.
function Scribe.GetBudgetSnapshot(): Budget.Snapshot
	return Budget.Snapshot()
end

-- Builds a Server/Client bundle; calling Scribe(options) uses the same function.
Scribe.new = buildBundle

-- The metatable is attached through a cast so it stays invisible to the type
-- system; the callable type is declared explicitly below instead (the new
-- solver does not yet instantiate generic __call metamethods).
setmetatable(Scribe :: any, {
	__call = function<T, S>(_self: any, options: ScribeOptions<T, S>): Bundle<T, S>
		return buildBundle(options)
	end,
})

export type ScribeModule = typeof(Scribe) & <T, S>(options: ScribeOptions<T, S>) -> Bundle<T, S>

return (Scribe :: any) :: ScribeModule
