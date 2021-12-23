using REPL.TerminalMenus

#--------------------------------------------------
# Utilities
function rawmode(f, term)
    REPL.Terminals.raw!(term, true)
    try
        print(term.out_stream, "\x1b[?25l") # hide the cursor
        f()
    finally
        print(term.out_stream, "\x1b[?25h") # unhide cursor
        REPL.Terminals.raw!(term, false)
    end
end

#--------------------------------------------------
# Keyboard input

struct Key
    keyboard::UInt32  # Id for the connected keyboard (may be remote)
    keycode::UInt32
end

# Import TerminalMenus.Key codes, but converted to UInt32 constants so that all
# keys can be of the same type (the numerical values of these don't represent
# unicode code points)
for k in (:ARROW_UP, :ARROW_DOWN, :ARROW_LEFT, :ARROW_RIGHT, :DEL_KEY,
          :HOME_KEY, :END_KEY, :PAGE_UP, :PAGE_DOWN)
    @eval const $k = UInt32(REPL.TerminalMenus.$k)
end

# Some additional keys constants represented as type Char
const CTRL_C = 0x3
const CTRL_R = 0x12

# Read a UInt32 terminal key code
function read_key(io=stdin)
    keycode = REPL.TerminalMenus.readkey(io)
    c = Char(keycode)
    # Ignore caps lock - make case-insensitive
    return isascii(c) && isletter(c) ? UInt32(lowercase(c)) : keycode
end

function make_keymap(keyboard_id, mapping_pairs)
    Dict(Key(keyboard_id, UInt32(k))=>v for (k,v) in mapping_pairs)
end

#--------------------------------------------------
# Terminal output / emoji rendering

# Some emoji chars for which textwidth is incorrect (??)
const brick = '🧱'
const cupcake = '🧁'
const parrot = '🦜'
const tree = '🌴'

# Emoji should always be two characters wide, but gnome-terminal in ubuntu
# 18.04 considers some of them to be one character wide. Presumably due to
# mismatched unicode versions.
# See https://bugs.launchpad.net/ubuntu/+source/gnome-terminal/+bug/1665140
function pad_emoji_string(str, expand_narrow_chars)
    io = IOBuffer()
    for c in str
        print(io, c)
        if (expand_narrow_chars && textwidth(c) == 1) || c in (cupcake, brick, parrot)
            print(io, ' ')
        end
    end
    String(take!(io))
end

# Screen layout
#
# B - main board
# L - left sidebar
# R - right sidebar
#
# LL BBBBBB RR
# LL BBBBBB RR
# LL BBBBBB RR
# LL BBBBBB RR

function pad_sidebar(str, width)
    if isempty(str)
        return ' '^width
    end
    ws = cumsum(textwidth.(collect(str)))
    n = findfirst(>=(width), ws)
    if !isnothing(n)
        return first(str, n)
    else
        return str * ' '^(width - ws[end])
    end
end

const sidebar_width = 6

function home_pos(io)
    print(io, "\e[1;1H")
end

function clear_screen(io)
    print(io, "\e[1;1H", "\e[J")
              #homepos   #clear
end

format_sidebar_line(line::AbstractChar) = format_sidebar_line(string(line))
function format_sidebar_line(line::AbstractString)
    pad_sidebar(line, sidebar_width-1)
end
function format_sidebar_line((item,count)::Pair)
    format_sidebar_line("$(pad_emoji_string(item, true))$(lpad(count,3))")
end
format_sidebar_line(::Nothing) = format_sidebar_line("")

function format_sidebar(height, content)
    content = copy(content)
    append!(content, fill(nothing, max(height-length(content), 0)))
    formatted = format_sidebar_line.(content)
end

function printboard(io, board, sidebars)
    for i=size(board,2):-1:1
        j = size(board,2)-i+1
        if !isempty(sidebars)
            left_sidebar = sidebars[1]
            # Render first sidebar on left
            x = j <= length(left_sidebar) ? left_sidebar[j] : nothing
            print(io, format_sidebar_line(x), '│')
        end
        print(io, pad_emoji_string(board[:,i], true))
        if length(sidebars) > 1
            # Render other sidebars on right
            for sidebar in sidebars[2:end]
                x = j <= length(sidebar) ? sidebar[j] : nothing
                print(io, '│', format_sidebar_line(x))
            end
        end
        i != 1 && println(io)
    end
end

# Get the maximum size of a board which fits into the terminal
function max_board_size(io, num_players)
    h,w = displaysize(io)
    board_size = VI[(w-num_players*sidebar_width)÷2, h]
end
