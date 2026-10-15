#!/bin/bash

set -uo pipefail

MAX_RETRY=10
retry_count=0

# ==========================================
# Parameter
# ==========================================
# Mode Guide :
# 1 = Quality-First (Quality, Stereo, float32le)
# 2 = Speed-First (Speed, Stereo, s16le, latency_msec=10)
# 3 = Stable (Stable, Stereo, s16le, 44100Hz)
# 4 = Mono (Mono, 1-Channel, s16le)
CLI_MODE="1" # Default: 1 (Quality-First)

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --mode)
      if [[ "$#" -lt 2 || ! "$2" =~ ^[1-4]$ ]]; then
        echo "[Error] The --mode value must be one of: 1, 2, 3, or 4." >&2
        exit 1
      fi
      CLI_MODE="$2"
      shift 2
      ;;
    *)
      echo "[Error] Unknown option provided: $1" >&2
      exit 1
      ;;
  esac
done

set -e

# ==========================================
# 2. Set Audio Mode
# ==========================================
audio_choice="$CLI_MODE"

case "$audio_choice" in
  2)
    AUDIO_RATE=48000
    AUDIO_FORMAT="s16le"
    AUDIO_EXTRA_ARGS="latency_msec=10"
    MODE_NAME="Speed"
    echo "[Info] Selected mode: Speed Priority (minimum latency)."
    ;;
  3)
    AUDIO_RATE=44100
    AUDIO_FORMAT="s16le"
    AUDIO_EXTRA_ARGS=""
    MODE_NAME="Stable"
    echo "[Info] Selected mode: Stability Profile (compatibility focused)."
    ;;
  4)
    AUDIO_RATE=48000
    AUDIO_FORMAT="s16le"
    AUDIO_EXTRA_ARGS="channels=1"
    MODE_NAME="Mono"
    echo "[Info] Selected mode: Mono Profile (single-channel audio)."
    ;;
  *)
    AUDIO_RATE=48000
    AUDIO_FORMAT="float32le"
    AUDIO_EXTRA_ARGS=""
    MODE_NAME="Quality"
    echo "[Info] Selected mode: Quality Priority (default)."
    ;;
esac

SHARED_DIR="/mnt/shared"
mkdir -p "$SHARED_DIR"

get_linux_ip() {
  ip route get 1.1.1.1 2> /dev/null \
    | awk '/src/ {
            for(i=1;i<=NF;i++)
                if($i=="src"){
                    print $(i+1)
                    exit
                }
        }'
}

wait_for_audio_server() {
  echo "[Info] Waiting for the audio server (PipeWire) to become ready..."
  
  local socket_path="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/pulse/native"
  local retries=60
  
  while [ ! -S "$socket_path" ]; do
    retries=$((retries - 1))
    if [ "$retries" -le 0 ]; then
      echo "[Error] Timed out while waiting for the PulseAudio socket." >&2
      exit 1
    fi
    sleep 0.2
  done

  if ! pactl info > /dev/null 2>&1; then
     echo "[Error] PulseAudio socket is present, but the server is not responding." >&2
     exit 1
  fi
}

show_error() {
  local reason="$1"
  echo "[Error] $reason" >&2
  if command -v notify-send > /dev/null; then
    notify-send -u critical -a "Termux Audio" "Audio Tunnel Error" "$reason\nThe service has failed more than ${retry_count} times."
  fi
}

remove_old_sink() {
  pactl unload-module module-tunnel-sink > /dev/null 2>&1 || true
}

