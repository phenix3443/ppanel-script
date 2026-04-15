#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

ACTION="${1:-help}"
TARGET="${2:-}"
shift $(( $# > 0 ? 1 : 0 )) || true
shift $(( $# > 0 ? 1 : 0 )) || true

PPANEL_ROOT="${PPANEL_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}"
FRONTEND_ROOT="${FRONTEND_ROOT:-$PPANEL_ROOT/ppanel-frontend}"
SERVER_ROOT="${SERVER_ROOT:-$PPANEL_ROOT/ppanel-server}"

STATE_DIR="${STATE_DIR:-$HOME/.cache/ppanel-local-dev}"
SERVER_PID_FILE="$STATE_DIR/server.pid"
FRONTEND_PID_FILE="$STATE_DIR/frontend.pid"
SERVER_LOG_FILE="$STATE_DIR/server.log"
FRONTEND_LOG_FILE="$STATE_DIR/frontend.log"
DEV_NETWORK="${DEV_NETWORK:-ppanel-local-dev}"
SERVER_CONTAINER="${SERVER_CONTAINER:-ppanel-local-server}"
SERVER_IMAGE="${SERVER_IMAGE:-ppanel-server-ppanel}"

FRONTEND_APP="${FRONTEND_APP:-user}"
LOCAL_SERVER_HOST="${LOCAL_SERVER_HOST:-127.0.0.1}"
LOCAL_SERVER_PORT="${LOCAL_SERVER_PORT:-8080}"
LOCAL_FRONTEND_HOST="${LOCAL_FRONTEND_HOST:-127.0.0.1}"
LOCAL_USER_PORT="${LOCAL_USER_PORT:-3000}"
LOCAL_ADMIN_PORT="${LOCAL_ADMIN_PORT:-3001}"

MYSQL_CONTAINER="${MYSQL_CONTAINER:-ppanel-local-mysql}"
MYSQL_IMAGE="${MYSQL_IMAGE:-mysql:8.4.5}"
MYSQL_PORT="${MYSQL_PORT:-13306}"
MYSQL_DATABASE="${MYSQL_DATABASE:-ppanel_dev}"
MYSQL_USER="${MYSQL_USER:-ppanel_dev}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-ppanel-dev-password}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-dev-root-password}"
SERVER_DB_USER="${SERVER_DB_USER:-root}"
SERVER_DB_PASSWORD="${SERVER_DB_PASSWORD:-$MYSQL_ROOT_PASSWORD}"

REDIS_CONTAINER="${REDIS_CONTAINER:-ppanel-local-redis}"
REDIS_IMAGE="${REDIS_IMAGE:-redis:7.4.2}"
REDIS_PORT="${REDIS_PORT:-16379}"

ADMIN_EMAIL="${ADMIN_EMAIL:-admin@ppanel.dev}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-password}"

# These defaults are intentionally local placeholders. Replace them with real
# provider credentials in your shell env if you want to complete the provider
# callback instead of just validating button exposure and redirect generation.
GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-ppanel-local-google-client.apps.googleusercontent.com}"
GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET:-ppanel-local-google-secret}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-123456789:ppanel-local-dev-bot-token}"

SERVER_URL="http://${LOCAL_SERVER_HOST}:${LOCAL_SERVER_PORT}"
CONFIG_PATH="$SERVER_ROOT/etc/ppanel.yaml"

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME up frontend [--frontend admin|user]
  $SCRIPT_NAME up server
  $SCRIPT_NAME up both [--frontend admin|user]
  $SCRIPT_NAME test-auth
  $SCRIPT_NAME status
  $SCRIPT_NAME leave [frontend|server|both]
  $SCRIPT_NAME help

What this script does now:
  - Starts local MySQL and Redis in Docker
  - Starts local ppanel-server from source
  - Initializes the backend automatically if needed
  - Enables Google + Telegram auth methods automatically
  - Runs OAuth redirect self-checks
  - Starts the local frontend dev server when requested

Helpful env vars:
  GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET
  TELEGRAM_BOT_TOKEN
  ADMIN_EMAIL / ADMIN_PASSWORD
  VITE_ALLOWED_HOSTS / VITE_DEVTOOLS_PORT
  LOCAL_SERVER_PORT / LOCAL_USER_PORT / LOCAL_ADMIN_PORT
  PPANEL_ROOT / FRONTEND_ROOT / SERVER_ROOT
EOF
}

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

die() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

ensure_state_dir() {
  mkdir -p "$STATE_DIR"
}

ensure_docker_network() {
  if ! docker network inspect "$DEV_NETWORK" >/dev/null 2>&1; then
    docker network create "$DEV_NETWORK" >/dev/null
  fi
}

frontend_port() {
  if [[ "$FRONTEND_APP" == "admin" ]]; then
    printf '%s\n' "$LOCAL_ADMIN_PORT"
  else
    printf '%s\n' "$LOCAL_USER_PORT"
  fi
}

frontend_devtools_port() {
  if [[ -n "${VITE_DEVTOOLS_PORT:-}" ]]; then
    printf '%s\n' "$VITE_DEVTOOLS_PORT"
    return
  fi

  if [[ "$FRONTEND_APP" == "admin" ]]; then
    printf '42070\n'
  else
    printf '42069\n'
  fi
}

frontend_dir() {
  if [[ "$FRONTEND_APP" == "admin" ]]; then
    printf '%s/apps/admin\n' "$FRONTEND_ROOT"
  else
    printf '%s/apps/user\n' "$FRONTEND_ROOT"
  fi
}

is_pid_running() {
  local pid="$1"
  [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1
}

stop_pid_if_running() {
  local pid="$1"
  if is_pid_running "$pid"; then
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" 2>/dev/null || true
  fi
}

read_pid() {
  local file="$1"
  if [[ -f "$file" ]]; then
    tr -d '[:space:]' <"$file"
  fi
}

wait_for_http() {
  local url="$1"
  local attempts="${2:-60}"
  local sleep_seconds="${3:-1}"
  local i
  for ((i=1; i<=attempts; i++)); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$sleep_seconds"
  done
  return 1
}

wait_for_http_status() {
  local url="$1"
  local attempts="${2:-60}"
  local sleep_seconds="${3:-1}"
  local i
  local status
  for ((i=1; i<=attempts; i++)); do
    status="$(curl -sS -o /dev/null -w '%{http_code}' "$url" || true)"
    if [[ "$status" != "000" ]]; then
      return 0
    fi
    sleep "$sleep_seconds"
  done
  return 1
}

json_extract() {
  local json_payload="$1"
  local path="$2"
  JSON_PAYLOAD="$json_payload" python3 - "$path" <<'PY'
import json
import os
import sys

path = sys.argv[1].split(".")
data = json.loads(os.environ["JSON_PAYLOAD"])

node = data
for part in path:
    if part == "":
        continue
    if isinstance(node, list):
        node = node[int(part)]
    else:
        node = node[part]

if isinstance(node, (dict, list)):
    print(json.dumps(node))
elif node is None:
    print("")
else:
    print(node)
PY
}

json_has_oauth_method() {
  local json_payload="$1"
  local method="$2"
  JSON_PAYLOAD="$json_payload" python3 - "$method" <<'PY'
import json
import os
import sys

method = sys.argv[1]
payload = json.loads(os.environ["JSON_PAYLOAD"])
methods = payload.get("data", {}).get("oauth_methods", [])
sys.exit(0 if method in methods else 1)
PY
}

ensure_python() {
  require_cmd python3
}

ensure_basic_tools() {
  require_cmd curl
  require_cmd docker
  require_cmd go
  ensure_python
}

frontend_dev_command() {
  if command -v bun >/dev/null 2>&1; then
    printf 'exec bun dev --host %s --port %s\n' "$LOCAL_FRONTEND_HOST" "$(frontend_port)"
    return
  fi

  if [[ -x "${FRONTEND_ROOT}/node_modules/.bin/vite" ]]; then
    printf 'exec "%s/node_modules/.bin/vite" --host %s --port %s\n' "$FRONTEND_ROOT" "$LOCAL_FRONTEND_HOST" "$(frontend_port)"
    return
  fi

  if command -v npm >/dev/null 2>&1; then
    printf 'exec npm exec -- vite --host %s --port %s\n' "$LOCAL_FRONTEND_HOST" "$(frontend_port)"
    return
  fi

  die "Missing frontend runner: neither bun nor npm is available"
}

start_detached_process() {
  local pid_file="$1"
  local log_file="$2"
  local cwd="$3"
  shift 3

  DETACHED_PID_FILE="$pid_file" \
  DETACHED_LOG_FILE="$log_file" \
  DETACHED_CWD="$cwd" \
  python3 - "$@" <<'PY'
import os
import subprocess
import sys

pid_file = os.environ["DETACHED_PID_FILE"]
log_file = os.environ["DETACHED_LOG_FILE"]
cwd = os.environ["DETACHED_CWD"]
command = sys.argv[1:]

env = os.environ.copy()

with open(os.devnull, "rb") as devnull, open(log_file, "ab", buffering=0) as log_handle:
    process = subprocess.Popen(
        command,
        cwd=cwd,
        env=env,
        stdin=devnull,
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        start_new_session=True,
        close_fds=True,
    )

with open(pid_file, "w", encoding="utf-8") as handle:
    handle.write(str(process.pid))
PY
}

find_listener_pid() {
  local port="$1"
  if ! command -v lsof >/dev/null 2>&1; then
    return 0
  fi

  lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | head -n 1 || true
}

ensure_frontend_port_available() {
  local port="$1"
  local label="$2"
  local pid command

  pid="$(find_listener_pid "$port")"
  [[ -n "$pid" ]] || return 0

  command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  if [[ "$command" == *"$FRONTEND_ROOT"* ]] && [[ "$command" == *"vite"* || "$command" == *"bun"* || "$command" == *"node"* ]]; then
    log "Stopping stale frontend process on ${label} port ${port} (PID ${pid})"
    stop_pid_if_running "$pid"
    sleep 1
    pid="$(find_listener_pid "$port")"
  fi

  [[ -z "$pid" ]] || die "${label} port ${port} is already in use by: ${command}"
}

docker_container_running() {
  local name="$1"
  docker ps --format '{{.Names}}' | grep -qx "$name"
}

docker_container_exists() {
  local name="$1"
  docker ps -a --format '{{.Names}}' | grep -qx "$name"
}

ensure_container_on_network() {
  local name="$1"
  if ! docker inspect -f '{{range $k, $_ := .NetworkSettings.Networks}}{{println $k}}{{end}}' "$name" | grep -qx "$DEV_NETWORK"; then
    docker network connect "$DEV_NETWORK" "$name" >/dev/null 2>&1 || true
  fi
}

sync_mysql_user_grants() {
  docker exec "$MYSQL_CONTAINER" mysql -uroot "-p${MYSQL_ROOT_PASSWORD}" <<EOF >/dev/null
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
ALTER USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
ALTER USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOF
}

start_mysql() {
  ensure_docker_network
  if docker_container_running "$MYSQL_CONTAINER"; then
    log "MySQL container is already running: $MYSQL_CONTAINER"
    ensure_container_on_network "$MYSQL_CONTAINER"
    sync_mysql_user_grants
    return
  fi

  if docker_container_exists "$MYSQL_CONTAINER"; then
    log "Starting existing MySQL container: $MYSQL_CONTAINER"
    docker start "$MYSQL_CONTAINER" >/dev/null
  else
    log "Creating local MySQL container: $MYSQL_CONTAINER"
    docker run -d \
      --name "$MYSQL_CONTAINER" \
      --network "$DEV_NETWORK" \
      -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" \
      -e MYSQL_DATABASE="$MYSQL_DATABASE" \
      -e MYSQL_USER="$MYSQL_USER" \
      -e MYSQL_PASSWORD="$MYSQL_PASSWORD" \
      -p "${MYSQL_PORT}:3306" \
      "$MYSQL_IMAGE" \
      --mysql-native-password=ON \
      --bind-address=0.0.0.0 >/dev/null
  fi

  log "Waiting for MySQL to become ready"
  local i
  for ((i=1; i<=90; i++)); do
    if docker exec "$MYSQL_CONTAINER" mysqladmin ping -h 127.0.0.1 -uroot "-p${MYSQL_ROOT_PASSWORD}" --silent >/dev/null 2>&1; then
      sync_mysql_user_grants
      return
    fi
    sleep 1
  done
  die "MySQL did not become ready in time"
}

start_redis() {
  if docker_container_running "$REDIS_CONTAINER"; then
    log "Redis container is already running: $REDIS_CONTAINER"
    ensure_container_on_network "$REDIS_CONTAINER"
    return
  fi

  if docker_container_exists "$REDIS_CONTAINER"; then
    log "Starting existing Redis container: $REDIS_CONTAINER"
    docker start "$REDIS_CONTAINER" >/dev/null
  else
    log "Creating local Redis container: $REDIS_CONTAINER"
    docker run -d \
      --name "$REDIS_CONTAINER" \
      --network "$DEV_NETWORK" \
      -p "${REDIS_PORT}:6379" \
      "$REDIS_IMAGE" >/dev/null
  fi

  log "Waiting for Redis to become ready"
  local i
  for ((i=1; i<=60; i++)); do
    if docker exec "$REDIS_CONTAINER" redis-cli ping >/dev/null 2>&1; then
      return
    fi
    sleep 1
  done
  die "Redis did not become ready in time"
}

stop_conflicting_compose_server() {
  if docker_container_running "ppanel-server"; then
    log "Stopping existing dockerized ppanel-server to free port ${LOCAL_SERVER_PORT}"
    docker stop ppanel-server >/dev/null
  fi
}

ensure_server_process() {
  ensure_state_dir
  ensure_docker_network

  if docker_container_running "$SERVER_CONTAINER"; then
    log "Local server container is already running: $SERVER_CONTAINER"
    return
  fi

  stop_conflicting_compose_server
  normalize_server_config

  if docker_container_exists "$SERVER_CONTAINER"; then
    docker rm -f "$SERVER_CONTAINER" >/dev/null 2>&1 || true
  fi

  log "Starting local ppanel-server container"
  docker run -d \
    --name "$SERVER_CONTAINER" \
    --network "$DEV_NETWORK" \
    -p "${LOCAL_SERVER_PORT}:8080" \
    -v "${SERVER_ROOT}/etc:/app/etc" \
    -e PPANEL_DB="${SERVER_DB_USER}:${SERVER_DB_PASSWORD}@tcp(${MYSQL_CONTAINER}:3306)/${MYSQL_DATABASE}?charset=utf8mb4&parseTime=true&loc=Asia%2FShanghai" \
    -e PPANEL_REDIS="redis://${REDIS_CONTAINER}:6379/0" \
    "$SERVER_IMAGE" >/dev/null

  if server_config_initialized; then
    if ! wait_for_http "${SERVER_URL}/v1/common/site/config" 90 1; then
      docker logs --tail=120 "$SERVER_CONTAINER" >"$SERVER_LOG_FILE" 2>&1 || true
      die "Local server failed to become ready. See $SERVER_LOG_FILE"
    fi
    return
  fi

  if ! wait_for_container_http "http://127.0.0.1:8080/init" 90 1; then
    docker logs --tail=120 "$SERVER_CONTAINER" >"$SERVER_LOG_FILE" 2>&1 || true
    die "Init server did not become ready inside container. See $SERVER_LOG_FILE"
  fi
}

normalize_server_config() {
  if [[ ! -s "$CONFIG_PATH" ]]; then
    return
  fi

  python3 - "$CONFIG_PATH" "$MYSQL_CONTAINER" "$MYSQL_DATABASE" "$SERVER_DB_USER" "$SERVER_DB_PASSWORD" "$REDIS_CONTAINER" <<'PY'
import re
import sys

path, mysql_host, mysql_db, mysql_user, mysql_password, redis_host = sys.argv[1:]
text = open(path, "r", encoding="utf-8").read()

replacements = [
    (r"(?m)^    Addr: .*$", f"    Addr: {mysql_host}:3306"),
    (r"(?m)^    Username: .*$", f"    Username: {mysql_user}"),
    (r"(?m)^    Password: .*$", f"    Password: {mysql_password}"),
    (r"(?m)^    Dbname: .*$", f"    Dbname: {mysql_db}"),
    (r"(?m)^    Host: .*$", f"    Host: {redis_host}:6379"),
]

for pattern, replacement in replacements:
    text = re.sub(pattern, replacement, text)

with open(path, "w", encoding="utf-8") as fh:
    fh.write(text)
PY
}

wait_for_container_http() {
  local url="$1"
  local attempts="${2:-60}"
  local sleep_seconds="${3:-1}"
  local i
  for ((i=1; i<=attempts; i++)); do
    if docker run --rm --network "container:${SERVER_CONTAINER}" curlimages/curl:8.12.1 -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$sleep_seconds"
  done
  return 1
}

server_config_initialized() {
  [[ -s "$CONFIG_PATH" ]] && grep -q 'AccessSecret' "$CONFIG_PATH" 2>/dev/null
}

initialize_backend_if_needed() {
  if server_config_initialized; then
    log "Backend config already initialized"
    return
  fi

  log "Initializing backend via ${SERVER_URL}/init/config"
  docker run --rm \
    --network "container:${SERVER_CONTAINER}" \
    curlimages/curl:8.12.1 \
    -fsS \
    -H 'Content-Type: application/json' \
    -X POST \
    "http://127.0.0.1:8080/init/config" \
    -d "$(cat <<EOF
{"adminEmail":"${ADMIN_EMAIL}","adminPassword":"${ADMIN_PASSWORD}","mysqlHost":"127.0.0.1","mysqlPort":"${MYSQL_PORT}","mysqlDatabase":"${MYSQL_DATABASE}","mysqlUser":"${SERVER_DB_USER}","mysqlPassword":"${SERVER_DB_PASSWORD}","redisHost":"127.0.0.1","redisPort":"${REDIS_PORT}","redisPassword":""}
EOF
)" >/dev/null

  if ! wait_for_http "${SERVER_URL}/v1/common/site/config" 120 1; then
    docker logs --tail=120 "$SERVER_CONTAINER" >"$SERVER_LOG_FILE" 2>&1 || true
    die "Backend initialization finished but API did not become ready. See $SERVER_LOG_FILE"
  fi
}

