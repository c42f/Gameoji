#!/bin/bash
#=
exec julia --project=. -e 'include(popfirst!(ARGS)); main()' \
    "${BASH_SOURCE[0]}" "$@"
=#

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

include("inventory.jl")
include("terminal.jl")

#-------------------------------------------------------------------------------
# Components for game entities

@component struct TimerComp
    time::Int
end
TimerComp() = TimerComp(0)

@component struct SpatialComp
    position::Vec2I
    velocity::Vec2I
end

SpatialComp(position::Vec2I) = SpatialComp(position, VI[0,0])

@component struct CollisionComp
    mass::Int
end

@component struct SpriteComp
    icon::Char
    draw_priority::Int
end

@component struct AnimatedSpriteComp
    icons::Vector{Char}
end

@component struct ExplosionComp
    deadline::Int
    radius::Int
end

@component struct InventoryComp
    items::Items
end
InventoryComp() = InventoryComp(Items())

@component struct PlayerInfoComp
    base_icon::Char
    number::Int
end

@component struct PlayerControlComp
    keymap::Dict{Any,Tuple{Symbol,Any}}
end

@component struct RandomVelocityControlComp
end

@component struct BoidControlComp
end

@component struct EntityKillerComp
end

@component struct ExplosionDamageComp
end

@component struct ExplosiveReactionComp
    type::Symbol # :none :die :explode :disappear (default)
end

@component struct LifetimeComp
    max_age::Int
end

@component struct CollectibleComp
end

@component struct NewLevelTriggerComp
end

#-------------------------------------------------------------------------------
# Systems

# Timer updates

struct TimerUpdate <: System end

Overseer.requested_components(::TimerUpdate) = (TimerComp,)

function Overseer.update(::TimerUpdate, m::AbstractLedger)
	timer = m[TimerComp]
    for e in @entities_in(timer)
        timer[e] = TimerComp(timer[e].time + 1)
	end
end

# Position update

struct PositionUpdate <: System end

Overseer.requested_components(::PositionUpdate) = (SpatialComp,CollisionComp)

function Overseer.update(::PositionUpdate, m::AbstractLedger)
	spatial = m[SpatialComp]
    collision = m[CollisionComp]

    collidables = collect(@entities_in(spatial && collision))

    max_mass = fill(0, m.board_size...)
    for obj in collidables
        pos = spatial[obj].position
        mass = collision[obj].mass
        if max_mass[pos...] < mass
            max_mass[pos...] = mass
        end
    end

    for obj in collidables
        pos = spatial[obj].position
        new_pos = pos + spatial[obj].velocity
        obj_mass = collision[obj].mass
        if #==# new_pos[1] < 1 || m.board_size[1] < new_pos[1] ||
                new_pos[2] < 1 || m.board_size[2] < new_pos[2] ||
                (max_mass[new_pos...] > obj_mass &&
                 max_mass[pos...] >= obj_mass)
                # ^^ Allows us to get unstuck if we're in the wall 😬
            # Inelastic collision with walls / border
            spatial[obj] = SpatialComp(pos, VI[0,0])
        end
    end

    for e in @entities_in(spatial)
        s = spatial[e]
        spatial[e] = SpatialComp(s.position + s.velocity, s.velocity)
    end
end

# Random Movement of NPCs

struct RandomVelocityUpdate <: System end

Overseer.requested_components(::RandomVelocityUpdate) = (SpatialComp,RandomVelocityControlComp)

function Overseer.update(::RandomVelocityUpdate, m::AbstractLedger)
	spatial = m[SpatialComp]
    control = m[RandomVelocityControlComp]
    velocities = (VI[1,0], VI[0,1], VI[-1,0], VI[0,-1])
    for e in @entities_in(spatial && control)
        s = spatial[e]
        vel = rand(velocities)
        spatial[e] = SpatialComp(s.position, vel)
	end
end

# Boid control of NPCs

struct BoidVelocityUpdate <: System end

Overseer.requested_components(::BoidVelocityUpdate) = (SpatialComp,BoidControlComp)

