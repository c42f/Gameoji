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

@component struct InventoryComp
    items::Items
end
InventoryComp() = InventoryComp(Items())

const MAIN_SCREEN_NUMBER = 1

@component struct PlayerInfoComp
    base_icon::Char
    screen_number::Int # Screen they're connected to
end

# Health contained within a health pack item
@component struct ItemHealthComp
    item_health::Int
end

# Health of a PC or monster
@component struct HealthComp
    health::Int
end

@component struct PlayerControlComp
    keymap::Dict{Any,Tuple{Symbol,Any}}
end

@component struct RandomVelocityControlComp
end

@component struct BoidControlComp
end

const DamageFlag       = UInt32
const NO_DAMAGE        = DamageFlag(0)
const EXPLOSION_DAMAGE = DamageFlag(1<<0)
const BITE_DAMAGE      = DamageFlag(1<<1)
const ALL_DAMAGE       = EXPLOSION_DAMAGE | BITE_DAMAGE

function has_flag(flags::DamageFlag, flag::DamageFlag)
    flags & flag == flag
end

function combine_flags(flags::DamageFlag...)
    fl = NO_DAMAGE
    for f in flags
        fl |= f
    end
    return fl
end

@component struct DamageDealer
    damage_type::DamageFlag
    damage_amount::Int
end

@component struct DamageImmunity
    damage_immunity::DamageFlag
end

# Reaction to dying
@component struct DeathAction
    death_action::Union{Symbol,Function}
end

function do_death(game, e, death_action, position)
    if e in death_action
        action = death_action[e].death_action
        if action isa Symbol
            # Hardcoded actions for dispatch efficiency
            if action === :explode || action === :explode2
                r = (action === :explode) ? 1 : 2
                for i in -r:r, j in -r:r
                    Entity(game,
                        SpatialComp(position + VI[i,j], VI[0,0]),
                        SpriteComp('💥', 50),
                        TimerComp(),
                        LifetimeComp(1),
                        DamageDealer(EXPLOSION_DAMAGE, 1),
                        DamageImmunity(ALL_DAMAGE),
                    )
                end
                schedule_delete!(game, e)
            elseif action == :nothing
                # pass
            else
                @warn "Unknown death action: $action"
            end
        else
            # Any other arbitrary action for generality
            action(game, e, position)
        end
    else
        schedule_delete!(game, e)
    end
end

@component struct EntityKillerComp
end

@component struct LifetimeComp
    max_age::Int
end

@component struct CollectibleComp
end

@component struct NewLevelTriggerComp
end

@component struct Spawner
    do_spawn::Function # f(game, position)
    spawn_probability::Float64
end

function Spawner(components::Tuple, probability)
    Spawner(probability) do game, pos
        Entity(game, pos, components...)
    end
end

#-------------------------------------------------------------------------------
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

#-------------------------------------------------------------------------------
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

function zero_velocity_update!(entities)
    spatial = game[SpatialComp]
    for e in entities
        spatial[e] = SpatialComp(spatial[e].position, VI[0,0])
    end
    return
end

function Overseer.update(::RandomVelocityUpdate, game::AbstractLedger)
    spatial = game[SpatialComp]
    control = game[RandomVelocityControlComp]
    if !isnothing(game.input_key) # timer update
        zero_velocity_update!(@entities_in(spatial && control))
        return
    end
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

    # FIXME: This async zero-velocity update kind of breaks boid dynamics
    if !isnothing(game.input_key) # timer update
        zero_velocity_update!(@entities_in(spatial && control))
        return
    end

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


#-------------------------------------------------------------------------------
# Lifetime events and damage system

# Entities with finite lifetime
struct LifetimeUpdate <: System end

Overseer.requested_components(::LifetimeUpdate) = (TimerComp,LifetimeComp,SpatialComp)

function Overseer.update(::LifetimeUpdate, game::AbstractLedger)
    death_action = game[DeathAction]
    for e in @entities_in(game, TimerComp && LifetimeComp && SpatialComp)
        if e.time > e.max_age
            do_death(game, bare_entity(e), death_action, e.position)
        end
    end
    delete_scheduled!(game)
end


# Random entity spawning
struct SpawnUpdate <: System end

Overseer.requested_components(::SpawnUpdate) = (SpatialComp,Spawner)

function Overseer.update(::SpawnUpdate, game::AbstractLedger)
    for spawner in @entities_in(game, SpatialComp && Spawner)
        if rand() < spawner.spawn_probability
            spawner.do_spawn(game, SpatialComp(spawner.position))
        end
    end
