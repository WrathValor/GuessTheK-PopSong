--| RemoteCodes
-- Shop codes from a text file on GitHub, so codes can be added or ended without touching
-- Studio (RewardsCatalog.CODES_URL). Read when the server starts and every REFRESH seconds
-- after; if a read fails, the last good list stays. RewardsService looks codes up here as
-- well as in RewardsCatalog.CODES (a code in both uses the file's).
-- File format: RewardsCatalog.ParseCodes (one code a line, or JSON). Needs Game Settings →
-- Security → Allow HTTP Requests.
--   RemoteCodes.Start()
--   RemoteCodes.Get("LAUNCH")   -- the code's entry (like a RewardsCatalog.CODES entry), or nil

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Catalog = require(ReplicatedStorage.Constants.RewardsCatalog)

local REFRESH = 60 -- seconds between reads

local RemoteCodes = {}

local codes: { [string]: any } = {}
local started = false

local function read(): boolean
	-- (the query string dodges any cached copy of the file)
	local url = `{Catalog.CODES_URL}?t={os.time()}`
	local ok, body = pcall(HttpService.GetAsync, HttpService, url, true)
	if not ok then
		warn("[RemoteCodes] couldn't read the codes file:", body)
		return false
	end
	local parsed, problems = Catalog.ParseCodes(body)
	for _, p in problems do
		warn("[RemoteCodes]", p)
	end
	if not parsed then
		return false -- (broken JSON: keep the last good list)
	end
	codes = parsed
	return true
end

function RemoteCodes.Get(code: string)
	return codes[code]
end

function RemoteCodes.Start()
	if started or (Catalog.CODES_URL or "") == "" then
		return
	end
	started = true
	if not HttpService.HttpEnabled then
		if RunService:IsStudio() then
			warn("[RemoteCodes] HTTP requests are off (Game Settings → Security): only RewardsCatalog.CODES work")
		end
		return
	end
	task.spawn(function()
		while true do
			read()
			task.wait(REFRESH)
		end
	end)
end

return RemoteCodes
