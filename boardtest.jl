# This file tests out ways of generating "maze-like" boards by randomly walking
# agents.

using StaticArrays
using LinearAlgebra
using Distributions

include("types.jl")
include("display.jl")
include("maze_levels.jl")

# Generate a unique path
function unique_path(gen)
    i = 1
    while true
        fname = gen(i)
        if !isfile(fname)
            return fname
        end
        i += 1
    end
end

function make_candidates(generator)
    perceptrons = []

    sheight,swidth = displaysize(stdout)
    height = sheight - 10
    width = swidth ÷ 2

    while true
        board = fill(' ', (width,height))
        coeffs = generator()
        board = run_walkers(board, (d, env)->perceptron(coeffs, 0.2, d, env))
        clear_screen(stdout)
        printboard(stdout, board)
        println(stdout)
        line = readline(stdin)
        if line == "q"
            break
        end
        if !isempty(line)
            try
                goodness = parse(Int, line)
                push!(perceptrons, goodness=>coeffs)
            catch
            end
        end
    end

    perceptrons
end

fname = "perceptrons_1.jld2"
#unique_path(i->"perceptrons_$i.jld2")

@load fname perceptrons
quality_dist = Categorical(normalize(first.(perceptrons), 1))
make_candidates() do
    p = last(perceptrons[rand(quality_dist)])
end

#perceptrons_new = make_candidates(()->randn(3,25) .^3)
#perceptrons_new = make_candidates(()->randn(3,25) .^3)
#append!(perceptrons, perceptrons_new)
#@save fname perceptrons

# Some of the generation schemes resulted in weird distribution normalizations
# One way to normalize them...
#=
for i=1:length(perceptrons)
    rating,coeffs = perceptrons[i]
    perceptrons[i] = rating=>coeffs ./ std(coeffs)
end
@save "perceptrons_1.jld2" perceptrons
=#

#=
sheight,swidth = displaysize(stdout)
height = sheight - 10
width = swidth ÷ 2

# RL problem where the goal is for the agent to live as long as possible??
=#
