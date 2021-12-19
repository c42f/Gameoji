# Utilities for editing the game with RemoteREPL.jl

plant_emojis = collect("🌲🌳🌱🌴🌵🌴🌳🌿🍀🍁🍂🍄")
monster_emojis = collect("👺👹")
junkfood_emojis = collect("🍔🍟🥤🍿🍕")

function find_icons(game, icon)
    es = Entity[]
    sprite = game.ledger[SpriteComp]
    for e in @entities_in(sprite)
        if sprite[e].icon == icon
            push!(es, bare_entity(e))
        end
    end
    es
end

function find_icons(game, icon, component)
    es = Entity[]
    sprite = game.ledger[SpriteComp]
    for e in @entities_in(sprite && component)
        if sprite[e].icon == icon
            push!(es, bare_entity(e))
        end
    end
    es
end

function set_god_mode(e)
    pop!(collision, e)
    entity_killer[e] = EntityKillerComp()
end

function reconstruct_background(game)
    background = fill(' ', game.board_size...)
    collision = game.ledger[CollisionComp]
    spatial = game.ledger[SpatialComp]
    sprite = game.ledger[SpriteComp]
    for e in @entities_in(collision && spatial)
        if collision[e].mass >= 100 # assumed to be background/walls
            pos = spatial[e].position
            background[pos...] = sprite[e].icon
        end
    end
    background
end

function spawn_vault(game)
    make_vault!(game.board_size, reconstruct_background(game))
end

function spawn_exit(game)
    make_exit!(game.board_size, reconstruct_background(game))
end

function spawn_bombs(game, number)
    background = reconstruct_background(game)
    flood_fill!(game.ledger, background, rand_unoccupied_pos(background),
                number,
                SpriteComp('💣', 1),
                ExplosiveReactionComp(:explode),
                CollectibleComp())
end

function spawn_exploding_pineapples(game, number)
    background = reconstruct_background(game)
    for _=1:number
        seed_rand!(game.ledger, background,
                   CollectibleComp(),
                   SpriteComp('🍍', 2),
                   TimerComp(),
                   ExplosionComp(rand(1:100)+rand(1:100), 1))
    end
end

function spawn_pineapples(game, number)
    background = reconstruct_background(game)
    for _=1:number
        seed_rand!(game.ledger, background,
                   CollectibleComp(),
                   SpriteComp('🍍', 2),
                   )
    end
end


function spawn_collectibles(game, emojis, number)
    background = reconstruct_background(game)
    if number > prod(game.board_size)
        flood_fill!(game.ledger, background, rand_unoccupied_pos(background),
                    number,
                    CollectibleComp(),
                    SpriteComp(rand(emojis), 2))
    else
        for _=1:number
            seed_rand!(game.ledger, background,
                       CollectibleComp(),
                       SpriteComp(rand(emojis), 2),
                       )
        end
    end
end


function spawn_bombs(game, number)
    background = reconstruct_background(game)
    flood_fill!(game.ledger, background, rand_unoccupied_pos(background),
                number,
                SpriteComp('💣', 1),
                ExplosiveReactionComp(:explode),
                CollectibleComp())
end

function spawn_boids(game, number, icon::Char, components...)
    background = reconstruct_background(game)
    for _=1:number
        seed_rand!(game.ledger, background,
                   # SpatialComp(boid_pos, VI[rand(-1:1), rand(-1:1)]),
                   #RandomVelocityControlComp(),
                   BoidControlComp(),
                   SpriteComp(icon, 10),
                   CollisionComp(1),
                   CollectibleComp(),
                   components...
                  )
    end
end

function spawn_chickens(game, number, components...)
    spawn_boids(game, number, '🐔')
end

function spawn_time_bombs(game, number)

    clocks = collect("🕛🕐🕑🕒🕓🕔🕕🕖🕗🕘🕙🕚")

    background = reconstruct_background(game)
    for _=1:number
        seed_rand!(game.ledger, background,
               TimerComp(),
               SpriteComp('💣', 20),
               AnimatedSpriteComp(clocks),
               ExplosionComp(length(clocks), 2),
               ExplosiveReactionComp(:none))
    end
end

function spawn_monsters(game, number)
    background = reconstruct_background(game)
    monsters = collect("👺👹")
    for _=1:number
        seed_rand!(game.ledger, background,
                   RandomVelocityControlComp(),
                   EntityKillerComp(),
                   CollisionComp(1),
                   SpriteComp(rand(monsters), 2))
    end
end

function delete_icons(game, icon)
    map(find_icons(game, icon, game[SpatialComp])) do e
        schedule_delete!(game.ledger, e)
    end
    delete_scheduled!(game.ledger)
end

function spawn_vault(game)
    background_chars = fill(' ', reverse(displaysize(stdout)) .÷ (2,1))
    make_vault!(game, background_chars)
end

#-------------------------------------------------------------------------------

collision     = game.ledger[CollisionComp]
spatial       = game.ledger[SpatialComp]
sprite        = game.ledger[SpriteComp]
collectible   = game.ledger[CollectibleComp]
entity_killer = game.ledger[EntityKillerComp]
inventory     = game.ledger[InventoryComp]
player_info   = game.ledger[PlayerInfoComp]

player_characters = collect(@entities_in(player_info))

function find_player(game, base_icon)
    player_info = game.ledger[PlayerInfoComp]
    for player in @entities_in(player_info)
        if player_info[player].base_icon == base_icon
            return player
        end
    end
    return nothing
end

function findall_by_comp(f::Function, game, comp_type)
    comp = game.ledger[comp_type]
    es = Entity[]
    for e in @entities_in(comp)
        if f(comp[e])
            push!(es, bare_entity(e))
        end
    end
    return es
end

function findall_by_comp(game, comp_type)
    comp = game.ledger[comp_type]
    collect(@entities_in(comp))
end

boy   = find_player(game, '👦')
girl  = find_player(game, '👧')

@info "Player Characters" boy girl

function rand_position_players(game)
	spatial = game.ledger[SpatialComp]
    player_info = game.ledger[PlayerInfoComp]

    for player in @entities_in(player_info)
        p = VI[rand(1:game.board_size[1]), rand(1:game.board_size[2])]
        spatial[player] = SpatialComp(p, VI[0,0])
    end
end

function remove_monsters(game)
    for m in monster_icons
        delete_icons(game, m)
    end
end

function teleport(game, entity, to_icon)
    spatial = game.ledger[SpatialComp]
    spatial[entity] = spatial[rand(find_icons(game, to_icon, spatial))]
end

