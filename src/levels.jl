# Utilities for building levels, 

module Emoji
    moons         = collect("🌑🌒🌓🌔🌕🌖🌗🌘")
    fruits        = collect("🍅🍆🍇🍈🍉🍊🍋🍌🍍🍎🍏🍐🍑🍒🍓")
    flowers       = collect("💮🌼💐🌺🌹🌸🌷🌻🏵")
    plants        = collect("🌲🌳🌱🌴🌵🌴🌳🌿🍀🍁🍂🍄")
    food          = collect("🌽🌾")
    treasure      = collect("💰💎")
    animals       = collect("🐇🐝🐞🐤🐥🐦🐧🐩🐪🐫")
    water_animals = collect("🐬🐳🐙🐊🐋🐟🐠🐡")
    buildings     = collect("🏰🏯🏪🏫🏬🏭🏥")
    monsters      = collect("👻👺👹👽🧟")
end

function rand_unoccupied_pos(board)
    for j=1:100
        pos = VI[rand(1:size(board,1)), rand(1:size(board,2))]
        if board[pos...] == ' '
            return pos
        end
    end
    return nothing
end

function seed_rand!(ledger::AbstractLedger, board, components::ComponentData...)
    pos = rand_unoccupied_pos(board)
    !isnothing(pos) || return
    Entity(ledger, SpatialComp(pos, VI[0,0]), components...)
end

function flood_fill!(ledger::AbstractLedger, board, position, max_fill, components::ComponentData...)
    # Temporary copy to record where we've flood filled
    board = copy(board)
    positions = Vec2I[position]
    nfilled = 0
    while !isempty(positions) && nfilled < max_fill
        p = pop!(positions)
        for i=max(p[1]-1, 1):min(p[1]+1,size(board,1))
            for j=max(p[2]-1, 1):min(p[2]+1,size(board,2))
                if board[i,j] == ' '
                    board[i,j] = 'x' # Record filled
                    nfilled += 1
                    q = VI[i,j]
                    push!(positions, q)
                    Entity(ledger, SpatialComp(q, VI[0,0]), components...)
                end
            end
        end
    end
end

empty_board(game::Game) = empty_board(game.board_size)
empty_board(board_size::AbstractVector) = fill(EMPTY_ENTITY, board_size...)

function fill_board(board_size, ledger, entities)
    board = empty_board(board_size)
    spatial = ledger[SpatialComp]
    for e in entities
        pos = spatial[e].position
    end
    board
end

#-------------------------------------------------------------------------------

function string_to_layout(str)
    function ascii_despace(s)
        # Remove every second ascii char to make variable spacing work
        cs = Char[]
        prev_ascii = false
        for c in s
            if prev_ascii
                prev_ascii = false
            else
                push!(cs, c)
                prev_ascii = isascii(c)
            end
        end
        cs
    end
    rows = ascii_despace.(split(str, '\n'))
    maxlen = maximum(length.(rows))
    reverse(hcat([[r; fill(' ', maxlen-length(r))] for r in rows]...), dims=2)
end

function overlay_board(func, board_size, background_chars, ledger, layout_str;
                       start = nothing)
    layout = string_to_layout(layout_str)

    sz = size(layout)

    if isnothing(start)
        while true
            start = VI[rand(2:(board_size[1] - sz[1] - 2)),
                       rand(2:(board_size[2] - sz[2] - 2))]
            # Environment, buffered by 1 char
            to_replace = background_chars[start[1] .+ (-1:sz[1]),
                                          start[2] .+ (-1:sz[2])]
            if all(to_replace .== ' ')
                break
            end
        end
    end

    to_delete = Set{Vec2I}()
    new_entities = Set{Entity}()

    for i = 1:size(layout,1)
        for j = 1:size(layout,2)
            c = layout[i,j]
            if c == ' '
                continue
            end
            pos = start - VI[1,1] + VI[i,j]
            background_chars[pos...] = c
            push!(to_delete, pos)
            spatialcomp = SpatialComp(pos, VI[0,0])
            if c != 'x'
                e = func(spatialcomp, c)
                if !isnothing(e)
                    push!(new_entities, e)
                end
            end
        end
    end

    spatial = ledger[SpatialComp]
    for e in @entities_in(spatial)
        if spatial[e].position in to_delete && !(bare_entity(e) in new_entities)
            schedule_delete!(ledger, e)
        end
    end
    delete_scheduled!(ledger)
end

function make_vault!(game, background)
    layout = """
          ⬛⬛⬛⬛⬛⬛
        ⬛............⬛
        ⬛............⬛
        ⬛............⬛
        ⬛............⬛
        ⬛............⬛
          ⬛⬛🚪⬛⬛⬛  """

    overlay_board(game.board_size, background, game.ledger, layout) do pos, c
        treasure = "💠💰💎"
        if c == '.'
            Entity(game.ledger, pos,
                   SpriteComp(rand(treasure), 2),
                   CollectibleComp()
                  )
        elseif c == '⬛'
            Entity(game.ledger, pos,
                   SpriteComp(c, 0),
                   CollisionComp(100),
                   ExplosiveReactionComp(:none),
                  )
        else
            Entity(game.ledger, pos,
                   SpriteComp(c, 0),
                  )
        end
    end
end

