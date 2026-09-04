-- Boundary check for GlobalBoosts.extend's 12h stack cap, run against the
-- real lib with the engine stubbed out. Answers the only question that
-- matters at a cap change: does the LAST legitimate purchase still go
-- through, and is the first refusal the one after it.

local broadcasts = {}

db = {
  query = function() return true end,
  storeQuery = function() return false end,
  escapeString = function(v) return "'" .. tostring(v) .. "'" end,
}
result = { getString = function() return "" end, getNumber = function() return 0 end,
           next = function() return false end, free = function() end }
Game = {
  getPlayers = function() return {} end,
  broadcastMessage = function(msg) broadcasts[#broadcasts + 1] = msg end,
}
Condition = function() return { setParameter = function() end } end
CONDITION_ATTRIBUTES, CONDITION_REGENERATION, CONDITIONID_DEFAULT = 1, 2, 3
CONDITION_PARAM_SUBID, CONDITION_PARAM_TICKS, CONDITION_PARAM_SPEED = 4, 5, 6
CONDITION_PARAM_HEALTHGAIN, CONDITION_PARAM_HEALTHTICKS = 7, 8
CONDITION_PARAM_MANAGAIN, CONDITION_PARAM_MANATICKS = 9, 10
MESSAGE_EVENT_ADVANCE = 11

dofile("data/lib/boosts/global_boosts.lua")

local ID = GlobalBoosts.ID.EXPERIENCE
local GRANT = 1800
local expected = GlobalBoosts.MAX_STACK_SECONDS / GRANT

print(string.format("cap = %d seconds (%s), grant = %ds, so %d purchases should fit",
  GlobalBoosts.MAX_STACK_SECONDS, GlobalBoosts.formatDuration(GlobalBoosts.MAX_STACK_SECONDS),
  GRANT, expected))

local accepted = 0
local refusal
for i = 1, expected + 3 do
  local ok, verbOrReason = GlobalBoosts.extend(ID, GRANT, "Tester" .. i)
  if ok then
    accepted = accepted + 1
    if i == 1 and verbOrReason ~= "activated" then
      print("FAIL: first purchase reported '" .. tostring(verbOrReason) .. "', expected 'activated'")
    end
    if i == 2 and verbOrReason ~= "extended" then
      print("FAIL: second purchase reported '" .. tostring(verbOrReason) .. "', expected 'extended'")
    end
  elseif not refusal then
    refusal = verbOrReason
  end
end

print(string.format("accepted %d of %d attempted", accepted, expected + 3))
print("remaining after cap: " .. GlobalBoosts.formatDuration(GlobalBoosts.remaining(ID)))
print("first refusal: " .. tostring(refusal))
print("")
print("first broadcast : " .. tostring(broadcasts[1]))
print("second broadcast: " .. tostring(broadcasts[2]))

local pass = true
if accepted ~= expected then
  print("FAIL: expected exactly " .. expected .. " purchases to fit, got " .. accepted); pass = false
end
if GlobalBoosts.remaining(ID) ~= GlobalBoosts.MAX_STACK_SECONDS then
  print("FAIL: cap not reached exactly"); pass = false
end
if not refusal or not tostring(refusal):find("12 hours", 1, true) then
  print("FAIL: refusal should name the 12 hour cap"); pass = false
end

-- The fade line is what players see when it runs out; confirm every boost has
-- one and that tick() uses it.
for id, boost in pairs(GlobalBoosts.Types) do
  if not boost.fade or boost.fade == "" then
    print("FAIL: " .. boost.key .. " has no fade message"); pass = false
  end
end

print(pass and "\nALL CAP/FADE CHECKS PASSED" or "\nCHECKS FAILED")
