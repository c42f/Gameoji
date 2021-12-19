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

@component struct EntityKillerComp
end

@component struct ExplosionDamageComp
end

@component struct ExplosiveReactionComp
    type::Symbol # :none :damage :explode :disappear (default)
end

@component struct LifetimeComp
    max_age::Int
end

@component struct CollectibleComp
end

@component struct NewLevelTriggerComp
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
# Explosions and damage

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
    health = m[HealthComp]
    sprite = m[SpriteComp]
    for e in @entities_in(spatial && killer_tag)
        pos = spatial[e].position
        push!(killer_positions, pos)
    end
    for e in @entities_in(spatial)
        if !(e in killer_tag) && (spatial[e].position in killer_positions)
            if e in health
                h = health[e].health
                if h > 0
                    health[e] = HealthComp(h - 1)
                end
            else
                schedule_delete!(m, e)
            end
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
    player_info = m[PlayerInfoComp]
    health = m[HealthComp]
    for e in @entities_in(spatial && !exp_damage)
        pos = spatial[e].position
        if pos in explosion_positions
            r = e in reaction ? reaction[e].type : :disappear
            if r === :disappear
                schedule_delete!(m, e)
            elseif r === :damage
                # FIXME: Set movement disabled property?
                if e in health
                    # things which have health loose one health
                    h = health[e].health - 1
                    health[e] = HealthComp(h)
                end
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
                for other_e in @entities_in(game, SpatialComp && PlayerInfoComp && HealthComp)
                    if other_e.position == position && bare_entity(other_e) != bare_entity(e)
                        health[other_e] = HealthComp(other_e.health + 10)
                        break
                    end
                end
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
    # Collect and render inventories
    sidebars = []
    for e in @entities_in(game, InventoryComp && PlayerInfoComp && HealthComp)
        if e.screen_number != 1
            continue
        end
        sidebar = []
        push!(sidebar, " $(e.base_icon)")
        push!(sidebar, '💖'=>e.health)
        push!(sidebar, "─────")
        item_counts = StatsBase.countmap([sprite_comp[i].icon
                                          for i in e.items])
        append!(sidebar, sort(item_counts))
        push!(sidebars, sidebar)
    end
    # Render
    print(game.term, "\e[1;1H") # Home position
    print(game.term, sprint(printboard, board, sidebars...))
end