login_admin() {
  curl -fsS \
    -H 'Content-Type: application/json' \
    -X POST \
    "${SERVER_URL}/v1/auth/login" \
    -d "$(cat <<EOF
{"email":"${ADMIN_EMAIL}","password":"${ADMIN_PASSWORD}","identifier":"local-dev-admin"}
EOF
)"
}

ensure_admin_user() {
  log "Ensuring local admin user exists"
  curl -fsS \
    -H 'Content-Type: application/json' \
    -X POST \
    "${SERVER_URL}/v1/auth/register" \
    -d "$(cat <<EOF
{"email":"${ADMIN_EMAIL}","password":"${ADMIN_PASSWORD}","identifier":"local-dev-admin"}
EOF
)" >/dev/null || true

  docker exec "$MYSQL_CONTAINER" mysql -uroot "-p${MYSQL_ROOT_PASSWORD}" "$MYSQL_DATABASE" <<EOF >/dev/null
UPDATE user AS u
JOIN user_auth_methods AS m ON m.user_id = u.id
SET u.is_admin = 1
WHERE m.auth_type = 'email' AND m.auth_identifier = '${ADMIN_EMAIL}';
EOF
}

admin_token() {
  local response code token
  response="$(login_admin)"
  code="$(json_extract "$response" "code")"

  if [[ "$code" != "200" ]]; then
    ensure_admin_user
    response="$(login_admin)"
    code="$(json_extract "$response" "code")"
  fi

  [[ "$code" == "200" ]] || die "Admin login failed: $response"
  token="$(json_extract "$response" "data.token")"
  printf '%s\n' "$token"
}

