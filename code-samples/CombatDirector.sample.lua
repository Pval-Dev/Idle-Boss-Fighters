-- CombatDirector.sample.lua
-- Technical portfolio excerpt from Idle Boss Fighters.
--
-- This sample demonstrates:
-- - State-driven combat orchestration
-- - Shield/Core combat phases
-- - Runtime turn coordination
-- - Weighted target selection
-- - Combo probability overflow
-- - Visual damage reconciliation
-- - Deterministic battle result resolution
--
-- This is not the full production script.
-- It is a curated implementation sample for portfolio review.

local CombatDirector = {}

local Config = require(script.Parent.Parent.Data.Config)
local ActionSystem = require(script.Parent.ActionSystem)
local CombatSystem = require(script.Parent.CombatSystem)
local BigNum = require(game.ServerScriptService.Modules.Helpers.BigNum)
local DamageNumbers = require(game.ServerScriptService.Modules.Helpers.DamageNumberService)
local BoostService = require(game.ServerScriptService.Modules.Systems.BoostService)

-- ============================================================
-- Runtime Synchronization Helpers
-- ============================================================
-- Keeps turn execution aligned with animation state and
-- prevents combat actions from overlapping.

local function waitForAnimation()
	repeat
		task.wait()
	until not ActionSystem.Busy
end

local function waitCooldown(seconds)
	task.wait(seconds or 0.5)
end

-- ============================================================
-- Damage Resolution
-- ============================================================
-- Resolves player damage from progression stats, critical
-- modifiers, core-damage multipliers and temporary boosts.

local function applyCritDamage(amount, critChance, critMultiplier)
	local afterCrit = BigNum.mul(amount, critMultiplier)

	if critChance < 1.0 then
		return afterCrit
	end

	return BigNum.mul(afterCrit, critChance)
end

local function getNPCData(playerData, npcType)
	if npcType == "melee" then
		return {
			damage = BigNum.new(playerData:getStatValue("gladiatorDamage")),
			critChance = playerData:getStatValue("gladiatorCritChance"),
			critMultiplier = math.max(1, playerData:getStatValue("gladiatorCritMultiplier")),
			coreDamage = math.max(1, playerData:getStatValue("gladiatorCoreDamage")),
		}

	elseif npcType == "brawler" then
		return {
			damage = BigNum.new(playerData:getStatValue("brawlerDamage")),
			critChance = playerData:getStatValue("brawlerCritChance"),
			critMultiplier = math.max(1, playerData:getStatValue("brawlerCritMultiplier")),
			coreDamage = math.max(1, playerData:getStatValue("brawlerCoreDamage")),
		}
	end

	return {
		damage = BigNum.new(0),
		critChance = 0,
		critMultiplier = 1,
		coreDamage = 1,
	}
end

local function calculateDamage(playerData, npc, isCoreAttack)
	local npcType =
		(npc == playerData.npcs.melee and "melee")
		or (npc == playerData.npcs.brawler and "brawler")
		or nil

	if not npcType then
		return BigNum.new(0)
	end

	local stats = getNPCData(playerData, npcType)
	local damage = stats.damage

	if isCoreAttack then
		damage = BigNum.mul(damage, stats.coreDamage)
	end

	damage = applyCritDamage(
		damage,
		stats.critChance,
		stats.critMultiplier
	)

	damage = BigNum.mul(
		damage,
		(playerData.multipliers.damage or 1)
			* BoostService.getMultiplier(playerData, "damage")
	)

	return damage
end

-- ============================================================
-- Weighted Target Selection
-- ============================================================
-- Selects the boss target using weighted probability and tank
-- aggro as a gameplay modifier.

