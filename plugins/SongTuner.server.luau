--| Song Tuner (Studio plugin)
-- Pick a company tab, then a song from Library/Songs/<Company>/<Group>, play it, adjust its
-- start (TimePosition), chorus (ChorusPosition), PlaybackSpeed and Volume while you listen,
-- preview the tier lengths, then Save writes the values back into that song's entry in its
-- group module.
--
-- Install: right-click the SongTuner script in ServerStorage → "Save as Local Plugin…".

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptEditorService = game:GetService("ScriptEditorService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

-- tabs = the company folders under Library/Songs (read when the widget opens; ↻ re-reads)
local TIERS = { 0.1, 0.5, 2, 8, 15 }

-- --------------------------------- Theme ---------------------------------- --
local C = Color3.fromHex
local BG = C("1E1B2E")
local PANEL = C("2A2640")
local ROW = C("353052")
local TEXT = C("F3EBDD")
local MUTED = C("A9A3C2")
local ACCENT = C("FFE07A")
local GOOD = C("A7E9B8")
local BAD = C("FF5A4E")
local LILAC = C("B9A6FF")
local FONT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

-- --------------------------------- Widget --------------------------------- --
local toolbar = plugin:CreateToolbar("Guess the K-Pop Song")
local button = toolbar:CreateButton("Song Tuner", "Tune song start, speed and volume", "rbxassetid://4458901886")
button.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGui(
	"SongTuner",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 340, 620, 300, 480)
)
widget.Title = "Song Tuner"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(p: Instance, r: number?)
	new("UICorner", { CornerRadius = UDim.new(0, r or 6) }, p)
end

local function textButton(parent: Instance, text: string, width: number, colour: Color3?, order: number?): TextButton
	local b = new("TextButton", {
		Size = UDim2.new(0, width, 0, 26),
		BackgroundColor3 = colour or ROW,
		TextColor3 = if colour then BG else TEXT,
		FontFace = FONT,
		TextSize = 13,
		Text = text,
		AutoButtonColor = true,
		LayoutOrder = order or 0,
	}, parent)
	corner(b)
	return b
end

local function label(parent: Instance, text: string, size: number, colour: Color3?, order: number?): TextLabel
	return new("TextLabel", {
		Size = UDim2.new(1, 0, 0, size + 6),
		BackgroundTransparency = 1,
		TextColor3 = colour or TEXT,
		FontFace = FONT,
		TextSize = size,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Text = text,
		LayoutOrder = order or 0,
	}, parent)
end

local function hrow(parent: Instance, order: number, height: number?): Frame
	local f = new("Frame", {
		Size = UDim2.new(1, 0, 0, height or 26),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, parent)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, f)
	return f
end

local root = new("ScrollingFrame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = BG,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
}, widget)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
	PaddingTop = UDim.new(0, 10),
	PaddingBottom = UDim.new(0, 10),
}, root)
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, root)

-- company tabs (wrap onto more rows when there are many)
local tabs = hrow(root, 1)
tabs.AutomaticSize = Enum.AutomaticSize.Y
tabs:FindFirstChildOfClass("UIListLayout").Wraps = true
local tabButtons: { [string]: TextButton } = {}
local refresh = textButton(tabs, "↻", 30, nil, 1000)

-- song list
local list = new("ScrollingFrame", {
	Size = UDim2.new(1, 0, 0, 190),
	BackgroundColor3 = PANEL,
	BorderSizePixel = 0,
	ScrollBarThickness = 5,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	LayoutOrder = 2,
}, root)
corner(list, 8)
new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, list)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 5),
	PaddingRight = UDim.new(0, 8),
	PaddingTop = UDim.new(0, 5),
	PaddingBottom = UDim.new(0, 5),
}, list)

-- selected song
local runHint = label(root, "You're in Run/Play: anything saved here is thrown away when you stop. Tune in Edit mode.", 12, BAD, 0)
local title = label(root, "Pick a song", 16, ACCENT, 3)
local info = label(root, "", 12, MUTED, 4)