function Overseer.update(::BoidVelocityUpdate, m::AbstractLedger)
	spatial = m[SpatialComp]
    control = m[BoidControlComp]

    boids = [(e,spatial[e]) for e in @entities_in(spatial && control)]
    length(boids) > 1 || return

    for e in @entities_in(spatial && control)
        pos = spatial[e].position

        # Local mean in position and velocity
        mean_pos = SA_F64[0,0]
        mean_vel = SA_F64[0,0]
        sep_vel = SA_F64[0,0]
        tot_weight = 0.0
        sep_weight = 0.0
        # O(N²) iteration
        for (e2,s) in boids
            d = pos - s.position
            d2 = d⋅d
            w = exp(-d2/4^2)
            mean_pos += w*s.position
            mean_vel += w*s.velocity
            tot_weight += w
            if e != e2 && d2 < 10
                if d == 0
                    θ = 2*π*rand()
                    d = SA[cos(θ), sin(θ)]
                end
                sw = 1/(d2+0.01)
                sep_weight += sw
                sep_vel += sw*d
            end
        end
        if tot_weight > 0
            mean_pos = mean_pos ./ tot_weight
            mean_vel = mean_vel ./ tot_weight
        end
        if sep_weight > 0
            sep_vel  = sep_vel ./ sep_weight
        end
        θ = 2*π*rand()
        rand_vel = SA[cos(θ), sin(θ)]
        cohesion_vel = mean_pos - pos
        if norm(cohesion_vel) != 0
            cohesion_vel = normalize(cohesion_vel)
        end
        vel = 0.2*cohesion_vel + 0.3*sep_vel + mean_vel + 0.5*rand_vel
        spatial[e] = SpatialComp(pos, clamp.(round.(Int, vel), -1, 1))
	end
end


# Explosions

struct TimedExplosion <: System end

Overseer.requested_components(::TimedExplosion) = (SpatialComp,TimerComp,ExplosionComp,ExplosionDamageComp)

function Overseer.update(::TimedExplosion, m::AbstractLedger)
	spatial = m[SpatialComp]
	timer = m[TimerComp]
    explosion = m[ExplosionComp]
    damage = m[ExplosionDamageComp]
    for e in @entities_in(spatial && timer && explosion)
        t = timer[e].time
        ex = explosion[e]
        r = t - ex.deadline
        if r >= 0
            position = spatial[e].position
            for i=-r:r, j=-r:r
                if abs(i) == r || abs(j) == r
                    Entity(m, SpatialComp(position + VI[i,j], VI[0,0]),
                           SpriteComp('💥', 50),
                           TimerComp(),
                           LifetimeComp(1),
                           ExplosionDamageComp(),
                          )
                end
            end
            if r >= ex.radius
                schedule_delete!(m, e)
            end
        end
	end
    delete_scheduled!(m)
end

# Sprites with finite lifetime
struct LifetimeUpdate <: System end

Overseer.requested_components(::LifetimeUpdate) = (TimerComp,LifetimeComp)

function Overseer.update(::LifetimeUpdate, m::AbstractLedger)
	timer = m[TimerComp]
    lifetime = m[LifetimeComp]
    for e in @entities_in(timer && lifetime)
        if timer[e].time > lifetime[e].max_age
            schedule_delete!(m, e)
        end
	end
    delete_scheduled!(m)
end


# Spatially deleting entities
struct EntityKillUpdate <: System end

Overseer.requested_components(::EntityKillUpdate) = (SpatialComp,EntityKillerComp)

function Overseer.update(::EntityKillUpdate, m::AbstractLedger)
	spatial = m[SpatialComp]
    killer_tag = m[EntityKillerComp]
    killer_positions = Set{Vec2I}()
    for e in @entities_in(spatial && killer_tag)
        pos = spatial[e].position
        push!(killer_positions, pos)
    end
    for e in @entities_in(spatial)
        if !(e in killer_tag) && (spatial[e].position in killer_positions)
            schedule_delete!(m, e)
        end
	end
    delete_scheduled!(m)
