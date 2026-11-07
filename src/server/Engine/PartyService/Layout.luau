--| PartyService · Layout
-- Lays out a Party Stage's spots for however many the host allows (2 for a Normal Duel,
-- 3–6 for a free-for-all): each spot is a copy of ServerStorage.PartyKit.Spot (the pad you
-- stand on, the platform + ring, the mic stand), spread evenly round the circle with the
-- steps left in a gap. Like the duel stages, each mic stands between its spot and the
-- middle, facing the player. Parts are named like the duel stages' own
-- (SpotPlatform<i>, MicStand<i> … in Visual), so StageCosmetics draws each player's equipped
-- stage + mic on their spot the same way. Build() replaces whatever spots were there.

local ServerStorage = game:GetService("ServerStorage")

local Layout = {}

local FFA_RADIUS = 7.8 -- 3+ spots sit further out so the mics fit inside the ring

local VISUAL_PARTS = { "SpotPlatform", "SpotPlatform_Ring", "MicStand", "Mic", "MicGrille" }

local function clear(model: Model)
	local spots = model:FindFirstChild("Spots")
	if spots then
		spots:ClearAllChildren()
	end
	local visual = model:FindFirstChild("Visual")
	if visual then
		for _, c in visual:GetChildren() do
			for _, base in VISUAL_PARTS do
				if c.Name:match("^" .. base .. "%d+$") or c.Name:match("^SpotPlatform%d+_Ring$") then
					c:Destroy()
					break
				end
			end
		end
	end
	for _, c in model:GetChildren() do
		if c.Name:match("^Cosmetic") then
			c:Destroy()
		end
	end
end

-- Returns { [i] = pad } for spots 1..count.
function Layout.Build(model: Model, count: number): { [number]: BasePart }
	clear(model)
	local kit = ServerStorage:FindFirstChild("PartyKit")
	local template = kit and kit:FindFirstChild("Spot") :: Model?
	local centrePart = model:FindFirstChild("RigSpot") :: BasePart?
	if not (template and centrePart) then
		warn(`[Party] {model.Name}: needs ServerStorage.PartyKit.Spot and a RigSpot`)
		return {}
	end
	local visual = model:FindFirstChild("Visual") :: Instance
	local spotsFolder = model:FindFirstChild("Spots") or Instance.new("Folder")
	spotsFolder.Name = "Spots"
	spotsFolder.Parent = model

	local centre = centrePart.Position
	local radius = if count > 2 then FFA_RADIUS else template:GetAttribute("Radius") or 6.9
	local height = template:GetAttribute("Height") or 0.7
	-- the steps sit in the gap between the last spot and the first
	local steps = visual and visual:FindFirstChild("Stage_Steps") :: BasePart?
	local toSteps = if steps then (steps.Position - centre) * Vector3.new(1, 0, 1) else Vector3.new(-1, 0, 0)
	if toSteps.Magnitude < 1e-3 then
		toSteps = Vector3.new(-1, 0, 0)
	end
	local base = math.atan2(toSteps.Z, toSteps.X)

	local pads = {}
	for i = 1, count do
		local angle = base + (i - 0.5) * (2 * math.pi / count)
		local at = centre + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
		local spot = template:Clone()
		-- the kit's own frame: from its pad towards its mic stand (whatever way it was built)
		local pad, stand = spot:FindFirstChild("Pad") :: BasePart, spot:FindFirstChild("MicStand") :: BasePart
		local padAt = pad.Position
		spot.PrimaryPart = nil -- else PivotTo goes by the pad's own rotation
		spot.WorldPivot = CFrame.lookAt(padAt, Vector3.new(stand.Position.X, padAt.Y, stand.Position.Z))
		spot:PivotTo(CFrame.lookAt(at, Vector3.new(centre.X, at.Y, centre.Z)))
		for _, part in spot:GetChildren() do
			if part.Name == "Pad" then
				part.Name = "Spot" .. i
				part.Parent = spotsFolder
				pads[i] = part
			elseif part.Name == "SpotPlatform_Ring" then
				part.Name = `SpotPlatform{i}_Ring`
				part.Parent = visual
			else
				part.Name = part.Name .. i
				part.Parent = visual
			end
		end
		spot:Destroy()
	end
	return pads
end

return Layout
