local checkChain = GlobalEvent("ChainCheck")
function checkChain.onStartup()
	local out = io.open("chain_report.txt", "w")
	local function describe(pos)
		local tile = Tile(pos)
		if not tile then
			out:write(string.format("  (%d,%d,%d): no tile\n", pos.x, pos.y, pos.z))
			return
		end
		local ground = tile:getGround()
		local groundId = ground and ground:getId() or 0
		out:write(string.format("  (%d,%d,%d): ground=%s(%d)\n", pos.x, pos.y, pos.z, ground and ground:getName() or "none", groundId))
		local things = tile:getThingCount()
		for i = 0, things - 1 do
			local thing = tile:getThing(i)
			if thing and thing:isItem() then
				out:write(string.format("    item: %s (%d)\n", thing:getName(), thing:getId()))
			end
		end
	end

	out:write("Original ladder chain (32323,32211,7 climbing up):\n")
	describe(Position(32323, 32211, 7))
	describe(Position(32323, 32211, 6))
	describe(Position(32323, 32211, 5))
	describe(Position(32323, 32211, 4))

	out:write("\nReported trapdoor position (32321,32211,6):\n")
	describe(Position(32321, 32211, 6))
	describe(Position(32321, 32211, 5))

	out:close()
	return true
end
checkChain:type("startup")
checkChain:register()
