-- PlayerData.sample.lua
-- Technical portfolio excerpt from Idle Boss Fighters.
--
-- This sample demonstrates:
-- - Persistent player profile modeling
-- - Incremental economy state
-- - Upgrade progression
-- - Resource processing
-- - Serialization and deserialization
-- - Backward-compatible data recovery
-- - Guided tutorial state progression
--
-- This is not the full production script.
-- It is a curated implementation sample for portfolio review.

local PlayerData = {}
PlayerData.__index = PlayerData

local Boss = require(script.Parent.Parent.Classes.Boss)
local NPC = require(script.Parent.Parent.Classes.NPC)
local Config = require(script.Parent.Config)
local BigNum = require(game.ServerScriptService.Modules.Helpers.BigNum)

-- ============================================================
-- Default Player Statistics
-- ============================================================
-- Defines the initial progression surface for combat, economy
-- and health distribution systems.

local function getDefaultStats()
	return {
		gladiatorDamage = 0,
		gladiatorCritChance = 0,
		gladiatorCritMultiplier = 0,
		gladiatorCoreDamage = 0,

		brawlerDamage = 0,
		brawlerCritChance = 0,
		brawlerCritMultiplier = 0,
		brawlerCoreDamage = 0,

		shieldTeamHealth = 0,
		shieldDamageReduction = 0,
		shieldRegeneration = 0,
		shieldAggro = 0,

		dualChance = 0,
		tripleChance = 0,
		dualPower = 0,
		triplePower = 0,

		backpackCapacity = 0,
		processorSpeed = 0,

		healthMeleePercent = 15,
		healthBrawlerPercent = 15,
		healthTankPercent = 70,
	}
end

-- ============================================================
-- Player Profile Construction
-- ============================================================
-- Builds the runtime player profile, including persistent state,
-- combat entities, economy values, cosmetics and progression.

function PlayerData.new(userId, plot)
	local self = setmetatable({}, PlayerData)

	self.userId = userId
	self.plot = plot

	self.createdAt = os.time()
	self.lastSave = os.time()
	self.version = Config.PLAYER_DATA_VERSION

	self.bossesDefeated = 0
	self.currentBoss = Boss.new(plot, 1, self)

	self.money = BigNum.new(150)
	self.unclaimedMoney = BigNum.new(0)
	self.gems = BigNum.new(0)
	self.gemsInProcessor = BigNum.new(0)
	self.processingQueue = BigNum.new(0)

	self.stats = getDefaultStats()
	self.stats.gladiatorDamage = 3
	self.stats.brawlerDamage = 3
	self.stats.shieldTeamHealth = 3

	self.healthDistribution = {
		melee = 15,
		brawler = 15,
		tank = 70,
	}

	self.npcs = {
		melee = NPC.new(plot, "melee", self),
		brawler = NPC.new(plot, "brawler", self),
		tank = NPC.new(plot, "tank", self),
	}

	self.skins = {
		gladiator = { equipped = "BASIC", unlocked = { BASIC = true } },
		brawler = { equipped = "BASIC", unlocked = { BASIC = true } },
		tank = { equipped = "BASIC", unlocked = { BASIC = true } },
		boss = { equipped = "BASIC", unlocked = { BASIC = true } },
	}

	self.npcAuras = {
		gladiator = { equipped = nil, unlocked = {} },
		brawler = { equipped = nil, unlocked = {} },
		tank = { equipped = nil, unlocked = {} },
		boss = { equipped = nil, unlocked = {} },
	}

	self.playerAuras = {
		equipped = nil,
		unlocked = {},
	}

	self.dealerTickets = {
		skin = 3,
		aura = 3,
	}

	self.rewards = {
		groupJoined = false,
		likeGiven = false,
		tutorialSeen = false,
	}

	self.tutorialState = {
		active = false,
		step = 0,
		bossCount = 0,
		requiredBosses = 2,
	}

	self.multipliers = {
		gemDrop = 1,
		moneyMultiplier = 1,
		processorSpeed = 1,
		damage = 1,
		offlineBoost = 1,
	}

	self.gamepasses = {
		gemDrop_x2 = false,
		gemDrop_x5 = false,
		gemDrop_x10 = false,

		money_x2 = false,
		money_x5 = false,
		money_x10 = false,

		damage_x2 = false,
		damage_x5 = false,
		damage_x10 = false,

		offlineBoost = false,
		autoPickup = false,
		instantProcessor = false,
		vip = false,
		autoForge = false,
	}

	self.activeBoosts = {}
	self.boostQueue = {
		money = {},
		gems = {},
		damage = {},
		processor = {},
	}

	self.keys = {}
	self.titleState = {
		unlocked = {},
		active = nil,
	}

	return self