function make_exit!(game, background)
    layout = """
        ⬛⬛⬛⬛
        🚪🌀🌀⬛
        ⬛🌀🌀⬛
        ⬛⬛⬛⬛"""

    overlay_board(game.board_size, background, game.ledger, layout) do pos, c
        if c == '⬛'
            Entity(game.ledger, pos,
                   SpriteComp(c, 0),
                   CollisionComp(100),
                   ExplosiveReactionComp(:none),
                  )
        elseif c == '🌀'
            Entity(game.ledger, pos,
                   SpriteComp(c, 0),
                   NewLevelTriggerComp(),
                  )
        else
            Entity(game.ledger, pos,
                   SpriteComp(c, 0),
                  )
        end
    end
end

function make_entry!(game, background)
    layout = """
        ⬛⬛⬛⬛
        x . . ⬛
        x x x 🚪
        x x x 🚪
        x . . ⬛
        ⬛⬛⬛⬛"""

    start_pos_mid = VI[1, game.board_size[2] ÷ 2]
    start_pos = start_pos_mid - VI[0,3]

    overlay_board(game.board_size, background, game.ledger, layout;
                  start=start_pos) do pos, c
        treasure = ('💣', '💠')
        if c == '.'
            Entity(game.ledger, pos,
                   SpriteComp(rand(treasure), 2),
                   CollectibleComp()
                  )
        elseif c == '⬛'
            Entity(game.ledger, pos,
                   SpriteComp(c, 0),
                   CollisionComp(100),
                   ExplosiveReactionComp(:none),
                  )
        elseif c in '🚪'
            Entity(game.ledger, pos,
                   SpriteComp(c, 0),
                  )
        else
        end
    end

    start_positions = Vec2I[]
    for i=0:1, j=0:1
        push!(start_positions, start_pos_mid + VI[i,j])
    end
    game.start_positions = start_positions
end

function new_level!(game)
    game.level_num += 1

    # Remove players from the board; delete everything with a position
    let
        spatial = game[SpatialComp]
        player_info = game[PlayerInfoComp]
        for player in @entities_in(player_info && spatial)
            pop!(spatial,player)
        end
        for e in @entities_in(spatial)
            schedule_delete!(game, e)
        end
        delete_scheduled!(game)
    end

    # Recreate the board, and place the players in it.
    background_chars = fill(' ', game.board_size...)

    make_entry!(game, background_chars)
    make_vault!(game, background_chars)
    make_exit!(game, background_chars)

    generate_maze!(background_chars)

    # Convert maze board into entities
    for i in 1:game.board_size[1]
        for j in 1:game.board_size[2]
            c = background_chars[i,j]
            if c == brick
                Entity(game.ledger,
                       SpriteComp(c, 0),
                       SpatialComp(VI[i,j], VI[0,0]),
                       CollisionComp(100))
            end
        end
    end

    #=
    # Dog random walkers
    for _=1:4
        Entity(game.ledger,
            SpatialComp(VI[10,10], VI[0,0]),
            RandomVelocityControlComp(),
            SpriteComp('🐕', 10),
            InventoryComp(),
            CollisionComp(1),
        )
    end
    =#

    # Flocking chickens
    #boid_pos = rand_unoccupied_pos(background_chars)
    for _=1:30
        seed_rand!(game.ledger, background_chars,
                   # SpatialComp(boid_pos, VI[rand(-1:1), rand(-1:1)]),
                   #RandomVelocityControlComp(),
                   BoidControlComp(),
                   SpriteComp('🐔', 10),
                   CollisionComp(1),
                   CollectibleComp()
                  )
    end

    # Collectibles
    fruits = collect("🍉🍌🍏🍐🍑🍒🍓")
    for _=1:10
        seed_rand!(game.ledger, background_chars,
                   CollectibleComp(),
                   SpriteComp(rand(fruits), 2))
    end
    treasure = collect("💰💎")
    for _=1:10
        seed_rand!(game.ledger, background_chars,
                   CollectibleComp(),
                   SpriteComp(rand(treasure), 2))
    end

    # Health packs
    for _=1:2
        seed_rand!(game.ledger, background_chars,
                   CollectibleComp(),
                   SpriteComp('💠', 2))
    end

    monsters = collect("👺👹")
    for _=1:(game.level_num-1)
        seed_rand!(game.ledger, background_chars,
                   RandomVelocityControlComp(),
                   EntityKillerComp(),
                   CollisionComp(1),
                   SpriteComp(rand(monsters), 2))
    end

    # Exploding pineapples
    for _=1:5
        seed_rand!(game.ledger, background_chars,
                   CollectibleComp(),
                   SpriteComp('🍍', 2),
                   TimerComp(),
                   ExplosionComp(rand(1:100)+rand(1:100), 1))
    end

    # FIXME: These seeding functions only see the walls, not the collectibles
    # which already exist, but are in the ledger rather than the board.

    # Bombs which may be collected, but explode if there's an explosion
    #=
    for _ = 1:length(background_chars)÷10
        seed_rand!(game.ledger, background_chars,
                   SpriteComp('💣', 1),
                   ExplosiveReactionComp(:explode),
                   CollectibleComp())
    end
    =#
    # Bomb concentrations!
    for _=1:2
        flood_fill!(game.ledger, background_chars, rand_unoccupied_pos(background_chars),
                    length(background_chars) ÷ 20,
                    SpriteComp('💣', 1),
                    ExplosiveReactionComp(:explode),
                    CollectibleComp())
    end

    position_players!(game)

    game
end

