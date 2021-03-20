# Utilities for editing the game with RemoteREPL.jl

function find_icons(game, icon)
    es = Entity[]
    sprite = game.ledger[SpriteComp]
    for e in @entities_in(sprite)
        if sprite[e].icon == icon
            push!(es, e)
        end
    end
    es
end

function set_god_mode(e)
    pop!(collision, e)
    entity_killer[e] = EntityKillerComp()
end

function spawn_vault(game)
    make_vault(game.board_size, reconstruct_background(game))
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

function spawn_plants(game, number)
    plants = collect("🌲🌳🌱🌴🌵🌴🌳🌿🍀🍁🍂🍄")
    background = reconstruct_background(game)
    for _=1:number
        seed_rand!(game.ledger, background,
                   CollectibleComp(),
                   SpriteComp(rand(plants), 2),
                   )
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

function spawn_chickens(game, number, components...)
    background = reconstruct_background(game)
    for _=1:number
        seed_rand!(game.ledger, background,
                   # SpatialComp(boid_pos, VI[rand(-1:1), rand(-1:1)]),
                   #RandomVelocityControlComp(),
                   BoidControlComp(),
                   SpriteComp('🐔', 10),
                   CollisionComp(1),
                   CollectibleComp(),
                   components...
                  )
    end
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
    map(find_icons(game, '🐔')) do e
        schedule_delete!(game.ledger, e)
    end
    delete_scheduled!(game.ledger)
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

function find_player(game, playernum)
    player_info = game.ledger[PlayerInfoComp]
    for player in @entities_in(player_info)
        if player_info[player].number == playernum
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
            push!(es, e)
        end
    end
    return es
end

function findall_by_comp(game, comp_type)
    comp = game.ledger[comp_type]
    collect(@entities_in(comp))
end

boy   = find_player(game, 1)
girl  = find_player(game, 2)

@info "Player Characters" boy girl

