module Gameoji

using StaticArrays
#using Revise
using Logging

using TerminalMenus
using TerminalMenus: ARROW_UP, ARROW_DOWN, ARROW_LEFT, ARROW_RIGHT

CTRL_C = Char(3)

const Vec = SVector{2,Int}

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


mutable struct Clock <: Sprite
    pos::Vec
    time::Int
end
Clock(pos) = Clock(pos, 0)
icon(c::Clock) = clocks[mod1(c.time, length(clocks))]


mutable struct Boom <: Sprite
    pos::Vec
    time::Int
end
Boom(pos) = Boom(pos, 1)
icon(::Boom) = '💥'


mutable struct Balloon <: Sprite
    pos::Vec
end
icon(::Balloon) = '🎈'


struct Grave <: Sprite
    pos::Vec
end
# Fixme... why doesn't skull & crossbones or coffin work?
icon(::Grave) = '💀'


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
    action = keymap(player, inchar)
    p = p0
    if action == :use_bomb
        if icon(player) != '🤮'
            # FIXME it's weird to push clocks onto the sprites list here
            x = pop!(player.items, '💣')
            if !isnothing(x)
                push!(sprites, Clock(player.pos))
                #board[p0...] = '⏰'
            end
        end
    elseif action == :up
        p += Vec(-1, 0)
    elseif action == :down
        p += Vec(1, 0)
    elseif action == :left
        p += Vec(0, -1)
    elseif action == :right
        p += Vec(0, 1)
    end
    return p
end

function transition!(girl::Girl, board, pos)
    girl.pos = pos
    c = board[pos...]
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
    elseif c == '💥'
        return Grave(pos)
    end
    if girl.icon == '🤮' && c == '💧'
        girl.icon = girl.base_icon
    end
    return girl
end

function transition!(boy::Boy, board, pos)
    boy.pos = pos
    c = board[pos...]
    if c == '🍕'
        board[pos...] = ' '
        return [boy, Balloon(pos)]
    elseif c in ('💣',fruits...)
        push!(boy.items, c)
        board[pos...] = ' '
    elseif c == '💥'
        return Grave(pos)
    end
    return boy
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

function propose_action!(dog::Dog, board, sprites, p0, inchar)
    # Random step move
    d = rand(Vec[(1,0), (-1,0), (0,1), (0,-1)])
    return p0 .+ d
end

function transition!(b::Boom, board, pos)
    if b.time == 1
        board[b.pos...] = '💥'
    end
    b.time += 1
    if b.time == 3
        board[b.pos...] = ' '
        return nothing
    end
    return b
end

function transition!(clock::Clock, board, pos)
    clock.time += 1
    if clock.time == 12
        return [Boom(pos .+ (i,j)) for i = -1:1, j=-1:1]
    end
    return clock
end


function propose_action!(balloon::Balloon, board, sprites, p0, inchar)
    # Balloons float to top
    p0 .+ Vec(-1,0)
end

function transition!(balloon::Balloon, board, pos)
    if pos[1] == 1
        return Boom(pos)
    end
    balloon.pos = pos
    return balloon
end


function transition!(ep::ExplodingPineapple, board, pos)
    if rand() < 0.01
        return [Boom(pos .+ Vec(i,j)) for i = -1:1, j=-1:1]
    end
    return ep
end


#-------------------------------------------------------------------------------

# Some emoji chars for which textwidth is incorrect (??)
const brick = '🧱'
const cupcake = '🧁'
const tree = '🌴'

# join(Char.(Int('🕐') .+ (0:11)))
clocks = collect("🕛🕐🕑🕒🕓🕔🕕🕖🕗🕘🕙🕚🕛")
#fruits = collect("🍅🍆🍇🍈🍉🍊🍋🍌🍍🍎🍏🍐🍑🍒🍓")
fruits = collect("🍌🍒")

function printboard(io, cs)
    print(io, "\e[1;1H", "\e[J")
              #homepos   #clear
    for i=1:size(cs,1)
        for j=1:size(cs,2)
            c = cs[i,j]
            print(io, c)
            if textwidth(c) == 1 || c in (cupcake, brick)
                print(io, ' ')
            end
        end
        i != size(cs,1) && println(io)
    end
end

function draw(board, sprites)
    io = IOBuffer()
    # Compose screen & print it
    screen = fill(' ', size(board,1)+1, size(board,2))
    screen[1:end-1, :] = board
    for obj in sprites
        screen[obj.pos...] = icon(obj)
    end
    players = [s for s in sprites if s isa Player]
    n_players = length(players)
    for (i,person) in enumerate(players)
        # Players on top of objects
        screen[person.pos...] = icon(person)
        j = 1 + (i-1)*size(screen,2) ÷ n_players
        screen[end, j] = icon(person)
        screen[end, j+1] = '|'
        j += 2
        for (item,cnt) in person.items
            str = "$(item)×$(cnt) "
            # FIXME: Proper drawing of state which doesn't crash...
            jend = clamp(j+length(str)-1, 1, size(screen,2))
            screen[end,j:jend] .= collect(str)[1:jend-j+1]
            j += length(str)
        end
    end
    print(sprint(printboard, screen))
end

# board initialization
function addrand!(cs, c, prob::Real)
    for i = 1:length(cs)
        if rand() < prob
            cs[i] = c
        end
    end
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
    open("log.txt", "w") do io
        with_logger(ConsoleLogger(io)) do
            rawmode(term) do
                in_stream = term.in_stream
                try
                    while true
                        if bytesavailable(in_stream) == 0
                            draw(board, sprites)
                            sleep(0.1)
                        end
                        key = read_key()
                        if key == CTRL_C
                            draw(fill(' ', size(board)), [])
                            return
                        end
                        flush(io) # Hack!
                        sprites_new = []
                        for obj in sprites
                            p0 = obj.pos
                            p1 = propose_action!(obj, board, sprites, p0, key)
                            p1 = clampmove(board, p1)
                            # You can climb onto the bricks from the tree
                            # HACK
                            if !(obj isa Balloon) && board[p1...] == brick && !(board[p0...] in (tree,brick))
                                p1 = p0
                            end
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
                catch exc
                    exc isa InterruptException || rethrow()
                    nothing
                finally
                end
            end
        end
    end
end

sheight,swidth = displaysize(stdout)
height = sheight - 1
width = swidth ÷ 2

board = fill(' ', height, width)
#addrand!(board, '💩', 100)
addrand!(board, brick, 0.6)
addrand!(board, cupcake, 0.02)
addrand!(board, '🍕', 0.05)
addrand!(board, tree, 0.01)
addrand!(board, '💧', 0.01)
addrand!(board, '💣', 0.03)
for f in fruits
    addrand!(board, f, 0.01)
end

middle = (height÷2, width÷2)
girl = Girl(middle)
boy = Boy(middle)
push!(girl.items, '💣')
push!(boy.items, '💣')

sprites = vcat(
    [Dog((rand(1:height),rand(1:width))) for i=1:4],
    [ExplodingPineapple((rand(1:height),rand(1:width))) for i=1:3],
    girl,
    boy
)

main_loop!(board, sprites)

end

