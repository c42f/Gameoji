using Overseer
using StaticArrays
using REPL

const Vec2I = SVector{2,Int}
const VI = SA{Int}

#-------------------------------------------------------------------------------
# Components

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

@component struct PlayerComp
    number::Int
    # items::Items
end

@component struct PlayerLeftControlComp
end

@component struct PlayerRightControlComp
end

@component struct RandomVelocityControlComp
end

@component struct TimerComp
    time::Int
end


#-------------------------------------------------------------------------------
# Systems

# Timer updates

struct TimerUpdate <: System end

Overseer.requested_components(::TimerUpdate) = (TimerComp,)

function Overseer.update(::TimerUpdate, m::AbstractLedger)
	timer = m[TimerComp]
    for e in @entities_in(timer)
        timer[e] += 1
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
    do_balloon = key == ' '
    for e in @entities_in(spatial_comp && control_comp)
        s = spatial_comp[e]
        spatial_comp[e] = SpatialComp(s.position, velocity)
        if do_balloon
            Entity(m, SpatialComp(s.position, VI[0,1]),
                   SpriteComp('🎈', 1))
        end
	end
end


# Rendering

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
        icon = obj.sprite.icon
        if 1 <= pos[1] <= m.board_size[1] && 1 <= pos[2] <= m.board_size[2]
            board[pos...] = icon
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
        Stage(:rendering, [TerminalRenderer()])
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
    rawmode(term) do
        in_stream = term.in_stream
        clear_screen(stdout)
        while true
            update(game)
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
