using Overseer
using StaticArrays
using REPL

const Vec2I = SVector{2,Int}
const VI = SA{Int}

include("inventory.jl")

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

@component struct PlayerInfoComp
    number::Int
end

InventoryComp() = InventoryComp(Items())

@component struct PlayerLeftControlComp
end

@component struct PlayerRightControlComp
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

    collidables = [(s=spatial[e], c=collision[e], e=e) for e in @entities_in(spatial && collision)]
    sort!(collidables, by=obj->obj.c.mass, rev=true)

    board = m.board
    for obj in collidables
        pos = obj.s.position
        new_pos = obj.s.position + obj.s.velocity
        if #==# new_pos[1] < 1 || size(board,1) < new_pos[1] ||
                new_pos[2] < 1 || size(board,2) < new_pos[2] ||
                (board[pos...] == ' ' && board[new_pos...] != ' ')
            # Inelastic collision with walls / border
            spatial[obj.e] = SpatialComp(pos, VI[0,0])
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
        norm(cohesion_vel) != 0 && (cohesion_vel = normalize(cohesion_vel))
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
        if 1 <= pos[1] <= m.board_size[1] && 1 <= pos[2] <= m.board_size[2]
            m.board[pos...] = ' '
        end
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
        pos = spatial[e].position
        push!(explosion_positions, pos)
        if 1 <= pos[1] <= m.board_size[1] && 1 <= pos[2] <= m.board_size[2]
            m.board[pos...] = ' '
        end
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
                schedule_delete!(m, e)
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

struct PlayerRightControlUpdate <: System end

Overseer.requested_components(::PlayerRightControlUpdate) = (SpatialComp, PlayerRightControlComp,)

function Overseer.update(::PlayerRightControlUpdate, m::AbstractLedger)
	spatial_comp = m[SpatialComp]
	control_comp = m[PlayerRightControlComp]
    key = m.input_key
    velocity = key == ARROW_UP    ? VI[0, 1] :
               key == ARROW_DOWN  ? VI[0,-1] :
               key == ARROW_LEFT  ? VI[-1,0] :
               key == ARROW_RIGHT ? VI[1, 0] :
               VI[0,0]
    use_item = key == ' '
    for e in @entities_in(spatial_comp && control_comp)
        s = spatial_comp[e]
        spatial_comp[e] = SpatialComp(s.position, velocity)
        if use_item
            # Some tests of various entity combinations

            # Rising Balloon
            Entity(m, SpatialComp(s.position, VI[0,1]),
                   SpriteComp('🎈', 1))

            # Ticking, random walking bomb. Lol
            clocks = collect("🕛🕐🕑🕒🕓🕔🕕🕖🕗💣🕘💣🕙💣🕚")
            Entity(m, SpatialComp(s.position, VI[0,0]),
                   #RandomVelocityControlComp(),
                   TimerComp(),
                   SpriteComp('💣', 1),
                   AnimatedSpriteComp(clocks),
                   ExplosionComp(length(clocks), 2),
                   ExplosiveReactionComp(:none)
                   )

            # Fruit random walkers :-D
            Entity(m, SpatialComp(s.position, VI[0,0]),
                   RandomVelocityControlComp(),
                   SpriteComp(rand(collect("🍅🍆🍇🍈🍉🍊🍋🍌🍍🍎🍏🍐🍑🍒🍓")), 1),
                   TimerComp(),
                   LifetimeComp(rand(1:10)+rand(1:10)))
        end
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

    for e in @entities_in(spatial && collectible && sprite)
        pos = spatial[e].position
        for collector in collectors
            if pos == collector.pos
                push!(collector.items, sprite[e].icon)
                schedule_delete!(m, e)
                break
            end
        end
    end
    delete_scheduled!(m)
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
    board = copy(m.board)
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
    left_sidebar = fill("", size(m.board,2))
    right_sidebar = fill("", size(m.board,2))
    for e in @entities_in(inventory && player_info)
        if player_info[e].number == 1
            sidebar = right_sidebar
        elseif player_info[e].number == 2
            sidebar = left_sidebar
        else
            continue
        end
        for (j,(item,count)) in enumerate(inventory[e].items)
            if j > length(sidebar)
                break
            end
            sidebar[end+1-j] = "$(item)$(lpad(count,3))"
        end
    end
    # Render
    printboard(m, board, left_sidebar, right_sidebar)