update_auth_method() {
  local token="$1"
  local method="$2"
  local enabled="$3"
  local config_json="$4"

  curl -fsS \
    -H 'Content-Type: application/json' \
    -H "Authorization: ${token}" \
    -X PUT \
    "${SERVER_URL}/v1/admin/auth-method/config" \
    -d "$(cat <<EOF
{"method":"${method}","enabled":${enabled},"config":${config_json}}
EOF
)" >/dev/null
}

configure_oauth_methods() {
  local token
  token="$(admin_token)"
  [[ -n "$token" ]] || die "Failed to obtain admin token"

  log "Enabling Google auth method"
  update_auth_method "$token" "google" "true" "$(cat <<EOF
{"client_id":"${GOOGLE_CLIENT_ID}","client_secret":"${GOOGLE_CLIENT_SECRET}","redirect_url":"http://${LOCAL_FRONTEND_HOST}:$(frontend_port)"}
EOF
)"

  log "Enabling Telegram auth method"
  update_auth_method "$token" "telegram" "true" "$(cat <<EOF
{"bot_token":"${TELEGRAM_BOT_TOKEN}","enable_notify":false,"webhook_domain":""}
EOF
)"
}

oauth_redirect_for() {
  local method="$1"
  curl -fsS \
    -H 'Content-Type: application/json' \
    -X POST \
    "${SERVER_URL}/v1/auth/oauth/login" \
    -d "$(cat <<EOF
{"method":"${method}","redirect":"http://${LOCAL_FRONTEND_HOST}:$(frontend_port)/oauth/${method}/"}
EOF
)"
}

