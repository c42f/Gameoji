using JLD2
using LinearAlgebra
using Distributions

# Simplistic maze like level generator

rand_turn(d) = rand((rot90p(d), rot90m(d)))

in_board(board, pos) = 1 <= pos[1] <= size(board,1) && 1 <= pos[2] <= size(board,2)

rot90p(d) = VI[-d[2], d[1]]
rot90m(d) = -rot90p(d)

"""
Observe local environment relative to coordinate frame defined by position
`pos` and direction `d`. The standard non-rotated orientation is when d == [1,0].
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
    if d == SA[-1,0]
        env = rot180(env)
    elseif d == SA[0,1]
        env = rotr90(env)
    elseif d == SA[0,-1]
        env = rotl90(env)
    end
    SMatrix(env)
end

function softmax(xs)
    e = exp.(xs .- maximum(xs))
    e ./ sum(e)
end

function perceptron(coeffs, temperature, d, env)
    traversable = env .== ' '
    action_weights = (coeffs * vec(traversable)) ./ temperature
    action_probs = softmax(action_weights)
    action = findfirst(rand() .< cumsum(action_probs))
    #action = argmax(action_probs)
    new_d = (d, rot90p(d), rot90m(d))[action]
    (new_d, true)
end

function wall_avoiding_perceptron(coeffs, temperature, d, env)
    traversable = env .== ' '
    action_weights = (coeffs * vec(traversable)) ./ temperature
    action_probs = softmax(action_weights)
    action = findfirst(rand() .< cumsum(action_probs))
    vs = (VI[1,0], VI[0,1], VI[0,-1])
    # Try various actions to avoid a wall
    for a in (action, 1, 2, 3, 4)
        if a == 4
            return (VI[0,0], false)
        end
        new_p = VI[3,3] + vs[a]
        if env[new_p...] ∈ (' ',brick,'\0')
            action = a
            break
        end
    end
    new_d = (d, rot90p(d), rot90m(d))[action]
    return (new_d, true)
end

function generate_maze!(board)
    perceptrons = jldopen(f->f["perceptrons"], joinpath(Base.pkgdir(Gameoji), "data/perceptrons_1.jld2"))
    quality_dist = Categorical(normalize(first.(perceptrons), 1))
    coeffs = last(perceptrons[rand(quality_dist)])
    #coeffs = randn(3,25)
    run_walkers(board, (d, env)->wall_avoiding_perceptron(coeffs, 1.0, d, env))
    return board
end

function run_walkers(board, choose_direction)
    while sum(==(' '), board) > 0.6*length(board)
        # Choose initial position, surrounded by spaces
        pos = VI[0,0]
        while true
            pos = VI[rand(2:size(board,1)-1), rand(2:size(board,2)-1)]
            if  board[pos...]             == ' '  &&
                board[(pos .+ (-1,0))...] == ' '  &&
                board[(pos .+ ( 1,0))...] == ' '  &&
                board[(pos .+ (0,-1))...] == ' '  &&
                board[(pos .+ (0, 1))...] == ' '
                break
            end
        end
        d = rand((VI[1,0], VI[-1,0], VI[0,1], VI[0,-1]))
        for i=1:100
            env = observe_env(board, pos, d, Char(0))
            (d, continue_walk) = choose_direction(d, env)
            if !continue_walk
                break
            end
            pos += d
            if !in_board(board, pos)
                break
            end
            board[pos...] = brick
            #=
            if i % 50 == 1
                home_pos(stdout)
                printboard(stdout, board)
            end
            =#
            # print(stdout, Crayon(background=:blue))
            # println(stdout)
            # println(stdout, "-----")
            # printboard(stdout, env)
            # println(stdout, "\n-----")
            # print(stdout, Crayon(reset=true))
            # #display(pos)
            # #display(traversable)
            # sleep(0.51)
        end
    end

    return board
end

