module Gameoji

using Overseer
using Overseer: EMPTY_ENTITY

using StaticArrays
using REPL
using Logging
import StatsBase

using RemoteREPL
using Sockets

const Vec2I = SVector{2,Int}
const VI = SA{Int}

bare_entity(e::Overseer.AbstractEntity) = Entity(e.id)

include("terminal.jl")

#-------------------------------------------------------------------------------
# Main game data structures

mutable struct Game <: AbstractLedger
    term
    next_keyboard_id::Int
    input_key::Union{Key,Nothing}
    term_size::Vec2I
    board_size::Vec2I
    visibility::BitMatrix
    ledger::Ledger
    start_positions
    level_num::Int
    joined_players::Vector
    do_render::Bool
    is_paused::Bool
end

function Game(term, term_size, board_size)
    Game(term, 1, nothing, term_size, board_size,
         falses(board_size...), gameoji_ledger(), [VI[1,1]], 0, [], true, false)
end

function gameoji_ledger()
    Ledger(
        Stage(:control, [
            RandomVelocityUpdate(),
            BoidVelocityUpdate(),
            PlayerControlUpdate()
        ]),
        Stage(:dynamics, [
            PositionUpdate(),
            TimerUpdate()
        ]),
        Stage(:lifetime, [
            InventoryCollectionUpdate(),
            ProximityFuseUpdate(),
            DamageUpdate(),
            LifetimeUpdate(),
            SpawnUpdate(),
            DeathActionUpdate()
        ]),
        Stage(:new_level, [
            NewLevelUpdate()
        ]),
        Stage(:rendering, [
            AnimatedSpriteUpdate(),
            TerminalRenderer()
        ]),
    )
end

function reset!(game::Game)
    empty!(entities(game))
    game.input_key = nothing
    game.ledger = gameoji_ledger()
    game.level_num = 0
    # Recreate all players
    for (screen_number,icon,keymap) in game.joined_players
        create_player!(game, screen_number, icon, keymap)
    end
end

function Base.show(io::IO, game::Game)
    print(io, "Game on $(game.board_size[1])×$(game.board_size[2]) board with $(length(game.ledger.entities) - length(game.ledger.free_entities)) current entities")
end

Overseer.stages(game::Game) = stages(game.ledger)
Overseer.ledger(game::Game) = game.ledger


include("inventory.jl")
include("systems.jl")
include("levels.jl")
include("players.jl")
include("maze_levels.jl")
include("client_server.jl")

dev_mode = true

# The main game update loop
function game_loop(game, event_channel)
    while true
        Base.invokelatest() do
            try
                reset!(game)
                new_level!(game)
            catch
                if dev_mode
                    @error "Level creation failed" exception=current_exceptions()
                else
                    rethrow()
                end
            end
        end
        game.is_paused = false
        clear_screen(stdout)
        while isopen(event_channel)
            if !game.is_paused
                # Allow live code modification
                Base.invokelatest() do
                    # Use our own update loop here so we can add in a try-catch
                    # for development mode.
                    for (stage_name,systems) in stages(game)
                        for system in systems
                            try
                                update(system, game)
                            catch exc
                                global dev_mode
                                if dev_mode
                                    @error("Exception running system update",
                                           system, exception=current_exceptions())
                                else
                                    rethrow()
                                end
                            end
                        end
                    end
                end
            end
            (event_type,value) = take!(event_channel)
            @debug "Read event" event_type value
            if event_type === :key
                key = value
                if key.keycode == CTRL_C
                    # Clear
                    clear_screen(stdout)
                    return
                elseif key.keycode == UInt32('p')
                    game.is_paused = !game.is_paused
                end
            end
            if !game.is_paused
                # Terminal rendering is _slow_, so drop frames if there's
                # more events in the buffer. This reduces latency between
                # keyboard input and seeing the results.
                game.do_render = !isready(event_channel)
                if event_type === :key
                    if key.keycode == CTRL_R
                        clear_screen(stdout)
                        break
                    end
                    game.input_key = key
                else
                    game.input_key = nothing
                end
            end
        end
    end
