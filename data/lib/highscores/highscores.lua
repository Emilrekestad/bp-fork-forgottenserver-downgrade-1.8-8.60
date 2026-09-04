-- Highscores — load order. Config first (pure data, and it self-validates on
-- load), then the projection and query engine which reads it.
dofile(CORE_DIRECTORY .. "/lib/highscores/highscores_config.lua")
dofile(CORE_DIRECTORY .. "/lib/highscores/highscores_db.lua")
