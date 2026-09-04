-- Pushes the three C++-backed Ledger tracks down onto the player.
--
-- Hard to Kill, Travelling Light and Night Watch have no Lua hook at all --
-- experience lost on death, equipment dropped on death and offline training
-- gained are decided entirely inside Player. Three small bindings were added
-- (Player::setBao*, src/luaplayer.cpp) and this is what feeds them.
--
-- (!) The RANKS remain the single source of truth, in the player's kv store.
-- Nothing is persisted on the C++ side, so these values have to be re-applied
-- on every login -- and immediately after a purchase, or the rank the player
-- just paid for does nothing until they relog.
--
-- Applied through BaoLedger.applyNative, which bao_protocol.lua also calls on
-- purchase, so there is one function to keep correct rather than two.

local applyLogin = CreatureEvent("BaoLedgerApply")

function applyLogin.onLogin(player)
	if BaoLedger and BaoLedger.applyNative then
		BaoLedger.applyNative(player)
	end

	-- Same login, same source: the kv store is only reachable through a
	-- Player, so this is the one moment an offline character's website row can
	-- be repaired. In normal play BaoLedger.purchase has already written it and
	-- this rewrites the same values; it exists for ranks bought before the
	-- mirror existed, and for anything lost to a crash mid-write.
	if BaoLedgerDB then
		BaoLedgerDB.refreshSummary(player)
	end

	player:registerEvent("BaoLedgerApply")
	return true
end

applyLogin:register()
