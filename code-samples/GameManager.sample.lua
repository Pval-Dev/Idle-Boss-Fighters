-- GameManager.sample.lua
-- Technical portfolio excerpt from Idle Boss Fighters.
--
-- This sample demonstrates:
-- - Player lifecycle orchestration
-- - Persistent data loading and saving
-- - Save throttling
-- - Runtime battle coordination
-- - Fault tolerance through entity recovery
-- - Communication channel validation
--
-- This is not the full production script.
-- It is a curated implementation sample for portfolio review.

local GameManager = {}
GameManager.__index = GameManager

GameManager.players = {}

-- Dependencies shown as architectural references.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local playerDataStore = DataStoreService:GetDataStore("PlayerDataStore")

local PlayerData = require(script.Parent.Data.PlayerData)
local PlotManager = require(script.Parent.Data.PlotManager)
local GameLoop = require(script.Parent.Systems.GameLoop)
local GemSpawner = require(script.Parent.Systems.GemSpawner)
local AnalyticsService = require(script.Parent.Systems.AnalyticsService)
local BigNum = require(script.Parent.Helpers.BigNum)

-- ============================================================
-- Persistent Data Loading
-- ============================================================
-- Responsible for loading persistent player state,
-- recovering saved progression and applying offline rewards.

function GameManager:loadPlayerData(userId, plot)
	local data = nil
	local maxRetries = 3

	for attempt = 1, maxRetries do
		local success, result = pcall(function()
			return playerDataStore:GetAsync(tostring(userId))
		end)

		if success then
			data = result
			break
		end

		if attempt < maxRetries then
			task.wait(1)
		end
	end

	local currentTime = os.time()
	local playerData = PlayerData.new(userId, plot)
	local offlineSeconds = 0

	if data then
		playerData:deserialize(data)

		local lastSave = data.lastSave or data.createdAt or currentTime
		offlineSeconds = math.max(0, currentTime - lastSave)
	end

	if offlineSeconds > 60 then
		local offlineGemValue = playerData:calculateOfflineGemValue(offlineSeconds)

		if BigNum.gt(offlineGemValue, 0) then
			GemSpawner.spawnOfflineGem(
				plot,
				offlineGemValue,
				playerData.currentBoss.nivel
			)
		end
	end

	playerData.lastSave = currentTime

	return playerData
end

-- ============================================================
-- Save Throttling
-- ============================================================
-- Prevents excessive persistence writes by delaying repeated
-- save requests within a short cooldown window.

GameManager.saveCooldown = 8
GameManager._lastSaveAttempt = {}
GameManager._pendingSave = {}

function GameManager:savePlayerData(userId)
	local lastSave = self._lastSaveAttempt[userId]

	if lastSave and (os.clock() - lastSave) < self.saveCooldown then
		if not self._pendingSave[userId] then
			self._pendingSave[userId] = true

			local delayTime = self.saveCooldown - (os.clock() - lastSave)

			task.delay(delayTime, function()
				self._pendingSave[userId] = nil

				if self.players[userId] then
					self:forceSavePlayerData(userId)
				end
			end)
		end

		return true
	end

	return self:forceSavePlayerData(userId)
end

function GameManager:forceSavePlayerData(userId)
	local playerData = self.players[userId]

	if not playerData then
		return false
	end

	playerData.lastSave = os.time()

	local serializedData = playerData:serialize()
	local maxRetries = 3

	for attempt = 1, maxRetries do
		local success = pcall(function()
			playerDataStore:UpdateAsync(tostring(userId), function()
				return serializedData
			end)
		end)

		if success then
			self._lastSaveAttempt[userId] = os.clock()
			return true
		end

		if attempt < maxRetries then
			task.wait(1)
		end
	end

	self._lastSaveAttempt[userId] = os.clock()

	return false
end

-- ============================================================
-- Player Lifecycle Orchestration
-- ============================================================
-- Coordinates plot ownership, data restoration, runtime systems,
-- cosmetics, quests, analytics and continuous gameplay loops.

function GameManager:onPlayerJoined(player)
	local plot = PlotManager.AssignPlot(player)

	if not plot then
		warn("No available plot for player:", player.Name)
		return nil
	end

	local playerData = self:loadPlayerData(player.UserId, plot)

	AnalyticsService.OnPlayerJoined(player)

	self.players[player.UserId] = playerData

	GameLoop.applySkinsToNPCs(playerData)
	GameLoop.applyHealthDistribution(playerData)

	playerData:applyAllNPCAuras()
	playerData:applyPlayerAuraToCharacter()

	self:startHudLoop(player.UserId)
	self:startProcessorLoop(player.UserId)
	self:startBattleLoop(player.UserId)
	self:startNPCGuard(player.UserId)
	self:setupLeaderstats(player, playerData)

	return playerData
end

function GameManager:onPlayerLeaving(player)
	AnalyticsService.OnPlayerLeaving(player)

	self:forceSavePlayerData(player.UserId)

	PlotManager.ReleasePlot(player)

	self.players[player.UserId] = nil
end

-- ============================================================
-- Runtime Battle Coordination
-- ============================================================
-- Executes the continuous combat loop and reacts to battle
-- outcomes such as victory, timeout or reset states.

