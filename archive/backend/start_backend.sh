#!/bin/bash

# Backend startup script with proper process management
# Prevents multiple instances and handles cleanup
# Portable: resolves paths relative to this script's location

# Ensure Homebrew and standard tool paths are available regardless of how this script is launched
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH"

# Resolve BACKEND_DIR from this script's real location (works from symlinks, .app bundles, etc.)
BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Write logs/pid to a user-writable location (app bundle is read-only on macOS)
SKRIFT_DATA_DIR="$HOME/Library/Application Support/Skrift"
mkdir -p "$SKRIFT_DATA_DIR"
PID_FILE="$SKRIFT_DATA_DIR/backend.pid"
LOG_FILE="$SKRIFT_DATA_DIR/backend.log"

cd "$BACKEND_DIR"

# ── Resolve dependencies folder ────────────────────────────
# Priority: user_settings.json > default relative to repo > ~/Skrift_dependencies
_resolve_deps_folder() {
    # 1. Try user_settings.json
    local settings_file="$BACKEND_DIR/config/user_settings.json"
    if [ -f "$settings_file" ]; then
        local from_settings
        from_settings=$(python3 -c "import json,sys; d=json.load(open('$settings_file')); print(d.get('dependencies_folder',''))" 2>/dev/null)
        if [ -n "$from_settings" ] && [ -d "$from_settings" ]; then
            echo "$from_settings"
            return
        fi
    fi
    # 2. Try ../Skrift_dependencies relative to repo root
    local repo_root
    repo_root="$(dirname "$BACKEND_DIR")"
    local relative="${repo_root}/../Skrift_dependencies"
    if [ -d "$relative" ]; then
        echo "$(cd "$relative" && pwd)"
        return
    fi
    # 3. Fallback to ~/Skrift_dependencies
    echo "$HOME/Skrift_dependencies"
}

DEPS_FOLDER="$(_resolve_deps_folder)"

# Persist resolved deps folder so the Python backend can find it
_persist_deps_folder() {
    local settings_file="$BACKEND_DIR/config/user_settings.json"
    local py="${PYExec:-python3}"
    if [ ! -f "$settings_file" ]; then
        echo "{\"dependencies_folder\": \"$DEPS_FOLDER\"}" > "$settings_file"
    else
        # Update only if not already set or pointing to a missing dir
        local current
        current=$("$py" -c "import json; d=json.load(open('$settings_file')); print(d.get('dependencies_folder',''))" 2>/dev/null || echo "")
        if [ -z "$current" ] || [ ! -d "$current" ]; then
            "$py" -c "
import json
with open('$settings_file','r') as f: d=json.load(f)
d['dependencies_folder']='$DEPS_FOLDER'
with open('$settings_file','w') as f: json.dump(d,f,indent=2)
" 2>/dev/null
        fi
    fi
}

# Function to check if process is running
is_running() {
    if [ ! -f "$PID_FILE" ]; then return 1; fi
    local pid
    pid=$(cat "$PID_FILE")
    kill -0 "$pid" 2>/dev/null || return 1
    # Verify the PID is actually listening on port 8000 (guards against PID reuse by other processes)
    lsof -i:8000 -t 2>/dev/null | grep -q "^${pid}$"
}

# Function to stop existing backend
stop_backend() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping existing backend (PID: $pid)"
            kill "$pid"
            # Wait up to 10 seconds for graceful shutdown
            for i in {1..10}; do
                if ! kill -0 "$pid" 2>/dev/null; then
                    break
                fi
                sleep 1
            done
            # Force kill if still running
            if kill -0 "$pid" 2>/dev/null; then
                echo "Force killing backend"
                kill -9 "$pid"
            fi
        fi
        rm -f "$PID_FILE"
    fi
    # Also kill any processes using port 8000
    lsof -ti:8000 | xargs kill -9 2>/dev/null || true
}

# Function to start backend
start_backend() {
    echo "Starting backend..."

    # Use external MLX venv from dependencies folder
    USER_MLX_VENV="$DEPS_FOLDER/mlx-env"
    PYExec="$USER_MLX_VENV/bin/python"

    _persist_deps_folder

    if [ ! -x "$PYExec" ]; then
        echo "Bootstrapping MLX venv at $USER_MLX_VENV ..."
        mkdir -p "$USER_MLX_VENV"
        python3 -m venv "$USER_MLX_VENV"
        "$PYExec" -m pip install --upgrade pip >/dev/null 2>&1 || true
        # Install backend requirements (includes FastAPI, etc.)
        "$PYExec" -m pip install -r "$BACKEND_DIR/requirements.txt" >/dev/null 2>&1 || true
        # Install MLX packages for transcription + enhancement
        "$PYExec" -m pip install --upgrade parakeet-mlx mlx-lm >/dev/null 2>&1 || true
    fi

    nohup "$PYExec" main.py > "$LOG_FILE" 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_FILE"
    echo "Backend started with PID: $pid"
    echo "Logs: tail -f $LOG_FILE"
}

# Main logic
case "${1:-start}" in
    start)
        if is_running; then
            echo "Backend is already running (PID: $(cat "$PID_FILE"))"
            exit 1
        fi
        stop_backend  # Clean up any orphaned processes
        start_backend
        ;;
    stop)
        stop_backend
        echo "Backend stopped"
        ;;
    restart)
        stop_backend
        sleep 2
        start_backend
        ;;
    status)
        if is_running; then
            echo "Backend is running (PID: $(cat "$PID_FILE"))"
        else
            echo "Backend is not running"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
