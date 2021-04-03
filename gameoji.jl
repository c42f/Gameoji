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
    screen_number::Int # Screen they're connected to
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
    if m.input_key != nothing
        return # Hack: input events don't cause timer updates
    end
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

function Overseer.update(::NewLevelUpdate, game::AbstractLedger)
    spatial = game[SpatialComp]
    player_info = game[PlayerInfoComp]
    new_level = game[NewLevelTriggerComp]

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
        new_level!(game)
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
    sidebars = []
    for e in @entities_in(inventory && player_info)
        if player_info[e].screen_number != 1
            continue
        end
        sidebar = []
        push!(sidebar, " $(player_info[e].base_icon)")
        push!(sidebar, "─────")
        item_counts = StatsBase.countmap([sprite_comp[i].icon
                                          for i in inventory[e].items])
        append!(sidebar, sort(item_counts))
        push!(sidebars, sidebar)
    end
    # Render
    print(m.term, "\e[1;1H") # Home position
    print(m.term, sprint(printboard, board, sidebars...))
end

#-------------------------------------------------------------------------------
# Actual Game

mutable struct Gameoji <: AbstractLedger
    term
    next_keyboard_id::Int
    input_key::Union{Key,Nothing}
    board_size::Vec2I
    ledger::Ledger
    start_positions
    level_num::Int
    joined_players::Vector
end

function Gameoji(term)
    h,w = displaysize(stdout)
    board_size = VI[(w-2*sidebar_width)÷2, h]
    Gameoji(term, 1, nothing, board_size, gameoji_ledger(), [VI[1,1]], 0, [])
end

function gameoji_ledger()
    Ledger(
        Stage(:control, [RandomVelocityUpdate(), BoidVelocityUpdate(), PlayerControlUpdate()]),
        Stage(:dynamics, [PositionUpdate()]),
        Stage(:dynamics_post, [TimerUpdate()]),
        Stage(:lifetime, [InventoryCollectionUpdate(), LifetimeUpdate(),
                          TimedExplosion(), ExplosionDamageUpdate(), EntityKillUpdate()]),
        Stage(:new_level, [NewLevelUpdate()]),
        Stage(:rendering, [AnimatedSpriteUpdate(), TerminalRenderer()]),
    )
end

function reset!(game::Gameoji)
    empty!(entities(game))
    game.input_key = nothing
    game.ledger = gameoji_ledger()
    game.level_num = 0
    for (screen_number,icon,keymap) in game.joined_players
        create_player!(game, screen_number, icon, keymap)
    end
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
        if spatial[e].position in to_delete && !(e in new_entities)
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

# Keys. May be bound to a keyboard using make_keymap()
right_hand_keys = Dict(
    ARROW_UP   =>(:move, VI[0, 1]),
    ARROW_DOWN =>(:move, VI[0,-1]),
    ARROW_LEFT =>(:move, VI[-1,0]),
    ARROW_RIGHT=>(:move, VI[1, 0]),
    '0'        =>(:use_item, '💣'),
    '9'        =>(:use_item, '💠'))

left_hand_keys = Dict(
    'w'=>(:move, VI[0, 1]),
    's'=>(:move, VI[0,-1]),
    'a'=>(:move, VI[-1,0]),
    'd'=>(:move, VI[1, 0]),
    '1'=>(:use_item, '💣'),
    '2'=>(:use_item, '💠'))

function join_player!(game, screen_number, icon, keymap)
    push!(game.joined_players, (screen_number, icon, keymap))
    player = create_player!(game, screen_number, icon, keymap)
    position_players!(game, [player])
end

function create_player!(game, screen_number, icon, keymap)
    items = Items(game.ledger)
    for i=1:5
        push!(items, Entity(game.ledger, SpriteComp('💣', 2)))
    end

    Entity(game.ledger,
        PlayerControlComp(keymap),
        InventoryComp(items),
        PlayerInfoComp(icon, screen_number),
        SpriteComp(icon, 1000),
        CollisionComp(1),
        ExplosiveReactionComp(:die),
    )
end

function position_players!(game, players)
    spatial = game.ledger[SpatialComp]
    for (i,player) in enumerate(players)
        pos = game.start_positions[mod1(i, length(game.start_positions))]
        spatial[player] = SpatialComp(pos, VI[0,0])
    end
end

function position_players!(game)
    player_info = game.ledger[PlayerInfoComp]
    position_players!(game, @entities_in(player_info))
end

function add_keyboard(game)
    id = game.next_keyboard_id
    game.next_keyboard_id += 1
    return id
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
    for _=1:4*(game.level_num-1)
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

include("maze_levels.jl")
include("client_server.jl")

# Global game object for use with RemoteREPL
game = nothing

function main()
    term = TerminalMenus.terminal
    open("log.txt", "w") do logio
        with_logger(ConsoleLogger(logio)) do
            @sync begin
                game_server = nothing
                repl_server = nothing
                try
                    repl_server = listen(Sockets.localhost, 27754)
                    @async begin
                        # Allow live modifications
                        serve_repl(repl_server)
                    end
                catch exc
                    @error "Failed to set up REPL server" exception=(exc,catch_backtrace())
                end
                global game = Gameoji(term)
                main_keyboard_id = add_keyboard(game)
                join_player!(game, 1, '👧',
                             make_keymap(main_keyboard_id, left_hand_keys))
                join_player!(game, 1, '👦',
                             make_keymap(main_keyboard_id, right_hand_keys))
                event_channel = Channel()
                try
                    game_server = listen(Sockets.localhost, default_port)
                    @async begin
                        # Allow live modifications
                        serve_game(game_server, event_channel, game)
                    end
                catch exc
                    @error "Failed to set up Gameoji server" exception=(exc,catch_backtrace())
                end
                @info "Initialized game"
                try
                    rawmode(term) do
                        clear_screen(stdout)
                        @async try while true
                            reset!(game)
                            new_level!(game)
                            while isopen(event_channel)
                                Base.invokelatest(update, game)
                                flush(logio) # Hack!
                                (type,value) = take!(event_channel)
                                @debug "Read event" type value
                                if type === :key
                                    key = value
                                    if key.keycode == CTRL_C
                                        # Clear
                                        clear_screen(stdout)
                                        return
                                    elseif key.keycode == CTRL_R
                                        clear_screen(stdout)
                                        break
                                    end
                                    game.input_key = key
                                else
                                    game.input_key = nothing
                                end
                            end
                        end
                        catch exc
                            @error "Game event loop failed" exception=(exc,catch_backtrace())
                            close(event_channel)
                        end
                        frame_timer = Timer(0; interval=0.2)
                        @async while true
                            # Frame timer events
                            wait(frame_timer)
                            isopen(event_channel) || break
                            push!(event_channel, (:timer,nothing))
                        end
                        # It appears we need to wait on stdin in the original
                        # task, otherwise we miss events (??)
                        try
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
end

function test_level_gen()
    term = TerminalMenus.terminal
    game = Gameoji(term)

    background_chars = fill(' ', reverse(displaysize(stdout)) .÷ (2,1))

    make_entry!(game, background_chars)
    make_vault!(game, background_chars)
    make_exit!(game, background_chars)

    generate_maze!(background_chars)
end
