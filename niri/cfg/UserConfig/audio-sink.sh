#!/usr/bin/env bash

SINK_FILE="$HOME/.local/state/audio-selected-sink"

# Icons
iDIR="$HOME/.config/swaync/icons"

# Ensure state dir exists
mkdir -p "$(dirname "$SINK_FILE")"

friendly_name() {
    pactl list sinks | awk -v sink="$1" '
        $1=="Name:" && $2==sink {found=1}
        found && $1=="Description:" {
            $1=""; sub(/^ /, ""); print; exit
        }'
}

get_selected_sink() {
    if [[ -f "$SINK_FILE" ]]; then
        cat "$SINK_FILE"
    else
        pactl info | awk -F': ' '/Default Sink/ {print $2}'
    fi
}

save_selected_sink() {
    echo "$1" > "$SINK_FILE"
}

# launcher detection
detect_launcher() {
    if command -v fuzzel &>/dev/null; then
        echo "fuzzel --dmenu"
        return
    fi
    if command -v wofi &>/dev/null; then
        echo "wofi --dmenu -p 'Select Audio Sink'"
        return
    fi
    if command -v rofi &>/dev/null; then
        echo "rofi -dmenu -p 'Select Audio Sink'"
        return
    fi
    echo ""
}

LAUNCHER=$(detect_launcher)

select_sink() {
    [[ -z "$LAUNCHER" ]] && { notify-send "No launcher found"; exit 1; }

    declare -A sink_map
    local friendly_list="" current chosen sink_id

    current=$(get_selected_sink)

    while read -r _ sink _; do
        friendly=$(friendly_name "$sink")
        [[ -z "$friendly" ]] && friendly="$sink"

        sink_map["$friendly"]="$sink"

        if [[ "$sink" == "$current" ]]; then
            friendly_list+="* $friendly\n"
        else
            friendly_list+="  $friendly\n"
        fi
    done < <(pactl list sinks short)

    chosen=$(printf "%b" "$friendly_list" | eval "$LAUNCHER" | sed 's/^[* ]*//')

    [[ -z "$chosen" ]] && exit 0

    sink_id="${sink_map[$chosen]}"
    [[ -z "$sink_id" ]] && exit 1

    save_selected_sink "$sink_id"
    notify_custom "$(friendly_name "$sink_id")" "Selected"
}

cycle_sink() {
    local direction="$1"
    local sinks current index new_index new_sink

    mapfile -t sinks < <(pactl list sinks short | awk '{print $2}')
    current=$(pactl info | awk -F': ' '/Default Sink/ {print $2}')

    for i in "${!sinks[@]}"; do
        [[ "${sinks[$i]}" == "$current" ]] && index=$i
    done

    [[ -z "$index" ]] && exit 1

    if [[ "$direction" == "next" ]]; then
        new_index=$(( (index + 1) % ${#sinks[@]} ))
    else
        new_index=$(( (index - 1 + ${#sinks[@]}) % ${#sinks[@]} ))
    fi

    new_sink="${sinks[$new_index]}"
    pactl set-default-sink "$new_sink"

    notify_custom "$(friendly_name "$new_sink")" "Default Sink Set"
}

get_volume() {
    pactl get-sink-volume "$(get_selected_sink)" | awk 'NR==1 {print $5}' | tr -d '%'
}

get_icon() {
    local v=$(get_volume)

    if [[ "$v" == "0" ]]; then
        echo "$iDIR/volume-mute.png"
    elif (( v <= 30 )); then
        echo "$iDIR/volume-low.png"
    elif (( v <= 60 )); then
        echo "$iDIR/volume-mid.png"
    else
        echo "$iDIR/volume-high.png"
    fi
}

notify_custom() {
    local sink_name="$1"
    local message="$2"
    local volume=$(get_volume)
    local icon=$(get_icon)

    notify-send --app-name=audio-sink-device -e -h int:value:"$volume" \
        -h string:x-canonical-private-synchronous:volume_notif \
        -u low -i "$icon" \
        " $sink_name:" " $message: $volume%"
}

change_volume() {
    pactl set-sink-volume "$(get_selected_sink)" "$1"
    notify_custom "$(friendly_name "$(get_selected_sink)")" "Volume"
}

toggle_mute() {
    pactl set-sink-mute "$(get_selected_sink)" toggle
    notify_custom "$(friendly_name "$(get_selected_sink)")" "Toggle"
}

watch_sink_changes() {
    pactl subscribe | while read -r line; do
        [[ "$line" =~ "sink" ]] || continue
        current=$(pactl info | awk -F': ' '/Default Sink/ {print $2}')
        notify_custom "$(friendly_name "$current")" "Output Changed"
    done
}

case "$1" in
    select) select_sink ;;
    next) cycle_sink next ;;
    prev) cycle_sink prev ;;
    mute) toggle_mute ;;
    +5%) change_volume "+5%" ;;
    -5%) change_volume "-5%" ;;
    watch) watch_sink_changes ;;
    *) echo "Usage: $0 {select|next|prev|mute|+5%|-5%|watch}" ;;
esac