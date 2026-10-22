--| StageLock
-- While you're on a duel stage (the server sets your "Stage" attribute), your controls are
-- switched off and your character is held still on this client too. Without this, keys still
-- held from walking up to the stage keep the walk animation going and the client keeps
-- pushing an anchored character around, which shakes the duel camera.

local Players = game:GetService("Players")

local LOCAL_PLAYER = Players.LocalPlayer

local StageLock = {}

local controls = nil

local function getControls()
	if controls then
		return controls
	end
	local scripts = LOCAL_PLAYER:WaitForChild("PlayerScripts")
	local playerModule = scripts:WaitForChild("PlayerModule", 10)
	if playerModule then
		local ok, module = pcall(require, playerModule)
		if ok and module and module.GetControls then
			controls = module:GetControls()
		end
	end
	return controls
end

local function settle(character: Model?)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid:Move(Vector3.zero)
	-- drop whatever walk/run animation was playing; Animate goes back to idle on its own
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			local name = track.Animation and track.Animation.Name or ""
			if name:lower():find("walk") or name:lower():find("run") then
				track:Stop(0.1)
			end
		end
	end
	humanoid:ChangeState(Enum.HumanoidStateType.Running)
end

local function apply()
	local onStage = LOCAL_PLAYER:GetAttribute("Stage") ~= nil
	local c = getControls()
	if c then
		if onStage then
			c:Disable()
		else
			c:Enable()
		end
	end
	if onStage then
		settle(LOCAL_PLAYER.Character)
	end
end

function StageLock.Start()
	LOCAL_PLAYER:GetAttributeChangedSignal("Stage"):Connect(apply)
	LOCAL_PLAYER.CharacterAdded:Connect(function()
		task.defer(apply)
	end)
	task.spawn(apply)
end

return StageLock
