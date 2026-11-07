--| PartyService
-- Party Stages (Workspace.Map.PartyStages.PartyStage1–N): private stages, separate from duel
-- matchmaking. Whoever steps on an empty one hosts it; the setlist is everyone in join order
-- and #1 is always the host (they leave → #2 takes over). The host picks:
--   • Match     Normal Duel (exactly 2) or Free-for-all (3–6, everyone their own score)
--   • Songs     every song, or a custom pool of groups (any mix of gens) minus single songs
--   • Owned songs count   on: the usual owned-song weighting, for everyone alike
--   • Spots     3–6 for FFA (never fewer than are on the stage); a duel is 2
--   • Every match: Friends only (friends + invites + accepted requests can join), Spectators
-- Guests ready up; START runs a COUNTDOWN anyone can stop by un-readying. Nobody can be removed
-- once it starts. A match is DuelService's Duels with a party table (any number of players,
-- custom pool, a pot roll but no vote); rewards are Rewards.ApplyParty (rolled pot × multiplier,
-- nothing for leavers, nothing on a custom pool under MIN_POOL_REWARDS songs). Leaving is
-- always allowed. The stage's spots are laid out for the spot count by ./Layout and redrawn
-- whenever it changes; ./Sign keeps the neon strip + sign up to date. You join from a prompt
-- on the spots themselves: every open spot has one (only the nearest shows), and a full or
-- busy stage keeps one on every spot for Watch / Full.
--
-- PartyRemote, client → server ({ Action = … }):
--   Leave · Ready { On } · Start · Settings { Mode?, Spots?, Boost?, FriendsOnly?, Spectators? }
--   Pool { All = true } | { Groups = { name }, Out = { songId } } · InviteList · Invite { Target }
--   Answer { Stage, Accept } (an invite) · Ask { Stage } · Request { UserId, Accept } (host)
--   MakeHost { UserId } · Remove { UserId, Block } · Spectate { Stage } · StopWatching
-- server → client ({ Message = … }):
--   State { … }  (the whole lobby: see statePacket) · Left { Reason }
--   Prompt { Kind = "FriendsOnly" | "Full" | "Busy", Stage, Title, Host, Count, Spots, Round, Rounds, Spectate }
--   Request { UserId, Name, Stage, Expires } (to the host) · RequestResult { Result, Title }
--   Invited { Stage, Title, Name, Count, Spots, Expires } · InviteGone · InviteList { Players }
--   Toast { Text } · Watch { Title, Round, Rounds, Players = { {Name, Score} } } · WatchEnd
-- Match packets go over DuelRemote like a duel (PreDuel has Party = true; End has Party = {…}).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Janitor = require(ReplicatedStorage.Packages.janitor)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PartyConstants = require(ReplicatedStorage.Constants.PartyConstants)
local Songs = require(ReplicatedStorage.Modules.Library.Songs)
local DuelService = require(script.Parent.DuelService)
local Duels = require(script.Parent.DuelService.Duels)
local Rewards = require(script.Parent.DuelService.Rewards)
local StageCosmetics = require(script.Parent.DuelService.StageCosmetics)
local Analytics = require(script.Parent.Analytics)
local Layout = require(script.Layout)
local Sign = require(script.Sign)

local PartyRemote = Bridgenet.ReferenceBridge("PartyRemote")
local DuelRemote = Bridgenet.ReferenceBridge("DuelRemote")

type Settings = {
	Mode: string,
	Spots: number,
	Boost: boolean,
	FriendsOnly: boolean,
	Spectators: boolean,
	Pool: { Groups: { string }, Out: { string } }?,
}

local PartyService = {}
PartyService.Stages = {} :: { [string]: any }
PartyService.PlayerParty = {} :: { [Player]: any }

local lastAction: { [Player]: number } = {}
local watching: { [Player]: any } = {}
local declined: { [string]: number } = {} -- "<host>:<asker>" → until

--| Helpers

local function key(p: Player): string
	return tostring(p.UserId)
end

local function defaults(): Settings
	return {
		Mode = PartyConstants.DEFAULT_MODE,
		Spots = PartyConstants.DEFAULT_SPOTS,
		Boost = PartyConstants.DEFAULT_BOOST,
		FriendsOnly = PartyConstants.DEFAULT_FRIENDS_ONLY,
		Spectators = PartyConstants.DEFAULT_SPECTATORS,
		Pool = nil,
	}
end

