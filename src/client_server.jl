using Sockets
using Serialization

# We're using a client-server message-based design here rather than the
# RPC-style interface natural in Distributed...

const protocol_magic = "Hi❤From❤Gameoji😸\n"
const gameoji_default_port = 10084

function serve_game(server::Base.IOServer, event_channel, game)
    open_sockets = Set()
    @sync try
        while isopen(server)
            socket = accept(server)
            push!(open_sockets, socket)
            peer=getpeername(socket)
            @info "Gameoji client opened a connection" peer
            @async try
                serve_game_session(socket, event_channel, game)
            catch exc
                if !(exc isa EOFError && !isopen(socket))
                    @warn "Something went wrong evaluating client command" #=
                        =# exception=exc,catch_backtrace()
                end
            finally
                close(socket)
                pop!(open_sockets, socket)
            end
        end
    catch exc
        if exc isa Base.IOError && !isopen(server)
            # Ok - server was closed
            return
        end
        @error "Unexpected server failure" isopen(server) exception=exc,catch_backtrace()
        rethrow()
    finally
        for socket in open_sockets
            close(socket)
        end
    end
end

function serve_game_session(socket, event_channel, game)
    keyboard_id = nothing
    try
        write(socket, protocol_magic)
        while isopen(socket)
            event = deserialize(socket)
            type,value = event
            if type === :join
                icons = value
                keyboard_id = add_keyboard(game)
                join_players!(game, icons, keyboard_id, keyboard_id)
                # TODO: Client-side rendering?
                #=
                add_render_callback(game, player) do board
                    serialize(socket, (:render, board))
                end
                =#
            elseif type == :leave
                close(socket)
            elseif type === :key
                push!(event_channel, (:key, Key(keyboard_id, value)))
            end
            if !isopen(event_channel)
                close(socket)
            end
        end
    catch exc
        @error "Error running game session" exception=(exc,catch_backtrace())
    finally
        if !isnothing(keyboard_id)
            # Delete player from ledger
            player_info = game[PlayerInfoComp]
            for player in @entities_in(player_info)
                if player_info[player].screen_number == keyboard_id
                    schedule_delete!(game, player)
                end
            end
            delete_scheduled!(game)
        end
        close(socket)
    end
    @info "Player with keyboard $keyboard_id left the game"
end

function run_game_client(; player_icons, host=Sockets.localhost, port=gameoji_default_port)
    socket = connect(host, port)
    magic = String(read(socket, sizeof(protocol_magic)))
    if magic != protocol_magic
        error("Gameoji protocol magic number mismatch: $(repr(magic)) != $(repr(protocol_magic))")
    end
    serialize(socket, (:join, player_icons))
    rawmode(TerminalMenus.terminal) do
        while true
            keycode = read_key(stdin)
            @debug "Read key" keycode Char(keycode)
            if keycode == CTRL_C
                serialize(socket, (:leave, nothing))
                break
            else
                serialize(socket, (:key, keycode))
            end
        end
    end
end