run_auth_self_check() {
  log "Running OAuth self-check"

  local config_json
  config_json="$(curl -fsS "${SERVER_URL}/v1/common/site/config")"
  json_has_oauth_method "$config_json" "google" || die "Google is not exposed in oauth_methods"
  json_has_oauth_method "$config_json" "telegram" || die "Telegram is not exposed in oauth_methods"

  local google_json google_redirect
  google_json="$(oauth_redirect_for google)"
  google_redirect="$(json_extract "$google_json" "data.redirect")"
  [[ "$google_redirect" == *"accounts.google.com"* ]] || die "Google redirect URL is invalid: $google_redirect"

  local telegram_json telegram_redirect
  telegram_json="$(oauth_redirect_for telegram)"
  telegram_redirect="$(json_extract "$telegram_json" "data.redirect")"
  [[ "$telegram_redirect" == *"oauth.telegram.org"* || "$telegram_redirect" == *"telegram.org"* ]] || die "Telegram redirect URL is invalid: $telegram_redirect"

  log "OAuth self-check passed"
  log "Google redirect: $google_redirect"
  log "Telegram redirect: $telegram_redirect"
}

ensure_backend() {
  ensure_basic_tools
  start_mysql
  start_redis
  ensure_server_process
  initialize_backend_if_needed
  configure_oauth_methods
  run_auth_self_check
}

