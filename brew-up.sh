#!/bin/bash

function prompt_checkbox() {
    # little helpers for terminal print control and key input
    ESC=$(printf "\033")
    cursor_blink_on() { printf "$ESC[?25h"; }
    cursor_blink_off() { printf "$ESC[?25l"; }
    cursor_to() { printf "$ESC[$1;${2:-1}H"; }
    print_inactive() { printf "$2 $1"; }
    print_active() { printf "$2 $ESC[7m$1$ESC[27m"; }
    get_cursor_row() {
        IFS=';' read -sdR -p $'\E[6n' ROW COL
        echo ${ROW#*[}
    }
    print_separator() {
        local title=$1
        local len=$2
        local line=$(printf "%$((($len - ${#title}) / 2))s" | tr ' ' '-')
        printf "$ESC[38;5;245m$line $title $line$ESC[m"
    }
    is_separator() {
        if [[ ${1:0:1} == '|' && ${1: -1} == '|' ]]; then
            return 0
        else
            return 1
        fi
    }
    key_input() {
        local key
        IFS= read -rsn1 key 2>/dev/null >&2
        if [[ $key = "" ]]; then echo enter; fi
        if [[ $key = $'\x20' ]]; then echo space; fi
        if [[ $key = $'\x1b' ]]; then
            read -rsn2 key
            if [[ $key = [A ]]; then echo up; fi
            if [[ $key = [B ]]; then echo down; fi
        fi
    }
    toggle_option() {
        local arr_name=$1
        eval "local arr=(\"\${${arr_name}[@]}\")"
        local option=$2
        if [[ ${arr[option]} == true ]]; then
            arr[option]=
        else
            arr[option]=true
        fi
        eval $arr_name='("${arr[@]}")'
    }

    local retval=$1
    local options
    local defaults
    local max_str_len=0

    IFS=';' read -r -a options <<<"$2"
    if [[ -z $3 ]]; then
        defaults=()
    else
        IFS=';' read -r -a defaults <<<"$3"
    fi
    local selected=()

    for ((i = 0; i < ${#options[@]}; i++)); do
        selected+=("${defaults[i]}")
        printf "\n"
        if [ ${#options[$i]} -gt $max_str_len ]; then
            max_str_len=${#options[$i]}
        fi
    done

    # determine current screen position for overwriting the options
    local lastrow=$(get_cursor_row)
    local startrow=$(($lastrow - ${#options[@]}))

    # ensure cursor and input echoing back on upon a ctrl+c during read -s
    trap "cursor_blink_on; stty echo; printf '\n'; exit" 2
    cursor_blink_off

    local active=0
    while true; do
        # print options by overwriting the last lines
        local idx=0
        for option in "${options[@]}"; do
            local prefix="◯"
            if [[ ${selected[idx]} == true ]]; then
                prefix="◉"
            fi

            cursor_to $(($startrow + $idx))
            if is_separator $option; then
                print_separator ${option:1:(${#option} - 2)} $max_str_len
            else
                if [ $idx -eq $active ]; then
                    print_active "$option" "$prefix"
                else
                    print_inactive "$option" "$prefix"
                fi
            fi
            ((idx++))
        done

        # user key control
        case $(key_input) in
        space) toggle_option selected $active ;;
        enter) break ;;
        up)
            ((active--))
            if [ $active -lt 0 ]; then active=$((${#options[@]} - 1)); fi
            if is_separator ${options[$active]}; then ((active--)); fi
            ;;
        down)
            ((active++))
            if is_separator ${options[$active]}; then ((active++)); fi
            if [ $active -ge ${#options[@]} ]; then active=0; fi
            ;;
        esac
    done

    # cursor position back to normal
    cursor_to $lastrow
    printf "\n"
    cursor_blink_on
    eval $retval='("${selected[@]}")'
}

function split() {
    local string=$1
    local output=$2
    local delimiter=$3
    local oldIFS=$IFS
    if [[ -z "$delimiter" ]]; then
        delimiter=$'\n'
    fi
    IFS=$delimiter
    eval $output='($string)'
    IFS=$oldIFS
}

set -o errexit
set -o pipefail

if [[ $1 == '-h' ]]; then
    echo "usage: brew-up [-s]"
    exit
fi
if [[ $1 != '-s' ]]; then
    brew update
fi

outdated=$(brew outdated -v --formula)
outdated_cask=$(brew outdated --cask --greedy --verbose)

if [[ -z ${outdated} && -z ${outdated_cask} ]]; then
    exit
fi

options=()
formulae_len=0

if [[ ! -z ${outdated} ]]; then
    split "${outdated[*]//</❯}" list
    options=("${options[@]}" "${list[@]}")
    formulae_len=${#list[@]}
fi

if [[ ! -z ${outdated_cask} ]]; then
    split "${outdated_cask[*]//!=/❯}" list
    options=("${options[@]}" '|Cask|' "${list[@]}")
fi

printf '\n'
prompt_checkbox result "$(
    IFS=$';'
    echo "${options[*]}"
)"

formulae=''
token=''

for i in "${!result[@]}"; do
    if [[ ${result[$i]} == true ]]; then
        option=${options[$i]%% *}
        if [[ $i -gt $formulae_len ]]; then
            token="${token} ${option}"
        else
            formulae="${formulae} ${option}"
        fi
    fi
done

if [[ ! -z ${formulae} ]]; then
    echo "brew upgrade$formulae"
    brew upgrade$formulae
fi

if [[ ! -z ${token} ]]; then
    echo "brew upgrade --cask$token"
    brew upgrade --cask$token
fi
