#!/bin/bash
#=
exec julia --project=. -e 'include(popfirst!(ARGS))' \
    "${BASH_SOURCE[0]}" "$@"
=#

module Gameoji

using StaticArrays
using Crayons
#using Revise
using Logging
using LinearAlgebra
using Distributions
using JLD2

using TerminalMenus
using TerminalMenus: ARROW_UP, ARROW_DOWN, ARROW_LEFT, ARROW_RIGHT

include("types.jl")
include("display.jl")
include("maze_levels.jl")

CTRL_C = Char(3)

function clampmove(board, p)
    (clamp(p[1], 1, size(board,1)),
     clamp(p[2], 1, size(board,2)))
end

struct Items
    d::Dict{Char,Int}
end

Items() = Items(Dict{Char,Int}())

Base.haskey(i::Items, x) = haskey(i.d, x)

function Base.push!(i::Items, x)
    if !haskey(i, x)
        i.d[x] = 1
    else
        i.d[x] += 1
    end
end

function Base.pop!(i::Items, x)
    if haskey(i, x)
        n = i.d[x] - 1
        if n == 0
            pop!(i.d, x)
        else
            i.d[x] = n
        end
        x
    else
        nothing
    end
end

Base.iterate(i::Items) = iterate(i.d)
Base.iterate(i::Items, state) = iterate(i.d, state)
Base.length(i::Items) = length(i.d)
Base.eltype(i::Items) = Pair{Char,Int}

#-------------------------------------------------------------------------------
# Sprites
abstract type Sprite end
abstract type Player <: Sprite end

"""
    Propose an action for the sprite.

Return the proposed next position for the sprite (game rules will be applied
to this position).
"""
propose_action!(::Sprite, board, sprites, p0, inchar) = p0

"""
    Move sprite to `pos`
"""
transition!(sprite::Sprite, board, pos) = sprite

"""
    Get current picture for a sprite
"""
icon(sprite::Sprite) = sprite.icon


mutable struct Girl <: Player
    base_icon::Char
    icon::Char
    pos::Vec
    items::Items
end
function Girl(pos)
    icon = '👧'
    Girl(icon, icon, pos, Items())
end


mutable struct Boy <: Player
    base_icon::Char
    icon::Char
    pos::Vec
    items::Items
end
function Boy(pos)
    icon = '👦'
    Boy(icon, icon, pos, Items())
end


mutable struct Dog <: Sprite
    base_icon::Char
    icon::Char
    pos::Vec
end
function Dog(pos)
    icon = '🐕'
    Dog(icon, icon, pos)
end


const ticking_clocks = collect("🕛🕐🕑🕒🕓🕔🕕🕖🕗🕘🕙🕚🕛")
mutable struct ExplodingClock <: Sprite
    pos::Vec
    time::Int
end
ExplodingClock(pos) = ExplodingClock(pos, 0)
icon(c::ExplodingClock) = ticking_clocks[mod1(c.time, length(ticking_clocks))]


mutable struct Boom <: Sprite
    pos::Vec
    time::Int
end
Boom(pos) = Boom(pos, 0)
icon(::Boom) = '💥'

function explosion(pos, radius)
    [Boom(pos .+ (i,j)) for i = -radius:radius, j=-radius:radius]
end

mutable struct Balloon <: Sprite
    pos::Vec
end
icon(::Balloon) = '🎈'


struct ExplodingPineapple <: Sprite
    pos::Vec
end
# Fixme... why doesn't skull & crossbones or coffin work?
icon(::ExplodingPineapple) = '🍍'

#-------------------------------------------------------------------------------
# Sprite behaviour

function keymap(::Girl, inchar)
    keys = Dict('w' => :up,
                's' => :down,
                'a' => :left,
                'd' => :right,
                '1' => :use_bomb,
               )
    get(keys, inchar, :none)
end

function keymap(::Boy, inchar)
    keys = Dict(ARROW_UP    => :up,
                ARROW_DOWN  => :down,
                ARROW_LEFT  => :left,
                ARROW_RIGHT => :right,
                '0'         => :use_bomb,
               )
    get(keys, inchar, :none)
end

