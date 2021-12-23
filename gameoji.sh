#!/bin/bash

exec julia --project=. -e 'using Gameoji; Gameoji.main(ARGS)' -- "$@"
