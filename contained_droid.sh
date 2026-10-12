#!/usr/bin/env bash
# Starts or stops contained_droid on Linux or macOS; the counterpart of
# contained_droid.bat. Run it without arguments for a menu, or as:
#   ./contained_droid.sh start | stop | status | update
set -u
cd "$(dirname "$0")"

URL=http://localhost:6080

if docker compose version > /dev/null 2>&1; then
    compose=(docker compose)
elif command -v podman-compose > /dev/null 2>&1; then
    compose=(podman-compose)
elif podman compose version > /dev/null 2>&1; then
    compose=(podman compose)
else
    echo "Neither 'docker compose' nor 'podman-compose' was found." >&2
    exit 1
fi

open_desktop() {
    echo "Waiting for the desktop..."
    for _ in $(seq 1 60); do
        if curl -s -o /dev/null "$URL/"; then
            if command -v xdg-open > /dev/null 2>&1; then
                xdg-open "$URL" > /dev/null 2>&1 &
            elif command -v open > /dev/null 2>&1; then
                open "$URL"
            fi
            echo "The desktop is at $URL. Android needs about a minute to boot."
            return 0
        fi
        sleep 2
    done
    return 1
}

show_log() {
    "${compose[@]}" logs --tail 25
}

start() {
    echo "Starting the container..."
    if "${compose[@]}" up -d "$@" && open_desktop; then
        return 0
    fi
    echo
    echo "Something went wrong. Recent log:"
    show_log
    return 1
}

stop() {
    echo "Stopping the container..."
    "${compose[@]}" down
}

status() {
    "${compose[@]}" ps
    echo
    show_log
}

update() {
    echo "Fetching the latest version..."
    if ! git pull; then
        echo
        echo "git pull failed, nothing was changed. See the message above."
        return 1
    fi
    start --build
}

case "${1:-}" in
    start | stop | status | update)
        "$1"
        exit
        ;;
    "") ;;
    *)
        echo "Usage: $0 [start|stop|status|update]" >&2
        exit 2
        ;;
esac

while true; do
    cat << 'MENU'

  contained_droid
  ---------------
  [1] Start and open the desktop in the browser
  [2] Stop  (compose down - Android and settings are kept)
  [3] Show status and recent log
  [4] Update (git pull, rebuild if needed, then start)
  [Q] Quit

MENU
    read -r -p "  Choose 1, 2, 3, 4 or Q: " choice || exit 0
    echo
    case "$choice" in
        1) start ;;
        2) stop ;;
        3) status ;;
        4) update ;;
        q | Q) exit 0 ;;
        *) echo "Unknown choice: $choice" ;;
    esac
done