function propose_action!(player::Player, board, sprites, p0, inchar)
    if icon(player) == '💀'
        return p0
    end
    action = keymap(player, inchar)
    p = p0
    if action == :use_bomb
        if icon(player) != '🤮'
            # FIXME it's weird to push clocks onto the sprites list here
            x = pop!(player.items, '💣')
            if !isnothing(x)
                push!(sprites, ExplodingClock(player.pos))
            end
        end
    elseif action == :up
        p += Vec(0, 1)
    elseif action == :down
        p += Vec(0, -1)
    elseif action == :left
        p += Vec(-1, 0)
    elseif action == :right
        p += Vec(1, 0)
    end
    return p
end

function transition!(girl::Girl, board, pos)
    c = board[pos...]
    if c == '💥'
        girl.icon = '💀'
        return girl
    end
    girl.pos = pos
    if c == '🧁'
        board[pos...] = ' '
        return [girl, Balloon(pos)]
    elseif c in ('💣',fruits...)
        push!(girl.items, c)
        board[pos...] = ' '
    elseif c == '🍕'
        board[pos...] = '💩'
    elseif c == '💩'
        board[pos...] = ' '
        girl.icon = '🤮'
    end
    if girl.icon == '🤮' && c == '💧'
        girl.icon = girl.base_icon
    end
    return girl
end

function transition!(boy::Boy, board, pos)
    c = board[pos...]
    if c == '💥'
        boy.icon = '💀'
        return boy
    end
    boy.pos = pos
    if c == '🍕'
        board[pos...] = ' '
        return [boy, Balloon(pos)]
    elseif c in ('💣',fruits...)
        push!(boy.items, c)
        board[pos...] = ' '
    end
    return boy
end

function propose_action!(dog::Dog, board, sprites, p0, inchar)
    # Random step move
    d = rand(Vec[(1,0), (-1,0), (0,1), (0,-1)])
    return p0 .+ d
end

function transition!(dog::Dog, board, pos)
    c = board[pos...]
    if c == '💩'
        board[pos...] = ' '
    elseif c == '🎈'
        board[pos...] = ' '
    elseif c == '🧁'
        board[pos...] = '🎈'
    elseif c == '🍕'
        board[pos...] = '💩'
    end
    dog.pos = pos
    return dog
end

function propose_action!(b::Boom, board, sprites, p0, inchar)
    return p0
end

function transition!(b::Boom, board, pos)
    if b.time == 0
        board[b.pos...] = '💥'
    elseif b.time == 1
        board[b.pos...] = ' '
        return nothing
    end
    b.time += 1
    return b
end

function transition!(clock::ExplodingClock, board, pos)
    clock.time += 1
    if clock.time > length(ticking_clocks)
        return explosion(pos, 1)
    end
    return clock
end


function propose_action!(balloon::Balloon, board, sprites, p0, inchar)
    # Balloons float to top
    p0 .+ Vec(0,1)
end

function transition!(balloon::Balloon, board, pos)
    if pos[1] == size(board,2)
        return Boom(pos)
    end
    balloon.pos = pos
    return balloon
end


function transition!(ep::ExplodingPineapple, board, pos)
    if rand() < 0.01
        return explosion(pos, 1)
    end
    return ep
end


#-------------------------------------------------------------------------------
# join(Char.(Int('🕐') .+ (0:11)))
clocks = collect("🕛🕐🕑🕒🕓🕔🕕🕖🕗🕘🕙🕚🕛")
moons = collect("🌑🌒🌓🌔🌕🌖🌗🌘")
fruits = collect("🍅🍆🍇🍈🍉🍊🍋🍌🍍🍎🍏🍐🍑🍒🍓")
#fruits = collect("🍌🍒")
flowers = collect("💮🌼💐🌺🌹🌸🌷🌻🏵")
plants = collect("🌲🌳🌱🌴🌵🌴🌳🌿🍀🍁🍂🍄")
food = collect("🌽🌾")
treasure = collect("💰💎")
animals = collect("🐇🐝🐞🐤🐥🐦🐧🐩🐪🐫")
water_animals = collect("🐬🐳🐙🐊🐋🐟🐠🐡")
buildings = collect("🏰🏯🏪🏫🏬🏭🏥")
monsters = collect("👻👺👹👽🧟")

