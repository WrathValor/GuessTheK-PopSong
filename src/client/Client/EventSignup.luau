--| EventSignup
-- "Notify me" in the world: every ProximityPrompt tagged EventConstants.PROMPT_TAG (the one on
-- the unlit server tree) opens Roblox's sign-up for the Christmas event (Modules/EventRsvp),
-- then reads "✓ You're going". The prompts are built in Studio (ActionText / ObjectText set
-- there); this only wires them. From EventConstants.STARTS they switch off: the tree is lit
-- and the event has begun. CustomPrompts draws them in the Photocard style.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventConstants = require(ReplicatedStorage.Constants.EventConstants)
local EventRsvp = require(ReplicatedStorage.Modules.EventRsvp)

local NOTIFY = "Notify me"
local GOING = "✓ You're going"

local EventSignup = {}

local prompts: { [ProximityPrompt]: boolean } = {}

local function paint(prompt: ProximityPrompt, going: boolean?)
	prompt.Enabled = EventRsvp.Phase() == "Before"
	prompt.ActionText = if going then GOING else NOTIFY
end

local function add(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") or prompts[prompt] then
		return
	end
	prompts[prompt] = true
	paint(prompt, false)
	task.spawn(function()
		paint(prompt, EventRsvp.IsGoing())
	end)
	prompt.Triggered:Connect(function()
		if EventRsvp.Phase() == "Before" then
			EventRsvp.Prompt()
		end
	end)
end

function EventSignup.Start()
	if EventRsvp.Phase() == "Over" then
		return
	end
	for _, prompt in CollectionService:GetTagged(EventConstants.PROMPT_TAG) do
		add(prompt)
	end
	CollectionService:GetInstanceAddedSignal(EventConstants.PROMPT_TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(EventConstants.PROMPT_TAG):Connect(function(prompt)
		prompts[prompt :: ProximityPrompt] = nil
	end)
	EventRsvp.Changed:Connect(function(going)
		for prompt in prompts do
			paint(prompt, going)
		end
	end)
	-- switch off when the event starts, without a rejoin
	local wait = EventConstants.STARTS - os.time()
	if wait > 0 then
		task.delay(wait, function()
			for prompt in prompts do
				prompt.Enabled = false
			end
		end)
	end
end

return EventSignup
