# Keys. May be bound to a keyboard using make_keymap()
keymaps = [
    Dict(
        ARROW_UP   =>(:move, VI[0, 1]),
        ARROW_DOWN =>(:move, VI[0,-1]),
        ARROW_LEFT =>(:move, VI[-1,0]),
        ARROW_RIGHT=>(:move, VI[1, 0]),
        '['        =>(:use_item, '💣'),
        ']'        =>(:use_item, '🔨'),
        '\\'       =>(:use_item, '💠')
    ),
    Dict(
        '8'=>(:move, VI[0, 1]),
        '2'=>(:move, VI[0,-1]),
        '4'=>(:move, VI[-1,0]),
        '6'=>(:move, VI[1, 0]),
        DEL_KEY   =>(:use_item, '💣'),
        END_KEY   =>(:use_item, '🔨'),
        PAGE_DOWN =>(:use_item, '💠')
    ),
    Dict(
        'd'=>(:move, VI[0, 1]),
        'c'=>(:move, VI[0,-1]),
        'x'=>(:move, VI[-1,0]),
        'v'=>(:move, VI[1, 0]),
        'q'=>(:use_item, '💣'),
        'w'=>(:use_item, '🔨'),
        'e'=>(:use_item, '💠')
    ),
    Dict(
        'h'=>(:move, VI[0, 1]),
        'n'=>(:move, VI[0,-1]),
        'b'=>(:move, VI[-1,0]),
        'm'=>(:move, VI[1, 0]),
        'r'=>(:use_item, '💣'),
        't'=>(:use_item, '🔨'),
        'y'=>(:use_item, '💠')
    ),
    Dict(
        'l'=>(:move, VI[0, 1]),
        '.'=>(:move, VI[0,-1]),
        ','=>(:move, VI[-1,0]),
        '/'=>(:move, VI[1, 0]),
        'u'=>(:use_item, '💣'),
        'i'=>(:use_item, '🔨'),
        'o'=>(:use_item, '💠')
    ),
]

function join_player!(game, screen_number, icon, keymap)
    push!(game.joined_players, (screen_number, icon, keymap))
    player = create_player!(game, screen_number, icon, keymap)
    position_players!(game, [player])
    player
end

# TODO: Do we need to distinguish keyboard_id and screen_number?
function join_players!(game, player_info, keyboard_id, screen_number)
    for (keys,icon) in player_info
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
    for (i,player) in enumerate(players)
        pos = game.start_positions[mod1(i, length(game.start_positions))]
        spatial[player] = SpatialComp(pos, VI[0,0])
    end
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