end

# Spatially deleting entities
struct ExplosionDamageUpdate <: System end

Overseer.requested_components(::ExplosionDamageUpdate) = (SpatialComp,ExplosionDamageComp,ExplosiveReactionComp)

function Overseer.update(::ExplosionDamageUpdate, m::AbstractLedger)
	spatial = m[SpatialComp]
    exp_damage = m[ExplosionDamageComp]
    explosion_positions = Set{Vec2I}()
    for e in @entities_in(spatial && exp_damage)
        push!(explosion_positions, spatial[e].position)
    end
    reaction = m[ExplosiveReactionComp]
    sprite = m[SpriteComp]
    for e in @entities_in(spatial && !exp_damage)
        pos = spatial[e].position
        if pos in explosion_positions
            r = e in reaction ? reaction[e].type : :disappear
            # :none :die :explode :disappear (default)
            if r === :disappear
                schedule_delete!(m, e)
            elseif r === :die
                # TODO: Set movement disabled property?
                sprite[e] = SpriteComp('💀', sprite[e].draw_priority)
            elseif r === :explode
                for i=-1:1, j=-1:1
                    Entity(m, SpatialComp(pos + VI[i,j], VI[0,0]),
                           SpriteComp('💥', 50),
                           TimerComp(),
                           LifetimeComp(1),
                           ExplosionDamageComp(),
                          )
                end
                schedule_delete!(m, e)
            elseif r === :none
                # pass
            else
                error("Unrecognized explosion reaction property $r")
            end
        end
	end
    delete_scheduled!(m)
end


# Player Control

struct PlayerControlUpdate <: System end

Overseer.requested_components(::PlayerControlUpdate) = (SpatialComp, PlayerControlComp, SpriteComp, InventoryComp, PlayerInfoComp)

function Overseer.update(::PlayerControlUpdate, m::AbstractLedger)
	spatial = m[SpatialComp]
	controls = m[PlayerControlComp]
    sprite = m[SpriteComp]
    inventory = m[InventoryComp]
    player_info = m[PlayerInfoComp]
    for e in @entities_in(spatial && controls && sprite && inventory)
        if sprite[e].icon == '💀'
            # Player is dead.
            # TODO: Might want to use something other than the icon for this
            # state machine!
            continue
        end
        position = spatial[e].position
        velocity = VI[0,0]
        action,value = get(controls[e].keymap, m.input_key, (:none,nothing))
        if action === :move
            velocity = value
        elseif action == :use_item
            # TODO: Should we use the returned entity in some way rather than
            # reconstructing it?
            has_item = !isnothing(pop!(inventory[e].items, value))

            if value == '💣' && has_item
                clocks = collect("🕛🕐🕑🕒🕓🕔🕕🕖🕗🕘🕙🕚")
                time_bomb = Entity(m,
                           SpatialComp(position, VI[0,0]),
                           TimerComp(),
                           SpriteComp('💣', 20),
                           AnimatedSpriteComp(clocks),
                           ExplosionComp(length(clocks), 2),
                           ExplosiveReactionComp(:none)
                          )
                if rand() < 0.05
                    # "Crazy bomb"
                    # 5 % chance of a randomly walking ticking bomb :-D
                    m[time_bomb] = RandomVelocityControlComp()
                end
            elseif value == '💠' && has_item
                # Player healing other player.
                # TODO: Move this out to be a more generic effect in its own system?
                for other_e in @entities_in(spatial && player_info && sprite)
                    if spatial[other_e].position == position
                        sprite[other_e] = SpriteComp(player_info[other_e].base_icon,
                                                     sprite[other_e].draw_priority)
                    end
                end
                sprite = m[SpriteComp]
            end
        end
        spatial[e] = SpatialComp(position, velocity)
	end
end

# Inventory management

struct InventoryCollectionUpdate <: System end

Overseer.requested_components(::InventoryCollectionUpdate) = (InventoryComp,SpatialComp,SpriteComp,CollectibleComp)