start_frontend() {
  ensure_backend
  ensure_state_dir

  local pid
  pid="$(read_pid "$FRONTEND_PID_FILE")"
  if is_pid_running "$pid"; then
    log "Frontend dev server is already running with PID $pid"
    return
  fi
  rm -f "$FRONTEND_PID_FILE"

  ensure_frontend_port_available "$(frontend_port)" "frontend"
  ensure_frontend_port_available "$(frontend_devtools_port)" "frontend devtools"

  log "Starting local frontend (${FRONTEND_APP})"
  : >"$FRONTEND_LOG_FILE"
  VITE_API_BASE_URL="$SERVER_URL" \
  VITE_API_PREFIX="" \
  start_detached_process \
    "$FRONTEND_PID_FILE" \
    "$FRONTEND_LOG_FILE" \
    "$(frontend_dir)" \
    /bin/sh -lc "$(frontend_dev_command)"

  if ! wait_for_http "http://${LOCAL_FRONTEND_HOST}:$(frontend_port)" 90 1; then
    die "Frontend did not become ready. See $FRONTEND_LOG_FILE"
  fi
}

stop_pid_file() {
  local file="$1"
  local label="$2"
  local pid
  pid="$(read_pid "$file")"
  if is_pid_running "$pid"; then
    log "Stopping $label (PID $pid)"
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -f "$file"
}

