#!/usr/local/bin/zsh

set -e

stty -echo

function hide_cursor() {
    gecho -en "\e[?25l"
}

function show_cursor() {
    gecho -en "\e[?12;25h"
}

hide_cursor

function show_help() {
    echo "Usage: minesweeper [height (default: 10)] [width (default: 10)] [number of bombs (default: 15% of the field)]"
    echo "    Height and width must be an integer not less than 5"
    echo "    The number of bombs must be a positive number"
    echo "    The number of bombs must be less than height * width - 9"
    echo ""
    key_description
    echo ""
    rule_description
}

function key_description() {
    echo "Keybindings"
    echo "[h][←] Left  [j][↓] Down  [k][↑] Up  [l][→] Right (just as like vim)"
    echo "[f] Put/remove a flag  [d] Open the cursored tile"
    echo "[q][Ctrl-C] Quit the game"
    echo "Tiles will automatically open recursively as long as all the adjacent tiles do not have a mine"
}

function rule_description() {
    echo "Remove all the mines by solving the puzzle!"
    echo "    Some of the tiles have a mine buried, and some others have numbers that are clues to the location of the mines"
    echo "    A number on a tile represents the number of mines hidden in the eight adjacent tiles"
    echo "    Be careful! A mine will explode immediately when you attempt to open a tile with one!"
    echo "    Use your flags to indicate where the mines are embedded"
    echo "    You will NOT get a mine in your first move: it is a pure tactical game!"
}

case $1 in
    "-h" | "--help" )
        show_help
        return 0
        ;;
    "" )
        height=10
        ;;
    * )
        if [[ $1 =~ "^[0-9]+$" && $1 -ge 5 ]]; then
            height=$1
        else
            show_help
            return 1
        fi
        ;;
esac

case $2 in
    "" )
        width=10
        ;;
    * )
        if [[ $2 =~ "^[0-9]+$" && $2 -ge 5 ]]; then
            width=$2
        else
            show_help
            return 1
        fi
        ;;
esac

case $3 in
    "" )
        bombs=$((height * width * 15 / 100))
        ;;
    * )
        if [[ $3 =~ "^[1-9][0-9]*$" && $3 -lt $((height * width - 9)) ]]; then
            bombs=$3
        else
            show_help
            return 1
        fi
        ;;
esac

blocks=$((height * width))
remaining_flags=$bombs
remaining_blocks=$((blocks - bombs))
first_open=true
key_description
echo ""
echo "Height: $height"
echo "Width: $width"
echo "Remaining Flags: $remaining_flags"
echo ""

reset_color="\e[0m"
light_grey_fg="\e[37m"
white_fg="\e[1;37m"
red_fg="\e[31m"
black_bg="\e[40m"
red_bg="\e[41m"
light_grey_bg="\e[47m"
numbers=()
number_colors=("\e[34m" "\e[32m" "\e[31m" "\e[35m" "\e[33m" "\e[34m" "\e[37m" "\e[1;37m" "\e[1;47m\e[1;30m")
for i in $(seq 1 8); do
    numbers+=("\e[40m${number_colors[i]}$i$reset_color")
done
numbers+=("${number_colors[9]}●$reset_color")
padding_num=5
padding_left="\e[${padding_num}C"

block="$light_grey_bg $reset_color"
flagged="$red_bg $reset_color"
opened="$black_bg $reset_color"

board_bomb=()
board_flag=()

gecho -en $padding_left
for i in `seq 1 $blocks`; do
    board_bomb+=("0")
    board_flag+=("-1")
    gecho -en "$block"
    if [[ $((i % width)) -eq 0 ]]; then
        gecho -e $reset_color
        gecho -en $padding_left
    fi
done

gecho -en "\e[${height}A"

y=0
x=0

function clear_format() {
    gecho -e "\e[0m\e[$((height -y))B"
    stty echo
    show_cursor
    exit 0
}

trap clear_format 1 2 3 4 5 9 15


function get_position() {
    gecho $(($1 * width + $2 + 1))
}

function in_range {
    if [[ $1 -ge 0 && $1 -lt $2 ]]; then
        return 0
    else
        return 1
    fi
}

