using Overseer
using StaticArrays
using REPL

const Vec2I = SVector{2,Int}
const VI = SA{Int}

#-------------------------------------------------------------------------------
# Components

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

@component struct PlayerComp
    number::Int
    items::Dict{Char,Int}
end

@component struct PlayerLeftControlComp
end

@component struct PlayerRightControlComp
end

@component struct RandomVelocityControlComp
end

@component struct EntityKillerComp
end

@component struct LifetimeComp
    max_age::Int
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

    #=
    #TODO: Collision resolution
    collision = m[CollisionComp]

    collidables = [(s=spatial[e], c=collision[e]) for e in @entities_in(spatial)]
    sort!(collidables, by=obj->obj.c.mass)
    =#

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

# Explosions

struct TimedExplosion <: System end

Overseer.requested_components(::TimedExplosion) = (SpatialComp,TimerComp,ExplosionComp,EntityKillerComp)

function Overseer.update(::TimedExplosion, m::AbstractLedger)
	spatial = m[SpatialComp]
	timer = m[TimerComp]
    explosion = m[ExplosionComp]
    killer_comp = m[EntityKillerComp]
    for e in @entities_in(spatial && timer && explosion)
        t = timer[e].time
        ex = explosion[e]
        r = t - ex.deadline
        if r == 0
            killer_comp[e] = EntityKillerComp()
        end
        if r >= 0
            position = spatial[e].position
            for i=-r:r, j=-r:r
                if abs(i) == r || abs(j) == r
                    Entity(m, SpatialComp(position + VI[i,j], VI[0,0]),
                           SpriteComp('💥', 50),
                           TimerComp(),
                           LifetimeComp(1),
                           EntityKillerComp(),
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
        push!(killer_positions, spatial[e].position)
    end
    for e in @entities_in(spatial)
        if !(e in killer_tag) && (spatial[e].position in killer_positions)
            schedule_delete!(m, e)
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
                   SpriteComp('💠', 1))

            # Ticking, random walking bomb. Lol
            clocks = collect("🕛🕐🕑🕒🕓🕔🕕🕖🕗💣🕘💣🕙💣🕚")
            Entity(m, SpatialComp(s.position, VI[0,0]),
                   # RandomVelocityControlComp(),
                   TimerComp(),
                   SpriteComp('💣', 1),
                   AnimatedSpriteComp(clocks),
                   ExplosionComp(length(clocks), 1))

            # Fruit random walkers :-D
            Entity(m, SpatialComp(s.position, VI[0,0]),
                   RandomVelocityControlComp(),
                   SpriteComp(rand(collect("🍅🍆🍇🍈🍉🍊🍋🍌🍍🍎🍏🍐🍑🍒🍓")), 1))
        end
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

Overseer.requested_components(::TerminalRenderer) = (SpatialComp,SpriteComp)

function Overseer.update(::TerminalRenderer, m::AbstractLedger)
	spatial_comp = m[SpatialComp]
    sprite_comp = m[SpriteComp]
    drawables = [(spatial=spatial_comp[e], sprite=sprite_comp[e], id=e.id)
                 for e in @entities_in(spatial_comp && sprite_comp)]
    sort!(drawables, by=obj->(obj.sprite.draw_priority,obj.id))
    board = fill(' ', m.board_size...)
    for obj in drawables
        pos = obj.spatial.position
        if 1 <= pos[1] <= m.board_size[1] && 1 <= pos[2] <= m.board_size[2]
            board[pos...] = obj.sprite.icon
        end
    end
    printboard(m, board)
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
    board_size = VI[w÷2,h]
    ledger = Ledger(
        Stage(:control, [RandomVelocityUpdate(), PlayerRightControlUpdate()]),
        Stage(:dynamics, [PositionUpdate()]),
        Stage(:lifetime, [LifetimeUpdate(), TimedExplosion(), EntityKillUpdate()]),
        Stage(:rendering, [AnimatedSpriteUpdate(), TerminalRenderer()]),
        Stage(:dynamics_post, [TimerUpdate()]),
    )
    Gameoji(term, '\0', board_size, ledger)
end

printboard(game::Gameoji, board) = printboard(game.term, board)

Overseer.stages(game::Gameoji) = stages(game.ledger)
Overseer.ledger(game::Gameoji) = game.ledger

function init_game(term)
    game = Gameoji(term)

    Entity(game.ledger,
        SpatialComp(VI[10,10], VI[0,0]),
        RandomVelocityControlComp(),
        SpriteComp('🐈', 10)
    )
    Entity(game.ledger,
        SpatialComp(VI[10,10], VI[0,0]),
        PlayerRightControlComp(),
        SpriteComp('👦', 1000)
    )

    game
end

include("terminal.jl")

function main()
    term = TerminalMenus.terminal
    game = init_game(term)
    open("log.txt", "w") do logio
        with_logger(ConsoleLogger(logio)) do
            rawmode(term) do
                in_stream = term.in_stream
                clear_screen(stdout)
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
                    if key == CTRL_C
                        # Clear
                        clear_screen(stdout)
                        return
                    end
                    game.input_key = key
                end
            end
        end
    end
end