function draw(board, sprites)
    io = IOBuffer()
    # Compose screen & print it
    screen = copy(board)
    # Draw sprites on top of background
    for obj in sprites
        screen[obj.pos...] = icon(obj)
    end
    players = [s for s in sprites if s isa Player]
    # Overdraw players so they're always on top
    for (i,person) in enumerate(players)
        screen[person.pos...] = icon(person)
    end
    left_sidebar = fill("", size(board,2))
    right_sidebar = fill("", size(board,2))
    for (i,(person, sidebar)) in enumerate(zip(players, [left_sidebar, right_sidebar]))
        for (j,(item,count)) in enumerate(person.items)
            if j > length(sidebar)
                break
            end
            sidebar[end+1-j] = "$(item)$(lpad(count,3))"
        end
    end
    clear_screen(stdout)
    print(stdout, sprint(printboard, screen, left_sidebar, right_sidebar))
end

function rawmode(f, term)
    raw_mode_enabled = TerminalMenus.enableRawMode(term)
    try
        # Stolen from TerminalMenus
        raw_mode_enabled && print(term.out_stream, "\x1b[?25l") # hide the cursor
        f()
    finally
        if raw_mode_enabled
            print(term.out_stream, "\x1b[?25h") # unhide cursor
            TerminalMenus.disableRawMode(term)
        end
    end
end

function read_key()
    k = TerminalMenus.readKey()
    if k in Int.((ARROW_UP, ARROW_DOWN, ARROW_LEFT, ARROW_RIGHT))
        return TerminalMenus.Key(k)
    elseif k == 3 #=^C=#
        return CTRL_C
    else
        return Char(k)
    end
end

function main_loop!(board, sprites)
    term = TerminalMenus.terminal
    open("log.txt", "w") do logio
        with_logger(ConsoleLogger(logio)) do
            rawmode(term) do
                in_stream = term.in_stream
                while true
                    if bytesavailable(in_stream) == 0
                        # Avoid repeated input lag by only drawing when no
                        # bytes are available.
                        draw(board, sprites)
                    end
                    key = read_key()
                    if key == CTRL_C
                        # Clear
                        println("\e[1;1H\e[J")
                        return
                    end
                    flush(logio) # Hack!
                    new_positions = []
                    for obj in sprites
                        p0 = obj.pos
                        p1 = propose_action!(obj, board, sprites, p0, key)
                        p1 = clampmove(board, p1)
                        # You can climb onto the bricks from the tree
                        # HACK
                        if !(obj isa Balloon) && board[p1...] == brick && !(board[p0...] in (tree,brick))
                            p1 = p0
                        end
                        push!(new_positions, p1)
                    end
                    sprites_new = []
                    for (p1,obj) in zip(new_positions,sprites)
                        obj = transition!(obj, board, p1)
                        if !isnothing(obj)
                            if obj isa AbstractArray
                                append!(sprites_new, obj)
                            else
                                obj::Sprite
                                push!(sprites_new, obj)
                            end
                        end
                    end
                    sprites = filter(sprites_new) do s
                        p = s.pos
                        1 <= p[1] <= size(board,1) && 1 <= p[2] <= size(board,2)
                    end
                end
            end
        end
    end
end

# board initialization
function addrand!(cs, c, prob::Real)
    for i = 1:length(cs)
        if rand() < prob && cs[i] == ' '
            cs[i] = c
        end
    end
end

sheight,swidth = displaysize(stdout)
height = sheight
width = (swidth - sidebar_width*2) ÷ 2

#=
# Level of correllated noise
# A few steps to create correlated noise
#board = fill(' ', height, width)
#addrand!(board, brick, 0.5)
for k=1:3
    for i = 1:size(board,1), j=1:size(board,2)
        i2 = clamp(i + rand(-1:1), 1, size(board,1))
        j2 = clamp(j + rand(-1:1), 1, size(board,2))
        c = board[i2, j2]
        if board[i,j] != c
            board[i,j] = c
        end
    end
end
=#

board = generate_maze((width,height))

addrand!(board, cupcake, 0.02)
addrand!(board, '🍕', 0.05)
addrand!(board, tree, 0.01)
addrand!(board, '💧', 0.01)
addrand!(board, '💣', 0.03)
for f in fruits
    addrand!(board, f, 0.01)
end

middle = size(board) .÷ 2
girl = Girl(middle)
boy = Boy(middle)
push!(girl.items, '💣')
push!(boy.items, '💣')

sprites = vcat(
    [Dog((rand(1:width),rand(1:height))) for i=1:4],
    [ExplodingPineapple((rand(1:width),rand(1:height))) for i=1:3],
    girl,
    boy,
)


#printboard(stdout, generate_maze(height, width))

main_loop!(board, sprites)

end

nothing
