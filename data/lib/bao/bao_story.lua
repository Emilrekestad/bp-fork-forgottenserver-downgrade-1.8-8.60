-- Old Man Bao's personal storyline ("The Hunter Who Came Home"). Kept in its
-- own file, separate from bao_config.lua, purely so it could be authored
-- without racing the concurrent hunt-roster content pass.
--
-- Keyed by the raw storyChapter integer (BaoState.getStoryChapter /
-- BaoConfig.Ranks[n].storyChapter) — NOT the same as the roman-numeral
-- chapter number shown in the text, which is independent flavor. Chapters 1,
-- 2, 3, 5, 6, 8 are reached automatically via BaoConfig.Ranks' storyChapter
-- fields (Tracker..Legend of the Hunt). Chapters 9 and 10 (VII, VIII) are
-- NOT wired to any rank — they're meant to be unlocked later via a specific
-- extreme-endgame hunt's storyChapterUnlock field (see bao_reward.lua's
-- announceStoryChapter, already wired and ready) once that content exists.
BaoConfig.StoryChapters = {
	[1] = {
		title = "Chapter I - The First Hunt",
		text = "You have proven you can follow instruction and return in one piece. That is not nothing. Many hunters die before they learn even that.",
	},
	[2] = {
		title = "Chapter II - Teeth and Claws",
		text = "Predators now. Things that decide, before you do, who eats and who is eaten. You are starting to understand why I test patience before teeth.",
	},
	[3] = {
		title = "Chapter III - Things That Hunt Men",
		text = "Careful now. Some of what you face next does not merely defend itself. It hunts. There is a difference, and it matters more than strength.",
	},
	[5] = {
		title = "Chapter IV - Fire Above the Mountains",
		text = "I once travelled with hunters who thought dragonfire was the worst thing a man could face. They were wrong. But they were also, for a long time, right enough to survive it.",
	},
	[6] = {
		title = "Chapter V - The Empty Caves",
		text = "There were caves, once, thick with monsters. Now they stand empty. A foolish hunter celebrates such news. I did not. When predators leave territory, something frightened them worse than we did.",
	},
	[8] = {
		title = "Chapter VI - The Hunter Before You",
		text = "You have earned enough trust that I will tell you plainly: the hunter in the stories I tell was not some other man. It was me, many years and fewer fingers ago.",
	},
	[9] = {
		title = "Chapter VII - The Hunt That Never Ended",
		text = "There was one creature we never finished. We told ourselves later it simply moved on. I have never fully believed that. Some hunts do not end. They wait.",
	},
	[10] = {
		title = "Chapter VIII - Bao's Last Hunt",
		text = "There is one task left. No. This one is not task. This one is mine. Walk with me, if you are ready.",
	},
}
