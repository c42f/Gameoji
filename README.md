# Gamoji - an emoji-based terminal game in Julia

A little emoji game for my children, Rebecca and Jeremy 😃


## Installation

You need a color terminal with a good emoji font.  I assume the terminal
supports [ANSI escape codes](https://en.wikipedia.org/wiki/ANSI_escape_code)
for color and various cursor control.

On Ubuntu 18.04 I've tested it with

* Terminal: `gnome-terminal`
* Emoji font: `fonts-noto-color-emoji`

```
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

## Running the game

Run with:

```
./gameoji.jl
```

or

```
julia --project=. gameoji.jl
```

or in development, just `include("gameoji.jl")`.

Then you walk around collecting items, there's not really an aim to the game!
Bombs can be used to explode walls to get access to new areas. Very different
levels are randomly generated each time.

## Controls

The girl and boy emoji both have controls on the same keyboard — WASD and arrow
keys respectively to move, and `1` and `Enter` to drop a bomb.