end

-- ============================================================
-- Upgrade Progression
-- ============================================================
-- Converts currency into permanent stat progression using
-- configurable cost formulas and effective-level calculations.

function PlayerData:getEffectiveLevel(statName)
	local upgrades = self.stats[statName] or 0
	local steps = Config.STATS_STEPS_PER_LEVEL[statName] or 3

	return math.floor(upgrades / steps)
end

function PlayerData:getProgress(statName)
	local upgrades = self.stats[statName] or 0
	local steps = Config.STATS_STEPS_PER_LEVEL[statName] or 3

	return upgrades % steps
end

function PlayerData:buyUpgrade(statName)
	local currentUpgrades = self.stats[statName] or 0
	local cost = Config:getUpgradeCost(statName, currentUpgrades)

	if BigNum.lt(self.money, cost) then
		return false, nil, cost, nil
	end

	self.money = BigNum.sub(self.money, cost)
	self.stats[statName] = currentUpgrades + 1

	local newEffectiveLevel = self:getEffectiveLevel(statName)

	self:addTutorialProgress("UpgradePurchased")

	return true, newEffectiveLevel, cost, self.stats[statName]
end

-- ============================================================
-- Stat Resolution
-- ============================================================
-- Resolves final stat values from upgrade levels, formulas
-- and cosmetic modifiers.

function PlayerData:getStatValue(statName)
	local effectiveLevel = self:getEffectiveLevel(statName)
	local formula = Config.STAT_FORMULAS[statName]

	if not formula then
		return 0
	end

	local baseValue = formula(effectiveLevel)
	local npcType = nil

	if statName:find("gladiator") then
		npcType = "gladiator"
	elseif statName:find("brawler") then
		npcType = "brawler"
	elseif statName:find("shield") then
		npcType = "tank"
	end

	if npcType then
		local bonus = self:getSkinBonus(npcType)

		if statName == "gladiatorDamage" or statName == "brawlerDamage" then
			baseValue = BigNum.mul(baseValue, bonus.damage_mult or 1)

		elseif statName == "gladiatorCritChance" or statName == "brawlerCritChance" then
			baseValue = baseValue + (bonus.crit_chance_add or 0)

		elseif statName == "gladiatorCritMultiplier" or statName == "brawlerCritMultiplier" then
			baseValue = baseValue * (bonus.crit_damage_mult or 1)

		elseif statName == "shieldTeamHealth" then
			baseValue = BigNum.mul(baseValue, bonus.health_mult or 1)
		end
	end

	return baseValue
end

function PlayerData:getSkinBonus(npcType)
	local equippedSkin = self:getEquippedSkin(npcType)

	local key =
		npcType == "gladiator" and "GLADIATOR"
		or npcType == "brawler" and "BRAWLER"
		or npcType == "tank" and "ESCUDERO"
		or "BOSS"

	local skinConfig =
		Config.SKINS
		and Config.SKINS[key]
		and Config.SKINS[key][equippedSkin]

	if skinConfig and skinConfig.bonus then
		return skinConfig.bonus
	end

	return {}
end