function set_bombs() {
    print_status_bar "Deploying mines..."
    for i in $(seq $((y - 1)) $((y + 1))); do
        for j in $(seq $((x - 1)) $((x + 1))); do
            if in_range $i $height && in_range $j $width; then
                board_flag[$(get_position $i $j)]="-3"
            fi
        done
    done
    board_temp=()
    for i in $(seq 1 $blocks); do
        if [[ ${board_flag[i]} -eq -1 ]]; then
            board_temp+=($i)
        fi
    done
    bombs_chosen=("${(@f)$(shuf -i 1-${#board_temp[@]} -n $bombs)}")
    for i in $bombs_chosen; do
        bomb_n=${board_temp[i]}
        board_bomb[$bomb_n]=9
        bomb_y=$(((bomb_n - 1) / width))
        bomb_x=$(((bomb_n - 1) % width))
        for dy in $(seq $((bomb_y - 1)) $((bomb_y + 1))); do
            for dx in $(seq $((bomb_x - 1)) $((bomb_x + 1))); do
                loc_temp=$(get_position $dy $dx)
                if [[ board_bomb[$loc_temp] -eq 9 ]]; then
                    continue
                fi
                if in_range $dy $height && in_range $dx $width; then
                    board_bomb[$loc_temp]=$((board_bomb[$loc_temp] + 1))
                fi
            done
        done
    done
    first_open=false
}

function open() {
    if $first_open; then
        set_bombs
    fi
    print_status_bar "Opening tile(s)..."
    case ${board_flag[$(get_position $y $x)]} in
        "0" )
            print_status_bar "${red_fg}The block is already opened"
            return 0
            ;;
        "1" )
            print_status_bar "${red_fg}The selected cell has been flagged. Do you really want to open it? (yN)"
            show_cursor
            if read -s -q; then
                print_status_bar "Continue..."
            else
                print_status_bar "Aborting..."
                return 0
            fi
            hide_cursor
            ;;
    esac
    block_qy=($y)
    block_qx=($x)
    while [[ ${#block_qy[@]} -gt 0 ]]; do
        tile_y=${block_qy[1]}
        tile_x=${block_qx[1]}
        shift block_qy
        shift block_qx
        cur_loc=$(get_position $tile_y $tile_x)
        if [[ ${board_flag[cur_loc]} -eq 0 ]]; then
            continue
        fi
        board_flag[$cur_loc]=0
        remaining_blocks=$((remaining_blocks - 1))
        update_tile $tile_y $tile_x
        if [[ ${board_bomb[cur_loc]} -eq 9 ]]; then
            print_status_bar "${red_bg}${white_fg}A mine has exploded!"
            show_answer
        fi
        print_remaining_flags
        if [[ $remaining_blocks -le 0 ]]; then
            game_clear
        fi
        if [[ ${board_bomb[cur_loc]} -eq 0 ]]; then
            for i in $(seq $((tile_y - 1)) $((tile_y + 1))); do
                for j in $(seq $((tile_x - 1)) $((tile_x + 1))); do
                    if in_range $i $height && in_range $j $width; then
                        loc_temp=$(get_position $i $j)
                        case ${board_flag[loc_temp]} in
                            "1" | "-1" | "-3" )
                                board_flag[$loc_temp]="-2"
                                block_qy+=($i)
                                block_qx+=($j)
                                ;;
                        esac
                    fi
                done
            done
        fi
    done
    print_status_bar "Tile(s) opened!"
}

function update_tile() {
    desty=$1
    destx=$2
    cur_move="\e[s"
    if [[ $desty -gt $y ]]; then
        cur_move="${cur_move}\e[$((desty - y))B"
    elif [[ $desty -lt $y ]]; then
        cur_move="${cur_move}\e[$((y - desty))A"
    fi
    if [[ $destx -gt $x ]]; then
        cur_move="${cur_move}\e[$((destx - x))C"
    elif [[ $destx -lt $x ]]; then
        cur_move="${cur_move}\e[$((x - destx))D"
    fi
    gecho -en $cur_move
    case $board_flag[$(get_position $desty $destx)] in
        "1" )
            gecho -en $flagged
            ;;
        "-1" )
            gecho -en $block
            ;;
        "0" )
            tile_val=$board_bomb[$(get_position $desty $destx)]
            if [[ $tile_val -eq 0 ]]; then
                gecho -en $opened
            else
                gecho -en $numbers[$tile_val]
            fi
            ;;
    esac
    gecho -en "\e[u"
}

