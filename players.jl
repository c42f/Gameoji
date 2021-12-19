# Keys. May be bound to a keyboard using make_keymap()
right_hand_keys = Dict(
    ARROW_UP   =>(:move, VI[0, 1]),
    ARROW_DOWN =>(:move, VI[0,-1]),
    ARROW_LEFT =>(:move, VI[-1,0]),
    ARROW_RIGHT=>(:move, VI[1, 0]),
    '0'        =>(:use_item, '💣'),
    '9'        =>(:use_item, '💠'))

left_hand_keys = Dict(
    'w'=>(:move, VI[0, 1]),
    's'=>(:move, VI[0,-1]),
    'a'=>(:move, VI[-1,0]),
    'd'=>(:move, VI[1, 0]),
    '1'=>(:use_item, '💣'),
    '2'=>(:use_item, '💠'))

function join_player!(game, screen_number, icon, keymap)
    push!(game.joined_players, (screen_number, icon, keymap))
    player = create_player!(game, screen_number, icon, keymap)
    position_players!(game, [player])
    player
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
        CollisionComp(1),
        ExplosiveReactionComp(:damage),
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
