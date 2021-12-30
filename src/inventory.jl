# Items, keyed by glyph
struct Items
    table::AbstractLedger
    es::Vector{Entity}
end

Items(table::AbstractLedger) = Items(table, Vector{Entity}())
Items(table::AbstractLedger, entities::Entity...) = Items(table, Entity[entities...])

function _find_by_icon(items::Items, c::Char)
    sprite = items.table[SpriteComp]
    findfirst(e->(e in sprite && sprite[e].icon == c), items.es)
end

Base.haskey(items::Items, c::Char) = !isnothing(_find_by_icon(items, c))
Base.getindex(items::Items, c::Char) = _find_by_icon(items, c)

Base.push!(items::Items, e::Entity) = push!(items.es, e)

function Base.pop!(items::Items, c::Char)
    i = _find_by_icon(items, c)
    isnothing(i) ? nothing : splice!(items.es, i)
end

Base.iterate(items::Items) = iterate(items.es)
Base.iterate(items::Items, state) = iterate(items.es, state)
Base.length(items::Items) = length(items.es)
Base.eltype(items::Items) = Entity