local function spotCount(party): number
	return if party.Settings.Mode == "Duel" then PartyConstants.DUEL_SPOTS else party.Settings.Spots
end

local function host(party): Player?
	return party.Members[1]
end

local function isFriend(a: Player, b: Player): boolean
	local ok, yes = pcall(a.IsFriendsWith, a, b.UserId)
	return ok and yes == true
end

local function levelOf(p: Player): number
	local ok, profile = pcall(Duels.ProfileOf, p)
	return if ok and profile then profile.Level else 1
end

local function toast(p: Player, text: string)
	if p.Parent then
		PartyRemote:Fire(p, { Message = "Toast", Text = text })
	end
end

-- the coin multiplier for `count` players with these settings, and how it's made up
local function multiplier(party, count: number): (number, string)
	local m, parts = 1, {}
	if party.Settings.Mode == "FFA" then
		local f = PartyConstants.FFA_MULTIPLIER[math.clamp(count, PartyConstants.MIN_FFA_PLAYERS, PartyConstants.MAX_SPOTS)] or 1
		m *= f
		table.insert(parts, `FFA ×{f}`)
	end
	if party.Settings.Pool then
		m *= PartyConstants.CUSTOM_POOL_MULTIPLIER
		table.insert(parts, `custom songs ×{PartyConstants.CUSTOM_POOL_MULTIPLIER}`)
	end
	m = math.floor(m * 100 + 0.5) / 100
	return m, table.concat(parts, " · ")
end

local function eligible(party): boolean
	return party.PoolSongs == nil or #party.PoolSongs >= PartyConstants.MIN_POOL_REWARDS
end

-- the songs a pool setting adds up to
local function poolSongs(pool): { any }
	local groups, out = {}, {}
	for _, g in pool.Groups do
		groups[g] = true
	end
	for _, id in pool.Out do
		out[id] = true
	end
	local list = {}
	for _, song in Songs.All do
		if groups[song.Artist] and not out[song.Id] then
			table.insert(list, song)
		end
	end
	return list
end

--| Lobby state

