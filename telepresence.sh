#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

ACTION="${1:-help}"
TARGET="${2:-}"
shift $(( $# > 0 ? 1 : 0 )) || true
shift $(( $# > 0 ? 1 : 0 )) || true

PPANEL_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
FRONTEND_ROOT="$PPANEL_ROOT/ppanel-frontend"
SERVER_ROOT="$PPANEL_ROOT/ppanel-server"

STATE_DIR="$HOME/.cache/ppanel-local-dev"
SERVER_PID_FILE="$STATE_DIR/server.pid"
FRONTEND_PID_FILE="$STATE_DIR/frontend.pid"
SERVER_STATE_FILE="$STATE_DIR/server.state"
FRONTEND_STATE_FILE="$STATE_DIR/frontend.state"
SERVER_LOG_FILE="$STATE_DIR/server.log"
FRONTEND_LOG_FILE="$STATE_DIR/frontend.log"
DEV_NETWORK="ppanel-local-dev"
SERVER_CONTAINER="ppanel-local-server"
SERVER_IMAGE="ppanel-server-ppanel"

FRONTEND_APP="user"
LOCAL_SERVER_HOST="127.0.0.1"
LOCAL_SERVER_PORT="8080"
LOCAL_FRONTEND_HOST="127.0.0.1"
TELEPRESENCE_LOCAL_ADDRESS="host.docker.internal"
LOCAL_USER_PORT="3000"
LOCAL_ADMIN_PORT="3001"
REMOTE_MYSQL_HOST="host.docker.internal"
REMOTE_REDIS_HOST="host.docker.internal"
K8S_NAMESPACE="ppanel-dev"
TELEPRESENCE_MANAGER_NAMESPACE="ppanel-dev"
INSTALL_TRAFFIC_MANAGER="false"
TELEPRESENCE_DAEMON_NAME="${TELEPRESENCE_DAEMON_NAME:-ppanel-dev}"

MYSQL_PORT="13306"
MYSQL_DATABASE="ppanel_dev"
SERVER_DB_USER="root"
SERVER_DB_PASSWORD="dev-root-password"

REDIS_PORT="16379"
REDIS_PASSWORD=""

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
  $SCRIPT_NAME up frontend [--frontend admin|user] [telepresence options]
  $SCRIPT_NAME up server [shared dependency options] [telepresence options]
  $SCRIPT_NAME up both [--frontend admin|user] [shared dependency options] [telepresence options]
  $SCRIPT_NAME test-auth [shared dependency options]
  $SCRIPT_NAME status
  $SCRIPT_NAME leave [frontend|server|both]
  $SCRIPT_NAME help

What this script does now:
  - up frontend: starts/reuses a local frontend and intercepts frontend traffic with Telepresence
  - up server: starts a local backend and intercepts API traffic with Telepresence
  - up both: intercepts both frontend + backend traffic with Telepresence
  - Always uses shared MySQL/Redis for the local backend
  - Initializes the backend automatically if needed and runs OAuth redirect self-checks

Shared dependency options:
  --mysql-host HOST
  --mysql-port PORT
  --mysql-database NAME
  --mysql-user USER
  --mysql-password PASSWORD
  --redis-host HOST
  --redis-port PORT
  --redis-password PASSWORD
  Defaults: host.docker.internal:13306 for MySQL, host.docker.internal:16379 for Redis

Telepresence options:
  --namespace NS
  --manager-namespace NS
  --install-traffic-manager
  Defaults: namespace=ppanel-dev, manager-namespace=ppanel-dev

Still configurable via env vars:
  GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET
  TELEGRAM_BOT_TOKEN
  ADMIN_EMAIL / ADMIN_PASSWORD
  VITE_ALLOWED_HOSTS / VITE_DEVTOOLS_PORT
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

require_option_value() {
  local option="$1"
  local value="${2:-}"
  [[ -n "$value" ]] || die "Missing value for ${option}"
}

parse_frontend_option() {
  local option="$1"
  local value="$2"
  require_option_value "$option" "$value"
  case "$value" in
    admin|user)
      FRONTEND_APP="$value"
      ;;
    *)
      die "Unsupported frontend app: $value"
      ;;
  esac
}

parse_shared_dependency_options() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --namespace)
        require_option_value "$1" "${2:-}"
        K8S_NAMESPACE="$2"
        shift 2
        ;;
      --manager-namespace)
        require_option_value "$1" "${2:-}"
        TELEPRESENCE_MANAGER_NAMESPACE="$2"
        shift 2
        ;;
      --install-traffic-manager)
        INSTALL_TRAFFIC_MANAGER="true"
        shift
        ;;
      --mysql-host)
        require_option_value "$1" "${2:-}"
        REMOTE_MYSQL_HOST="$2"
        shift 2
        ;;
      --mysql-port)
        require_option_value "$1" "${2:-}"
        MYSQL_PORT="$2"
        shift 2
        ;;
      --mysql-database)
        require_option_value "$1" "${2:-}"
        MYSQL_DATABASE="$2"
        shift 2
        ;;
      --mysql-user)
        require_option_value "$1" "${2:-}"
        SERVER_DB_USER="$2"
        shift 2
        ;;
      --mysql-password)
        require_option_value "$1" "${2:-}"
        SERVER_DB_PASSWORD="$2"
        shift 2
        ;;
      --redis-host)
        require_option_value "$1" "${2:-}"
        REMOTE_REDIS_HOST="$2"
        shift 2
        ;;
      --redis-port)
        require_option_value "$1" "${2:-}"
        REDIS_PORT="$2"
        shift 2
        ;;
      --redis-password)
        require_option_value "$1" "${2:-}"
        REDIS_PASSWORD="$2"
        shift 2
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