-- transport
local transport = hrow(root, 5, 28)
local playBtn = textButton(transport, "▶ Play", 70, GOOD, 1)
local stopBtn = textButton(transport, "■ Stop", 64, nil, 2)
local markBtn = textButton(transport, "Set start here", 110, LILAC, 3)
local transport2 = hrow(root, 6, 28)
local chorusPlayBtn = textButton(transport2, "▶ Chorus", 70, GOOD, 1)
local chorusMarkBtn = textButton(transport2, "Set chorus here", 120, ACCENT, 2)
local posLabel = label(root, "Position —", 13, TEXT, 7)

-- scrub bar for the start point
local scrub = new("Frame", {
	Size = UDim2.new(1, 0, 0, 18),
	BackgroundColor3 = PANEL,
	LayoutOrder = 8,
}, root)
corner(scrub, 9)
local scrubFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = LILAC, BorderSizePixel = 0 }, scrub)
corner(scrubFill, 9)
local playHead = new("Frame", {
	Size = UDim2.new(0, 3, 1, 4),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0, 0.5),
	BackgroundColor3 = ACCENT,
	BorderSizePixel = 0,
	Visible = false,
}, scrub)
-- chorus marker on the bar
local chorusMark = new("Frame", {
	Size = UDim2.new(0, 4, 1, 6),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0, 0.5),
	BackgroundColor3 = ACCENT,
	BorderSizePixel = 0,
	ZIndex = 2,
}, scrub)
local scrubHit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "" }, scrub)

-- value rows: name, textbox, nudges
local function valueRow(order: number, name: string, nudges: { number }): (TextBox, { TextButton })
	local r = hrow(root, order)
	new("TextLabel", {
		Size = UDim2.new(0, 58, 1, 0),
		BackgroundTransparency = 1,
		TextColor3 = MUTED,
		FontFace = FONT,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = name,
		LayoutOrder = 0,
	}, r)
	local box = new("TextBox", {
		Size = UDim2.new(0, 62, 1, 0),
		BackgroundColor3 = PANEL,
		TextColor3 = TEXT,
		FontFace = FONT,
		TextSize = 13,
		Text = "",
		ClearTextOnFocus = false,
		LayoutOrder = 1,
	}, r)
	corner(box)
	local buttons = {}
	for i, n in nudges do
		local b = textButton(r, (if n > 0 then "+" else "") .. tostring(n), 44, nil, 1 + i)
		b:SetAttribute("Step", n)
		table.insert(buttons, b)
	end
	return box, buttons
end

local startBox, startNudges = valueRow(9, "Start", { -1, -0.1, 0.1, 1 })
local chorusBox, chorusNudges = valueRow(10, "Chorus", { -1, -0.1, 0.1, 1 })
local speedBox, speedNudges = valueRow(11, "Speed", { -0.05, -0.01, 0.01, 0.05 })
local volumeBox, volumeNudges = valueRow(12, "Volume", { -0.1, 0.1 })

-- tier previews
label(root, "Preview a tier from the start point", 12, MUTED, 13)
local tierRow = hrow(root, 14)
local tierButtons = {}
for i, t in TIERS do
	tierButtons[i] = textButton(tierRow, `{t}s`, 52, nil, i)
end

-- save / revert
local saveRow = hrow(root, 15, 32)
local saveBtn = textButton(saveRow, "Save to module", 130, ACCENT, 1)
saveBtn.Size = UDim2.new(0, 130, 0, 30)
local revertBtn = textButton(saveRow, "Revert", 70, nil, 2)
revertBtn.Size = UDim2.new(0, 70, 0, 30)
local status = label(root, "", 12, MUTED, 16)

-- --------------------------------- State ---------------------------------- --
local currentFile = "" -- company folder name
local songs: { any } = {}
local selected: number? = nil
local values = { Start = 0, Chorus = 0, Speed = 1, Volume = 1 }
local saved = { Start = 0, Chorus = 0, Speed = 1, Volume = 1 }

local function snapshot(from, to)
	to.Start, to.Chorus, to.Speed, to.Volume = from.Start, from.Chorus, from.Speed, from.Volume
end
local sound: any = nil -- the AudioPlayer
local rigFolder: Folder? = nil
local playing = false
local playFrom, playClock = 0, 0
local playToken = 0

local function round(n: number, step: number): number
	return math.floor(n / step + 0.5) * step
end

