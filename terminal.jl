using TerminalMenus

using TerminalMenus: ARROW_UP, ARROW_DOWN, ARROW_LEFT, ARROW_RIGHT
const CTRL_C = Char(3)
const CTRL_R = '\x12'

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

function clear_screen(io)
    print(io, "\e[1;1H", "\e[J")
              #homepos   #clear
end

function printboard(io, board, left_sidebar=nothing, right_sidebar=nothing)
    for i=size(board,2):-1:1
        if !isnothing(left_sidebar)
            lc = pad_sidebar(left_sidebar[i], sidebar_width-1)
            print(io, pad_emoji_string(lc, false), '│')
        end
        print(io, pad_emoji_string(board[:,i], true))
        if !isnothing(right_sidebar)
            rc = pad_sidebar(right_sidebar[i], sidebar_width-1)
            print(io, '│', pad_emoji_string(rc, false))
        end
        i != 1 && println(io)
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

function read_key(io=stdin)
    k = TerminalMenus.readKey(io)
    if k in Int.((ARROW_UP, ARROW_DOWN, ARROW_LEFT, ARROW_RIGHT))
        return TerminalMenus.Key(k)
    elseif k == 3 #=^C=#
        return CTRL_C
    else
        return Char(k)
    end
end

