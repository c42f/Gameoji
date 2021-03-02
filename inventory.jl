struct Items
    d::Dict{Char,Int}
end

Items() = Items(Dict{Char,Int}())

Base.haskey(i::Items, x) = haskey(i.d, x)

function Base.push!(i::Items, x)
    if !haskey(i, x)
        i.d[x] = 1
    else
        i.d[x] += 1
    end
end

function Base.pop!(i::Items, x)
    if haskey(i, x)
        n = i.d[x] - 1
        if n == 0
            pop!(i.d, x)
        else
            i.d[x] = n
        end
        x
    else
        nothing
    end
end

Base.iterate(i::Items) = iterate(i.d)
Base.iterate(i::Items, state) = iterate(i.d, state)
Base.length(i::Items) = length(i.d)
Base.eltype(i::Items) = Pair{Char,Int}

