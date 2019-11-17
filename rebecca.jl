#using StaticArrays
using Logging

function all_about_dollies(number_of_dollies;
                           cupcake_flavours=["Strawberry", "Carrot", "Vanilla"])
    if number_of_dollies > 2
        println("The dollies are having a tea party")
        for i = 1:number_of_dollies
            flavour = rand(cupcake_flavours)
            println("Dolly number $i eats a $flavour flavoured cupcake")
        end
    else
        println("The dollies have a nice sleep")
    end
end


function eat_cupcakes()
    food = "🍕"
    number_of_cupcakes = 1000000
    while number_of_cupcakes > 0
        surprise_cupcakes = rand([zeros(Int,100); 1:10])
        if surprise_cupcakes > 0
            println("Oooooh I found $(food^surprise_cupcakes)")
            number_of_cupcakes = number_of_cupcakes + surprise_cupcakes
            println("Now I have $number_of_cupcakes $food")
        end
        number_of_cupcakes = number_of_cupcakes - 1
        if number_of_cupcakes > 1
            println("I ate one $food. There are $number_of_cupcakes $food left 😃")
        elseif number_of_cupcakes == 1
            println("I ate one $food. I only have one $food left 😦")
        else    
            println("I have noooooo cupcakes 😱")
        end
    end
end

using TerminalMenus

const brick = '🧱'
const cupcake = '🧁'
const tree = '🌴'

function printchar(io, c)
    print(io, c)
    if textwidth(c) == 1 || c in (cupcake, brick)
        print(io, ' ')
    end
end

function printboard(io, cs)
    print(io, "\e[1;1H")
    for i=1:size(cs,1)
        for j=1:size(cs,2)
            printchar(io, cs[i,j])
        end
        i != size(cs,1) && println(io)
    end
end

function addrand!(cs, c, prob::Real)
    for i = 1:length(cs)
        if rand() < prob
            cs[i] = c
        end
    end
end

function randmove(rng, inchar)
    p->(p[1] + rand(rng),
        p[2] + rand(rng))
end

function stepmove(p, inchar)
    p .+ rand([(1,0), (-1,0), (0,1), (0,-1)])
end

std_cursors = Int.([TerminalMenus.ARROW_UP, TerminalMenus.ARROW_DOWN,
                   TerminalMenus.ARROW_LEFT, TerminalMenus.ARROW_RIGHT])

left_cursors = Int.(['w', 's', 'a', 'd'])

function make_cursormove(up,down,left,right)
    function cursormove(p, inchar)
        δ = inchar == up    ? (-1, 0) :
            inchar == down  ? ( 1, 0) :
            inchar == left  ? ( 0,-1) :
            inchar == right ? ( 0, 1) :
            (0, 0)
        p .+ δ
    end
end

function clampmove(board, p)
    (clamp(p[1], 1, size(board,1)),
     clamp(p[2], 1, size(board,2)))
end

mutable struct Person
    base_icon::Char
    icon::Char
    pos::Tuple{Int,Int}
    state
    trymove
    transition!
end

Person(icon::Char, pos, state, trymove, update) =
    Person(icon, icon, pos, state, trymove, update)

transition!(p::Person, board, pos) = p.transition!(p, board, pos)

function girl_update(person, board, pos)
    c = board[pos...]
    if c == '🧁'
        board[pos...] = '🎈'
    elseif c == '🍕'
        board[pos...] = '💩'
    elseif c == '💩'
        board[pos...] = ' '
        person.icon = '🤮'
    end
    if person.icon == '🤮' && c == '💧'
        person.icon = person.base_icon
    end
    person.pos = pos
end

function boy_update(person, board, pos)
    c = board[pos...]
    if c == '🍕'
        board[pos...] = '🎈'
    end
    person.pos = pos
end


N,M = displaysize(stdout)
#N -= 1
M ÷= 2
board = fill(' ', N, M)
#addrand!(board, '💩', 100)
addrand!(board, brick, 0.4)
addrand!(board, cupcake, 0.02)
addrand!(board, '🍕', 0.05)
addrand!(board, tree, 0.01)
addrand!(board, '💧', 0.01)

middle = (N÷2, M÷2)
people = vcat(
    [Person('🐕', (rand(1:N),rand(1:M)), :hungry, stepmove,
           function (dog, board, pos)
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
           end) for i=1:10],
    # People drawn last
    Person('👧', middle, :hungry, make_cursormove(left_cursors...), girl_update),
    Person('👦', middle, :hungry, make_cursormove(std_cursors...),  boy_update),
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

term = TerminalMenus.terminal
open("log.txt", "w") do io
    with_logger(ConsoleLogger(io)) do
        rawmode(term) do
            in_stream = term.in_stream
            try
                while true
                    if bytesavailable(in_stream) == 0
                        tmpboard = copy(board)
                        for person in people
                            tmpboard[person.pos...] = person.icon
                        end
                        print(sprint(printboard, tmpboard))
                        sleep(0.1)
                    end
                    inchar = TerminalMenus.readKey()
                    if inchar == 3 #=^C=# || inchar == 'q'
                        break
                    end
                    for person in people
                        p0 = person.pos
                        p1 = clampmove(board, person.trymove(p0, inchar))
                        # You can climb onto the bricks from the tree
                        if board[p1...] == brick && !(board[p0...] in (tree,brick))
                            p1 = p0
                        end
                        transition!(person, board, p1)
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



# Linux input events are available by reading /dev/input/eventX
#
# https://unix.stackexchange.com/questions/72483/how-to-distinguish-input-from-different-keyboards/72554
# 
# The data is in binary packets defined in the linux headers.
# Relevant definitions:
#
# In /usr/src/linux-headers-4.15.0-51/include/uapi/asm-generic/posix_types.h
#
#   typedef long        __kernel_long_t;
#
# In /usr/include/linux/input.h
#
#   struct timeval {
#      __kernel_time_t     tv_sec;     /* seconds */
#      __kernel_suseconds_t    tv_usec;    /* microseconds */
#   };
#
# In
#
#   struct input_event {
#      struct timeval time;
#      __u16 type;
#      __u16 code;
#      __s32 value;
#   };
#

#=
struct timeval
    tv_sec::Clong
    tv_usec::Clong
end

struct input_type
    time::Ctimeval
    type::UInt16
    code::UInt16
    value::Int32
end

kb_stream = read("/dev/input/by-path/platform-i8042-serio-0-event-kbd")

while true
    event = read(kb_stream)
end

=#
