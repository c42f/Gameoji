# Simplistic maze like level generator

rand_step() = rand((Vec(1,0), Vec(-1,0), Vec(0,1), Vec(0,-1),))

in_board(board, pos) = 1 <= pos[1] <= size(board,1) && 1 <= pos[2] <= size(board,2)

function generate_maze(height, width)
    board = fill(' ', height, width)

    while true
        n_brick = sum(board .== brick)
        if n_brick >= 0.4*prod(size(board))
            break
        end
        pos = Vec(rand(1:size(board,1)), rand(1:size(board,2)))
        d = Vec(1,0)
        num_fails = 0
        while true
            board[pos...] = brick
            if rand() < 0.1
                d = rand_step()
            end
            while true
                if num_fails > 10
                    @goto path_end
                end
                p1 = pos + d
                p2 = pos + 2*d
                if !in_board(board, p1) || board[p1...] == brick ||
                    (in_board(board, p2) && board[p2...] == brick)
                    d = rand_step()
                    num_fails += 1
                    continue
                end
                num_fails = 0
                pos = pos + d
                break
            end
            #printboard(stdout, board)
            #sleep(0.01)
        end
        @label path_end
    end

    return board
end

