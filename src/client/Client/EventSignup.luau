--| EventSignup
-- "Notify me" in the world: every ProximityPrompt tagged EventConstants.PROMPT_TAG (the one on
-- the unlit server tree) opens Roblox's sign-up for the configured event (Modules/EventRsvp),
-- then reads "✓ You're going". The prompts are built in Studio (ActionText / ObjectText set
-- there); this only wires them. They're on only before the event starts, and off when no event
-- is configured. CustomPrompts draws them in the Photocard style.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventConstants = require(ReplicatedStorage.Constants.EventConstants)
local EventRsvp = require(ReplicatedStorage.Modules.EventRsvp)

local NOTIFY = "Notify me"
local GOING = "✓ You're going"

local EventSignup = {}

local prompts: { [ProximityPrompt]: boolean } = {}
local info: EventRsvp.Info? = nil

local function paint(prompt: ProximityPrompt)
	prompt.Enabled = info ~= nil and EventRsvp.Phase(info) == "Before"
	prompt.ActionText = if info and info.Going then GOING else NOTIFY
end

local function paintAll()
	for prompt in prompts do
		paint(prompt)
	end
end

local function refresh()
	info = EventRsvp.Info()
	paintAll()
end

local function add(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") or prompts[prompt] then
		return
	end
	prompts[prompt] = true
	paint(prompt)
	prompt.Triggered:Connect(function()
		if info and EventRsvp.Phase(info) == "Before" then
			EventRsvp.Prompt()
		end
	end)
end

function EventSignup.Start()
	for _, prompt in CollectionService:GetTagged(EventConstants.PROMPT_TAG) do
		add(prompt)
	end
	CollectionService:GetInstanceAddedSignal(EventConstants.PROMPT_TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(EventConstants.PROMPT_TAG):Connect(function(prompt)
		prompts[prompt :: ProximityPrompt] = nil
	end)
	EventRsvp.Changed:Connect(function()
		task.spawn(refresh)
	end)
	task.spawn(function()
		refresh()
		-- switch off when the event starts, without a rejoin
		while true do
			task.wait(60)
			paintAll()
		end
	end)
end

return EventSignup