function show_answer() {
    for i in $(seq 1 $blocks); do
        board_flag[$i]=0
        update_tile $(((i - 1) / width)) $(((i - 1) % width))
    done
    clear_format
}

function flag() {
    if $first_open; then
        print_status_bar "${red_fg}Your first move must be opening a block"
        return 0
    fi
    case $board_flag[$(get_position $y $x)] in
        "0" )
            print_status_bar "${red_fg}The block is already opened"
            ;;
        * )
            cur_flag=$board_flag[$(get_position $y $x)]
            remaining_flags=$((remaining_flags + cur_flag))
            print_remaining_flags
            board_flag[$(get_position $y $x)]=$((cur_flag * -1))
            update_tile $y $x
            print_status_bar "Toggled the flag"
            ;;
    esac
}

function up() {
    if in_range $((y - 1)) $height; then
        y=$((y - 1))
        gecho -en "\e[A"
        print_status_bar "Moved up"
    else
        print_status_bar "${red_fg}Cursor is at the top"
    fi
}

function down() {
    if in_range $((y + 1)) $height; then
        y=$((y + 1))
        gecho -en "\e[B"
        print_status_bar "Moved down"
    else
        print_status_bar "${red_fg}Cursor is at the bottom"
    fi
}

function left() {
    if in_range $((x - 1)) $width; then
        x=$((x - 1))
        gecho -en "\e[D"
        print_status_bar "Moved left"
    else
        print_status_bar "${red_fg}Cursor is at the left-most position"
    fi
}

function right() {
    if in_range $((x + 1)) $width; then
        x=$((x + 1))
        gecho -en "\e[C"
        print_status_bar "Moved right"
    else
        print_status_bar "${red_fg}Cursor is at the right-most position"
    fi
}

function print_status_bar() {
    gecho -en "\e[s\e[$((y + 1))F\e[2K${light_grey_fg}Status: ${reset_color}$1${reset_color}\e[u"
}

function print_remaining_flags() {
    print_color=""
    if [[ $remaining_flags -lt 0 ]]; then
        print_color=$red_fg
    fi
    gecho -en "\e[s\e[$((y + 2))F\e[2KRemaining Flags: ${print_color}$remaining_flags${reset_color}\e[u"
}

function game_clear() {
    clear_str=""
    clear_temp=("C" "l" "e" "a" "r" "e" "d" "!")
    for i in $(seq 1 8); do
        clear_str="$clear_str${number_colors[i]}${clear_temp[i]}"
    done
    print_status_bar $clear_str
    clear_format
}

chtcd=""
while [[ $remaining_blocks -gt 0 ]]; do
    key_in=""
    show_cursor
    builtin read -s -k 1 key_in
    hide_cursor
    case $key_in in
        "j" | "J" )
            down
            ;;
        "k" | "K" )
            up
            ;;
        "h" | "H" )
            left
            ;;
        "l" | "L" )
            right
            ;;
        "d" | "D" )
            open
            ;;
        "f" | "F" )
            flag
            ;;
        "q" | "Q" )
            print_status_bar "Quitting..."
            break
            ;;
        $'\x1b' )
            escaped_in=""
            builtin read -s -k 2 escaped_in
            case $escaped_in in
                $'\x5b\x41' )
                    up
                    ;;
                $'\x5b\x42' )
                    down
                    ;;
                $'\x5b\x43' )
                    right
                    ;;
                $'\x5b\x44' )
                    left
                    ;;
            esac
            ;;
        "a" )
            chtcd="a"
            ;|
        "e" | "m" | "o" | "s" | "w" )
            chtcd+=$key_in
            ;|
        * )
            if [[ $chtcd = "awesome" ]]; then
                print_status_bar ${(j::)board_bomb}
            elif [[ $chtcd = "awesomemeow" ]]; then
                print_status_bar "Achievement unlocked: \e[1m\"A cheated victory tastes awful\""
                show_answer
            else
                print_status_bar "${red_fg}Invalid input"
            fi
            ;;
    esac
done

clear_format

return 0

