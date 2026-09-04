-- Music Box (item 16244) is real Tibia's universal taming item -- it can
-- unlock any one of several specific mounts, chosen from a selection window,
-- instead of a single fixed mount like every other taming item. Lives under
-- data/lib (not data/scripts) so this table is guaranteed loaded before
-- data/scripts/actions/items/music_box.lua and
-- data/scripts/creaturescripts/mounts/music_box_modal.lua both reference it
-- at file-load time -- same reasoning as RarityRebirth's own lib table.

MusicBox = MusicBox or {}

MusicBox.ITEM_ID = 16244
MusicBox.MODAL_WINDOW_ID = 9010
MusicBox.BUTTON_PLAY = 1
MusicBox.BUTTON_CANCEL = 0

-- Real Tibia pairing: these are the mounts a Music Box can charm, alongside
-- each one's own dedicated taming item.
MusicBox.MOUNTS = {
	{ id = 31, name = "Dragonling" },
	{ id = 6,  name = "Draptor" },
	{ id = 29, name = "Ironblight" },
	{ id = 18, name = "Kingly Deer" },
	{ id = 30, name = "Magma Crawler" },
	{ id = 5,  name = "Midnight Panther" },
	{ id = 19, name = "Tamed Panda" },
	{ id = 17, name = "War Horse" },
	{ id = 1,  name = "Widow Queen" },
}

-- [playerId] = true while that player has an open Music Box window, so the
-- modal response handler knows to actually consume an item on a valid pick.
MusicBox.pending = MusicBox.pending or {}