leave_server() {
  if docker_container_exists "$SERVER_CONTAINER"; then
    log "Stopping local server container: $SERVER_CONTAINER"
    docker rm -f "$SERVER_CONTAINER" >/dev/null 2>&1 || true
  fi
}

leave_frontend() {
  stop_pid_file "$FRONTEND_PID_FILE" "frontend dev server"
}

status() {
  ensure_state_dir

  local server_pid frontend_pid
  server_pid="$(read_pid "$SERVER_PID_FILE")"
  frontend_pid="$(read_pid "$FRONTEND_PID_FILE")"

  printf 'Server process:   %s\n' "$(docker_container_running "$SERVER_CONTAINER" && printf 'running (container %s)' "$SERVER_CONTAINER" || printf 'stopped')"
  printf 'Frontend process: %s\n' "$(is_pid_running "$frontend_pid" && printf 'running (pid %s)' "$frontend_pid" || printf 'stopped')"
  printf 'MySQL container:  %s\n' "$(docker_container_running "$MYSQL_CONTAINER" && printf 'running' || printf 'stopped')"
  printf 'Redis container:  %s\n' "$(docker_container_running "$REDIS_CONTAINER" && printf 'running' || printf 'stopped')"
  printf 'Server URL:       %s\n' "$SERVER_URL"
  printf 'Frontend URL:     %s\n' "http://${LOCAL_FRONTEND_HOST}:$(frontend_port)"
  printf 'Server log:       %s\n' "$SERVER_LOG_FILE"
  printf 'Frontend log:     %s\n' "$FRONTEND_LOG_FILE"
}

case "$ACTION" in
  up)
    case "$TARGET" in
      frontend)
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --frontend)
              FRONTEND_APP="${2:-user}"
              shift 2
              ;;
            *)
              die "Unknown argument: $1"
              ;;
          esac
        done
        start_frontend
        ;;
      server)
        ensure_backend
        ;;
      both)
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --frontend)
              FRONTEND_APP="${2:-user}"
              shift 2
              ;;
            *)
              die "Unknown argument: $1"
              ;;
          esac
        done
        ensure_backend
        start_frontend
        ;;
      *)
        usage
        exit 1
        ;;
    esac
    ;;
  test-auth)
    ensure_backend
    ;;
  status)
    status
    ;;
  leave|down)
    case "$TARGET" in
      frontend)
        leave_frontend
        ;;
      server)
        leave_server
        ;;
      both|"")
        leave_frontend
        leave_server
        ;;
      *)
        usage
        exit 1
        ;;
    esac
    ;;
  help|-h|--help|"")
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