function GameManager:startBattleLoop(userId)
	task.spawn(function()
		task.wait(1)

		while self.players[userId] do
			local playerData = self.players[userId]

			if not playerData then
				break
			end

			GameLoop.applyHealthDistribution(playerData)

			if playerData.npcs.melee then
				playerData.npcs.melee:reset()
			end

			if playerData.npcs.brawler then
				playerData.npcs.brawler:reset()
			end

			if playerData.npcs.tank then
				playerData.npcs.tank:reset()
			end

			playerData.midDropCount = 0
			playerData._pendingGems = nil

			local result = GameLoop.startBattle(
				playerData,
				playerData.currentBoss
			)

			if result.bossDefeated then
				if playerData._pendingGems and #playerData._pendingGems > 0 then
					GemSpawner.spawnGems(playerData.plot, playerData._pendingGems)
					playerData._pendingGems = nil
				end

				local defeatedLevel = playerData.currentBoss.nivel

				playerData.bossesDefeated =
					(playerData.bossesDefeated or 0) + 1

				local Boss = require(script.Parent.Classes.Boss)
				playerData.currentBoss =
					Boss.new(playerData.plot, defeatedLevel + 1, playerData)

				GameLoop.applySkinsToNPCs(playerData)
				GameLoop.applyHealthDistribution(playerData)
				playerData:applyAllNPCAuras()

				self:savePlayerData(userId)

				task.wait(2)

			elseif result.timeout then
				playerData.currentBoss:reset()
				GameLoop.applyHealthDistribution(playerData)

				task.wait(2)

			else
				playerData.currentBoss:reset()

				task.wait(2)
			end

			task.wait(0.5)
		end
	end)
end

-- ============================================================
-- Runtime Entity Recovery
-- ============================================================
-- Validates critical runtime entities and rebuilds missing
-- NPC or boss instances when physics/runtime anomalies occur.

function GameManager:startNPCGuard(userId)
	task.spawn(function()
		task.wait(4)

		while self.players[userId] do
			task.wait(3)

			local playerData = self.players[userId]

			if not playerData then
				break
			end

			local plot = playerData.plot
			local needsReset = false

			local npcChecks = {
				{ object = playerData.npcs.melee, modelName = "Gladiator" },
				{ object = playerData.npcs.brawler, modelName = "Brawler" },
				{ object = playerData.npcs.tank, modelName = "ShieldMan" },
			}

			for _, check in ipairs(npcChecks) do
				local model = plot.NPCs:FindFirstChild(check.modelName)
				local root = model and model:FindFirstChild("HumanoidRootPart")

				if not root then
					needsReset = true
					break
				end
			end

			if not needsReset then
				local bossModel = plot.Boss:FindFirstChild("Boss")
				local bossRoot =
					bossModel and bossModel:FindFirstChild("HumanoidRootPart")

				if not bossRoot then
					needsReset = true
				end
			end

			if needsReset then
				local NPC = require(script.Parent.Classes.NPC)
				local Boss = require(script.Parent.Classes.Boss)

				playerData.npcs.melee =
					NPC.new(plot, "melee", playerData)

				playerData.npcs.brawler =
					NPC.new(plot, "brawler", playerData)

				playerData.npcs.tank =
					NPC.new(plot, "tank", playerData)

				playerData.currentBoss =
					Boss.new(plot, playerData.currentBoss.nivel, playerData)

				GameLoop.applySkinsToNPCs(playerData)
				GameLoop.applyHealthDistribution(playerData)
				playerData:applyAllNPCAuras()
			end
		end
	end)
end

-- ============================================================
-- Communication Channel Factory
-- ============================================================
-- Creates or validates client-server communication channels.
-- This prevents inconsistent runtime interfaces.

local PlayerRemotes = ReplicatedStorage:FindFirstChild("PlayerRemotes")

if not PlayerRemotes then
	PlayerRemotes = Instance.new("Folder")
	PlayerRemotes.Name = "PlayerRemotes"
	PlayerRemotes.Parent = ReplicatedStorage
end

local function ensureRemote(name, remoteType)
	local existing = PlayerRemotes:FindFirstChild(name)

	if existing then
		if existing:IsA(remoteType) then
			return existing
		end

		existing:Destroy()
	end

	local remote = Instance.new(remoteType)
	remote.Name = name
	remote.Parent = PlayerRemotes

	return remote
end

-- ============================================================
-- Validated Request Handling
-- ============================================================
-- Server-side request handlers validate player state before
-- modifying persistent progression or cosmetic ownership.

local GetQuests = ensureRemote("GetQuests", "RemoteFunction")

GetQuests.OnServerInvoke = function(player)
	local playerData = GameManager.players[player.UserId]

	if not playerData then
		return nil
	end

	local QuestService = require(script.Parent.QuestService.QuestService)

	return {
		daily = QuestService.GetDailyQuests(playerData),
		permanent = QuestService.GetPermanentQuests(playerData),
		infinite = QuestService.GetInfiniteQuests(playerData),
	}
end

local ClaimQuest = ensureRemote("ClaimQuest", "RemoteEvent")

ClaimQuest.OnServerEvent:Connect(function(player, group, questId)
	local playerData = GameManager.players[player.UserId]

	if not playerData then
		return
	end

	local QuestService = require(script.Parent.QuestService.QuestService)

	local success = QuestService.ClaimQuest(playerData, group, questId)

	if success then
		GameManager:savePlayerData(player.UserId)
	end
end)

-- ============================================================
-- Graceful Shutdown Persistence
-- ============================================================
-- Forces pending player data to be saved during server shutdown.

game:BindToClose(function()
	local pendingSaves = {}

	for userId in pairs(GameManager.players) do
		table.insert(pendingSaves, userId)
	end

	if #pendingSaves == 0 then
		return
	end

	local completed = 0

	for _, userId in ipairs(pendingSaves) do
		task.spawn(function()
			GameManager:forceSavePlayerData(userId)
			completed += 1
		end)
	end

	local elapsed = 0

	while completed < #pendingSaves and elapsed < 25 do
		task.wait(0.1)
		elapsed += 0.1
	end
end)

return GameManager