-- ============================================================
-- Resource Acquisition
-- ============================================================
-- Applies multipliers, group rewards and quest progress when
-- resources enter the player's economy.

function PlayerData:addGems(amount)
	if type(amount) == "number" then
		amount = BigNum.new(amount)
	end

	local BoostService = require(script.Parent.Parent.Systems.BoostService)

	local multiplier =
		(self.multipliers.gemDrop or 1)
		* BoostService.getMultiplier(self, "gems")

	if self.rewards and self.rewards.groupJoined then
		multiplier *= 1.2
	end

	local finalAmount = BigNum.mul(amount, multiplier)

	self.gems = BigNum.add(self.gems, finalAmount)

	local QuestService = require(script.Parent.Parent.QuestService.QuestService)
	local numericAmount = tonumber(tostring(finalAmount)) or 0

	QuestService.AddProgress(self, "GemsCollected", numericAmount)

	self:addTutorialProgress("GemCollected")
end

-- ============================================================
-- Resource Processing
-- ============================================================
-- Converts collected resources into claimable currency through
-- a controlled processing queue.

function PlayerData:emptyBackpackToProcessor()
	if BigNum.le(self.gems, 0) then
		return
	end

	self.gemsInProcessor = BigNum.add(self.gemsInProcessor, self.gems)
	self.processingQueue = BigNum.add(self.processingQueue, self.gems)
	self.gems = BigNum.new(0)

	self:addTutorialProgress("ProcessorUsed")
end

function PlayerData:processGems(deltaTime)
	local BoostService = require(script.Parent.Parent.Systems.BoostService)

	if self.gamepasses.autoForge then
		self:emptyBackpackToProcessor()
	end

	if BigNum.le(self.processingQueue, 0) then
		return BigNum.new(0)
	end

	if self.gamepasses.instantProcessor then
		return self:instantProcessAll()
	end

	local speed = self:getStatValue("processorSpeed")
	local speedNumber = tonumber(tostring(speed)) or 0
	local queueNumber = tonumber(tostring(self.processingQueue)) or 0

	local toProcessNumber = math.min(queueNumber, speedNumber * deltaTime)

	if toProcessNumber <= 0 then
		return BigNum.new(0)
	end

	local toProcess = BigNum.new(toProcessNumber)

	local earned = BigNum.mul(
		toProcess,
		(self.multipliers.moneyMultiplier or 1)
			* BoostService.getMultiplier(self, "money")
	)

	self.unclaimedMoney = BigNum.add(self.unclaimedMoney, earned)
	self.totalMoneyEarned = BigNum.add(
		self.totalMoneyEarned or BigNum.new(0),
		earned
	)

	self.processingQueue = BigNum.sub(self.processingQueue, toProcess)
	self.gemsInProcessor = BigNum.sub(self.gemsInProcessor, toProcess)

	if self.gamepasses.autoForge and BigNum.gt(self.unclaimedMoney, BigNum.new(0)) then
		self:collectMoney()
	end

	return earned
end

function PlayerData:instantProcessAll()
	if BigNum.le(self.processingQueue, 0) then
		return BigNum.new(0)
	end

	local allGems = self.processingQueue

	local BoostService = require(script.Parent.Parent.Systems.BoostService)

	local earned = BigNum.mul(
		allGems,
		(self.multipliers.moneyMultiplier or 1)
			* BoostService.getMultiplier(self, "money")
	)

	self.unclaimedMoney = BigNum.add(self.unclaimedMoney, earned)

	self.processingQueue = BigNum.new(0)
	self.gemsInProcessor = BigNum.new(0)

	self.totalMoneyEarned = BigNum.add(
		self.totalMoneyEarned or BigNum.new(0),
		earned
	)

	return earned
end

