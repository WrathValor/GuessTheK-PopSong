--| Run
-- Runs every *.spec module in ServerStorage.Tests with Jest Lua (DevPackages, from wally.toml's
-- [dev-dependencies]). A ModuleScript, not a Script, so nothing runs in a live server. From the
-- Studio command bar (Edit mode is fine):
--   require(game.ServerStorage.Tests.Run)()
-- Returns true when everything passed. Jest Lua needs { "FFlagEnableLoadModule": true } in
-- Studio's ClientSettings/ClientAppSettings.json (in the Studio version folder; a Studio update
-- can wipe it, so add it again if Jest says loadmodule is missing).

local ServerStorage = game:GetService("ServerStorage")

local Jest = require(ServerStorage.DevPackages.Jest)

return function(): boolean
	local tests = script.Parent
	local status, result = Jest.runCLI(tests, { verbose = false, ci = false }, { tests }):awaitStatus()
	if status == "Rejected" then
		warn(`[Tests] Jest didn't run: {tostring(result)}`)
		return false
	end
	local r = result.results
	local passed = r.numFailedTestSuites == 0 and r.numFailedTests == 0
	print(`[Tests] {r.numPassedTests} passed, {r.numFailedTests} failed ({r.numTotalTestSuites} files)`)
	return passed
end