end


# Spatially-local damage system
struct DamageUpdate <: System end

Overseer.requested_components(::DamageUpdate) =
    (SpatialComp,DamageDealer,HealthComp,DamageImmunity,DeathAction)

function Overseer.update(::DamageUpdate, game::AbstractLedger)
    # 1. Aggregate dealt damage per position on game board
    explosion_damage = Dict{Vec2I,Int}()
    bite_damage = Dict{Vec2I,Int}()
    for e in @entities_in(game, SpatialComp && DamageDealer)
        if has_flag(e.damage_type, EXPLOSION_DAMAGE)
            explosion_damage[e.position] = get(explosion_damage, e.position, 0) + e.damage_amount
        end
        if has_flag(e.damage_type, BITE_DAMAGE)
            bite_damage[e.position] = get(bite_damage, e.position, 0) + e.damage_amount
        end
    end

    # 2. Deal damage to any entities at that position, unless they're immune to it
    health = game[HealthComp]
    damage_dealers = game[DamageDealer]
    damage_immunity = game[DamageImmunity]
    death_action = game[DeathAction]
    player_info = game[PlayerInfoComp]
    for e in @entities_in(game, SpatialComp)
        # Damage occurring at this position
        exp_dmg  = get(explosion_damage, e.position, 0)
        bite_dmg = get(bite_damage, e.position, 0)
        if exp_dmg == 0 && bite_dmg == 0
            continue
        end

        # Compute immunity
        immunity = NO_DAMAGE
        if e in damage_immunity
            immunity = damage_immunity[e].damage_immunity
        elseif e in damage_dealers
            # By default, damage dealers are immune to the type of damage they deal
            immunity |= damage_dealers[e].damage_type
        end

        # Deal the damage
        damage_amount = 0
        if !has_flag(immunity, EXPLOSION_DAMAGE)
            damage_amount += exp_dmg
        end
        if !has_flag(immunity, BITE_DAMAGE)
            damage_amount += bite_dmg
        end

        is_dead = false
        if e in health
            h = max(-9, health[e].health - damage_amount)
            health[e] = HealthComp(h)
            is_dead = h <= 0
        elseif damage_amount > 0
            is_dead = true
        end
        if is_dead
            do_death(game, bare_entity(e), death_action, e.position)
        end
    end
    delete_scheduled!(game)
end

#-------------------------------------------------------------------------------
# Player Control

struct PlayerControlUpdate <: System end

Overseer.requested_components(::PlayerControlUpdate) = (SpatialComp, PlayerControlComp, SpriteComp, InventoryComp, PlayerInfoComp)

function Overseer.update(::PlayerControlUpdate, m::AbstractLedger)
    spatial = m[SpatialComp]
    controls = m[PlayerControlComp]
    sprite = m[SpriteComp]
    health = m[HealthComp]
    inventory = m[InventoryComp]
    player_info = m[PlayerInfoComp]
    for e in @entities_in(spatial && controls && sprite && inventory && health)
        position = spatial[e].position
        velocity = VI[0,0]
        if health[e].health <= 0
            # Player is dead and can't move!
            spatial[e] = SpatialComp(position, velocity)
            continue
        end
        action,value = get(controls[e].keymap, m.input_key, (:none,nothing))
        if action === :move
            velocity = value
        elseif action == :use_item
            # TODO: Should we use the returned entity in some way rather than
            # reconstructing it?
            has_item = haskey(inventory[e].items, value)
            used_item = false
            if value == '💣' && has_item
                time_bomb = spawn_time_bomb(m, position)
                if rand() < 0.05
                    # "Crazy bomb"
                    # 5 % chance of a randomly walking ticking bomb :-D
                    m[time_bomb] = RandomVelocityControlComp()
                end
                used_item = true
            elseif value == '💠' && has_item
                # Player healing other player.
                for other_e in @entities_in(game, SpatialComp && PlayerInfoComp && HealthComp)
                    if other_e.position == position && bare_entity(other_e) != bare_entity(e)
                        health[other_e] = HealthComp(other_e.health + 5)
                        used_item = true
                        break
                    end
                end
            end
            if used_item
                pop!(inventory[e].items, value)
            end
        end
        spatial[e] = SpatialComp(position, velocity)
    end
end

#-------------------------------------------------------------------------------
# Inventory management

struct InventoryCollectionUpdate <: System end

Overseer.requested_components(::InventoryCollectionUpdate) = (InventoryComp,SpatialComp,SpriteComp,CollectibleComp)

