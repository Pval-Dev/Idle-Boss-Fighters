-- PlotManager.sample.lua
-- Technical portfolio excerpt from Idle Boss Fighters.
--
-- This sample demonstrates:
-- - Runtime resource allocation
-- - Per-player world ownership
-- - Plot lookup by player identity
-- - Spatial ownership resolution
-- - Resource cleanup on player leave
--
-- This is not the full production script.
-- It is a curated implementation sample for portfolio review.

local PlotManager = {}

local plotsFolder = workspace:WaitForChild("Plots")

-- ============================================================
-- Plot Assignment
-- ============================================================
-- Assigns the first available runtime environment to a player.
-- Each plot becomes exclusively owned by one player through
-- lightweight metadata attributes.

function PlotManager.AssignPlot(player)
	for _, plot in ipairs(plotsFolder:GetChildren()) do
		if not plot:GetAttribute("Claimed") then
			plot:SetAttribute("Claimed", true)
			plot:SetAttribute("OwnerId", player.UserId)

			return plot
		end
	end

	warn("No available plots")

	return nil
end

-- ============================================================
-- Ownership Lookup
-- ============================================================
-- Resolves the plot owned by a specific player.
-- This is used by gameplay systems to validate rewards,
-- interactions and world references.

function PlotManager.GetPlayerPlot(player)
	for _, plot in ipairs(plotsFolder:GetChildren()) do
		if plot:GetAttribute("OwnerId") == player.UserId then
			return plot
		end
	end

	return nil
end

-- ============================================================
-- Spatial Ownership Resolution
-- ============================================================
-- Resolves the plot associated with a world object.
-- Useful for interaction validation when a player touches or
-- activates an object inside a runtime environment.

function PlotManager.GetPlotFromPart(part)
	local plot = part:FindFirstAncestorWhichIsA("Model")

	if plot and plot.Parent == workspace.Plots then
		return plot
	end

	return nil
end

-- ============================================================
-- Spawn Resolution
-- ============================================================
-- Finds the player's spawn location inside the assigned runtime
-- environment. Recursive search supports nested plot structures.

function PlotManager.GetSpawnPart(plot)
	return plot:FindFirstChild("Spawn", true)
end

-- ============================================================
-- Plot Release
-- ============================================================
-- Releases runtime ownership when a player leaves.
-- This prevents stale ownership and allows the environment to
-- be reassigned safely.

function PlotManager.ReleasePlot(player)
	local plot = PlotManager.GetPlayerPlot(player)

	if not plot then
		return
	end

	plot:SetAttribute("Claimed", false)
	plot:SetAttribute("OwnerId", 0)
end

return PlotManager
