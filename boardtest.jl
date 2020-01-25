using StaticArrays

include("types.jl")
include("display.jl")
include("maze_levels.jl")

sheight,swidth = displaysize(stdout)
height = sheight-10
width = swidth÷2

clear_screen(stdout)
printboard(stdout, generate_maze((width,height)))
