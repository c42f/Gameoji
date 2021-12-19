#!/bin/bash

exec julia --project=. -e 'using Gameoji; if (length(ARGS) >= 1 && ARGS[1] in ("-r","remote")) ; Gameoji.run_game_client() else Gameoji.main() end'
