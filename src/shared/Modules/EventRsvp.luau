--| EventRsvp
-- Client only. The local player's sign-up to the Christmas event (EventConstants.EVENT_ID),
-- through Roblox's own RSVP prompt (SocialService). The HUD's Christmas card and the world's
-- "Notify me" prompts share it, so signing up at one updates the other (Changed).
-- SocialService doesn't work in Studio playtests: IsGoing() is then nil and Prompt() warns;
-- test it in a published game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Signal = require(ReplicatedStorage.Packages.signal)
local EventConstants = require(ReplicatedStorage.Constants.EventConstants)

export type Phase = "Before" | "Live" | "Over"

local EventRsvp = {}

-- fires (going: boolean) when the player signs up or backs out
EventRsvp.Changed = Signal.new()

local going: boolean? = nil -- nil until Roblox has answered
local prompting = false

function EventRsvp.Phase(): Phase
	local now = os.time()
	if now < EventConstants.STARTS then
		return "Before"
	elseif now < EventConstants.ENDS then
		return "Live"
	end
	return "Over"
end

-- Time until the event starts, for the HUD: "14d", then "5h" on the last day, then "30m".
function EventRsvp.Countdown(): string
	local left = math.max(0, EventConstants.STARTS - os.time())
	if left >= 86400 then
		return `{math.ceil(left / 86400)}d`
	elseif left >= 3600 then
		return `{math.ceil(left / 3600)}h`
	end
	return `{math.max(1, math.ceil(left / 60))}m`
end

-- Yields the first time. true / false once Roblox has said; nil if it couldn't (Studio).
function EventRsvp.IsGoing(): boolean?
	if going == nil then
		local ok, status = pcall(SocialService.GetEventRsvpStatusAsync, SocialService, EventConstants.EVENT_ID)
		if ok then
			going = status == Enum.RsvpStatus.Going
		end
	end
	return going
end

-- Opens Roblox's sign-up prompt (yields until it closes). One at a time.
function EventRsvp.Prompt()
	if prompting then
		return
	end
	prompting = true
	local ok, status = pcall(SocialService.PromptRsvpToEventAsync, SocialService, EventConstants.EVENT_ID)
	prompting = false
	if not ok then
		warn("EventRsvp: sign-up prompt failed:", status)
		return
	end
	local now = status == Enum.RsvpStatus.Going
	if now ~= going then
		going = now
		EventRsvp.Changed:Fire(now)
	end
end

return EventRsvp
