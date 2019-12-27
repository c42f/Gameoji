# The aim here is to create some kind of random level resembling an ecosystem
# of different plants (and animals?)

function generate_nature_level()
    species = collect("🌲🌳🌴🌱🌿🍀💮🌺🏵💐🌹")

    # The following 
    board = rand(1:length(species), height, width)

    for k=1:100
        for i = 1:size(board,1), j=1:size(board,2)
            i2 = clamp(i + rand(-1:1), 1, size(board,1))
            j2 = clamp(j + rand(-1:1), 1, size(board,2))
            c = board[i2, j2]
            board[i,j] = c
        end
    end

    board = species[board]
end

#=
# Some experimentation with making plant communities rather than blocks of
# single plant species.  In current form this just doesn't look that good as it
# becomes visually confusing.

plants = collect("🌲🌳🌴🌵🌱🌿🍀🍁🍂🍄")
flowers = collect("💮🌼💐🌺🌹🌸🌷🌻🏵")
animals = collect("🐇🐝🐞🐤🐥🐦🐧🐩🐪🐫")

species = vcat(plants, flowers)

N = length(species)

# Probability of species being found together
eco_matrix = exp.(-4 .* rand(N,N))
for i = 1:N
    eco_matrix[i,i] = 1
end
eco_matrix[1:7,1:7] .= 1
eco_matrix[8:10,8:10] .= 1
eco_matrix[11:end,11:end] .= 1

board = rand(1:length(species), height, width)

for k=1:10
    for i = 1:size(board,1), j=1:size(board,2)
        i2 = clamp(i + rand(-1:1), 1, size(board,1))
        j2 = clamp(j + rand(-1:1), 1, size(board,2))
        c = board[i2, j2]
        board[i,j] = c
        affinity_prob = eco_matrix[board[i,j], board[i2,j2]]
        if rand() > affinity_prob
            if rand() > 0.0
                board[i,j] = c
            else
                # Plant random species
                board[i,j] = rand(1:length(species))
                #board[i,j] = rand([1,8,11])
            end
        end
    end
end
=#

#=
# Thin things out so that the board is navigable by making spaces between the
# different species

for k=1:3
    for i = 1:size(board,1), j=1:size(board,2)
        i2 = clamp(i + rand(-1:1), 1, size(board,1))
        j2 = clamp(j + rand(-1:1), 1, size(board,2))
        c = board[i2, j2]
        if board[i,j] != c && c != ' '
            board[i,j] = ' '
        end
    end
end
=#
