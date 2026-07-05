-- AnalyticsService.sample.lua
-- Technical portfolio excerpt from Idle Boss Fighters.
--
-- This sample demonstrates:
-- - Player session tracking
-- - Persistent analytics storage
-- - Session duration measurement
-- - Historical session summaries
-- - Active session inspection
-- - Product validation telemetry
--
-- This is not the full production script.
-- It is a curated implementation sample for portfolio review.

local AnalyticsService = {}

local DataStoreService = game:GetService("DataStoreService")

local AnalyticsStore = DataStoreService:GetDataStore("AnalyticsStore")

local activeSessions = {}

-- ============================================================
-- Persistent Analytics Access
-- ============================================================
-- Loads and saves player analytics records through a persistence
-- boundary isolated from gameplay systems.

local function loadPlayerAnalytics(userId)
	local success, data = pcall(function()
		return AnalyticsStore:GetAsync("player_" .. userId)
	end)

	if success and data then
		return data
	end

	return nil
end

local function savePlayerAnalytics(userId, data)
	local success = pcall(function()
		AnalyticsStore:SetAsync("player_" .. userId, data)
	end)

	return success
end

-- ============================================================
-- Session Start Tracking
-- ============================================================
-- Opens an in-memory active session and initializes persistent
-- analytics data for first-time players.

function AnalyticsService.OnPlayerJoined(player)
	local userId = player.UserId
	local username = player.Name
	local now = os.time()

	activeSessions[userId] = {
		startTime = now,
		username = username,
	}

	task.spawn(function()
		local data = loadPlayerAnalytics(userId)

		if not data then
			data = {
				userId = userId,
				username = username,
				firstJoin = now,
				totalSessions = 0,
				totalMinutes = 0,
				sessions = {},
			}
		end

		data.username = username

		data._pendingSession = {
			joinTime = now,
		}

		savePlayerAnalytics(userId, data)
	end)
end

-- ============================================================
-- Session Close Tracking
-- ============================================================
-- Calculates session duration, stores bounded historical data
-- and updates aggregate metrics.

function AnalyticsService.OnPlayerLeaving(player)
	local userId = player.UserId
	local session = activeSessions[userId]

	if not session then
		return
	end

	local now = os.time()
	local durationSeconds = now - session.startTime
	local durationMinutes = math.round(durationSeconds / 60 * 10) / 10

	activeSessions[userId] = nil

	task.spawn(function()
		local data = loadPlayerAnalytics(userId)

		if not data then
			return
		end

		data.sessions = data.sessions or {}

		if #data.sessions >= 50 then
			table.remove(data.sessions, 1)
		end

		table.insert(data.sessions, {
			joinTime = session.startTime,
			leaveTime = now,
			durationMins = durationMinutes,
			date = os.date("%Y-%m-%d %H:%M", session.startTime),
		})

		data.totalSessions = (data.totalSessions or 0) + 1

		data.totalMinutes =
			math.round(((data.totalMinutes or 0) + durationMinutes) * 10) / 10

		data._pendingSession = nil

		savePlayerAnalytics(userId, data)
	end)
end

-- ============================================================
-- Historical Player Analytics Query
-- ============================================================
-- Retrieves aggregated analytics and recent session history for
-- a specific player.

function AnalyticsService.GetPlayerData(userId)
	local data = loadPlayerAnalytics(userId)

	if not data then
		return nil
	end

	return {
		userId = data.userId,
		username = data.username,
		firstJoin = data.firstJoin,
		totalSessions = data.totalSessions or 0,
		totalMinutes = data.totalMinutes or 0,
		recentSessions = data.sessions or {},
	}
end

-- ============================================================
-- Active Session Query
-- ============================================================
-- Returns the current in-memory session state for online players.

function AnalyticsService.GetActiveSession(userId)
	local session = activeSessions[userId]

	if not session then
		return nil
	end

	local elapsedMinutes =
		math.round((os.time() - session.startTime) / 60 * 10) / 10

	return {
		username = session.username,
		startTime = session.startTime,
		elapsedMins = elapsedMinutes,
	}
end

-- ============================================================
-- Active Session Summary
-- ============================================================
-- Returns a compact snapshot of all active player sessions.

function AnalyticsService.GetActiveSessionsSummary()
	local summary = {}

	for userId, session in pairs(activeSessions) do
		local elapsedMinutes =
			math.round((os.time() - session.startTime) / 60 * 10) / 10

		table.insert(summary, {
			userId = userId,
			username = session.username,
			elapsedMins = elapsedMinutes,
		})
	end

	return summary
end

return AnalyticsService