local function statePacket(party)
	local list = {}
	for i, p in party.Members do
		table.insert(list, {
			UserId = p.UserId,
			Name = p.DisplayName,
			Level = levelOf(p),
			Ready = i == 1 or party.Ready[p] == true,
			Host = i == 1,
		})
	end
	local s = party.Settings
	local m, text = multiplier(party, #party.Members)
	local count = 0
	for _ in party.Watchers do
		count += 1
	end
	return {
		Message = "State",
		Stage = party.Name,
		Title = party.Title,
		Host = host(party) and host(party).UserId,
		Members = list,
		Status = party.Status,
		CountdownEnds = party.CountdownEnds,
		Settings = {
			Mode = s.Mode,
			Spots = spotCount(party),
			FFASpots = s.Spots,
			Boost = s.Boost,
			FriendsOnly = s.FriendsOnly,
			Spectators = s.Spectators,
			Pool = if s.Pool then { Groups = s.Pool.Groups, Out = s.Pool.Out, Count = #party.PoolSongs } else nil,
		},
		Multiplier = m,
		MultiplierText = text,
		Eligible = eligible(party),
		Watching = count,
		LibrarySize = #Songs.All,
	}
end

local onPrompt: (any, Player) -> ()

-- a prompt over each spot (rebuilt with the spots); refreshPrompts says which ones show
local function makePrompts(party)
	for _, old in party.Prompts do
		old:Destroy()
	end
	party.Prompts = {}
	for i, pad in party.Spots do
		local at = Instance.new("Attachment")
		at.Name = "PromptAt"
		at.Position = Vector3.new(0, 2.5, 0)
		at.Parent = pad
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PartyPrompt"
		prompt.ObjectText = party.Title
		prompt.RequiresLineOfSight = false
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton -- just the nearest spot's
		prompt.MaxActivationDistance = PartyConstants.PROMPT_DISTANCE
		prompt.Triggered:Connect(function(player)
			onPrompt(party, player)
		end)
		party.Prompts[i] = prompt
	end
end

-- open spots (nobody on them) show theirs; a full / starting / playing stage shows every spot's
-- (Watch or Full). Shown = parented under the spot's PromptAt, hidden = no parent.
local function refreshPrompts(party)
	local n, spots = #party.Members, spotCount(party)
	local open = party.Status == "Waiting" and n < spots
	local action = if n == 0 then "Host a party"
		elseif not open then (if party.Settings.Spectators and party.Status == "InMatch" then "Watch" else "Full")
		elseif party.Settings.FriendsOnly then "Join (friends only)"
		else "Join party"
	for i, prompt in party.Prompts do
		prompt.ObjectText = party.Title
		prompt.ActionText = action
		local pad = party.Spots[i]
		local holder = pad and pad:FindFirstChild("PromptAt")
		prompt.Parent = if holder and (not open or i > n) then holder else nil
	end
end

local function refreshSign(party)
	local n, spots = #party.Members, spotCount(party)
	local line, state
	if party.Status == "InMatch" then
		local round = party.Model:GetAttribute("Round") or 0
		line, state = `In match · round {math.max(round, 1)} / 7`, "Live"
	elseif party.Status == "Countdown" then
		line, state = "Starting…", "Live"
	elseif n == 0 then
		line, state = "Step on to host a party", "Empty"
	elseif party.Settings.FriendsOnly then
		line, state = `Friends only · {n} / {spots}`, "Waiting"
	else
		line, state = `Waiting for players · {n} / {spots}`, "Waiting"
	end
	Sign.Refresh(party, line, state)
	refreshPrompts(party)
end

local function broadcast(party)
	refreshSign(party)
	if #party.Members > 0 then
		PartyRemote:Fire(Bridgenet.Players(party.Members), statePacket(party))
	end
end

--| Standing on spots

local function freeze(player: Player, humanoid: Humanoid)
	if humanoid:GetAttribute("DuelWalkSpeed") == nil then
		humanoid:SetAttribute("DuelWalkSpeed", humanoid.WalkSpeed)
		humanoid:SetAttribute("DuelJumpPower", humanoid.JumpPower)
		humanoid:SetAttribute("DuelJumpHeight", humanoid.JumpHeight)
	end
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	humanoid:Move(Vector3.zero)
end

local function unfreeze(player: Player)
	local character = player.Character
	local root = character and character.PrimaryPart
	if root then
		root.Anchored = false
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = humanoid:GetAttribute("DuelWalkSpeed") or 16
		humanoid.JumpPower = humanoid:GetAttribute("DuelJumpPower") or 50
		humanoid.JumpHeight = humanoid:GetAttribute("DuelJumpHeight") or 7.2
		humanoid.AutoRotate = true
		humanoid:SetAttribute("DuelWalkSpeed", nil)
		humanoid:SetAttribute("DuelJumpPower", nil)
		humanoid:SetAttribute("DuelJumpHeight", nil)
	end
end

local function place(party, i: number, player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local pad = party.Spots[i]
	if not (character and humanoid and pad and character.PrimaryPart) then
		return
	end
	freeze(player, humanoid)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local rootHalf = if root then root.Size.Y / 2 else 1
	local standAt = pad.Position + Vector3.new(0, pad.Size.Y / 2 + humanoid.HipHeight + rootHalf, 0)
	local centre = party.Model:FindFirstChild("RigSpot") :: BasePart?
	local lookAt = if centre then Vector3.new(centre.Position.X, standAt.Y, centre.Position.Z) else standAt + pad.CFrame.LookVector
	character.PrimaryPart.Anchored = false
	character:PivotTo(CFrame.lookAt(standAt, lookAt))
	character.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
	character.PrimaryPart.AssemblyAngularVelocity = Vector3.zero
	character.PrimaryPart.Anchored = true
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0)
		end
	end
end

-- (re)lay the spots out when their number changes, then put everyone back on theirs
local function arrange(party)
	local count = spotCount(party)
	if party.SpotCount ~= count then
		party.SpotCount = count
		for i = 1, PartyConstants.MAX_SPOTS do
			StageCosmetics.Apply(party, tostring(i), nil)
		end
		party.Spots = Layout.Build(party.Model, count)
		makePrompts(party)
		refreshPrompts(party)
	end
	for i = 1, count do
		local p = party.Members[i]
		StageCosmetics.Apply(party, tostring(i), p)
		if p then
			place(party, i, p)
		end
	end
end

--| Countdown

local function cancelCountdown(party, why: string?)
	if party.Status ~= "Countdown" then
		return
	end
	if party.CountdownThread and coroutine.running() ~= party.CountdownThread then
		pcall(task.cancel, party.CountdownThread)
	end
	party.CountdownThread = nil
	party.CountdownEnds = nil
	party.Status = "Waiting"
	if why then
		for _, p in party.Members do
			toast(p, why)
		end
	end
end

-- why the host can't start yet (nil = they can)
local function blocker(party): string?
	local n = #party.Members
	if party.Settings.Mode == "Duel" and n ~= 2 then
		return "A Normal Duel needs exactly 2 players"
	elseif party.Settings.Mode == "FFA" and n < PartyConstants.MIN_FFA_PLAYERS then
		return `Free-for-all needs {PartyConstants.MIN_FFA_PLAYERS}+ players`
	end
	for i = 2, n do
		if not party.Ready[party.Members[i]] then
			return "Waiting for everyone to ready up"
		end
	end
	return nil
end

--| Join / leave

local leave -- forward

local function join(party, player: Player, how: string): boolean
	if PartyService.PlayerParty[player] or DuelService.PlayerStage[player] then
		return false
	end
	if party.Status ~= "Waiting" or #party.Members >= spotCount(party) then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	if watching[player] then
		watching[player].Watchers[player] = nil
		watching[player] = nil
	end

	table.insert(party.Members, player)
	PartyService.PlayerParty[player] = party
	party.Invited[player.UserId] = nil
	party.Requests[player.UserId] = nil
	local j = Janitor.new()
	party.Janitors[player] = j
	j:Add(humanoid.Died:Connect(function()
		leave(player, "Left")
	end))
	j:Add(player.CharacterRemoving:Connect(function()
		leave(player, "Left")
	end))
	player:SetAttribute("Stage", party.Name) -- locks controls (client StageLock) + camera / round screen lookups
	player:SetAttribute("PartyStage", party.Name)
	arrange(party)
	Analytics.Event(player, "PartyJoined", 1, party.Name, if #party.Members == 1 then "Host" else how)
	Analytics.Onboarding(player, "SteppedOnStage")
	if #party.Members > 1 then
		for _, p in party.Members do
			if p ~= player then
				toast(p, `{player.DisplayName} joined`)
			end
		end
	end
	broadcast(party)
	return true
end

function leave(player: Player, reason: string?)
	local party = PartyService.PlayerParty[player]
	if not party then
		return
	end
	local i = table.find(party.Members, player)
	if not i then
		return
	end
	local wasHost = i == 1
	PartyService.PlayerParty[player] = nil
	table.remove(party.Members, i)
	party.Ready[player] = nil
	local j = party.Janitors[player]
	party.Janitors[player] = nil
	if j then
		j:Destroy()
	end
	if party.Duel then
		party.Duel:Forfeit(player)
	end
	cancelCountdown(party, `{player.DisplayName} left · countdown stopped`)

	player:SetAttribute("Stage", nil)
	player:SetAttribute("PartyStage", nil)
	unfreeze(player)
	if player.Parent then
		PartyRemote:Fire(player, { Message = "Left", Reason = reason or "Left" })
	end

	if #party.Members == 0 then
		-- an empty stage starts fresh for the next host
		party.Settings = defaults()
		party.PoolSongs = nil
		party.Blocked = {}
		party.Invited = {}
		party.Requests = {}
		for w in party.Watchers do
			watching[w] = nil
			PartyRemote:Fire(w, { Message = "WatchEnd" })
		end
		party.Watchers = {}
	else
		local now = host(party)
		for _, p in party.Members do
			if wasHost then
				toast(p, if p == now then `{player.DisplayName} left · you're the host now` else `{player.DisplayName} left · {now.DisplayName} is the host now`)
			else
				toast(p, `{player.DisplayName} left`)
			end
		end
	end
	if party.Status == "Waiting" then
		arrange(party) -- everyone after them moves up a spot
	end
	broadcast(party)
end

--| Walking up

function onPrompt(party, player: Player)
	if PartyService.PlayerParty[player] == party then
		return
	end
	if PartyService.PlayerParty[player] or DuelService.PlayerStage[player] then
		return
	end
	local n, spots = #party.Members, spotCount(party)
	if n == 0 then
		join(party, player, "Host")
		return
	end
	local who = host(party)
	if party.Status ~= "Waiting" or n >= spots then
		PartyRemote:Fire(player, {
			Message = "Prompt",
			Kind = if party.Status == "InMatch" and party.Settings.Spectators then "Full" else "Busy",
			Stage = party.Name,
			Title = party.Title,
			Host = who and who.DisplayName,
			Count = n,
			Spots = spots,
			Round = party.Model:GetAttribute("Round"),
			Status = party.Status,
			Spectate = party.Status == "InMatch" and party.Settings.Spectators,
		})
		return
	end
	if party.Blocked[player.UserId] then
		toast(player, "The host has closed this stage to you")
		return
	end
	local invited = party.Invited[player.UserId] and party.Invited[player.UserId] > os.clock()
	if party.Settings.FriendsOnly and not invited and not (who and isFriend(player, who)) then
		PartyRemote:Fire(player, {
			Message = "Prompt",
			Kind = "FriendsOnly",
			Stage = party.Name,
			Title = party.Title,
			Host = who and who.DisplayName,
			Count = n,
			Spots = spots,
		})
		return
	end
	join(party, player, if invited then "Invite" else "Walked")
end

--| Host actions

local function isHost(party, player: Player): boolean
	return party ~= nil and host(party) == player
end

local function memberById(party, userId: any): Player?
	for _, p in party.Members do
		if p.UserId == userId then
			return p
		end
	end
	return nil
end

local function setSettings(party, player: Player, packet)
	if not isHost(party, player) or party.Status == "InMatch" then
		return
	end
	local s = party.Settings
	local n = #party.Members
	if packet.Mode == "Duel" or packet.Mode == "FFA" then
		if packet.Mode == "Duel" and n > PartyConstants.DUEL_SPOTS then
			toast(player, "Too many players here for a Normal Duel")
		else
			s.Mode = packet.Mode
		end
	end
	if type(packet.Spots) == "number" then
		local want = math.clamp(math.floor(packet.Spots), math.max(PartyConstants.MIN_SPOTS, n), PartyConstants.MAX_SPOTS)
		s.Spots = want
	end
	if type(packet.Boost) == "boolean" then
		s.Boost = packet.Boost
	end
	if type(packet.FriendsOnly) == "boolean" then
		s.FriendsOnly = packet.FriendsOnly
	end
	if type(packet.Spectators) == "boolean" then
		s.Spectators = packet.Spectators
		if not packet.Spectators then
			for w in party.Watchers do
				watching[w] = nil
				PartyRemote:Fire(w, { Message = "WatchEnd" })
			end
			party.Watchers = {}
		end
	end
	cancelCountdown(party, "The host changed the settings · countdown stopped")
	arrange(party)
	broadcast(party)
end

local function setPool(party, player: Player, packet)
	if not isHost(party, player) or party.Status == "InMatch" then
		return
	end
	if packet.All then
		party.Settings.Pool = nil
		party.PoolSongs = nil
	else
		local groups, out = {}, {}
		local known = {}
		for _, song in Songs.All do
			known[song.Artist] = true
		end
		for _, g in (type(packet.Groups) == "table" and packet.Groups) or {} do
			if type(g) == "string" and known[g] and not table.find(groups, g) then
				table.insert(groups, g)
			end
		end
		for _, id in (type(packet.Out) == "table" and packet.Out) or {} do
			if type(id) == "string" and Songs.GetById(id) and not table.find(out, id) then
				table.insert(out, id)
			end
		end
		local pool = { Groups = groups, Out = out }
		local list = poolSongs(pool)
		if #list < PartyConstants.MIN_POOL then
			toast(player, `Pick at least {PartyConstants.MIN_POOL} songs`)
			broadcast(party)
			return
		end
		party.Settings.Pool = pool
		party.PoolSongs = list
	end
	cancelCountdown(party, "The host changed the songs · countdown stopped")
	broadcast(party)
end

local function setReady(party, player: Player, on: boolean)
	if isHost(party, player) or party.Status == "InMatch" then
		return
	end
	party.Ready[player] = on or nil
	if not on then
		cancelCountdown(party, `{player.DisplayName} isn't ready · countdown stopped`)
	end
	broadcast(party)
end

local beginMatch -- forward

local function start(party, player: Player)
	if not isHost(party, player) or party.Status ~= "Waiting" then
		return
	end
	local why = blocker(party)
	if why then
		toast(player, why)
		return
	end
	party.Status = "Countdown"
	party.CountdownEnds = workspace:GetServerTimeNow() + PartyConstants.COUNTDOWN
	broadcast(party)
	party.CountdownThread = task.delay(PartyConstants.COUNTDOWN, function()
		party.CountdownThread = nil
		if party.Status ~= "Countdown" then
			return
		end
		if blocker(party) then
			cancelCountdown(party)
			broadcast(party)
			return
		end
		beginMatch(party)
	end)
end

local function makeHost(party, player: Player, userId: any)
	if not isHost(party, player) or party.Status ~= "Waiting" then
		return
	end
	local target = memberById(party, userId)
	if not target or target == player then
		return
	end
	table.remove(party.Members, table.find(party.Members, target))
	table.insert(party.Members, 1, target)
	party.Ready[target] = nil
	party.Ready[player] = true -- the old host was ready by definition
	for _, p in party.Members do
		toast(p, if p == target then "You're the host now" else `{target.DisplayName} is the host now`)
	end
	arrange(party)
	broadcast(party)
end

local function remove(party, player: Player, userId: any, block: boolean)
	if not isHost(party, player) or party.Status ~= "Waiting" then
		return -- locked once the countdown starts
	end
	local target = memberById(party, userId)
	if not target or target == player then
		return
	end
	if block then
		party.Blocked[target.UserId] = true
	end
	leave(target, "Removed")
end

--| Invites + requests

local function inviteList(party, player: Player)
	if not isHost(party, player) then
		return
	end
	local list = {}
	for _, other in Players:GetPlayers() do
		if other == player then
			continue
		end
		local status = "Open"
		if PartyService.PlayerParty[other] == party then
			status = "Here"
		elseif PartyService.PlayerParty[other] or DuelService.PlayerStage[other] then
			status = "Busy"
		elseif party.Invited[other.UserId] and party.Invited[other.UserId] > os.clock() then
			status = "Sent"
		end
		table.insert(list, {
			UserId = other.UserId,
			Name = other.DisplayName,
			Level = levelOf(other),
			Friend = isFriend(player, other),
			Status = status,
		})
	end
	table.sort(list, function(a, b)
		if a.Friend ~= b.Friend then
			return a.Friend
		end
		return a.Name < b.Name
	end)
	PartyRemote:Fire(player, { Message = "InviteList", Players = list })
end

local function invite(party, player: Player, targetId: any)
	if not isHost(party, player) or party.Status ~= "Waiting" then
		return
	end
	local target = type(targetId) == "number" and Players:GetPlayerByUserId(targetId)
	if not target or target == player or PartyService.PlayerParty[target] or DuelService.PlayerStage[target] then
		toast(player, "They can't join right now")
		return
	end
	party.Blocked[target.UserId] = nil -- inviting someone lifts a block
	party.Invited[target.UserId] = os.clock() + PartyConstants.INVITE_TIME
	local okFriend, friend = pcall(target.IsFriendsWith, target, player.UserId)
	PartyRemote:Fire(target, {
		Message = "Invited",
		Stage = party.Name,
		Title = party.Title,
		Name = player.DisplayName,
		From = player.UserId, -- the invite toast's headshot
		Friend = okFriend and friend == true,
		Count = #party.Members,
		Spots = spotCount(party),
		Mode = party.Settings.Mode,
		Expires = workspace:GetServerTimeNow() + PartyConstants.INVITE_TIME,
	})
	toast(player, `Invite sent to {target.DisplayName}`)
	inviteList(party, player)
end

local function answerInvite(player: Player, stageName: any, accept: boolean)
	local party = PartyService.Stages[stageName]
	if not party or not accept then
		return
	end
	local until_ = party.Invited[player.UserId]
	if not until_ or until_ < os.clock() then
		PartyRemote:Fire(player, { Message = "InviteGone" })
		return
	end
	if not join(party, player, "Invite") then
		PartyRemote:Fire(player, { Message = "InviteGone" })
	end
end

local function ask(player: Player, stageName: any)
	local party = PartyService.Stages[stageName]
	local who = party and host(party)
	if not who or PartyService.PlayerParty[player] then
		return
	end
	local k = `{who.UserId}:{player.UserId}`
	if declined[k] and declined[k] > os.clock() then
		toast(player, "Give it a moment before asking again")
		return
	end
	party.Requests[player.UserId] = { Player = player, Until = os.clock() + PartyConstants.INVITE_TIME }
	PartyRemote:Fire(who, {
		Message = "Request",
		UserId = player.UserId,
		Name = player.DisplayName,
		Level = levelOf(player),
		Stage = party.Name,
		Expires = workspace:GetServerTimeNow() + PartyConstants.INVITE_TIME,
	})
	PartyRemote:Fire(player, { Message = "RequestResult", Result = "Sent", Title = party.Title, Host = who.DisplayName })
end

local function answerRequest(party, player: Player, userId: any, accept: boolean)
	if not isHost(party, player) then
		return
	end
	local req = party.Requests[userId]
	party.Requests[userId] = nil
	if not req or req.Until < os.clock() or not req.Player.Parent then
		return
	end
	if not accept then
		declined[`{player.UserId}:{userId}`] = os.clock() + PartyConstants.REQUEST_COOLDOWN
		PartyRemote:Fire(req.Player, { Message = "RequestResult", Result = "Declined", Title = party.Title })
		return
	end
	party.Invited[userId] = os.clock() + PartyConstants.INVITE_TIME -- skips Friends only
	if not join(party, req.Player, "Request") then
		PartyRemote:Fire(req.Player, { Message = "RequestResult", Result = "Failed", Title = party.Title })
	end
end

--| Spectating

local function watchPacket(party, packet)
	local duel = party.Duel
	if not duel then
		return nil
	end
	local list = {}
	for _, p in duel:Placement() do
		table.insert(list, { Name = p.DisplayName, Score = duel.Scores[p] or 0, Left = duel.Left[p] == true })
	end
	return { Message = "Watch", Stage = party.Name, Title = party.Title, Round = duel.Round, Rounds = duel.RoundCount, Players = list }
end

local function spectate(player: Player, stageName: any)
	local party = PartyService.Stages[stageName]
	if not party or party.Status ~= "InMatch" or not party.Settings.Spectators or PartyService.PlayerParty[player] then
		return
	end
	if watching[player] then
		watching[player].Watchers[player] = nil
	end
	watching[player] = party
	party.Watchers[player] = true
	local packet = watchPacket(party)
	if packet then
		PartyRemote:Fire(player, packet)
	end
	broadcast(party)
end

local function stopWatching(player: Player)
	local party = watching[player]
	if party then
		party.Watchers[player] = nil
		watching[player] = nil
		broadcast(party)
	end
	PartyRemote:Fire(player, { Message = "WatchEnd" })
end

--| The match

local function onEnded(party, result)
	local duel = party.Duel
	party.Duel = nil
	if duel then
		duel:Destroy()
	end
	local info = { Multiplier = party.MatchMultiplier or 1, Eligible = party.MatchEligible ~= false, Kind = party.MatchKind or "FFA" }
	local earned = Rewards.ApplyParty(result, info)

	local placement = {}
	for place, p in result.Placement or {} do
		local e = earned[p]
		table.insert(placement, {
			UserId = p.UserId,
			Name = p.DisplayName,
			Place = place,
			Points = result.Scores[p] or 0,
			Firsts = result.Firsts and result.Firsts[p] or 0,
			Left = result.Left and result.Left[p] == true,
			Coins = e and e.Coins or 0,
			XP = e and e.XP or 0,
		})
	end
	local rewards = {}
	for p, e in earned do
		rewards[key(p)] = e
	end
	local scores = {}
	for p, s in result.Scores do
		scores[key(p)] = s
	end
	if #party.Members > 0 then
		DuelRemote:Fire(Bridgenet.Players(party.Members), {
			Message = "End",
			Party = {
				Title = party.Title,
				Kind = info.Kind,
				Multiplier = info.Multiplier,
				MultiplierText = party.MatchMultiplierText or "",
				Eligible = info.Eligible,
				Players = #placement,
				Rounds = #result.Rounds,
				Placement = placement,
				Payout = if info.Kind == "Duel" then PartyConstants.DUEL_PAYOUT else PartyConstants.PAYOUT,
				Base = result.Stake or 0, -- the pot (rolled stake × multiplier)
				Roll = result.StakeRoll or 0,
			},
			Scores = scores,
			Rewards = rewards,
			Mode = result.Mode,
		})
	end
	for w in party.Watchers do
		watching[w] = nil
		PartyRemote:Fire(w, { Message = "WatchEnd" })
	end
	party.Watchers = {}
	party.Status = "Waiting"
	party.Ready = {}
	party.Model:SetAttribute("Round", 0)
	arrange(party)
	broadcast(party)
end

function beginMatch(party)
	party.Status = "InMatch"
	party.CountdownEnds = nil
	local players = table.clone(party.Members)
	party.MatchKind = party.Settings.Mode
	party.MatchMultiplier, party.MatchMultiplierText = multiplier(party, #players)
	party.MatchEligible = eligible(party)
	local duel = Duels.new(party, nil, nil, false, {
		Kind = party.Settings.Mode,
		Players = players,
		Pool = party.PoolSongs,
		Boost = party.Settings.Boost,
		Multiplier = party.MatchMultiplier,
		MultiplierText = party.MatchMultiplierText,
		Eligible = party.MatchEligible,
	})
	party.Duel = duel
	duel.OnPacket = function(packet)
		if packet.Message == "Round" or packet.Message == "RoundEnd" then
			refreshSign(party)
			local watchers = {}
			for w in party.Watchers do
				if w.Parent then
					table.insert(watchers, w)
				end
			end
			local wp = #watchers > 0 and watchPacket(party, packet)
			if wp then
				PartyRemote:Fire(Bridgenet.Players(watchers), wp)
			end
		end
	end
	duel.Ended:Connect(function(result)
		onEnded(party, result)
	end)
	for _, p in players do
		Analytics.Event(p, "PartyStarted", #players, party.MatchKind, if party.PoolSongs then "Custom" else "All")
	end
	broadcast(party)
	duel:Start()
end

--| Setup

local function createParty(model: Model, index: number)
	local party = {
		Name = model.Name,
		Title = `Party Stage {model:GetAttribute("PartyId") or index}`,
		Model = model,
		Members = {} :: { Player },
		Ready = {} :: { [Player]: boolean },
		Settings = defaults(),
		PoolSongs = nil :: { any }?,
		Status = "Waiting" :: string, -- "Waiting" | "Countdown" | "InMatch"
		Duel = nil,
		Spots = {},
		SpotCount = 0,
		Janitors = {},
		Watchers = {} :: { [Player]: boolean },
		Blocked = {} :: { [number]: boolean },
		Invited = {} :: { [number]: number },
		Requests = {} :: { [number]: any },
		Players = {}, -- StageCosmetics reads stage.Players; unused here
		Prompts = {} :: { ProximityPrompt }, -- one per spot (see makePrompts)
	}
	arrange(party)
	refreshSign(party)
	return party
end

function PartyService.Start()
	local map = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("PartyStages")
	if not folder then
		return
	end
	for i, model in folder:GetChildren() do
		if model:IsA("Model") then
			PartyService.Stages[model.Name] = createParty(model, i)
		end
	end

	PartyRemote:Connect(function(player: Player, packet)
		if type(packet) ~= "table" then
			return
		end
		local now = os.clock()
		if lastAction[player] and now - lastAction[player] < PartyConstants.ACTION_GAP then
			return
		end
		lastAction[player] = now
		local party = PartyService.PlayerParty[player]
		local action = packet.Action
		if action == "Leave" then
			leave(player, "Left")
		elseif action == "Ask" then
			ask(player, packet.Stage)
		elseif action == "Answer" then
			answerInvite(player, packet.Stage, packet.Accept == true)
		elseif action == "Spectate" then
			spectate(player, packet.Stage)
		elseif action == "StopWatching" then
			stopWatching(player)
		elseif not party then
			return
		elseif action == "Ready" then
			setReady(party, player, packet.On == true)
		elseif action == "Start" then
			start(party, player)
		elseif action == "Settings" then
			setSettings(party, player, packet)
		elseif action == "Pool" then
			setPool(party, player, packet)
		elseif action == "InviteList" then
			inviteList(party, player)
		elseif action == "Invite" then
			invite(party, player, packet.Target)
		elseif action == "Request" then
			answerRequest(party, player, packet.UserId, packet.Accept == true)
		elseif action == "MakeHost" then
			makeHost(party, player, packet.UserId)
		elseif action == "Remove" then
			remove(party, player, packet.UserId, packet.Block == true)
		elseif action == "State" then
			PartyRemote:Fire(player, statePacket(party))
		end
	end)

	-- round actions (Loaded / Unlock / Guess) for players in a party match
	DuelRemote:Connect(function(player: Player, packet)
		local party = PartyService.PlayerParty[player]
		if party and party.Duel and type(packet) == "table" then
			party.Duel:Action(player, packet)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		leave(player, "Left")
		if watching[player] then
			watching[player].Watchers[player] = nil
			watching[player] = nil
		end
		lastAction[player] = nil
	end)
end

-- for Cmdr / tests
PartyService.Leave = function(player: Player)
	leave(player, "Left")
end
-- same as walking up to the stage and pressing its prompt
PartyService.Prompt = function(player: Player, stageName: string)
	local party = PartyService.Stages[stageName]
	if party then
		onPrompt(party, player)
	end
end

return PartyService
