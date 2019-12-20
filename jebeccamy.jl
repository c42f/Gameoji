module Jebeccamy

#using StaticArrays
#using Revise
using Logging

using TerminalMenus
using TerminalMenus: ARROW_UP, ARROW_DOWN, ARROW_LEFT, ARROW_RIGHT

CTRL_C = Char(3)
const right_cursors = (ARROW_UP, ARROW_DOWN, ARROW_LEFT, ARROW_RIGHT)

const left_cursors = ('w', 's', 'a', 'd')

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
abstract type Player end

mutable struct Girl <: Player
    base_icon::Char
    icon::Char
    pos::Tuple{Int,Int}
    items::Items
end

function Girl(pos)
    icon = '👧'
    Girl(icon, icon, pos, Items())
end

mutable struct Boy <: Player
    base_icon::Char
    icon::Char
    pos::Tuple{Int,Int}
    items::Items
end

function Boy(pos)
    icon = '👦'
    Boy(icon, icon, pos, Items())
end

mutable struct Dog
    base_icon::Char
    icon::Char
    pos::Tuple{Int,Int}
end

function Dog(pos)
    icon = '🐕'
    Dog(icon, icon, pos)
end

function cursormove(up, down, left, right, inchar)
    inchar == up    ? (-1, 0) :
    inchar == down  ? ( 1, 0) :
    inchar == left  ? ( 0,-1) :
    inchar == right ? ( 0, 1) :
                      ( 0, 0)
end

function action!(girl::Girl, board, p0, inchar)
    if inchar == '1'
        x = pop!(girl.items, '💣')
        if !isnothing(x)
            board[p0...] = '⏰'
        end
    end
    d = cursormove(left_cursors..., inchar)
    return p0 .+ d
end

function transition!(girl::Girl, board, pos)
    c = board[pos...]
    if c == '🧁'
        board[pos...] = '🎈'
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
    girl.pos = pos
end

function action!(boy::Boy, board, p0, inchar)
    d = cursormove(right_cursors..., inchar)
    return p0 .+ d
end

function transition!(boy::Boy, board, pos)
    c = board[pos...]
    if c == '🍕'
        board[pos...] = '🎈'
    elseif c in ('💣',fruits...)
        push!(boy.items, c)
        board[pos...] = ' '
    end
    boy.pos = pos
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
end

function action!(dog::Dog, board, p0, inchar)
    # Random step move
    d = rand([(1,0), (-1,0), (0,1), (0,-1)])
    return p0 .+ d
end


#-------------------------------------------------------------------------------

mutable struct Screen
    io::IO
    height::Int
    width::Int
end

function Screen(io::IO)
    dsize = displaysize(io)
    Screen(io, dsize[1]-1, dsize[2]÷2)
end

# Some emoji chars for which textwidth is incorrect (??)
const brick = '🧱'
const cupcake = '🧁'
const tree = '🌴'

# join(Char.(Int('🕐') .+ (0:11)))
clocks = collect("🕐🕑🕒🕓🕔🕕🕖🕗🕘🕙🕚🕛")
#fruits = collect("🍅🍆🍇🍈🍉🍊🍋🍌🍍🍎🍏🍐🍑🍒🍓")
fruits = collect("🍍🍒")

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
        screen[obj.pos...] = obj.icon
    end
    players = [p for p in sprites if p isa Player]
    for (i,person) in enumerate(players)
        j = 1 + (i-1)*size(screen,2)÷length(players)
        screen[end, j] = person.icon
        screen[end, j+1] = '|'
        j += 2
        for (item,cnt) in person.items
            str = "$(item)×$(cnt) "
            screen[end,j:j+length(str)-1] .= collect(str)
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

screen = Screen(stdout)

board = fill(' ', screen.height, screen.width)
#addrand!(board, '💩', 100)
addrand!(board, brick, 0.4)
addrand!(board, cupcake, 0.02)
addrand!(board, '🍕', 0.05)
addrand!(board, tree, 0.01)
addrand!(board, '💧', 0.01)
addrand!(board, '💣', 0.2)
for f in fruits
    addrand!(board, f, 0.005)
end

middle = (screen.height÷2, screen.width÷2)
sprites = vcat(
    [Dog((rand(1:screen.height),rand(1:screen.width))) for i=1:10],
    # People drawn last
    Girl(middle),
    Boy(middle),
)

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
                    key != CTRL_C || break
                    flush(io) # Hack!
                    for obj in sprites
                        p0 = obj.pos
                        p1 = action!(obj, board, p0, key)
                        p1 = clampmove(board, p1)
                        # You can climb onto the bricks from the tree
                        if board[p1...] == brick && !(board[p0...] in (tree,brick))
                            p1 = p0
                        end
                        transition!(obj, board, p1)
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
