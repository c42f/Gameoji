using Sockets
using Serialization

# We're using a client-server message-based design here rather than the
# RPC-style interface natural in Distributed...

const protocol_magic = "Hi❤From❤Gamoji😸\n"
const default_port = 12345

function serve_game(server::Base.IOServer, event_channel, game)
    open_sockets = Set()
    @sync try
        while isopen(server)
            socket = accept(server)
            push!(open_sockets, socket)
            peer=getpeername(socket)
            @info "Gamoji client opened a connection" peer
            @async try
                serve_game_session(socket, event_channel, game)
            catch exc
                if !(exc isa EOFError && !isopen(socket))
                    @warn "Something went wrong evaluating client command" #=
                        =# exception=exc,catch_backtrace()
                end
            finally
                @info "Game client exited" peer
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
    try
        write(socket, protocol_magic)
        keyboard_id = nothing
        while isopen(socket)
            event = deserialize(socket)
            type,value = event
            if type === :join
                icon = value
                keyboard_id = add_keyboard(game)
                join_player!(game, keyboard_id, icon,
                             make_keymap(keyboard_id, right_hand_keys))
                # TODO: Rendering
                #=
                add_render_callback(game, player) do board
                    serialize(socket, (:render, board))
                end
                =#
            elseif type == :leave
                close(socket)
                # Delete player from ledger
                player_info = game[PlayerInfoComp]
                for player in @entities_in(player_info)
                    if player_info[player].screen_number == keyboard_id
                        schedule_delete!(game, player)
                    end
                end
                delete_scheduled!(game)
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
        close(socket)
    end
end

function run_game_client(host=Sockets.localhost, port=default_port)
    socket = connect(host, port)
    magic = String(read(socket, sizeof(protocol_magic)))
    if magic != protocol_magic
        error("Gameoji protocol magic number mismatch: $(repr(magic)) != $(repr(protocol_magic))")
    end
    serialize(socket, (:join, '🧔'))
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