parse_frontend_and_dependency_options() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --frontend)
        parse_frontend_option "$1" "${2:-}"
        shift 2
        ;;
      --namespace|--manager-namespace|--install-traffic-manager|--mysql-host|--mysql-port|--mysql-database|--mysql-user|--mysql-password|--redis-host|--redis-port|--redis-password)
        parse_shared_dependency_options "$@"
        return
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
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

ensure_frontend_tools() {
  require_cmd curl
  ensure_python
}

ensure_telepresence_tools() {
  require_cmd kubectl
  require_cmd telepresence
}

mysql_runtime_host() {
  printf '%s\n' "$REMOTE_MYSQL_HOST"
}

mysql_runtime_port() {
  printf '%s\n' "$MYSQL_PORT"
}

redis_runtime_host() {
  printf '%s\n' "$REMOTE_REDIS_HOST"
}

redis_runtime_port() {
  printf '%s\n' "$REDIS_PORT"
}

redis_runtime_url() {
  printf 'redis://%s:%s/0\n' "$(redis_runtime_host)" "$(redis_runtime_port)"
}

frontend_service_name() {
  if [[ "$FRONTEND_APP" == "admin" ]]; then
    printf 'ppanel-admin-web\n'
  else
    printf 'ppanel-user-web\n'
  fi
}

traffic_manager_installed() {
  kubectl get deployment traffic-manager -n "$TELEPRESENCE_MANAGER_NAMESPACE" >/dev/null 2>&1
}

telepresence_name_slug() {
  printf '%s' "${K8S_NAMESPACE}" | tr -c '[:alnum:]-' '-'
}

telepresence_configure() {
  TELEPRESENCE_DAEMON_NAME="ppanel-$(telepresence_name_slug)"
}

