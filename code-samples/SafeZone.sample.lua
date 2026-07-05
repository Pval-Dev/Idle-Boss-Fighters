-- SafeZone.sample.lua
-- Technical portfolio excerpt from Idle Boss Fighters.
--
-- This sample demonstrates:
-- - Runtime fault tolerance
-- - Entity position validation
-- - Physics state recovery
-- - Per-plot monitoring
-- - Automatic NPC and boss repositioning
--
-- This is not the full production script.
-- It is a curated implementation sample for portfolio review.

local SafeZone = {}

local SAFE_RADIUS = 150
local CHECK_INTERVAL = 0.5

-- ============================================================
-- Default Position Resolution
-- ============================================================
-- Resolves the expected recovery position for a runtime entity
-- inside an isolated player environment.

local function getDefaultPosition(plot, modelName)
	local defaultFolder = plot:FindFirstChild("DefaultPos")

	if not defaultFolder then
		return nil
	end

	return defaultFolder:FindFirstChild(modelName .. "Pos")
end

-- ============================================================
-- Physics State Recovery
-- ============================================================
-- Stops accumulated physics velocity, restores humanoid control
-- and moves the entity back to a valid runtime position.

local function resetModel(model, targetCFrame)
	if not model or not targetCFrame then
		return
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")

	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.CFrame = targetCFrame
	end

	if humanoid then
		humanoid.PlatformStand = false
	end

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
end

-- ============================================================
-- Entity Validation
-- ============================================================
-- Checks whether a model has moved outside the allowed runtime
-- radius and restores it if necessary.

local function validateEntity(plot, folderName, modelName, verticalOffset)
	local defaultPart = getDefaultPosition(plot, modelName)

	if not defaultPart then
		return
	end

	local folder = plot:FindFirstChild(folderName)

	if not folder then
		return
	end

	local model = folder:FindFirstChild(modelName)

	if not model then
		return
	end

	local root = model:FindFirstChild("HumanoidRootPart")

	if not root then
		return
	end

	local distance = (root.Position - defaultPart.Position).Magnitude

	if distance <= SAFE_RADIUS then
		return
	end

	local recoveryCFrame =
		defaultPart.CFrame * CFrame.new(0, verticalOffset or 0, 0)

	resetModel(model, recoveryCFrame)
end

-- ============================================================
-- Plot-Level Monitoring
-- ============================================================
-- Starts a lightweight recovery loop for a single player plot.
-- This keeps fault tolerance scoped to the player's runtime world.

function SafeZone.start(plot)
	task.spawn(function()
		while plot and plot.Parent do
			task.wait(CHECK_INTERVAL)

			local defaultFolder = plot:FindFirstChild("DefaultPos")

			if not defaultFolder then
				continue
			end

			validateEntity(plot, "NPCs", "Gladiator", 0)
			validateEntity(plot, "NPCs", "Brawler", 0)
			validateEntity(plot, "NPCs", "ShieldMan", 0)

			validateEntity(plot, "Boss", "Boss", 10)
		end
	end)
end

return SafeZone
