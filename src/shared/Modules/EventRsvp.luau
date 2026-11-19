--| EventRsvp
-- Client only. The event the HUD button points at (ReplicatedStorage attribute
-- EventConstants.ATTRIBUTE, set from Configs by Server/EventConfigService) and the local
-- player's sign-up to it, through Roblox's own RSVP prompt (SocialService). The HUD button and
-- the world's "Notify me" prompts share it, so signing up at one updates the other (Changed).
-- Info() asks Roblox for the event (title, times, RSVP) once per ID; if it can't (Studio), it
-- falls back to EventConstants.EVENTS[id] and Going is nil. Test sign-ups in a published game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Signal = require(ReplicatedStorage.Packages.signal)
local EventConstants = require(ReplicatedStorage.Constants.EventConstants)

export type Phase = "Before" | "Live" | "Over"
export type Info = {
	Id: string,
	Title: string,
	Icon: string,
	Starts: number,
	Ends: number,
	Going: boolean?, -- nil if Roblox couldn't say
	Live: { Name: string, Opens: string }?,
}

local EventRsvp = {}

-- fires () when the event changes (Configs) or the player signs up / backs out
EventRsvp.Changed = Signal.new()

local cache: { [string]: Info | false } = {}
local loading: { [string]: boolean } = {}
local prompting = false

local function unix(t: { [string]: number }): number
	return DateTime.fromUniversalTime(t.Year, t.Month, t.Day, t.Hour, t.Minute, t.Second, t.Millisecond or 0).UnixTimestamp
end

-- The configured event ID, or nil if there's none (Configs set to "").
function EventRsvp.Id(): string?
	local id = ReplicatedStorage:GetAttribute(EventConstants.ATTRIBUTE)
	if type(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

-- Yields the first time per event. nil if there's no event or Roblox doesn't know it.
function EventRsvp.Info(): Info?
	local id = EventRsvp.Id()
	if not id then
		return nil
	end
	while loading[id] do
		task.wait()
	end
	local cached = cache[id]
	if cached ~= nil then
		return cached or nil
	end
	loading[id] = true
	local extra = EventConstants.EVENTS[id] or {}
	local info: Info? = nil
	local ok, event = pcall(SocialService.GetExperienceEventAsync, SocialService, id)
	if ok and event then
		local title = if event.DisplayTitle ~= "" then event.DisplayTitle else event.Title
		info = {
			Id = id,
			Title = extra.Name or title,
			Icon = extra.Icon or EventConstants.ICON,
			Starts = unix(event.StartTime),
			Ends = unix(event.EndTime),
			Going = if event.UserRsvpStatus then event.UserRsvpStatus == Enum.RsvpStatus.Going else nil,
			Live = extra.Live,
		}
	elseif extra.Starts and extra.Ends then
		info = {
			Id = id,
			Title = extra.Name or "Event",
			Icon = extra.Icon or EventConstants.ICON,
			Starts = extra.Starts, Ends = extra.Ends,
			Live = extra.Live,
		}
	end
	if info and info.Going == nil then
		local okStatus, status = pcall(SocialService.GetEventRsvpStatusAsync, SocialService, id)
		if okStatus then
			info.Going = status == Enum.RsvpStatus.Going
		end
	end
	cache[id] = info or false
	loading[id] = nil
	return info
end

function EventRsvp.Phase(info: Info): Phase
	local now = os.time()
	if now < info.Starts then
		return "Before"
	elseif now < info.Ends then
		return "Live"
	end
	return "Over"
end

-- Time until the event starts, for the HUD: "14d", then "5h" on the last day, then "30m".
function EventRsvp.Countdown(info: Info): string
	local left = math.max(0, info.Starts - os.time())
	if left >= 86400 then
		return `{math.ceil(left / 86400)}d`
	elseif left >= 3600 then
		return `{math.ceil(left / 3600)}h`
	end
	return `{math.max(1, math.ceil(left / 60))}m`
end

-- Opens Roblox's sign-up prompt for the current event (yields until it closes). One at a time.
function EventRsvp.Prompt()
	local info = EventRsvp.Info()
	if prompting or not info then
		return
	end
	prompting = true
	local ok, status = pcall(SocialService.PromptRsvpToEventAsync, SocialService, info.Id)
	prompting = false
	if not ok then
		warn("EventRsvp: sign-up prompt failed:", status)
		return
	end
	local now = status == Enum.RsvpStatus.Going
	if now ~= info.Going then
		info.Going = now
		EventRsvp.Changed:Fire()
	end
end

ReplicatedStorage:GetAttributeChangedSignal(EventConstants.ATTRIBUTE):Connect(function()
	EventRsvp.Changed:Fire()
end)

return EventRsvp