local function fmt(n: number): string
	local s = string.format("%.3f", n)
	s = s:gsub("0+$", ""):gsub("%.$", "")
	return s
end

local function songsFolder(): Instance?
	local lib = ReplicatedStorage:FindFirstChild("Modules")
	lib = lib and lib:FindFirstChild("Library")
	return lib and lib:FindFirstChild("Songs")
end

local function companyFolder(): Instance?
	local folder = songsFolder()
	return folder and folder:FindFirstChild(currentFile)
end

local function setStatus(text: string, colour: Color3?)
	status.Text = text
	status.TextColor3 = colour or MUTED
end

local function length(): number
	return sound and sound.TimeLength or 0
end

-- where you last stopped or clicked on the bar (nil = nothing yet, use the start point)
local cursor: number? = nil

local function position(): number
	if playing and sound then
		return sound.TimePosition -- AudioPlayer reports its real position, even in Edit
	end
	return cursor or values.Start
end

local function stop()
	if playing then
		cursor = position() -- remember where you stopped, so "Set … here" still works
	end
	playToken += 1
	playing = false
	if sound then
		sound:Stop()
	end
	local len = length()
	playHead.Visible = cursor ~= nil and len > 0
	if cursor and len > 0 then
		playHead.Position = UDim2.fromScale(math.clamp(cursor / len, 0, 1), 0.5)
	end
end

local function play(from: number, duration: number?)
	if not sound then
		return
	end
	stop()
	local token = playToken
	sound.PlaybackSpeed = values.Speed
	sound.Volume = values.Volume
	sound.TimePosition = from
	sound:Play()
	playing = true
	playFrom, playClock = from, os.clock()
	playHead.Visible = true
	if duration then
		-- stop by the audio's own clock, the same way the game does
		local to = from + duration * values.Speed
		task.spawn(function()
			local deadline = os.clock() + duration + 2
			while playToken == token and os.clock() < deadline do
				if sound.IsPlaying and sound.TimePosition >= to then
					break
				end
				task.wait()
			end
			if playToken == token then
				stop()
			end
		end)
	end
end

local function refreshValues()
	local len = length()
	startBox.Text = fmt(values.Start)
	chorusBox.Text = fmt(values.Chorus)
	chorusMark.Position = UDim2.fromScale(if len > 0 then math.clamp(values.Chorus / len, 0, 1) else 0, 0.5)
	speedBox.Text = fmt(values.Speed)
	volumeBox.Text = fmt(values.Volume)
	scrubFill.Size = UDim2.fromScale(if len > 0 then math.clamp(values.Start / len, 0, 1) else 0, 1)
	local dirty = values.Start ~= saved.Start or values.Chorus ~= saved.Chorus or values.Speed ~= saved.Speed or values.Volume ~= saved.Volume
	saveBtn.Text = if dirty then "Save to module •" else "Save to module"
end

-- live position readout
task.spawn(function()
	while true do
		task.wait(0.05)
		local len = length()
		if selected then
			local pos = position()
			posLabel.Text = string.format("Position %.1f / %.1f   %s", pos, len, if playing then "playing" else "stopped")
			if playing and len > 0 then
				playHead.Position = UDim2.fromScale(math.clamp(pos / len, 0, 1), 0.5)
				if pos >= len then
					stop()
				end
			end
		end
	end
end)

-- ------------------------------ Loading songs ----------------------------- --
local function speedOf(song): number
	return song.PlaybackSpeed or song.playbackSpeed or song.Pitch or 1
end