function PlayerData:collectMoney()
	local reward = self.unclaimedMoney or BigNum.new(0)

	if self.rewards and self.rewards.groupJoined then
		reward = BigNum.mul(reward, 1.2)
	end

	self.money = BigNum.add(self.money, reward)
	self.unclaimedMoney = BigNum.new(0)

	self:addTutorialProgress("MoneyCollected")

	return reward
end

-- ============================================================
-- Serialization
-- ============================================================
-- Converts runtime state into a persistence-safe structure.

function PlayerData:serialize()
	return {
		userId = self.userId,
		createdAt = self.createdAt,
		lastSave = os.time(),
		version = self.version,

		bossesDefeated = self.bossesDefeated,
		currentBossLevel = self.currentBoss.nivel,

		money = BigNum.serialize(self.money),
		unclaimedMoney = BigNum.serialize(self.unclaimedMoney),
		gems = BigNum.serialize(self.gems),
		gemsInProcessor = BigNum.serialize(self.gemsInProcessor),
		processingQueue = BigNum.serialize(self.processingQueue),

		healthDistribution = self.healthDistribution,
		stats = self.stats,

		skins = self.skins,
		npcAuras = self.npcAuras,
		playerAuras = self.playerAuras,

		rewards = self.rewards,
		tutorialState = self.tutorialState,

		multipliers = self.multipliers,
		gamepasses = self.gamepasses,

		activeBoosts = self.activeBoosts,
		boostQueue = self.boostQueue,

		keys = self.keys,
		dealerTickets = self.dealerTickets,
		questState = self.questState,
		titleState = self.titleState,
	}
end

-- ============================================================
-- Deserialization With Backward Compatibility
-- ============================================================
-- Restores persisted state while preserving compatibility with
-- older save versions and missing fields.

function PlayerData:deserialize(data)
	if not data then
		return
	end

	self.userId = data.userId
	self.createdAt = data.createdAt
	self.lastSave = data.lastSave
	self.version = data.version or Config.PLAYER_DATA_VERSION

	self.bossesDefeated = data.bossesDefeated or 0
	self.currentBoss = Boss.new(self.plot, data.currentBossLevel or 1, self)

	self.money = BigNum.deserialize(data.money)
	self.unclaimedMoney = BigNum.deserialize(data.unclaimedMoney)
	self.gems = BigNum.deserialize(data.gems)
	self.gemsInProcessor = BigNum.deserialize(data.gemsInProcessor)
	self.processingQueue = BigNum.deserialize(data.processingQueue)

	self.dealerTickets = data.dealerTickets or {
		skin = 0,
		aura = 0,
	}

	self.healthDistribution = data.healthDistribution or {
		melee = 15,
		brawler = 15,
		tank = 70,
	}

	self.rewards = data.rewards or {
		groupJoined = false,
		likeGiven = false,
		tutorialSeen = false,
	}

	if self.rewards.tutorialSeen == nil then
		self.rewards.tutorialSeen = false
	end

	self.tutorialState = data.tutorialState or {
		active = false,
		step = 0,
		bossCount = 0,
		requiredBosses = 2,
	}

	self.tutorialState.bossCount = self.tutorialState.bossCount or 0
	self.tutorialState.requiredBosses = self.tutorialState.requiredBosses or 2

	local savedStats = data.stats or {}
	local defaultStats = getDefaultStats()

	self.stats = {}

	for key, value in pairs(savedStats) do
		self.stats[key] = value
	end

	for key, defaultValue in pairs(defaultStats) do
		if self.stats[key] == nil then
			self.stats[key] = defaultValue
		end
	end

	self.skins = data.skins or {}
	self.npcAuras = data.npcAuras or {}
	self.playerAuras = data.playerAuras or {
		equipped = nil,
		unlocked = {},
	}

	self.questState = data.questState or {}
	self.titleState = data.titleState or {
		unlocked = {},
		active = nil,
	}

	self.multipliers = data.multipliers or self.multipliers
	self.gamepasses = data.gamepasses or self.gamepasses
	self.activeBoosts = data.activeBoosts or {}
	self.boostQueue = data.boostQueue or {
		money = {},
		gems = {},
		damage = {},
		processor = {},
	}

	self.keys = data.keys or {}

	local QuestService = require(script.Parent.Parent.QuestService.QuestService)
	QuestService.InitPlayer(self)