function Overseer.update(::InventoryCollectionUpdate, m::AbstractLedger)
    inventory = m[InventoryComp]
    item_health = m[ItemHealthComp]
    health = m[HealthComp]
    spatial = m[SpatialComp]
    sprite = m[SpriteComp]
    collectible = m[CollectibleComp]

    collectors = [(e=bare_entity(e), pos=spatial[e].position, items=inventory[e].items)
                  for e in @entities_in(inventory && spatial)]

    to_delete = Entity[]
    for e in @entities_in(spatial && collectible && sprite)
        pos = spatial[e].position
        for collector in collectors
            if collector.e == bare_entity(e)
                # Entities can't collect themselves!
                continue
            end
            if pos == collector.pos
                if e in item_health && collector.e in health
                    # Transfer health
                    health[collector.e] = HealthComp(health[collector.e].health + item_health[e].item_health)
                    item_health[e] = ItemHealthComp(0)
                end
                push!(collector.items, bare_entity(e))
                push!(to_delete, bare_entity(e))
                break
            end
        end
    end
    delete!(spatial, to_delete)
end

#-------------------------------------------------------------------------------
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

#-------------------------------------------------------------------------------
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

function Overseer.update(::TerminalRenderer, game::AbstractLedger)
    if !game.do_render
        return
    end
    spatial_comp = game[SpatialComp]
    sprite_comp = game[SpriteComp]
    health = game[HealthComp]
    drawables = [(spatial=spatial_comp[e],
                  sprite=sprite_comp[e],
                  is_dead=(e in health) ? health[e].health <= 0 : false,
                  id=e.id)
                 for e in @entities_in(spatial_comp && sprite_comp)]
    sort!(drawables, by=obj->(obj.sprite.draw_priority, obj.id))
    board = fill(' ', game.board_size...)
    # Fill in board
    for obj in drawables
        pos = obj.spatial.position
        if 1 <= pos[1] <= game.board_size[1] && 1 <= pos[2] <= game.board_size[2]
            board[pos...] = obj.is_dead ? '💀' : obj.sprite.icon
        end
    end
    # Update visibility mask
    is_wall = falses(game.board_size...)
    for e in @entities_in(game, SpriteComp && SpatialComp && CollisionComp)
        if e.icon in (brick, '⬛')  # Ugh!!
            is_wall[e.position...] = true
        end
    end
    # Persistent visibility
    visibility = game.visibility
    # Immediate visibility:
    # visibility = falses(game.board_size...)
    always_visible_radius = 1
    max_visible_range = 10 #norm(game.board_size)/3
    for player in @entities_in(game, SpatialComp && PlayerInfoComp)
        # Area around the player is visible
        pos = player.position
        # Suuuuper simple ray casting!
        # Cast rays toward a fixed border of coordinates around the player.
        # Oversample a bit to ensure we hit every discrete coordinate.
        N = ceil(Int,2*π*max_visible_range)
        for i in 0:N-1
            θ = 2*π*i/N
            # w is the coordinate we're tracing toward, relative to the player.
            w = max_visible_range * SA[cos(θ), sin(θ)]
            l = norm(w)
            w = normalize(w)
            hit_wall = false
            for t in range(0, l, length=ceil(Int, 2*l))
                p = round.(Int, pos + t*w)
                if #==# p[1] < 1 || game.board_size[1] < p[1] ||
                        p[2] < 1 || game.board_size[2] < p[2]
                    break # Outside board
                end
                visibility[p...] = true
                # Always allow to see a small region around the player
                if hit_wall && t > always_visible_radius
                    break
                end
                if is_wall[p...]
                    hit_wall = true
                end
            end
        end
    end
    for ind in eachindex(board, visibility)
        if !visibility[ind]
            board[ind] = '░'
        end
    end
    # Collect and render inventories
    sidebars = []
    for e in @entities_in(game, InventoryComp && PlayerInfoComp && HealthComp)
        if e.screen_number != MAIN_SCREEN_NUMBER
            continue
        end
        sidebar = []
        push!(sidebar, " $(e.base_icon)")
        push!(sidebar, '💖'=>e.health)
        push!(sidebar, repeat('─', sidebar_width-1))
        item_counts = StatsBase.countmap([sprite_comp[i].icon for i in e.items])
        append!(sidebar, sort(item_counts))
        push!(sidebars, sidebar)
    end
    statusbar = "Level $(game.level_num)"
    # Render
    print(game.term, "\e[1;1H") # Home position
    print(game.term, sprint(printboard, game.term_size, board, sidebars, statusbar))
end