write_state_file() {
  local file="$1"
  shift
  : >"$file"
  while [[ $# -gt 0 ]]; do
    printf '%s=%s\n' "$1" "$2" >>"$file"
    shift 2
  done
}

read_state_value() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 0
  python3 - "$file" "$key" <<'PY'
import sys

path, key = sys.argv[1:]
value = ""
with open(path, "r", encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        if k == key:
            value = v
            break
print(value)
PY
}

frontend_state_value() {
  read_state_value "$FRONTEND_STATE_FILE" "$1"
}

server_state_value() {
  read_state_value "$SERVER_STATE_FILE" "$1"
}

write_frontend_state() {
  local api_base_url="$1"
  write_state_file \
    "$FRONTEND_STATE_FILE" \
    app "$FRONTEND_APP" \
    port "$(frontend_port)" \
    api_base_url "$api_base_url"
}

write_server_state() {
  write_state_file \
    "$SERVER_STATE_FILE" \
    mysql_host "$(mysql_runtime_host)" \
    mysql_port "$(mysql_runtime_port)" \
    mysql_database "$MYSQL_DATABASE" \
    mysql_user "$SERVER_DB_USER" \
    redis_host "$(redis_runtime_host)" \
    redis_port "$(redis_runtime_port)" \
    redis_password "$REDIS_PASSWORD"
}

telepresence_cmd() {
  telepresence --use "$TELEPRESENCE_DAEMON_NAME" "$@"
}

ensure_traffic_manager() {
  if traffic_manager_installed; then
    return
  fi

  if [[ "$INSTALL_TRAFFIC_MANAGER" != "true" ]]; then
    die "Telepresence traffic-manager is not installed in namespace ${TELEPRESENCE_MANAGER_NAMESPACE}. Rerun with --install-traffic-manager, or install it manually with: telepresence helm install --manager-namespace ${TELEPRESENCE_MANAGER_NAMESPACE} -n ${K8S_NAMESPACE}"
  fi

  log "Installing Telepresence traffic-manager into namespace ${TELEPRESENCE_MANAGER_NAMESPACE}"
  telepresence helm install --manager-namespace "$TELEPRESENCE_MANAGER_NAMESPACE" -n "$K8S_NAMESPACE"
}

telepresence_connect() {
  ensure_telepresence_tools
  ensure_traffic_manager
  telepresence_configure

  if telepresence status 2>&1 | grep -Eq 'file stale and removed|multiple daemons are running'; then
    telepresence quit --stop-daemons >/dev/null 2>&1 || true
  fi

  log "Connecting Telepresence to namespace ${K8S_NAMESPACE} (manager namespace ${TELEPRESENCE_MANAGER_NAMESPACE})"
  telepresence connect \
    --docker \
    --name "$TELEPRESENCE_DAEMON_NAME" \
    -n "$K8S_NAMESPACE" \
    --manager-namespace "$TELEPRESENCE_MANAGER_NAMESPACE"
}

telepresence_leave_intercept() {
  local name="$1"
  telepresence_configure
  telepresence_cmd leave "$name" >/dev/null 2>&1 || true
}

intercept_frontend_traffic() {
  local service
  service="$(frontend_service_name)"

  telepresence_connect
  telepresence_leave_intercept "$service"

  log "Intercepting frontend service ${K8S_NAMESPACE}/${service} to ${TELEPRESENCE_LOCAL_ADDRESS}:$(frontend_port)"
  telepresence_cmd intercept "$service" \
    --service "$service" \
    --port "$(frontend_port):3000" \
    --address "$TELEPRESENCE_LOCAL_ADDRESS"
}

intercept_server_traffic() {
  telepresence_connect
  telepresence_leave_intercept "ppanel-server"

  log "Intercepting backend service ${K8S_NAMESPACE}/ppanel-server to ${TELEPRESENCE_LOCAL_ADDRESS}:${LOCAL_SERVER_PORT}"
  telepresence_cmd intercept "ppanel-server" \
    --service "ppanel-server" \
    --port "${LOCAL_SERVER_PORT}:8080" \
    --address "$TELEPRESENCE_LOCAL_ADDRESS"
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

stop_conflicting_compose_server() {
  if docker_container_running "ppanel-server"; then
    log "Stopping existing dockerized ppanel-server to free port ${LOCAL_SERVER_PORT}"
    docker stop ppanel-server >/dev/null
  fi
}

ensure_server_process() {
  local current_mysql_host current_mysql_port current_mysql_database
  local current_mysql_user current_redis_host current_redis_port current_redis_password

  ensure_state_dir
  ensure_docker_network

  current_mysql_host="$(server_state_value mysql_host)"
  current_mysql_port="$(server_state_value mysql_port)"
  current_mysql_database="$(server_state_value mysql_database)"
  current_mysql_user="$(server_state_value mysql_user)"
  current_redis_host="$(server_state_value redis_host)"
  current_redis_port="$(server_state_value redis_port)"
  current_redis_password="$(server_state_value redis_password)"

  if docker_container_running "$SERVER_CONTAINER"; then
    if [[ "$current_mysql_host" != "$(mysql_runtime_host)" ]] || \
       [[ "$current_mysql_port" != "$(mysql_runtime_port)" ]] || \
       [[ "$current_mysql_database" != "$MYSQL_DATABASE" ]] || \
       [[ "$current_mysql_user" != "$SERVER_DB_USER" ]] || \
       [[ "$current_redis_host" != "$(redis_runtime_host)" ]] || \
       [[ "$current_redis_port" != "$(redis_runtime_port)" ]] || \
       [[ "$current_redis_password" != "$REDIS_PASSWORD" ]]; then
      log "Local server container config changed; recreating $SERVER_CONTAINER"
      docker rm -f "$SERVER_CONTAINER" >/dev/null 2>&1 || true
    else
      log "Local server container is already running: $SERVER_CONTAINER"
      return
    fi
  fi

  if docker_container_exists "$SERVER_CONTAINER"; then
    docker rm -f "$SERVER_CONTAINER" >/dev/null 2>&1 || true
  fi

  stop_conflicting_compose_server
  normalize_server_config

  log "Starting local ppanel-server container"
  docker run -d \
    --name "$SERVER_CONTAINER" \
    --network "$DEV_NETWORK" \
    -p "${LOCAL_SERVER_PORT}:8080" \
    -v "${SERVER_ROOT}/etc:/app/etc" \
    -e PPANEL_DB="${SERVER_DB_USER}:${SERVER_DB_PASSWORD}@tcp($(mysql_runtime_host):$(mysql_runtime_port))/${MYSQL_DATABASE}?charset=utf8mb4&parseTime=true&loc=Asia%2FShanghai" \
    -e PPANEL_REDIS="$(redis_runtime_url)" \
    "$SERVER_IMAGE" >/dev/null

  write_server_state

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

stop_frontend_listener() {
  local port="$1"
  local label="$2"
  local pid command

  pid="$(find_listener_pid "$port")"
  [[ -n "$pid" ]] || return 0

  command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  if [[ "$command" == *"$FRONTEND_ROOT"* ]] && [[ "$command" == *"vite"* || "$command" == *"bun"* || "$command" == *"node"* ]]; then
    log "Stopping $label on port ${port} (PID ${pid})"
    stop_pid_if_running "$pid"
    sleep 1
  fi
}

normalize_server_config() {
  if [[ ! -s "$CONFIG_PATH" ]]; then
    return
  fi

  python3 - "$CONFIG_PATH" "$(mysql_runtime_host)" "$(mysql_runtime_port)" "$MYSQL_DATABASE" "$SERVER_DB_USER" "$SERVER_DB_PASSWORD" "$(redis_runtime_host)" "$(redis_runtime_port)" "$REDIS_PASSWORD" <<'PY'
import re
import sys

path, mysql_host, mysql_port, mysql_db, mysql_user, mysql_password, redis_host, redis_port, redis_password = sys.argv[1:]
text = open(path, "r", encoding="utf-8").read()

replacements = [
    (r"(?m)^    Addr: .*$", f"    Addr: {mysql_host}:{mysql_port}"),
    (r"(?m)^    Username: .*$", f"    Username: {mysql_user}"),
    (r"(?m)^    Password: .*$", f"    Password: {mysql_password}"),
    (r"(?m)^    Dbname: .*$", f"    Dbname: {mysql_db}"),
    (r"(?m)^    Host: .*$", f"    Host: {redis_host}:{redis_port}"),
    (r"(?m)^    Pass: .*$", f"    Pass: {redis_password}"),
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
{"adminEmail":"${ADMIN_EMAIL}","adminPassword":"${ADMIN_PASSWORD}","mysqlHost":"$(mysql_runtime_host)","mysqlPort":"$(mysql_runtime_port)","mysqlDatabase":"${MYSQL_DATABASE}","mysqlUser":"${SERVER_DB_USER}","mysqlPassword":"${SERVER_DB_PASSWORD}","redisHost":"$(redis_runtime_host)","redisPort":"$(redis_runtime_port)","redisPassword":"${REDIS_PASSWORD}"}
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

  die "Admin login failed and the script cannot auto-promote a user in shared MySQL. Set ADMIN_EMAIL/ADMIN_PASSWORD to an existing admin account before rerunning."
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

ensure_server_backend() {
  ensure_basic_tools
  log "Using shared dependencies: MySQL $(mysql_runtime_host):$(mysql_runtime_port), Redis $(redis_runtime_host):$(redis_runtime_port)"
  ensure_server_process
  initialize_backend_if_needed
  configure_oauth_methods
  run_auth_self_check
}

start_frontend() {
  local api_base_url="${1:-}"
  local current_app current_api_base_url pid

  ensure_frontend_tools
  ensure_state_dir

  current_app="$(frontend_state_value app)"
  current_api_base_url="$(frontend_state_value api_base_url)"

  if [[ "$current_app" == "$FRONTEND_APP" ]] && [[ "$current_api_base_url" == "$api_base_url" ]] && [[ -z "$api_base_url" ]] && wait_for_http_status "http://${LOCAL_FRONTEND_HOST}:$(frontend_port)" 5 1; then
    log "Frontend is already reachable at http://${LOCAL_FRONTEND_HOST}:$(frontend_port); reusing existing dev server"
    return
  fi

  pid="$(read_pid "$FRONTEND_PID_FILE")"
  if is_pid_running "$pid"; then
    if [[ "$current_app" == "$FRONTEND_APP" ]] && [[ "$current_api_base_url" == "$api_base_url" ]]; then
      log "Frontend dev server is already running with PID $pid"
      return
    fi
    log "Frontend config changed; restarting frontend dev server (PID $pid)"
    stop_pid_if_running "$pid"
  fi
  rm -f "$FRONTEND_PID_FILE"
  rm -f "$FRONTEND_STATE_FILE"

  stop_frontend_listener "$LOCAL_USER_PORT" "stale frontend listener"
  stop_frontend_listener "$LOCAL_ADMIN_PORT" "stale frontend listener"

  ensure_frontend_port_available "$(frontend_port)" "frontend"
  ensure_frontend_port_available "$(frontend_devtools_port)" "frontend devtools"

  log "Starting local frontend (${FRONTEND_APP})"
  : >"$FRONTEND_LOG_FILE"
  if [[ -n "$api_base_url" ]]; then
    VITE_API_BASE_URL="$api_base_url" \
    VITE_API_PREFIX="" \
    start_detached_process \
      "$FRONTEND_PID_FILE" \
      "$FRONTEND_LOG_FILE" \
      "$(frontend_dir)" \
      /bin/sh -lc "$(frontend_dev_command)"
  else
    start_detached_process \
      "$FRONTEND_PID_FILE" \
      "$FRONTEND_LOG_FILE" \
      "$(frontend_dir)" \
      /bin/sh -lc "$(frontend_dev_command)"
  fi

  write_frontend_state "$api_base_url"

  if ! wait_for_http "http://${LOCAL_FRONTEND_HOST}:$(frontend_port)" 90 1; then
    die "Frontend did not become ready. See $FRONTEND_LOG_FILE"
  fi
}

up_frontend() {
  start_frontend
  intercept_frontend_traffic
}

up_server() {
  ensure_server_backend
  intercept_server_traffic
}

up_both() {
  ensure_server_backend
  start_frontend "$SERVER_URL"
  intercept_server_traffic
  intercept_frontend_traffic
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
  telepresence_leave_intercept "ppanel-server"
  if docker_container_exists "$SERVER_CONTAINER"; then
    log "Stopping local server container: $SERVER_CONTAINER"
    docker rm -f "$SERVER_CONTAINER" >/dev/null 2>&1 || true
  fi
  rm -f "$SERVER_STATE_FILE"
}

leave_frontend() {
  telepresence_leave_intercept "ppanel-admin-web"
  telepresence_leave_intercept "ppanel-user-web"
  stop_pid_file "$FRONTEND_PID_FILE" "frontend dev server"
  stop_frontend_listener "$LOCAL_USER_PORT" "frontend dev server"
  stop_frontend_listener "$LOCAL_ADMIN_PORT" "frontend dev server"
  rm -f "$FRONTEND_STATE_FILE"
}

status() {
  ensure_state_dir

  local server_pid frontend_pid frontend_app frontend_port_value frontend_api_base_url
  server_pid="$(read_pid "$SERVER_PID_FILE")"
  frontend_pid="$(read_pid "$FRONTEND_PID_FILE")"
  frontend_app="$(frontend_state_value app)"
  frontend_port_value="$(frontend_state_value port)"
  frontend_api_base_url="$(frontend_state_value api_base_url)"

  printf 'Server process:   %s\n' "$(docker_container_running "$SERVER_CONTAINER" && printf 'running (container %s)' "$SERVER_CONTAINER" || printf 'stopped')"
  printf 'Frontend process: %s\n' "$(is_pid_running "$frontend_pid" && printf 'running (pid %s)' "$frontend_pid" || printf 'stopped')"
  printf 'MySQL target:     %s:%s\n' "$(mysql_runtime_host)" "$(mysql_runtime_port)"
  printf 'Redis target:     %s:%s\n' "$(redis_runtime_host)" "$(redis_runtime_port)"
  printf 'K8s namespace:    %s\n' "$K8S_NAMESPACE"
  printf 'TP manager ns:    %s\n' "$TELEPRESENCE_MANAGER_NAMESPACE"
  printf 'Server URL:       %s\n' "$SERVER_URL"
  printf 'Frontend app:     %s\n' "${frontend_app:-unknown}"
  printf 'Frontend URL:     %s\n' "http://${LOCAL_FRONTEND_HOST}:${frontend_port_value:-unknown}"
  printf 'Frontend API URL: %s\n' "${frontend_api_base_url:-<default>}"
  printf 'Server log:       %s\n' "$SERVER_LOG_FILE"
  printf 'Frontend log:     %s\n' "$FRONTEND_LOG_FILE"

  if command -v telepresence >/dev/null 2>&1; then
    telepresence_configure
    printf '\nTelepresence:\n'
    telepresence_cmd status 2>&1 || true
    telepresence_cmd list --intercepts 2>&1 || true
  fi
}

case "$ACTION" in
  up)
    case "$TARGET" in
      frontend)
        parse_frontend_and_dependency_options "$@"
        up_frontend
        ;;
      server)
        parse_shared_dependency_options "$@"
        up_server
        ;;
      both)
        parse_frontend_and_dependency_options "$@"
        up_both
        ;;
      *)
        usage
        exit 1
        ;;
    esac
    ;;
  test-auth)
    parse_shared_dependency_options "$@"
    ensure_server_backend
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