local function select(index: number)
	stop()
	cursor = nil
	playHead.Visible = false
	selected = index
	local song = songs[index]
	title.Text = string.format("%s - %s", song.Artist or "?", song.Name or "?")
	if rigFolder then
		rigFolder:Destroy()
	end
	-- Studio only plays a plugin's audio in Edit mode through the newer audio objects:
	-- AudioPlayer → Wire → AudioDeviceOutput. (A plain Sound stays silent.)
	local folder = Instance.new("Folder")
	folder.Name = "__SongTuner"
	folder.Archivable = false
	local s = Instance.new("AudioPlayer")
	s.Asset = song.MusicId or ""
	s.Parent = folder
	local out = Instance.new("AudioDeviceOutput")
	out.Parent = folder
	local wire = Instance.new("Wire")
	wire.SourceInstance = s
	wire.TargetInstance = out
	wire.Parent = folder
	folder.Parent = workspace
	rigFolder = folder
	sound = s

	values.Speed = speedOf(song)
	values.Volume = song.Volume or 1
	values.Start = song.TimePosition or 0
	values.Chorus = song.ChorusPosition or values.Start
	snapshot(values, saved)
	info.Text = "Loading…"
	refreshValues()
	setStatus("")

	task.spawn(function()
		local deadline = os.clock() + 8
		while not s.IsReady and os.clock() < deadline and sound == s do
			task.wait(0.1)
		end
		if sound ~= s then
			return
		end
		if not s.IsReady or s.TimeLength == 0 then
			info.Text = `Didn't load: {s.Asset}`
			info.TextColor3 = BAD
		else
			info.Text = string.format("%s  ·  %.1fs long", s.Asset, s.TimeLength)
			info.TextColor3 = MUTED
			if song.TimePosition == nil then
				-- no start saved yet: suggest halfway, same as the game does
				values.Start = round(s.TimeLength / 2, 0.1)
			end
			if song.ChorusPosition == nil then
				values.Chorus = values.Start
			end
			refreshValues()
		end
	end)
end

local songButtons = {}
local function loadFile(name: string)
	stop()
	currentFile = name
	for n, b in tabButtons do
		b.BackgroundColor3 = if n == name then LILAC else ROW
		b.TextColor3 = if n == name then BG else TEXT
	end
	for _, b in songButtons do
		b:Destroy()
	end
	songButtons = {}
	songs = {}
	local folder = companyFolder()
	if not folder then
		setStatus(`Couldn't find Library.Songs.{name}`, BAD)
		return
	end
	-- every song of every group in this company; each remembers its module + position
	local modules = {}
	for _, m in folder:GetChildren() do
		if m:IsA("ModuleScript") then
			table.insert(modules, m)
		end
	end
	table.sort(modules, function(a, b)
		return a.Name:lower() < b.Name:lower()
	end)
	for _, m in modules do
		local ok, group = pcall(function()
			return require(m:Clone()) -- clone so edits show up without a Studio restart
		end)
		if ok and type(group) == "table" and type(group.Songs) == "table" then
			for i, song in group.Songs do
				local entry = table.clone(song)
				entry.Artist = group.Group or m.Name
				entry.Module = m
				entry.Index = i
				table.insert(songs, entry)
			end
		else
			setStatus(`{m.Name} didn't load: {group}`, BAD)
		end
	end
	for i, song in songs do
		local draft = if song.Draft then "  (draft)" else ""
		local b = textButton(list, string.format("%s - %s%s", song.Artist or "?", song.Name or "?", draft), 0, nil, i)
		b.Size = UDim2.new(1, 0, 0, 24)
		b.TextXAlignment = Enum.TextXAlignment.Left
		new("UIPadding", { PaddingLeft = UDim.new(0, 8) }, b)
		b.Activated:Connect(function()
			for _, other in songButtons do
				other.BackgroundColor3 = ROW
			end
			b.BackgroundColor3 = PANEL
			select(i)
		end)
		table.insert(songButtons, b)
	end
	if selected and songs[selected] then
		songButtons[selected].BackgroundColor3 = PANEL
	end
end

-- One tab per company folder.
local function buildTabs()
	for _, b in tabButtons do
		b:Destroy()
	end
	tabButtons = {}
	local folder = songsFolder()
	local names = {}
	for _, f in folder and folder:GetChildren() or {} do
		if f:IsA("Folder") then
			table.insert(names, f.Name)
		end
	end
	table.sort(names)
	for i, name in names do
		local b = textButton(tabs, name, 0, nil, i)
		b.AutomaticSize = Enum.AutomaticSize.X
		new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, b)
		b.Activated:Connect(function()
			selected = nil
			title.Text = "Pick a song"
			info.Text = ""
			loadFile(name)
		end)
		tabButtons[name] = b
	end
	if currentFile == "" or not table.find(names, currentFile) then
		currentFile = names[1] or ""
	end
end