function Overseer.update(::InventoryCollectionUpdate, m::AbstractLedger)
    inventory = m[InventoryComp]
    spatial = m[SpatialComp]
    sprite = m[SpriteComp]
    collectible = m[CollectibleComp]

    collectors = [(pos=spatial[e].position, items=inventory[e].items)
                  for e in @entities_in(inventory && spatial)]

    to_delete = Entity[]
    for e in @entities_in(spatial && collectible && sprite)
        pos = spatial[e].position
        for collector in collectors
            if pos == collector.pos
                push!(collector.items, e)
                # When it's in an inventory, simply delete the spatial component
                push!(to_delete, e)
                break
            end
        end
    end
    delete!(spatial, to_delete)
end

# Game events
struct NewLevelUpdate <: System end

Overseer.requested_components(::NewLevelUpdate) = (PlayerInfoComp,SpatialComp,NewLevelTriggerComp)

function Overseer.update(::NewLevelUpdate, m::AbstractLedger)
    spatial = m[SpatialComp]
    player_info = m[PlayerInfoComp]
    new_level = m[NewLevelTriggerComp]

    new_level_triggers = Set([spatial[e].position
                              for e in @entities_in(spatial && new_level)])
    new_level = false
    for player in @entities_in(spatial && player_info)
        if spatial[player].position in new_level_triggers
            # Recreate
            new_level = true
            break
        end
    end
    if new_level
        # Remove players from the board, delete everything with a position,
        # recreate the board, and place the players in it.
        for player in @entities_in(player_info)
            pop!(spatial,player)
        end
        for e in @entities_in(spatial)
            schedule_delete!(m, e)
        end
        delete_scheduled!(m)
        init_board(m)
        position_players(m)
    end
end

# Graphics & Rendering

struct AnimatedSpriteUpdate <: System end

Overseer.requested_components(::AnimatedSpriteUpdate) = (TimerComp,SpriteComp,AnimatedSpriteComp)

function Overseer.update(::AnimatedSpriteUpdate, m::AbstractLedger)
	sprite = m[SpriteComp]
	anim_sprite = m[AnimatedSpriteComp]
    timer = m[TimerComp]
    for e in @entities_in(sprite && timer && anim_sprite)
        t = timer[e].time
        sprites = anim_sprite[e].icons
        sprite[e] = SpriteComp(sprites[mod1(t,length(sprites))],
                               sprite[e].draw_priority)
	end
end


struct TerminalRenderer <: System end

Overseer.requested_components(::TerminalRenderer) = (SpatialComp,SpriteComp,
                                                     InventoryComp,PlayerInfoComp)

function Overseer.update(::TerminalRenderer, m::AbstractLedger)
	spatial_comp = m[SpatialComp]
    sprite_comp = m[SpriteComp]
    drawables = [(spatial=spatial_comp[e], sprite=sprite_comp[e], id=e.id)
                 for e in @entities_in(spatial_comp && sprite_comp)]
    sort!(drawables, by=obj->(obj.sprite.draw_priority,obj.id))
    board = fill(' ', m.board_size...)
    # Fill in board
    for obj in drawables
        pos = obj.spatial.position
        if 1 <= pos[1] <= m.board_size[1] && 1 <= pos[2] <= m.board_size[2]
            board[pos...] = obj.sprite.icon
        end
    end
    # Collect and render inventories
    inventory = m[InventoryComp]
    player_info = m[PlayerInfoComp]
    left_sidebar = fill("", m.board_size[2])
    right_sidebar = fill("", m.board_size[2])
    for e in @entities_in(inventory && player_info)
        if player_info[e].number == 1
            sidebar = right_sidebar
        elseif player_info[e].number == 2
            sidebar = left_sidebar
        else
            continue
        end
        item_counts = StatsBase.countmap([sprite_comp[i].icon for i in inventory[e].items])
        for (j,(item,count)) in enumerate(item_counts)
            if j > length(sidebar)
                break
            end
            sidebar[end+1-j] = "$(item)$(lpad(count,3))"
        end
    end
    # Render
    print(m.term, "\e[1;1H") # Home position
    print(m.term, sprint(printboard, board, left_sidebar, right_sidebar))