end

function run_game(player_info)
    term = TerminalMenus.terminal
    open("log.txt", "w") do logio
        with_logger(ConsoleLogger(IOContext(logio, :color=>true))) do
            @sync begin
                game_server = nothing
                repl_server = nothing
                try
                    # Live code modification via RemoteREPL
                    repl_server = listen(Sockets.localhost, 27754)
                    @async begin
                        serve_repl(repl_server, on_client_connect=sess->sess.in_module=Gameoji)
                    end
                catch exc
                    @error "Failed to set up REPL server" exception=(exc,catch_backtrace())
                end
                # Use global Game object for access from RemoteREPL.jl
                tsize = term_size(term)
                global game = Game(term, tsize,
                                   max_board_size(tsize, length(player_info)))
                event_channel = Channel()
                try
                    # Game server for local players to join with keyboards from
                    # other devices
                    game_server = listen(Sockets.localhost, gameoji_default_port)
                    @async begin
                        serve_game(game_server, event_channel, game)
                    end
                catch exc
                    @error "Failed to set up Gameoji server" exception=(exc,catch_backtrace())
                end
                @info "Initialized game"
                try
                    rawmode(term) do
                        # Main game loop
                        @async try
                            game_loop(game, event_channel)
                        catch exc
                            @error "Game event loop failed" exception=(exc,catch_backtrace())
                            close(event_channel)
                            # Close stdin to terminate wait on keyboard input
                            close(stdin)
                        end

                        # Frame timer events
                        @async try
                            frame_timer = Timer(0; interval=0.2)
                            while true
                                wait(frame_timer)
                                isopen(event_channel) || break
                                push!(event_channel, (:timer,nothing))
                                # Hack! flush stream
                                flush(logio)
                            end
                        catch exc
                            if isopen(event_channel)
                                @error "Adding key failed" exception=(exc,catch_backtrace())
                            end
                        end

                        # Main keyboard handling.
                        # It seems we need run this in the original task,
                        # otherwise we miss events (??)
                        try
                            main_keyboard_id = add_keyboard(game)
                            join_players!(game, player_info, main_keyboard_id,
                                          MAIN_SCREEN_NUMBER)
                            while true
                                keycode = read_key(stdin)
                                key = Key(main_keyboard_id, keycode)
                                @debug "Read key" key Char(key.keycode)
                                push!(event_channel, (:key, key))
                                if keycode == CTRL_C
                                    break
                                end
                            end
                        catch exc
                            @error "Adding key failed" exception=(exc,catch_backtrace())
                            rethrow()
                        finally
                            close(event_channel)
                        end
                    end
                finally
                    close(event_channel)
                    isnothing(repl_server) || close(repl_server)
                    isnothing(game_server) || close(game_server)
                end
            end
        end
    end
    write(stdout, read("log.txt"))
end

function select_players()
    player_info = []
    if isempty(player_info)
        selection = string.(collect("🦊👾🐖🐈🐨🐇🐢🦖🦕👧👦🧔"))
        pushfirst!(selection, "[none]")
        menu = REPL.TerminalMenus.RadioMenu(selection)
        for i=1:length(keymaps)
            default_sel = i > 3 ? 1 : i+1
            p = REPL.TerminalMenus.request("Select player $i", menu,
                                           cursor=default_sel)
            if p != 1
                push!(player_info, (keymaps[i], only(selection[p])))
            end
        end
    end
    return player_info
end

function main(args)
    remote = false
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "-r"
            remote = true
        else
            error("Unknown option: \"$arg\"")
        end
        i += 1
    end
    player_info = select_players()
    if isempty(player_info)
        println(stderr, "ERROR: Must have at least one keymap selected")
        exit(1)
    end
    if remote
        Gameoji.run_game_client(; player_info)
    else
        run_game(player_info)
    end
end

end
