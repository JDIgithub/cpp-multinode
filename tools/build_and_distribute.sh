#!/usr/bin/env bash
set -euo pipefail

# Resolve paths relative to this script
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

# Config
PORT="${PORT:=7777}"
CPP_DIR="${CPP_DIR:-$REPO_ROOT/cpp-addon}"
LOCAL_DIR="${LOCAL_DIR:-/vllm-workspace/cpp-wheels}"
PY="${PY:-python}"

echo "==> CPP_DIR=$CPP_DIR"
echo "==> LOCAL_DIR=$LOCAL_DIR"
echo "==> Using temp HTTP http://$HOST:$PORT/"

# Ensure temp HTTP is cleaned up even on error
cleanup() {
  if [[ -f /tmp/wheel_http.pid ]]; then
    pid="$(cat /tmp/wheel_http.pid || true)"
    [[ -n "$pid" ]] && kill "$pid" >/dev/null 2>&1 || true
    rm -f /tmp/wheel_http.pid
  fi
}
trap cleanup EXIT


BUMP=0
if [[ "${1:-}" == "--bump" ]]; then
  BUMP=1
fi

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


# 1) Build wheel
pushd "$CPP_DIR" >/dev/null
rm -rf build/ dist/
$PY -m build --wheel
WHEEL_PATH="$(find "$CPP_DIR/dist" -maxdepth 1 -type f -name '*.whl' \
            -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)"
popd >/dev/null

if [[ -z "${WHEEL_PATH:-}" || ! -f "$WHEEL_PATH" ]]; then
  echo "ERROR: build produced no wheel" >&2
  exit 1
fi

WHEEL_FILE="$(basename "$WHEEL_PATH")"
SHA256="$(sha256sum "$WHEEL_PATH" | awk '{print $1}')"
echo "==> Built: $WHEEL_FILE  (sha256=$SHA256)"

# 2) Start HTTP server
( cd "$CPP_DIR/dist" && $PY -m http.server "$PORT" --bind 0.0.0.0 >/tmp/wheel_http.log 2>&1 & echo $! > /tmp/wheel_http.pid )
# Wait until live
for _ in {1..30}; do curl -fsS "http://$HOST:$PORT/" >/dev/null 2>&1 && break || sleep 0.2; done

# 3) Fan-out: each node downloads to LOCAL_DIR (no SSH; uses Ray on the cluster)
WHEEL_URL="http://$HOST:$PORT/$WHEEL_FILE"
echo "==> Distributing $WHEEL_URL -> $LOCAL_DIR on all nodes"
"$PY" "$REPO_ROOT/tools/distribute_wheel.py" --url "$WHEEL_URL" --dst "$LOCAL_DIR" --sha256 "$SHA256" --show-nodes

# 4) Stop HTTP server
if [[ -f /tmp/wheel_http.pid ]] && ps -p "$(cat /tmp/wheel_http.pid)" >/dev/null 2>&1; then
  kill "$(cat /tmp/wheel_http.pid)" || true
  rm -f /tmp/wheel_http.pid
fi

PYMAJ="$($PY -c 'import sys; print(sys.version_info.major)')"
PYMIN="$($PY -c 'import sys; print(sys.version_info.minor)')"

echo "==> Done. Wheel cached on all nodes in $LOCAL_DIR"
echo "    Driver can use: CPP_WHEEL_LOCAL=\"$LOCAL_DIR/cpp_addon-latest-cp${PYMAJ}${PYMIN}.whl\""
