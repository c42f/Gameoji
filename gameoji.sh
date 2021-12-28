#!/bin/bash

cd $(dirname $0)
exec julia --project=. -e 'using Gameoji; Gameoji.main(ARGS)' -- "$@"