end

#-------------------------------------------------------------------------------
# Actual Game

mutable struct Gameoji <: AbstractLedger
    term
    input_key
    board_size::Vec2I
    board::Matrix{Char}
    ledger::Ledger
end

function Gameoji(term)
    h,w = displaysize(stdout)
    board_size = VI[(w-2*sidebar_width)÷2, h]
    board = fill(' ', tuple(board_size...))
    ledger = Ledger(
        Stage(:control, [RandomVelocityUpdate(), BoidVelocityUpdate(), PlayerRightControlUpdate()]),
        Stage(:dynamics, [PositionUpdate()]),
        Stage(:lifetime, [InventoryCollectionUpdate(), LifetimeUpdate(),
                          TimedExplosion(), ExplosionDamageUpdate(), EntityKillUpdate()]),
        Stage(:rendering, [AnimatedSpriteUpdate(), TerminalRenderer()]),
        Stage(:dynamics_post, [TimerUpdate()]),
    )
    Gameoji(term, '\0', board_size, board, ledger)
end

function Base.show(io::IO, game::Gameoji)
    print(io, "Gameoji on $(game.board_size[1])×$(game.board_size[2]) board with $(length(game.ledger.entities) - length(game.ledger.free_entities)) current entities")
end

printboard(game::Gameoji, args...) = printboard(game.term, args...)

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

function init_game(term)
    game = Gameoji(term)

    game.board = generate_maze(tuple(game.board_size...))

    Entity(game.ledger,
        SpatialComp(VI[10,10], VI[0,0]),
        PlayerRightControlComp(),
        InventoryComp(),
        PlayerInfoComp(1),
        SpriteComp('👦', 1000),
        CollisionComp(1),
    )

    for _=1:4
        Entity(game.ledger,
            SpatialComp(VI[10,10], VI[0,0]),
            RandomVelocityControlComp(),
            SpriteComp('🐕', 10),
            InventoryComp(),
            CollisionComp(1),
        )
    end

    # Flocking chickens
    #boid_pos = rand_unoccupied_pos(game.board)
    for _=1:30
        seed_rand!(game.ledger, game.board,
                   # SpatialComp(boid_pos, VI[rand(-1:1), rand(-1:1)]),
                   #RandomVelocityControlComp(),
                   BoidControlComp(),
                   SpriteComp('🐔', 10),
                   CollisionComp(1),
                  )
    end

    # Collectibles
    fruits = collect("🍉🍌🍏🍐🍑🍒🍓")
    for _=1:100
        seed_rand!(game.ledger, game.board,
                   CollectibleComp(),
                   SpriteComp(rand(fruits), 2))
    end
    treasure = collect("💰💎")
    for _=1:10
        seed_rand!(game.ledger, game.board,
                   CollectibleComp(),
                   SpriteComp(rand(treasure), 2))
    end

    monsters = collect("👺👹")
    for _=1:5
        seed_rand!(game.ledger, game.board,
                   RandomVelocityControlComp(),
                   EntityKillerComp(),
                   CollisionComp(1),
                   SpriteComp(rand(monsters), 2))
    end

    # Exploding pineapples
    for _=1:5
        seed_rand!(game.ledger, game.board,
                   CollectibleComp(),
                   SpriteComp('🍍', 2),
                   TimerComp(),
                   ExplosionComp(rand(1:100)+rand(1:100), 1))
    end

    # Bombs which may be collected, but explode if there's an explosion
    for _=1:prod(game.board_size)
        seed_rand!(game.ledger, game.board,
                   SpriteComp('💣', 1),
                   ExplosiveReactionComp(:explode),
                   CollectibleComp())
    end

    game
end

include("terminal.jl")
include("maze_levels.jl")

function main()
    term = TerminalMenus.terminal
    open("log.txt", "w") do logio
        with_logger(ConsoleLogger(logio)) do
            rawmode(term) do
                in_stream = term.in_stream
                clear_screen(stdout)
                while true
                    game = init_game(term)
                    while true
                        update(game)
                        flush(logio) # Hack!
                        #=
                        if bytesavailable(in_stream) == 0
                            # Avoid repeated input lag by only drawing when no
                            # bytes are available.
                            draw(board, sprites)
                        end
                        =#
                        key = read_key()
                        @info "key" key
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
        end
    end
end
