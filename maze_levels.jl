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

@generated function Base.cumsum(a::StaticVector{N}) where {N}
    N > 0 || return :a
    es = [Symbol("e$i") for i=1:N]
    vals = [:(e1 = a[1])]
    for i=2:N
        push!(vals, :($(es[i]) = $(es[i-1]) + a[$i]))
    end
    quote
        $(vals...)
        elems = tuple($(es...))
        StaticArrays._construct_similar(a, Size(a), elems)
    end
end

function perceptron(coeffs, temperature, d, environment)
    action_weights = (coeffs * vec(environment)) ./ temperature
    action_probs = softmax(action_weights)
    action = findfirst(rand() .< cumsum(action_probs))
    #action = argmax(action_probs)
    new_d = (d, rot90p(d), rot90m(d))[action]
end

function generate_maze(boardsize)
    @load "perceptrons_1.jld2" perceptrons
    quality_dist = Categorical(normalize(first.(perceptrons), 1))
    board = fill(' ', boardsize)
    coeffs = last(perceptrons[rand(quality_dist)])
    #coeffs = randn(3,25)
    run_walkers(board, (d, env)->perceptron(coeffs, 1.0, d, env))
    return board
end

function run_walkers(board, choose_direction)
    while sum(==(' '), board) > 0.6*length(board)
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
        c = brick
        for i=1:100
            env = observe_env(board, pos, d, Char(0))
            traversable = env .== ' '
            d = choose_direction(d, traversable)
            pos += d
            if !in_board(board, pos)
                break
            end
            board[pos...] = c
            # clear_screen(stdout)
            # printboard(stdout, board)
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

