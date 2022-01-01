# Keys. May be bound to a keyboard using make_keymap()
right_keys = Dict(
    ARROW_UP   =>(:move, VI[0, 1]),
    ARROW_DOWN =>(:move, VI[0,-1]),
    ARROW_LEFT =>(:move, VI[-1,0]),
    ARROW_RIGHT=>(:move, VI[1, 0]),
    '0'        =>(:use_item, '💣'),
    '-'        =>(:use_item, '🔨'),
    '='        =>(:use_item, '💠'))

left_keys = Dict(
    'w'=>(:move, VI[0, 1]),
    's'=>(:move, VI[0,-1]),
    'a'=>(:move, VI[-1,0]),
    'd'=>(:move, VI[1, 0]),
    '1'=>(:use_item, '💣'),
    '2'=>(:use_item, '🔨'),
    '3'=>(:use_item, '💠'))

middle_keys = Dict(
    'i'=>(:move, VI[0, 1]),
    'k'=>(:move, VI[0,-1]),
    'j'=>(:move, VI[-1,0]),
    'l'=>(:move, VI[1, 0]),
    '5'=>(:use_item, '💣'),
    '6'=>(:use_item, '🔨'),
    '7'=>(:use_item, '💠'))

function join_player!(game, screen_number, icon, keymap)
    push!(game.joined_players, (screen_number, icon, keymap))
    player = create_player!(game, screen_number, icon, keymap)
    position_players!(game, [player])
    player
end

# TODO: Do we need to distinguish keyboard_id and screen_number?
function join_players!(game, player_icons, keyboard_id, screen_number)
    all_keys = [left_keys, right_keys, middle_keys]
    if length(player_icons) == 1
        # Prefer right hand keys for single player
        all_keys = [right_keys]
    end
    for (icon,keys) in zip(player_icons, all_keys)
        join_player!(game, screen_number, icon,
                     make_keymap(keyboard_id, keys))
    end
end

function delete_player!(game, player)
    delete!(game.ledger, [player])
end

function create_player!(game, screen_number, icon, keymap)
    items = Items(game.ledger)
    for i=1:5
        push!(items, Entity(game.ledger, SpriteComp('💣', 2)))
    end

    Entity(game.ledger,
        PlayerControlComp(keymap),
        InventoryComp(items),
        PlayerInfoComp(icon, screen_number),
        HealthComp(5),
        SpriteComp(icon, 1000),
        CollisionComp(1, WALL_COLLIDE),
        Orientation(),
        DeathAction(:nothing),
    )
end

function position_players!(game, players)
    spatial = game.ledger[SpatialComp]
    ps = collect(players)
    length(ps) > 0 && (spatial[ps[1]] = SpatialComp(VI[1,1]))
    length(ps) > 1 && (spatial[ps[2]] = SpatialComp(game.board_size))
    #=
    for (i,player) in enumerate(players)
        pos = game.start_positions[mod1(i, length(game.start_positions))]
        spatial[player] = SpatialComp(pos, VI[0,0])
    end
    =#
end

function position_players!(game)
    player_info = game.ledger[PlayerInfoComp]
    position_players!(game, @entities_in(player_info))
end

function add_keyboard(game)
    id = game.next_keyboard_id
    game.next_keyboard_id += 1
    return id
end
