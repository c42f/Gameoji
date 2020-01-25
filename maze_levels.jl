# Simplistic maze like level generator

rand_turn(d) = rand((rot90p(d), rot90m(d)))

in_board(board, pos) = 1 <= pos[1] <= size(board,1) && 1 <= pos[2] <= size(board,2)

rot90p(d) = Vec(-d[2], d[1])
rot90m(d) = -rot90p(d)

"""
Observe local environment relative to coordinate frame defined by position
`pos` and direction `d`.
"""
function observe_env(board, pos, d, fill_val)
    env = fill(fill_val, MMatrix{5,5,eltype(board)})
    for i=-2:2
        px = pos[1] + i
        if 1 <= px <= size(board,1)
            for j=-2:2
                py = pos[2] + j
                if 1 <= py <= size(board,2)
                    env[i+3,j+3] = board[px,py]
                end
            end
        end
    end
    if d == SA[1,0]
        env = rotr90(env)
    elseif d == SA[0,-1]
        env = rot180(env)
    elseif d == SA[-1,0]
        env = rotl90(env)
    end
    SMatrix(env)
end

function choose_direction(coeffs, d, traversable)
    transition = coeffs * vec(traversable)
    action = argmax(transition)
    new_d = (d, rot90p(d), rot90m(d))[action]
end

function generate_maze(boardsize)
    board = fill(' ', boardsize)

    # RL problem where the goal is for the agent to live as long as possible??

    coeffs = randn(3,25)

    while sum(board .== brick) <= 0.4*prod(size(board))
        # Choose initial position, not surrounded by bricks
        pos = Vec(0,0)
        while true
            pos = Vec(rand(2:size(board,1)-1), rand(2:size(board,2)-1))
            if  board[pos...]             != brick  &&
                board[(pos .+ (-1,0))...] != brick  &&
                board[(pos .+ ( 1,0))...] != brick  &&
                board[(pos .+ (0,-1))...] != brick  &&
                board[(pos .+ (0, 1))...] != brick
                break
            end
        end
        d = rand((Vec(1,0), Vec(-1,0), Vec(0,1), Vec(0,-1)))
        for i=1:100
            out_of_bounds = Char(0)
            env = observe_env(board, pos, d, out_of_bounds)
            traversable = env .== ' '
            d = choose_direction(coeffs, d, traversable)
            pos += d
            if !in_board(board, pos)
                break
            end
            board[pos...] = brick
            #clear_screen(stdout)
            #printboard(stdout, board)
            #print(stdout, Crayon(background=:blue), "\n")
            #printboard(stdout, env)
            #print(stdout, Crayon(reset=true))
            ##display(pos)
            ##display(traversable)
            #sleep(0.51)
        end
    end

    return board
end

