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
    junkfood      = collect("🍔🍟🥤🍿🍕")
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


#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------
# Functions for spawning game items


function spawn_vault(game, background=reconstruct_background(game))
    layout = """
        ⬛⬛⬛⬛⬛⬛⬛⬛
        ⬛............⬛
        ⬛............⬛
        ⬛............⬛
        ⬛............⬛
        ⬛............⬛
        ⬛⬛⬛🚪⬛⬛⬛⬛"""

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
                   CollisionComp(100, WALL_COLLIDE),
                   DamageImmunity(ALL_DAMAGE)
                  )
        elseif c == '🚪'
            Entity(game.ledger, pos,
                   SpriteComp(c, 0),
                   CollisionComp(100, DOOR_COLLIDE),
                  )
        else
            Entity(game.ledger, pos,
                   SpriteComp(c, 0),
                  )
        end
    end
end

function spawn_exit(game, background=reconstruct_background(game))
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
                   DamageImmunity(ALL_DAMAGE),
                  )
        elseif c == '🚪'
            Entity(game.ledger, pos,
                   SpriteComp(c, 0),
                   CollisionComp(100, DOOR_COLLIDE),
                  )
        elseif c == '🌀'
            Entity(game.ledger, pos,
                   SpriteComp(c, 0),
                   NewLevelTriggerComp(),
                   DamageImmunity(BITE_DAMAGE)
                  )
        else
            Entity(game.ledger, pos,
                   SpriteComp(c, 0),
                  )
        end
    end
end

function spawn_entry(game, background)
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
                   DamageImmunity(ALL_DAMAGE),
                  )
        elseif c == '🚪'
            Entity(game.ledger, pos,
                   SpriteComp(c, 0),
                   CollisionComp(100, DOOR_COLLIDE),
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

function reconstruct_background(game)
    background = fill(' ', game.board_size...)
    for e in @entities_in(game, CollisionComp && SpatialComp && SpriteComp)
        if e.mass >= 100 # assumed to be background/walls
            pos = e.position
            background[pos...] = e.icon
        end
    end
    background
end

function spawn_bombs(game, num_bombs,
        background_chars=reconstruct_background(game))
    # Bombs which may be collected, but explode if there's an explosion
    flood_fill!(game.ledger, background_chars,
        rand_unoccupied_pos(background_chars),
        num_bombs,
        SpriteComp('💣', 1),
        DamageImmunity(BITE_DAMAGE),
        DeathAction(:explode),
        CollectibleComp()
    )
end

function spawn_time_bomb(game, position)
    clocks = collect("🕛🕐🕑🕒🕓🕔🕕🕖🕗🕘🕙🕚")
    Entity(game,
        SpatialComp(position, VI[0,0]),
        TimerComp(),
        SpriteComp('💣', 20),
        AnimatedSpriteComp(clocks),
        LifetimeComp(length(clocks)),
        DeathAction(:explode2),
        DamageImmunity(ALL_DAMAGE)
    )
end

function spawn_exploding_pineapples(game, number,
        background_chars=reconstruct_background(game))
    for _=1:number
        seed_rand!(game.ledger, background_chars,
            CollectibleComp(),
            SpriteComp('🍍', 2),
            TimerComp(),
            LifetimeComp(rand(1:100)+rand(1:100)),
            DeathAction(:explode)
        )
    end
end

function spawn_ghosts(game, number,
        background_chars=reconstruct_background(game);
        monster_icons=collect("👺👹"))
    for _ = 1:number
        # A ghost monster which spawns monsters
        seed_rand!(game.ledger, background_chars,
            RandomVelocityControlComp(),
            DamageImmunity(BITE_DAMAGE),
            CollisionComp(1),
            SpriteComp('👻', 4),
            Spawner(0.001) do game, pos
                Entity(game, pos,
                       RandomVelocityControlComp(),
                       DamageDealer(BITE_DAMAGE, 5),
                       CollisionComp(1),
                       SpriteComp(rand(monster_icons), 4))
            end
        )
    end
end

function spawn_monsters(game, number,
        background_chars=reconstruct_background(game);
        icons=collect("👺👹"))
    for _ in 1:number
        seed_rand!(game.ledger, background_chars,
            RandomVelocityControlComp(),
            DamageDealer(BITE_DAMAGE, 5),
            CollisionComp(1),
            SpriteComp(rand(icons), 4)
        )
    end
end

function spawn_chickens(game, number,
        background_chars=reconstruct_background(game))
    for _=1:number
        seed_rand!(game.ledger, background_chars,
            BoidControlComp(),
            SpriteComp('🐔', 10),
            CollisionComp(1),
            CollectibleComp(),
            Spawner(  # chickens lay eggs which provide health
                (SpriteComp('🥚', 10),
                 CollectibleComp(),
                 ItemHealthComp(1)),
                0.0005
            )
        )
    end
end

#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------
# Level building
function new_level!(game)
    game.level_num += 1
    game.visibility .= false

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

    spawn_entry(game, background_chars)
    if rand() < 0.3
        spawn_vault(game, background_chars)
    end
    spawn_exit(game, background_chars)

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
    for _=1:30
        seed_rand!(game.ledger, background_chars,
            BoidControlComp(),
            SpriteComp('🐔', 10),
            CollisionComp(1),
            CollectibleComp(),
            Spawner(  # chickens lay eggs which provide health
                (SpriteComp('🥚', 10),
                 CollectibleComp(),
                 ItemHealthComp(1)),
                0.0005
            )
        )
    end

    # Collectibles
    edibles = collect("🍉🍌🍏🍐🍑🍒🍓🍊🥝🍅🍎🥑🥕🍈🍇🥦🥔🌽🥥")
    for _=1:30
        seed_rand!(game.ledger, background_chars,
            CollectibleComp(),
            SpriteComp(rand(edibles), 2),
            DamageImmunity(BITE_DAMAGE),
        )
    end
    treasure = collect("💰💎")
    for _=1:10
        seed_rand!(game.ledger, background_chars,
                   CollectibleComp(),
                   SpriteComp(rand(treasure), 2))
    end

    # Poison spiders
    for _=1:5
        seed_rand!(game.ledger, background_chars,
                   CollectibleComp(),
                   DamageDealer(BITE_DAMAGE, 2),
                   SpriteComp(spider, 2))
    end

    # Health packs
    for _=1:2
        seed_rand!(game.ledger, background_chars,
            CollectibleComp(),
            SpriteComp('💠', 2),
            DamageImmunity(BITE_DAMAGE),
        )
    end
    for _=1:5
        seed_rand!(game.ledger, background_chars,
                   CollectibleComp(),
                   ItemHealthComp(2),
                   SpriteComp('💖', 3))
    end

    monster_icons=collect("👺👹")
    spawn_monsters(game, 2*(game.level_num-1), background_chars; icons=monster_icons)

    spawn_ghosts(game, 1; monster_icons)

    spawn_exploding_pineapples(game, 5, background_chars)

    for _=1:2
        spawn_bombs(game, length(background_chars) ÷ 20, background_chars)
    end

    position_players!(game)

    game
end