end

#-------------------------------------------------------------------------------
# Actual Game

mutable struct Gameoji <: AbstractLedger
    term
    input_key
    board_size::Vec2I
    ledger::Ledger
end

function Gameoji(term)
    h,w = displaysize(stdout)
    board_size = VI[(w-2*sidebar_width)÷2, h]
    ledger = Ledger(
        Stage(:control, [RandomVelocityUpdate(), BoidVelocityUpdate(), PlayerControlUpdate()]),
        Stage(:dynamics, [PositionUpdate()]),
        Stage(:dynamics_post, [TimerUpdate()]),
        Stage(:lifetime, [InventoryCollectionUpdate(), LifetimeUpdate(),
                          TimedExplosion(), ExplosionDamageUpdate(), EntityKillUpdate()]),
        Stage(:new_level, [NewLevelUpdate()]),
        Stage(:rendering, [AnimatedSpriteUpdate(), TerminalRenderer()]),
    )
    Gameoji(term, '\0', board_size, ledger)
end

function Base.show(io::IO, game::Gameoji)
    print(io, "Gameoji on $(game.board_size[1])×$(game.board_size[2]) board with $(length(game.ledger.entities) - length(game.ledger.free_entities)) current entities")
end

Overseer.stages(game::Gameoji) = stages(game.ledger)
Overseer.ledger(game::Gameoji) = game.ledger

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

empty_board(game::Gameoji) = empty_board(game.board_size)
empty_board(board_size::AbstractVector) = fill(EMPTY_ENTITY, board_size...)

function fill_board(board_size, ledger, entities)
    board = empty_board(board_size)
    spatial = ledger[SpatialComp]
    for e in entities
        pos = spatial[e].position
    end
    board
end

#=
moons = collect("🌑🌒🌓🌔🌕🌖🌗🌘")
fruits = collect("🍅🍆🍇🍈🍉🍊🍋🍌🍍🍎🍏🍐🍑🍒🍓")
flowers = collect("💮🌼💐🌺🌹🌸🌷🌻🏵")
plants = collect("🌲🌳🌱🌴🌵🌴🌳🌿🍀🍁🍂🍄")
food = collect("🌽🌾")
treasure = collect("💰💎")
animals = collect("🐇🐝🐞🐤🐥🐦🐧🐩🐪🐫")
water_animals = collect("🐬🐳🐙🐊🐋🐟🐠🐡")
buildings = collect("🏰🏯🏪🏫🏬🏭🏥")
monsters = collect("👻👺👹👽🧟")
=#

function string_to_layout(str)
    # Remove every second ascii char
    ascii_despace(s) = [c for (i,c) in enumerate(s) if !isascii(c) || iseven(i)]
    rows = ascii_despace.(split(str, '\n'))
    maxlen = maximum(length.(rows))
    reverse(hcat([[r; fill(' ', maxlen-length(r))] for r in rows]...), dims=2)
end

function overlay_board(func, board_size, background_chars, ledger, layout_str)
    layout = string_to_layout(layout_str)

    sz = size(layout)

    start = VI[rand(2:(board_size[1] - sz[1] - 1)),
               rand(2:(board_size[2] - sz[2] - 1))]

    to_delete = Set{Vec2I}()
    new_entities = Set{Entity}()

    for i = 1:size(layout,1)
        for j = 1:size(layout,2)
            c = layout[i,j]
            if c == ' '
                continue
            end
            pos = start + VI[i,j]
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
        if spatial[e].position in to_delete && !(e in new_entities)
            schedule_delete!(ledger, e)
        end
    end
    delete_scheduled!(ledger)
end

function make_vault(game, background)
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

function make_exit(game, background)
    layout = """
        ⬛⬛⬛⬛
        🚪🌀🌀⬛
        ⬛🌀🌀⬛
        ⬛⬛⬛⬛"""

    overlay_board(game.board_size, background, game.ledger, layout) do pos, c
        treasure = "💠💰💎"
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