-- ------------------------------ Saving to file ---------------------------- --
-- Finds the source range of the nth song in a group module
-- (`return { Group = …, Songs = { {..}, {..} } }`: songs sit at table depth 3), skipping
-- strings and comments.
local SONG_DEPTH = 3
local function entryRange(src: string, n: number): (number?, number?)
	local depth, count, start = 0, 0, nil
	local i, len = 1, #src
	while i <= len do
		local ch = src:sub(i, i)
		if ch == '"' or ch == "'" then
			local j = i + 1
			while j <= len and src:sub(j, j) ~= ch do
				if src:sub(j, j) == "\\" then
					j += 1
				end
				j += 1
			end
			i = j
		elseif ch == "-" and src:sub(i, i + 1) == "--" then
			local e = src:find("\n", i, true)
			i = e or len
		elseif ch == "{" then
			depth += 1
			if depth == SONG_DEPTH then
				count += 1
				if count == n then
					start = i
				end
			end
		elseif ch == "}" then
			if depth == SONG_DEPTH and start then
				return start, i
			end
			depth -= 1
		end
		i += 1
	end
	return nil, nil
end

local function fieldPattern(key: string): string
	return "\n([ \t]*)" .. key .. "%s*=%s*[^,\n]*,?[ \t]*"
end

local function setField(block: string, key: string, value: string?): string
	local pat = fieldPattern(key)
	if block:find(pat) then
		if value == nil then
			return (block:gsub(pat, "", 1))
		end
		return (block:gsub(pat, function(indent)
			return `\n{indent}{key} = {value},`
		end, 1))
	end
	if value == nil then
		return block
	end
	-- add it after MusicId (or at the top of the entry), matching the indentation
	-- add it after AnimationId (or MusicId, or at the top), matching the indentation
	local indent = block:match("\n([ \t]*)MusicId") or block:match("\n([ \t]*)%a") or "\t\t\t"
	local after = block:find("AnimationId[^\n]*\n") or block:find("MusicId[^\n]*\n")
	if after then
		local lineEnd = block:find("\n", after, true)
		return block:sub(1, lineEnd) .. `{indent}{key} = {value},\n` .. block:sub(lineEnd + 1)
	end
	return block:sub(1, 1) .. `\n{indent}{key} = {value},` .. block:sub(2)
end

-- Writes start/chorus/speed/volume into song `index` of group module `mod`. Returns ok, message.
local function writeEntry(mod: ModuleScript, index: number, v): (boolean, string, string?)
	if not mod or not mod.Parent then
		return false, "That group module is gone; press ↻"
	end
	local src = mod.Source
	local a, b = entryRange(src, index)
	if not (a and b) then
		return false, `Couldn't find song {index} in {mod.Name}`
	end
	local block = src:sub(a, b)
	if v.Name and not block:find('Name%s*=%s*"' .. v.Name:gsub("%p", "%%%0") .. '"') then
		return false, `{mod.Name} #{index} isn't {v.Name} any more; press ↻`
	end
	local speedKey = "PlaybackSpeed"
	block = setField(block, speedKey, if v.Speed ~= 1 then fmt(v.Speed) else nil)
	block = setField(block, "TimePosition", fmt(v.Start))
	if v.Chorus then
		block = setField(block, "ChorusPosition", fmt(v.Chorus))
	end
	block = setField(block, "Volume", if v.Volume ~= 1 then fmt(v.Volume) else nil)
	local newSource = src:sub(1, a - 1) .. block .. src:sub(b + 1)

	local recording = ChangeHistoryService:TryBeginRecording("Song Tuner save")
	local ok, err = pcall(function()
		ScriptEditorService:UpdateSourceAsync(mod, function()
			return newSource
		end)
	end)
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	if not ok then
		return false, `Save failed: {err}`
	end
	return true, "ok", speedKey
end

