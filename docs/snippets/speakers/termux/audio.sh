#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

SHARED_DIR="$HOME/storage/shared"
PIDFILE="/data/data/com.termux/files/usr/var/run/termux-audio.pid"
POLL_INTERVAL=5 

mkdir -p "$SHARED_DIR"
mkdir -p "$(dirname "$PIDFILE")"

rm -f "$SHARED_DIR/android_ip.txt"

unset DISPLAY WAYLAND_DISPLAY

check_dependencies() {
    local missing_pkgs=""
    
    if ! command -v jq >/dev/null 2>&1; then missing_pkgs="$missing_pkgs jq"; fi
    if ! command -v pulseaudio >/dev/null 2>&1; then missing_pkgs="$missing_pkgs pulseaudio"; fi
    if ! command -v termux-notification >/dev/null 2>&1; then missing_pkgs="$missing_pkgs termux-api"; fi

    if [[ -n "$missing_pkgs" ]]; then
        echo "Required packages are missing. Run 'pkg install$missing_pkgs' to continue."
        termux-notification \
            --id 1001 \
            --title "Dependency Error" \
            --content "The following packages are required: $missing_pkgs" \
            --priority high >/dev/null 2>&1 || true
        exit 1
    fi
}
check_dependencies

LAST_NOTIFY_TITLE=""
LAST_NOTIFY_CONTENT=""

notify() {
    local title="$1"
    local content="$2"

    if [[ "$title" == "$LAST_NOTIFY_TITLE" && "$content" == "$LAST_NOTIFY_CONTENT" ]]; then
        return 0
    fi

    termux-notification \
        --id 1001 \
        --title "$title" \
        --content "$content" \
        --priority high >/dev/null 2>&1 || true

    LAST_NOTIFY_TITLE="$title"
    LAST_NOTIFY_CONTENT="$content"
}

cleanup() {
    rm -f "$PIDFILE"
    termux-notification-remove 1001 >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

error_handler() {
    local line="$1"
    notify "Termux Audio Server Error" "Unexpected termination detected (line: $line)."
    exit 1
}
trap 'error_handler $LINENO' ERR

if [[ -f "$PIDFILE" ]]; then
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null || true)
    if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "Stopping existing process ($OLD_PID)..."
        pkill -P "$OLD_PID" 2>/dev/null || true
        kill "$OLD_PID" 2>/dev/null || true

        for _ in {1..10}; do
            if ! kill -0 "$OLD_PID" 2>/dev/null; then break; fi
            sleep 0.2
        done

        if kill -0 "$OLD_PID" 2>/dev/null; then
            kill -9 "$OLD_PID" 2>/dev/null || true
        fi
    fi
fi
echo $$ > "$PIDFILE"

validate_ip() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if ((octet < 0 || octet > 255)); then return 1; fi
        done
        return 0
    fi
    return 1
}

get_android_ip() {
    local ip
    ip=$(termux-wifi-connectioninfo 2>/dev/null | jq -r '.ip // empty' 2>/dev/null || true)
    if [[ -n "$ip" && "$ip" != "null" ]] && validate_ip "$ip"; then
        echo "$ip"
    fi
}

wait_for_audio_server() {
    local retry=30
    until pactl info >/dev/null 2>&1; do
        ((retry--)) || true
        if [[ "$retry" -le 0 ]]; then
            notify "Error" "Failed to start PulseAudio service."
            exit 1
        fi
        sleep 1
    done
}

ensure_sink() {
    if pactl list short sinks | grep -q 'AAudio_sink'; then
        pactl set-default-sink AAudio_sink >/dev/null 2>&1 || true
        return 0
    fi
    return 1
}

reload_server() {
    local module_ids
    module_ids=$(pactl list short modules | awk '$2=="module-native-protocol-tcp"{print $1}')
    for id in $module_ids; do
        pactl unload-module "$id" >/dev/null 2>&1 || true
    done

    sleep 0.2

    if ! validate_ip "${LINUX_IP}"; then
        notify "Error" "Invalid Linux IP format detected: ${LINUX_IP}"
        return 1
    fi

    if ! pactl load-module module-native-protocol-tcp \
        port=4713 \
        listen=0.0.0.0 \
        "auth-ip-acl=127.0.0.1;${LINUX_IP}" >/dev/null 2>&1; then
        notify "Error" "Failed to load the TCP module for audio forwarding."
        return 1
    fi
    
    return 0
}

ANDROID_IP="$(get_android_ip)"
if [[ -z "$ANDROID_IP" ]]; then
    notify "Error" "Unable to retrieve Android IP address. Check your Wi-Fi connection."
    exit 1
fi

echo "$ANDROID_IP" > "$SHARED_DIR/android_ip.txt"
wait_for_linux_ip() {
    notify "Waiting" "Waiting for the Linux IP address..."
    local wait_count=0
    while true; do
        if [[ -s "$SHARED_DIR/linux_ip.txt" ]]; then
            local temp_ip
            temp_ip="$(tr -d '[:space:]' < "$SHARED_DIR/linux_ip.txt")"
            if validate_ip "$temp_ip"; then
                LINUX_IP="$temp_ip"
                break
            fi
        fi
        sleep 2
        ((wait_count++)) || true
        if [[ $((wait_count % 30)) -eq 0 ]]; then
            notify "Waiting" "Still waiting for the Linux IP address... (${wait_count}s elapsed)"
        fi
    done
}
wait_for_linux_ip

if ! pulseaudio --check 2>/dev/null; then
    pulseaudio --exit-idle-time=-1 >/dev/null 2>&1 &
fi

wait_for_audio_server
ensure_sink || true

if ! reload_server; then
    exit 1
fi

notify "Audio Connection Established" "Android: $ANDROID_IP / Linux: $LINUX_IP"
termux-toast "Audio connection completed successfully." >/dev/null 2>&1 || true

while true; do
    sleep "$POLL_INTERVAL"

    NEW_ANDROID_IP="$(get_android_ip)"
    NEW_LINUX_IP=""
    UPDATED=0

    if [[ -s "$SHARED_DIR/linux_ip.txt" ]]; then
        TEMP_IP="$(tr -d '[:space:]' < "$SHARED_DIR/linux_ip.txt" 2>/dev/null || true)"
        if validate_ip "$TEMP_IP"; then
            NEW_LINUX_IP="$TEMP_IP"
        fi
    fi

    if [[ -n "$NEW_ANDROID_IP" && "$NEW_ANDROID_IP" != "$ANDROID_IP" ]]; then
        ANDROID_IP="$NEW_ANDROID_IP"
        echo "$ANDROID_IP" > "$SHARED_DIR/android_ip.txt"
        UPDATED=1
    fi

    if [[ -n "$NEW_LINUX_IP" && "$NEW_LINUX_IP" != "$LINUX_IP" ]]; then
        LINUX_IP="$NEW_LINUX_IP"
        UPDATED=1
    fi

    if [[ "$UPDATED" -eq 1 ]]; then
        if reload_server; then
            notify "IP Address Update Complete" "A: $ANDROID_IP / L: $LINUX_IP"
            termux-toast "Audio server IP update completed." >/dev/null 2>&1 || true
        fi
    fi

    ensure_sink || true
done