reload_sink() {
  echo "[Info] Rebuilding tunnel sink..."
  remove_old_sink
  sleep 0.2

  echo "[Info] Verifying connectivity to Android endpoint (${ANDROID_IP}:4713)..."
  if ! timeout 2 bash -c "</dev/tcp/${ANDROID_IP}/4713" 2>/dev/null; then
    echo "[Error] Android port 4713 is closed or unreachable." >&2
    return 1
  fi

 if ! timeout 5 pactl load-module module-tunnel-sink \
    server="tcp:${ANDROID_IP}:4713" \
    sink_name=termux_stream \
    rate=${AUDIO_RATE} \
    format=${AUDIO_FORMAT} \
    ${AUDIO_EXTRA_ARGS} \
    sink_properties="'device.description=\"Audio Service Mode: ${MODE_NAME}\"'" \
    > /dev/null; then
    echo "[Error] Failed to create the audio sink." >&2
    return 1
  fi

  for i in {1..20}; do
    if timeout 1 pactl list short sinks 2> /dev/null | grep -q "termux_stream"; then
      break
    fi
    sleep 0.1
  done

  if ! timeout 1 pactl list short sinks 2> /dev/null | grep -q "termux_stream"; then
    echo "[Error] termux_stream sink was not created successfully." >&2
    return 1
  fi

  if command -v paplay > /dev/null 2>&1; then
    paplay < /dev/null > /dev/null 2>&1 &
  fi

  if ! timeout 2 pactl set-default-sink termux_stream; then
    echo "[Error] Failed to set termux_stream as the default output sink." >&2
    return 1
  fi

  retry_count=0
  echo "[Success] Default output sink set to termux_stream."
  return 0
}

LINUX_IP="$(get_linux_ip)"

if [ -z "$LINUX_IP" ]; then
  echo "[Error] Unable to determine the Linux IP address." >&2
  exit 1
fi

echo "$LINUX_IP" > "${SHARED_DIR}/linux_ip.txt"
echo "[Info] Linux IP: $LINUX_IP"
echo "[Info] Waiting for Android IP address..."

while [ ! -s "${SHARED_DIR}/android_ip.txt" ]; do
  sleep 0.2
done

ANDROID_IP="$(tr -d '[:space:]' < "${SHARED_DIR}/android_ip.txt")"

if [ -z "$ANDROID_IP" ]; then
  echo "[Error] Failed to read the Android IP address." >&2
  exit 1
fi

echo "[Info] Android IP: $ANDROID_IP"

wait_for_audio_server

until reload_sink; do
  retry_count=$((retry_count + 1))
  echo "[Warn] Retrying initial connection (${retry_count}/${MAX_RETRY})."

  if [ "$retry_count" -ge "$MAX_RETRY" ]; then
    show_error "Initial sink creation failed."
    exit 1
  fi
  sleep 2
done

echo "[Success] Audio tunnel established successfully (mode: $MODE_NAME)."

while true; do
  NEW_LINUX_IP="$(get_linux_ip)"
  NEW_ANDROID_IP="$(tr -d '[:space:]' < "${SHARED_DIR}/android_ip.txt" 2> /dev/null || true)"

  if [ -n "$NEW_LINUX_IP" ] && [ "$NEW_LINUX_IP" != "$LINUX_IP" ]; then
    LINUX_IP="$NEW_LINUX_IP"
    echo "$LINUX_IP" > "${SHARED_DIR}/linux_ip.txt"
    echo "[Info] Linux IP changed to: $LINUX_IP"
  fi

  if [ -n "$NEW_ANDROID_IP" ] && [ "$NEW_ANDROID_IP" != "$ANDROID_IP" ]; then
    ANDROID_IP="$NEW_ANDROID_IP"
    echo "[Info] Android IP changed to: $ANDROID_IP"

    if ! reload_sink; then
      retry_count=$((retry_count + 1))
      echo "[Warn] Retrying after Android IP change (${retry_count}/${MAX_RETRY})."

      if [ "$retry_count" -ge "$MAX_RETRY" ]; then
        show_error "Sink creation failed after Android IP update."
        exit 1
      fi
      sleep 2
    else
      retry_count=0
    fi
  fi

  if ! timeout 2 pactl list short sinks 2> /dev/null | grep -q '^.*termux_stream'; then
    echo "[Warn] termux_stream sink is missing."

    if ! reload_sink; then
      retry_count=$((retry_count + 1))
      echo "[Warn] Retrying sink recovery (${retry_count}/${MAX_RETRY})."

      if [ "$retry_count" -ge "$MAX_RETRY" ]; then
        show_error "termux_stream sink keeps disappearing."
        exit 1
      fi
      sleep 2
    else
      retry_count=0
    fi
  fi
  sleep 1
done
