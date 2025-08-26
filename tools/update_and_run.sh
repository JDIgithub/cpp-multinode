#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SRC="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SRC")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"

# If HOST not set (or set to "auto"), detect this VM's private IPv4
if [[ -z "${HOST:-}" || "${HOST}" == "auto" ]]; then

  # Default-route source IP (works on most Linux)
  HOST="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src"){print $(i+1)}}' | head -n1)"

  # First global IPv4 on any interface (last-resort)
  if [[ -z "$HOST" ]]; then
    HOST="$(ip -4 -o addr show scope global up | awk '{print $4}' | cut -d/ -f1 | head -n1)"
    echo "==> Third if Using HOST IP: $HOST"
  fi

  if [[ -z "$HOST" ]]; then
    echo "ERROR: Could not auto-detect HOST IP. Please set HOST=..."
    exit 1
  fi
fi

# ---- Config (override via env vars) ----
PORT="${PORT:=7777}"                       # HTTP port
CPP_DIR="${CPP_DIR:=$REPO_ROOT/cpp-addon}"         # path to C++ addon
APP_DIR="${APP_DIR:=$REPO_ROOT/python-app}"        # path to Python app
DRIVER="${DRIVER:-run_cluster.py}"         # driver script name
PY="${PY:-python}"

BUMP=0
if [[ "${1:-}" == "--bump" ]]; then
  BUMP=1
fi

echo "==> HOST=$HOST PORT=$PORT CPP_DIR=$CPP_DIR APP_DIR=$APP_DIR DRIVER=$DRIVER"

# ---- Bump patch version in pyproject.toml ----
if [[ $BUMP -eq 1 ]]; then
  echo "==> Bumping patch version in $CPP_DIR/pyproject.toml"
  "$PY" - "$CPP_DIR/pyproject.toml" <<'PY'
import sys, re, tomllib
from pathlib import Path

p = Path(sys.argv[1])
data = p.read_text()

cfg = tomllib.loads(data)
ver = cfg["project"]["version"]
maj, mi, pa = map(int, ver.split("."))
new = f"{maj}.{mi}.{pa+1}"

new_data = re.sub(
    r'(?m)^version\s*=\s*"\d+\.\d+\.\d+"\s*$',
    f'version = "{new}"',
    data,
)

p.write_text(new_data)
print(f"Bumped version: {ver} -> {new}")
PY
fi

# ---- Build the wheel ----
echo "==> Building wheel"
pushd "$CPP_DIR" >/dev/null
rm -rf build/ dist/
"$PY" -m build --wheel
WHEEL_PATH="$(ls -1 dist/*.whl | sort | tail -n1)"
WHEEL_FILE="$(basename "$WHEEL_PATH")"
popd >/dev/null
echo "==> Built: $WHEEL_FILE"

# ---- Serve the wheel directory ----
echo "==> Ensuring HTTP server on :$PORT"
if ! curl -fsS "http://$HOST:$PORT/" >/dev/null 2>&1; then
  echo "    Starting http.server..."
  # Run in background, log to /tmp
  ( cd "$CPP_DIR/dist" && "$PY" -m http.server "$PORT" --bind 0.0.0.0 \
      > /tmp/wheel_server.log 2>&1 & echo $! > /tmp/wheel_server.pid )
  # Wait until it’s up
  for i in {1..20}; do
    if curl -fsS "http://$HOST:$PORT/" >/dev/null 2>&1; then break; fi
    sleep 0.2
  done
fi

# ---- Compose the wheel URL with cache-buster ----
STAMP="$(date +%s)"
WHEEL_URL="http://$HOST:$PORT/$WHEEL_FILE?nocache=$STAMP"
echo "==> Wheel URL: $WHEEL_URL"

# ---- Run the driver with that wheel URL ----
echo "==> Running driver: $APP_DIR/$DRIVER"
pushd "$APP_DIR" >/dev/null
CPP_WHEEL_URL="$WHEEL_URL" "$PY" "$DRIVER"
popd >/dev/null