local function getWeightedTarget(npcs, playerData)
	local entries = {}
	local totalWeight = 0

	if npcs.melee:isAlive() then
		totalWeight += 1
		table.insert(entries, {
			npc = npcs.melee,
			weight = 1,
		})
	end

	if npcs.brawler:isAlive() then
		totalWeight += 1
		table.insert(entries, {
			npc = npcs.brawler,
			weight = 1,
		})
	end

	if npcs.tank:isAlive() then
		local aggro = playerData:getStatValue("shieldAggro")
		local weight = 1 + aggro

		totalWeight += weight

		table.insert(entries, {
			npc = npcs.tank,
			weight = weight,
		})
	end

	if totalWeight <= 0 then
		return nil
	end

	local roll = math.random() * totalWeight
	local current = 0

	for _, entry in ipairs(entries) do
		current += entry.weight

		if roll <= current then
			return entry.npc
		end
	end

	return entries[#entries].npc
end

local function teamAlive(npcs)
	return
		npcs.melee:isAlive()
		or npcs.brawler:isAlive()
		or npcs.tank:isAlive()
end

local function combatNPCsAlive(npcs)
	return
		npcs.melee:isAlive()
		and npcs.brawler:isAlive()
end

-- ============================================================
-- Combo Overflow
-- ============================================================
-- Converts excess combo probability into additional power,
-- allowing progression to remain valuable after probability caps.

local function applyComboOverflow(chance, cap, power)
	if chance <= cap then
		return chance / cap, power
	end

	local overflowMultiplier = chance / cap

	return 1.0, power * overflowMultiplier
end

-- ============================================================
-- Visual Damage Reconciliation
-- ============================================================
-- Applies damage progressively for visual feedback, then commits
-- any remaining residue to guarantee the final damage total.

local VISUAL_CURVE = {
	0.55,
	0.18,
	0.10,
	0.06,
	0.04,
	0.03,
	0.02,
	0.01,
	0.01,
}

function CombatDirector.StartVisualDamage(target, totalDamage, damageMethod, model)
	local controller = {
		_stop = false,
		_dealt = BigNum.new(0),
		_total = totalDamage,
	}

	task.spawn(function()
		for _, percentage in ipairs(VISUAL_CURVE) do
			if controller._stop then
				break
			end

			local chunk = BigNum.mul(totalDamage, percentage)

			controller._dealt = BigNum.add(controller._dealt, chunk)

			damageMethod(chunk)
			DamageNumbers:Show(model, chunk, 1)

			task.wait(0.5)
		end
	end)

	function controller:Commit()
		local residue = BigNum.sub(self._total, self._dealt)

		if BigNum.gt(residue, BigNum.new(0)) then
			damageMethod(residue)
			DamageNumbers:Show(model, residue, 1)
		end

		self._stop = true
	end

	return controller
end

function CombatDirector.StartVisualDamageNPC(npc, totalDamage, model)
	return CombatDirector.StartVisualDamage(
		npc,
		totalDamage,
		function(chunk)
			npc:takeDamage(chunk)
		end,
		model
	)
end

-- ============================================================
-- Tank Support Turn
-- ============================================================
-- Executes defensive support behavior through probabilistic
-- formation activation and team healing.

function CombatDirector.ExecuteShieldMan(npcs, boss, state, playerData)
	if not npcs.tank:isAlive() then
		return
	end

	playerData.currentCombo = 0
	ActionSystem.ChangeFinisher(false)

	local aggro = playerData:getStatValue("shieldAggro")
	local regeneration = playerData:getStatValue("shieldRegeneration")

	local formationChance = math.min(
		0.10 + (aggro - 0.5) * 0.6,
		0.50
	)

	if math.random() <= formationChance then
		ActionSystem.ShieldFormation(npcs.tank, npcs.melee, npcs.brawler)

		waitForAnimation()

		state.shieldFormationActive = true

		local healPercent = math.min(0.10 + regeneration, 0.30)

		npcs.melee:heal(BigNum.mul(npcs.melee.maxHealth, healPercent))
		npcs.brawler:heal(BigNum.mul(npcs.brawler.maxHealth, healPercent))
		npcs.tank:heal(BigNum.mul(npcs.tank.maxHealth, healPercent))

		CombatSystem.EndAnimation(
			npcs.melee,
			npcs.brawler,
			npcs.tank,
			boss
		)
	end
end

-- ============================================================
-- Boss Turn Resolution
-- ============================================================
-- Resolves boss attacks, formation mitigation and final damage
-- commitment after the selected animation finishes.

function CombatDirector.BossTurn(npcs, boss, state, plot, playerData)
	if not boss:isAlive() then
		return
	end

	playerData.currentCombo = 0

	local target = getWeightedTarget(npcs, playerData)

	if not target then
		return
	end

	local damage = boss:getDamage()

	if state.shieldFormationActive then
		state.shieldFormationActive = false

		if npcs.tank:isAlive() then
			target = npcs.tank
		end

		damage = BigNum.mul(damage, 0.5)
	end

	local visualDamage =
		CombatDirector.StartVisualDamageNPC(target, damage, target.model)

	ActionSystem.BossAttack1(boss, npcs.melee, npcs.brawler, npcs.tank)

	waitForAnimation()

	visualDamage:Commit()

	CombatSystem.EndAnimation(
		npcs.melee,
		npcs.brawler,
		npcs.tank,
		boss
	)
end

-- ============================================================
-- Shield Phase
-- ============================================================
-- Handles the shield-breaking stage before the boss core becomes
-- vulnerable.

function CombatDirector.ShieldPhase(npcs, boss, state, plot, playerData)
	local GameLoop = require(script.Parent.GameLoop)

	CombatDirector.ResetPositions(npcs, boss, plot)

	waitCooldown()

	if npcs.melee:isAlive() and BigNum.gt(boss.meleeShield, BigNum.new(0)) then
		playerData.currentCombo = 1

		local damage = calculateDamage(playerData, npcs.melee, false)

		local visualDamage = CombatDirector.StartVisualDamage(
			{ health = boss.meleeShield },
			damage,
			function(chunk)
				boss:damageMeleeShield(chunk)
			end,
			boss.model
		)

		ActionSystem.GladiatorAttack1(npcs.melee, boss)

		waitForAnimation()

		visualDamage:Commit()

		GameLoop.dropGemsDuringFight(boss, damage, plot)

		CombatSystem.EndAnimation(
			npcs.melee,
			npcs.brawler,
			npcs.tank,
			boss
		)

		waitCooldown()
	end

	if npcs.brawler:isAlive() and BigNum.gt(boss.swordShield, BigNum.new(0)) then
		playerData.currentCombo = 1

		local damage = calculateDamage(playerData, npcs.brawler, false)

		local visualDamage = CombatDirector.StartVisualDamage(
			{ health = boss.swordShield },
			damage,
			function(chunk)
				boss:damageSwordShield(chunk)
			end,
			boss.model
		)

		ActionSystem.BrawlerAttack1(npcs.brawler, boss)

		waitForAnimation()

		visualDamage:Commit()

		GameLoop.dropGemsDuringFight(boss, damage, plot)

		CombatSystem.EndAnimation(
			npcs.melee,
			npcs.brawler,
			npcs.tank,
			boss
		)

		waitCooldown()
	end

	CombatDirector.ExecuteShieldMan(npcs, boss, state, playerData)

	waitCooldown()

	CombatDirector.BossTurn(npcs, boss, state, plot, playerData)
end

-- ============================================================
-- Core Phase
-- ============================================================
-- Handles the vulnerable boss-core stage, including single,
-- dual and triple combo resolution.

function CombatDirector.CorePhase(npcs, boss, state, plot, playerData)
	local GameLoop = require(script.Parent.GameLoop)

	CombatDirector.ResetPositions(npcs, boss, plot)

	waitCooldown()

	local tripleChance = playerData:getStatValue("tripleChance")
	local dualChance = playerData:getStatValue("dualChance")

	local dualPower = playerData:getStatValue("dualPower")
	local triplePower = playerData:getStatValue("triplePower")

	local tripleProbability, triplePowerFinal =
		applyComboOverflow(tripleChance, 0.30, triplePower)

	local dualProbability, dualPowerFinal =
		applyComboOverflow(dualChance, 0.40, dualPower)

	local roll = math.random()
	local bothDamageNPCsAlive = combatNPCsAlive(npcs)

	if bothDamageNPCsAlive and roll <= tripleProbability then
		local meleeDamage = calculateDamage(playerData, npcs.melee, true)
		local brawlerDamage = calculateDamage(playerData, npcs.brawler, true)

		local totalDamage =
			BigNum.mul(
				BigNum.add(meleeDamage, brawlerDamage),
				triplePowerFinal
			)

		local visualDamage = CombatDirector.StartVisualDamage(
			{ health = boss.coreHealth },
			totalDamage,
			function(chunk)
				boss:damageCore(chunk)
			end,
			boss.model
		)

		ActionSystem.TripleCombo1(
			npcs.melee,
			npcs.brawler,
			npcs.tank,
			boss
		)

		waitForAnimation()

		visualDamage:Commit()

		GameLoop.dropGemsDuringFight(boss, totalDamage, plot)

	elseif bothDamageNPCsAlive and roll <= (tripleProbability + dualProbability) then
		local meleeDamage = calculateDamage(playerData, npcs.melee, true)
		local brawlerDamage = calculateDamage(playerData, npcs.brawler, true)

		local totalDamage =
			BigNum.mul(
				BigNum.add(meleeDamage, brawlerDamage),
				dualPowerFinal
			)

		local visualDamage = CombatDirector.StartVisualDamage(
			{ health = boss.coreHealth },
			totalDamage,
			function(chunk)
				boss:damageCore(chunk)
			end,
			boss.model
		)

		ActionSystem.DualCombo1(npcs.melee, npcs.brawler, boss)

		waitForAnimation()

		visualDamage:Commit()

		GameLoop.dropGemsDuringFight(boss, totalDamage, plot)

	else
		if npcs.melee:isAlive() and boss:isAlive() and boss.phase == "CORE" then
			local damage = calculateDamage(playerData, npcs.melee, true)

			local visualDamage = CombatDirector.StartVisualDamage(
				{ health = boss.coreHealth },
				damage,
				function(chunk)
					boss:damageCore(chunk)
				end,
				boss.model
			)

			ActionSystem.GladiatorAttack1(npcs.melee, boss)

			waitForAnimation()

			visualDamage:Commit()

			GameLoop.dropGemsDuringFight(boss, damage, plot)
		end

		waitCooldown()

		if npcs.brawler:isAlive() and boss:isAlive() and boss.phase == "CORE" then
			local damage = calculateDamage(playerData, npcs.brawler, true)

			local visualDamage = CombatDirector.StartVisualDamage(
				{ health = boss.coreHealth },
				damage,
				function(chunk)
					boss:damageCore(chunk)
				end,
				boss.model
			)

			ActionSystem.BrawlerAttack1(npcs.brawler, boss)

			waitForAnimation()

			visualDamage:Commit()

			GameLoop.dropGemsDuringFight(boss, damage, plot)
		end
	end

	CombatDirector.ExecuteShieldMan(npcs, boss, state, playerData)

	CombatSystem.EndAnimation(
		npcs.melee,
		npcs.brawler,
		npcs.tank,
		boss
	)

	waitCooldown()

	CombatDirector.BossTurn(npcs, boss, state, plot, playerData)

	if boss.phase == "CORE" then
		boss:tickCoreTurn()
	end
end

-- ============================================================
-- Battle Result Resolution
-- ============================================================
-- Runs the complete battle simulation until victory, defeat or
-- timeout conditions are reached.

function CombatDirector.RunBattle(npcs, boss, plot, playerData)
	local state = {
		shieldFormationActive = false,
	}

	local startTime = os.clock()
	local maxDuration = Config.BOSS.TIMER

	playerData.battleStartTime = startTime

	while
		boss:isAlive()
		and teamAlive(npcs)
		and (os.clock() - startTime < maxDuration)
	do
		if
			not npcs.melee:isAlive()
			and not npcs.brawler:isAlive()
			and npcs.tank:isAlive()
		then
			return {
				teamDefeated = true,
				bossDefeated = false,
				timeout = false,
			}
		end

		if boss.phase == "SHIELD" then
			if not npcs.melee:isAlive() or not npcs.brawler:isAlive() then
				return {
					teamDefeated = true,
					bossDefeated = false,
					timeout = false,
				}
			end

			CombatDirector.ShieldPhase(npcs, boss, state, plot, playerData)

		else
			CombatDirector.CorePhase(npcs, boss, state, plot, playerData)
		end

		if not boss:isAlive() then
			break
		end
	end

	local duration = os.clock() - startTime

	if duration >= maxDuration then
		return {
			timeout = true,
			bossDefeated = false,
			teamDefeated = false,
		}
	end

	if boss:isAlive() and not teamAlive(npcs) then
		return {
			teamDefeated = true,
			bossDefeated = false,
			timeout = false,
		}
	end

	if not boss:isAlive() then
		return {
			bossDefeated = true,
			teamDefeated = false,
			timeout = false,
		}
	end

	return {
		timeout = true,
		bossDefeated = false,
		teamDefeated = false,
	}
end

return CombatDirector