right_hand_keymap =
    Dict(ARROW_UP   =>(:move, VI[0, 1]),
         ARROW_DOWN =>(:move, VI[0,-1]),
         ARROW_LEFT =>(:move, VI[-1,0]),
         ARROW_RIGHT=>(:move, VI[1, 0]),
         '0'        =>(:use_item, '💣'),
         '9'        =>(:use_item, '💠'))

left_hand_keymap =
    Dict('w'=>(:move, VI[0, 1]),
         's'=>(:move, VI[0,-1]),
         'a'=>(:move, VI[-1,0]),
         'd'=>(:move, VI[1, 0]),
         '1'=>(:use_item, '💣'),
         '2'=>(:use_item, '💠'))

function create_player(game, icon, playernum, keymap)
    items = Items(game.ledger)
    for i=1:5
        push!(items, Entity(game.ledger, SpriteComp('💣', 2)))
    end

    e = Entity(game.ledger,
        PlayerControlComp(keymap),
        InventoryComp(items),
        PlayerInfoComp(icon, playernum),
        SpriteComp(icon, 1000),
        CollisionComp(1),
        ExplosiveReactionComp(:die),
    )
    @info "Created player" e
end

function position_players(game)
	spatial = game.ledger[SpatialComp]
    player_info = game.ledger[PlayerInfoComp]

    board_centre = game.board_size .÷ 2
    for player in @entities_in(player_info)
        spatial[player] = SpatialComp(board_centre, VI[0,0])
    end
end

function init_game(term)
    game = Gameoji(term)

    create_player(game, '👦', 1, right_hand_keymap)
    create_player(game, '👧', 2, left_hand_keymap)
    init_board(game)

    position_players(game)

    return game
end

function init_board(game)
    background_chars = generate_maze(tuple(game.board_size...))

    # Convert maze board into entities
    for i in 1:game.board_size[1]
        for j in 1:game.board_size[2]
            c = background_chars[i,j]
            if c != ' '
                Entity(game.ledger,
                       SpriteComp(c, 0),
                       SpatialComp(VI[i,j], VI[0,0]),
                       CollisionComp(100))
            end
        end
    end

    make_vault(game, background_chars)
    make_exit(game, background_chars)

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
    for _=1:200
        seed_rand!(game.ledger, background_chars,
                   CollectibleComp(),
                   SpriteComp(rand(fruits), 2))
    end
    treasure = collect("💰💎")
    for _=1:20
        seed_rand!(game.ledger, background_chars,
                   CollectibleComp(),
                   SpriteComp(rand(treasure), 2))
    end

    # Health packs
    for _=1:10
        seed_rand!(game.ledger, background_chars,
                   CollectibleComp(),
                   SpriteComp('💠', 2))
    end

    monsters = collect("👺👹")
    for _=1:5
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
                    length(background_chars)÷20,
                    SpriteComp('💣', 1),
                    ExplosiveReactionComp(:explode),
                    CollectibleComp())
    end

    game
end

include("maze_levels.jl")

# Global game object for use with RemoteREPL
game = nothing

function main()
    term = TerminalMenus.terminal
    open("log.txt", "w") do logio
        with_logger(ConsoleLogger(logio)) do
            @sync begin
                server = listen(Sockets.localhost, 27754)
                @async begin
                    # Allow live modifications
                    serve_repl(server)
                end
                try
                    rawmode(term) do
                        clear_screen(stdout)
                        # TODO: Try async read from stdin & timed game loop?
                        while true
                            # invokelatest for use with Revise.jl
                            global game = Base.invokelatest(init_game, term)
                            while true
                                Base.invokelatest(update, game)
                                flush(logio) # Hack!
                                key = read_key()
                                if key == CTRL_C
                                    # Clear
                                    clear_screen(stdout)
                                    return
                                elseif key == CTRL_R
                                    clear_screen(stdout)
                                    break
                                end
                                game.input_key = key
                            end
                        end
                    end
                finally
                    close(server)
                end
            end
        end
    end
end