local function save()
	if not selected then
		return
	end
	local song = songs[selected]
	local v = { Name = song.Name, Start = values.Start, Chorus = values.Chorus, Speed = values.Speed, Volume = values.Volume }

	local ok, msg, speedKey = writeEntry(song.Module, song.Index, v)
	if ok then
		snapshot(values, saved)
		song.ChorusPosition = values.Chorus
		song[speedKey :: string], song.TimePosition, song.Volume = values.Speed, values.Start, if values.Volume ~= 1 then values.Volume else nil
		refreshValues()
		setStatus(`Saved {song.Name}: start {fmt(values.Start)}, chorus {fmt(values.Chorus)}, speed {fmt(values.Speed)}, volume {fmt(values.Volume)}`, GOOD)
	else
		setStatus(msg, BAD)
	end
end

-- --------------------------------- Wiring --------------------------------- --
refresh.Activated:Connect(function()
	buildTabs()
	loadFile(currentFile)
end)

playBtn.Activated:Connect(function()
	play(values.Start)
end)
stopBtn.Activated:Connect(stop)
markBtn.Activated:Connect(function()
	if selected then
		values.Start = math.max(0, round(position(), 0.1))
		stop()
		refreshValues()
	end
end)

local function setStart(v: number)
	local len = length()
	values.Start = math.clamp(round(v, 0.1), 0, if len > 0 then len else math.huge)
	refreshValues()
	if playing then
		play(values.Start)
	end
end

local function setChorus(v: number)
	local len = length()
	values.Chorus = math.clamp(round(v, 0.1), 0, if len > 0 then len else math.huge)
	refreshValues()
	if playing then
		play(values.Chorus)
	end
end

local function setSpeed(v: number)
	if playing then
		-- keep the readout honest when the speed changes mid-play
		playFrom, playClock = position(), os.clock()
	end
	values.Speed = math.clamp(round(v, 0.01), 0.1, 3)
	if sound then
		sound.PlaybackSpeed = values.Speed
	end
	refreshValues()
end

local function setVolume(v: number)
	values.Volume = math.clamp(round(v, 0.05), 0, 10)
	if sound then
		sound.Volume = values.Volume
	end
	refreshValues()
end

for _, b in startNudges do
	b.Activated:Connect(function()
		setStart(values.Start + b:GetAttribute("Step"))
	end)
end
for _, b in chorusNudges do
	b.Activated:Connect(function()
		setChorus(values.Chorus + b:GetAttribute("Step"))
	end)
end
chorusBox.FocusLost:Connect(function()
	setChorus(tonumber(chorusBox.Text) or values.Chorus)
end)
chorusPlayBtn.Activated:Connect(function()
	play(values.Chorus)
end)
chorusMarkBtn.Activated:Connect(function()
	if selected then
		values.Chorus = math.max(0, round(position(), 0.1))
		stop()
		refreshValues()
	end
end)
for _, b in speedNudges do
	b.Activated:Connect(function()
		setSpeed(values.Speed + b:GetAttribute("Step"))
	end)
end
for _, b in volumeNudges do
	b.Activated:Connect(function()
		setVolume(values.Volume + b:GetAttribute("Step"))
	end)
end
startBox.FocusLost:Connect(function()
	setStart(tonumber(startBox.Text) or values.Start)
end)
speedBox.FocusLost:Connect(function()
	setSpeed(tonumber(speedBox.Text) or values.Speed)
end)
volumeBox.FocusLost:Connect(function()
	setVolume(tonumber(volumeBox.Text) or values.Volume)
end)

-- clicking the bar just jumps playback there; it never changes the saved values
scrubHit.MouseButton1Down:Connect(function(x)
	local len = length()
	if len > 0 then
		local f = math.clamp((x - scrub.AbsolutePosition.X) / scrub.AbsoluteSize.X, 0, 1)
		play(round(f * len, 0.1))
	end
end)

for i, b in tierButtons do
	b.Activated:Connect(function()
		play(values.Start, TIERS[i])
	end)
end

revertBtn.Activated:Connect(function()
	snapshot(saved, values)
	if sound then
		sound.PlaybackSpeed, sound.Volume = values.Speed, values.Volume
	end
	refreshValues()
	setStatus("Reverted to the saved values")
end)
saveBtn.Activated:Connect(save)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	if not widget.Enabled then
		stop()
	end
end)
plugin.Unloading:Connect(function()
	stop()
	if rigFolder then
		rigFolder:Destroy()
	end
end)

buildTabs()
loadFile(currentFile)

runHint.Visible = RunService:IsRunning()
