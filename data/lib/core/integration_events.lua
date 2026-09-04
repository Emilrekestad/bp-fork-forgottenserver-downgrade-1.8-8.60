IntegrationEvents = IntegrationEvents or {}

local function escaped(value)
	return db.escapeString(tostring(value))
end

function IntegrationEvents.publish(eventType, eventKey, visibility, payload)
	local now = os.time()
	local encoded = json.encode(payload)
	return db.query(string.format(
		"INSERT IGNORE INTO `integration_events` " ..
		"(`event_key`, `event_type`, `visibility`, `payload`, `available_at`, `created_at`) " ..
		"VALUES (%s, %s, %s, %s, %d, %d)",
		escaped(eventKey),
		escaped(eventType),
		escaped(visibility),
		escaped(encoded),
		now,
		now
	))
end

function IntegrationEvents.recordWorldFirst(player, achievement)
	if achievement.secret then
		return false
	end

	local playerId = player:getGuid()
	local playerName = player:getName()
	local achievedAt = os.time()

	local isWinner = false
	local committed = db.transaction(function()
		local inserted = db.query(string.format(
			"INSERT IGNORE INTO `world_first_achievements` " ..
			"(`achievement_id`, `achievement_name`, `player_id`, `player_name`, `achieved_at`) " ..
			"VALUES (%d, %s, %d, %s, %d)",
			achievement.id,
			escaped(achievement.name),
			playerId,
			escaped(playerName),
			achievedAt
		))
		if not inserted then
			error("Could not record world-first achievement")
		end

		-- INSERT IGNORE also succeeds when another player owns the row. Verify
		-- the winner while the transaction still protects the unique key.
		local query = string.format(
			"SELECT `player_id` FROM `world_first_achievements` WHERE `achievement_id` = %d",
			achievement.id
		)
		local resultId = db.storeQuery(query)
		if not resultId then
			error("Could not verify world-first achievement")
		end

		local winnerId = result.getNumber(resultId, "player_id")
		result.free(resultId)
		if winnerId ~= playerId then
			return
		end

		if not IntegrationEvents.publish(
			"achievement.world_first",
			"achievement.world_first:" .. achievement.id,
			"public",
			{
				eventVersion = 1,
				achievementId = achievement.id,
				achievementName = achievement.name,
				achievementGrade = achievement.grade or 1,
				achievementPoints = achievement.points or 0,
				playerId = playerId,
				playerName = playerName,
				achievedAt = achievedAt
			}
		) then
			error("Could not publish world-first integration event")
		end
		isWinner = true
	end)

	return committed and isWinner
end