end

-- ============================================================
-- Offline Progression
-- ============================================================
-- Estimates offline rewards using boss health, progression level,
-- reward multipliers and minimum reward guarantees.

function PlayerData:calculateOfflineGemValue(offlineSeconds)
	local hours = offlineSeconds / 3600
	local bossLevel = math.max(1, self.currentBoss.nivel)

	local bossHealth = BigNum.mul(
		Config.BOSS.BASE_HEALTH,
		BigNum.pow(Config.BOSS.HEALTH_MULTIPLIER, bossLevel - 1)
	)

	local gemsPerBattle = BigNum.mul(
		bossHealth,
		Config.GEMS.DROP_RATIO * Config.GEMS.DROP_ON_DEATH
	)

	local estimatedBattles = 60 * hours

	local total = BigNum.mul(
		gemsPerBattle,
		estimatedBattles
			* (self.multipliers.offlineBoost or 1)
			* (self.multipliers.gemDrop or 1)
	)

	if BigNum.lt(total, BigNum.new(100)) then
		return BigNum.new(100)
	end

	return total
end

-- ============================================================
-- Health Distribution
-- ============================================================
-- Allows the player profile to redistribute team health while
-- preserving a bounded 100% allocation model.

function PlayerData:adjustHealthDistribution(stat, delta)
	self.healthDistribution = self.healthDistribution or {
		melee = 15,
		brawler = 15,
		tank = 70,
	}

	local newValue = self.healthDistribution[stat] + delta

	if newValue < 0 or newValue > 100 then
		return false
	end

	local candidates = { "melee", "brawler", "tank" }
	local sourceStat = nil
	local sourceValue = 0

	for _, candidate in ipairs(candidates) do
		if candidate ~= stat and self.healthDistribution[candidate] > sourceValue then
			sourceStat = candidate
			sourceValue = self.healthDistribution[candidate]
		end
	end

	if sourceStat and sourceValue >= delta then
		self.healthDistribution[stat] = newValue
		self.healthDistribution[sourceStat] =
			self.healthDistribution[sourceStat] - delta

		local GameLoop = require(script.Parent.Parent.Systems.GameLoop)
		GameLoop.applyHealthDistribution(self)

		return true
	end

	return false
end

-- ============================================================
-- Guided Tutorial State Machine
-- ============================================================
-- Tracks tutorial progression through ordered gameplay events.

local TUTORIAL_STEP_MAP = {
	BossDefeated = 1,
	GemCollected = 2,
	ProcessorUsed = 3,
	MoneyCollected = 4,
	UpgradePurchased = 5,
}

function PlayerData:startGuidedTutorial()
	self.tutorialState = {
		active = true,
		step = 0,
		bossCount = 0,
		requiredBosses = 2,
	}
end

function PlayerData:skipGuidedTutorial()
	self.tutorialState = self.tutorialState or {}
	self.tutorialState.active = false
end

function PlayerData:addTutorialProgress(eventName)
	if not self.tutorialState or not self.tutorialState.active then
		return
	end

	if eventName == "BossDefeated" then
		self.tutorialState.bossCount =
			(self.tutorialState.bossCount or 0) + 1

		if self.tutorialState.bossCount < self.tutorialState.requiredBosses then
			return
		end
	end

	local stepNumber = TUTORIAL_STEP_MAP[eventName]

	if not stepNumber then
		return
	end

	if stepNumber ~= self.tutorialState.step + 1 then
		return
	end

	self.tutorialState.step = stepNumber

	if stepNumber >= 5 then
		self.tutorialState.active = false
		self.tutorialState.step = 6
	end
end

return PlayerData
