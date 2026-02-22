#!/usr/bin/env bash
# Unified startup for the proep.az ecosystem.
# Use for both first start and restart: ./start.sh [--nginx] [--no-docker]
# --nginx     Start with nginx reverse proxy on port 80
# --no-docker Skip Docker/Colima; use when Colima is broken. Script exits after printing manual steps.
# Starts Colima (Docker) if the daemon is not running (e.g. after reboot).

set -e
cd "$(dirname "$0")"

COMPOSE_FILE="docker-compose.unified.yml"
COMPOSE_OPTS="-f $COMPOSE_FILE"
SKIP_DOCKER=
for arg in "$@"; do
  if [[ "$arg" == "--no-docker" ]]; then
    SKIP_DOCKER=1
    break
  fi
done
if [[ "${1:-}" == "--nginx" && -z "$SKIP_DOCKER" ]]; then
  COMPOSE_OPTS="$COMPOSE_OPTS --profile with-nginx"
fi

# Load .env so DB_* and other vars are set (for compose and for pg_isready)
if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi
DB_USER="${DB_USER:-pro}"
DB_PASSWORD="${DB_PASSWORD:-Projson!}"
DB_NAME="${DB_NAME:-proep}"

# Warn if disk space is very low (avoids ENOSPC during build)
check_disk_space() {
  local avail_k
  avail_k=$(df -k . 2>/dev/null | awk 'NR==2 {print $4}' || echo "999999999")
  if [[ "$avail_k" =~ ^[0-9]+$ ]] && [[ "$avail_k" -lt 524288 ]]; then
    echo "==> WARNING: Low disk space (~$((avail_k / 1024))MB free). Build may fail with ENOSPC." >&2
    echo "    Free space: rm -rf admin.proep.az/dist-server  admin.proep.az/dist  admin.proep.az/node_modules/.vite" >&2
    echo "    Docker:     docker system prune -af" >&2
    echo "" >&2
  fi
}
check_disk_space

# Ensure Docker is running (start Colima if needed)
ensure_docker() {
  if docker info &>/dev/null; then
    return 0
  fi
  echo "==> Docker daemon not running. Trying to start Colima..."
  if ! command -v colima &>/dev/null; then
    echo "    Colima not found. Install Colima or Docker Desktop, start it, then run ./start.sh again." >&2
    exit 1
  fi

  try_colima_start() {
    local out
    out=$(colima start 2>&1) || true
    echo "$out"
    # Give Docker a moment to become ready after Colima starts
    echo "    Waiting for Docker (up to 60s)..."
    for i in {1..30}; do
      if docker info &>/dev/null; then
        return 0
      fi
      sleep 2
    done
    if echo "$out" | grep -qE "existing instance|Exiting:true"; then
      echo "" >&2
      echo "    Your Colima VM is in a bad state (existing instance won't start)." >&2
      echo "    Run this to recreate the VM, then ./start.sh again:" >&2
      echo "" >&2
      echo "      colima delete && colima start" >&2
      echo "" >&2
      echo "    Or:  COLIMA_RECREATE=1 ./start.sh" >&2
      echo "" >&2
    else
      echo "" >&2
      echo "    Colima started but Docker did not become ready. Try:" >&2
      echo "      colima start --verbose" >&2
      echo "      colima delete && colima start" >&2
      echo "    Logs: ~/.colima/_lima/colima/ha.stderr.log" >&2
      echo "" >&2
    fi
    echo "    To run without Docker:  ./start.sh --no-docker" >&2
    echo "" >&2
    return 1
  }

  if try_colima_start; then
    return 0
  fi

  if [[ -n "${COLIMA_RECREATE:-}" ]]; then
    echo "" >&2
    echo "==> COLIMA_RECREATE: Deleting Colima VM and creating a new one..." >&2
    colima delete -f 2>/dev/null || true
    sleep 2
    echo "    Starting new Colima VM (this can take 1–2 minutes)..." >&2
    recreate_out=$(colima start 2>&1) || true
    echo "$recreate_out"
    for i in {1..60}; do
      if docker info &>/dev/null; then
        echo "    Docker is ready."
        return 0
      fi
      [[ $i -eq 1 ]] && echo "    Waiting for Docker..."
      sleep 2
    done
    echo "    Docker did not become ready after recreate. Check: colima status; ~/.colima/_lima/colima/ha.stderr.log" >&2
    exit 1
  fi

  exit 1
}

if [[ -n "$SKIP_DOCKER" ]]; then
  echo "==> --no-docker: Skipping Docker/Colima."
  echo ""
  echo "  Run the stack manually:"
  echo "    1. Start Postgres (e.g. local install or another Docker run)."
  echo "    2. Set DB_HOST, DB_PORT, DB_USER, DB_NAME if needed, then run migrations from admin.proep.az/scripts/."
  echo "    3. Start admin backend:   cd admin.proep.az && npm run build:server && npm run start"
  echo "    4. Start admin frontend: cd admin.proep.az && npm run dev"
  echo "    5. Start scraping service, proep backend, etc. as required."
  echo ""
  echo "  To use Docker again: fix Colima (e.g. colima delete && colima start) then run ./start.sh without --no-docker."
  echo ""
  exit 0
fi

ensure_docker

for i in {1..30}; do
  if docker info &>/dev/null; then
    echo "    Docker is ready."
    break
  fi
  [[ $i -eq 1 ]] && echo "    Waiting for Docker to be ready..."
  sleep 2
done
if ! docker info &>/dev/null; then
  echo "    Timeout waiting for Docker." >&2
  echo "    To skip Docker and run services manually, use:  ./start.sh --no-docker" >&2
  exit 1
fi

# Prefer "docker compose" (v2 plugin); fall back to "docker-compose" (v1) if -f is not recognized
COMPOSE_CMD="docker compose"
if ! $COMPOSE_CMD $COMPOSE_OPTS config &>/dev/null 2>&1; then
  if command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
    echo "==> Using docker-compose (v1)."
  else
    echo "==> ERROR: Docker Compose not available (plugin failed and docker-compose not found)." >&2
    echo "    Install:  brew install docker-compose" >&2
    exit 1
  fi
fi

echo "==> Building and starting services (works for first start and restart)..."
$COMPOSE_CMD $COMPOSE_OPTS up -d --build

echo "==> Waiting for PostgreSQL to be healthy..."
PG_READY=
for i in {1..60}; do
  if $COMPOSE_CMD $COMPOSE_OPTS exec -T postgres pg_isready -U "$DB_USER" -d "$DB_NAME" 2>/dev/null; then
    PG_READY=1
    break
  fi
  echo "    Postgres not ready yet, retrying in 3s... ($i/60)"
  sleep 3
done
if [[ -z "$PG_READY" ]]; then
  echo "    Timeout waiting for Postgres." >&2
  exit 1
fi
echo "    Postgres is ready."

echo "==> Running migrations (idempotent)..."
if [[ -f db/schema.sql ]]; then
  cat db/schema.sql | $COMPOSE_CMD $COMPOSE_OPTS exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" -q -f - 2>/dev/null || true
  echo "    db/schema.sql applied."
fi
if [[ -f admin.proep.az/scripts/migrate-admin-auth.sql ]]; then
  cat admin.proep.az/scripts/migrate-admin-auth.sql | $COMPOSE_CMD $COMPOSE_OPTS exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" -q -f - 2>/dev/null || true
  echo "    Admin auth migration applied (admin_users / admin_sessions)."
fi
if [[ -f admin.proep.az/scripts/grant-scraping-to-pro.sql ]]; then
  cat admin.proep.az/scripts/grant-scraping-to-pro.sql | $COMPOSE_CMD $COMPOSE_OPTS exec -T postgres psql -U postgres -d "$DB_NAME" -q -f - 2>/dev/null || true
  echo "    Grants for scraping schema (pro) applied."
fi
if [[ -f admin.proep.az/scripts/migrate-job-tables.sql ]]; then
  cat admin.proep.az/scripts/migrate-job-tables.sql | $COMPOSE_CMD $COMPOSE_OPTS exec -T postgres psql -U postgres -d "$DB_NAME" -q -f - 2>/dev/null || true
  echo "    Job tables migration applied (job_config, job_execution_log)."
fi
if [[ -f admin.proep.az/scripts/init-job-configs-in-docker.sql ]]; then
  cat admin.proep.az/scripts/init-job-configs-in-docker.sql | $COMPOSE_CMD $COMPOSE_OPTS exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" -q -f - 2>/dev/null || true
  echo "    Scraping schema and articles table (admin articles API) applied."
fi
if [[ -f admin.proep.az/scripts/create-listings-table.sql ]]; then
  cat admin.proep.az/scripts/create-listings-table.sql | $COMPOSE_CMD $COMPOSE_OPTS exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" -q -f - 2>/dev/null || true
  echo "    Listings table (bina.az) applied."
fi

echo "==> Waiting for scraping service and triggering jobs (turbo.az, bina.az)..."
SCRAPING_URL="${SCRAPING_URL:-http://localhost:4000}"
for i in {1..30}; do
  if curl -sf "${SCRAPING_URL}/health" >/dev/null 2>&1; then
    if curl -sf -X POST "${SCRAPING_URL}/api/run-turbo-az" >/dev/null 2>&1; then
      echo "    turbo.az job triggered."
    else
      echo "    Scraping service up; turbo.az trigger skipped (job may not be in DB yet)."
    fi
    if curl -sf -X POST "${SCRAPING_URL}/api/run-bina-az" >/dev/null 2>&1; then
      echo "    bina.az job triggered."
    else
      echo "    bina.az trigger skipped (job or listings table may not be in DB yet)."
    fi
    break
  fi
  [[ $i -eq 1 ]] && echo "    Waiting for scraping service (up to 60s)..."
  sleep 2
done
if ! curl -sf "${SCRAPING_URL}/health" >/dev/null 2>&1; then
  echo "    Scraping service not ready; jobs will run when scheduler picks them up."
fi

echo ""
echo "=============================================="
echo "  Proep.az stack is up (TZ: Asia/Baku)"
echo "=============================================="
echo ""
echo "  Admin panel:     http://localhost:3002   (login: admin / admin123)"
echo "  Proep.az site:   http://localhost:3001"
echo "  Admin API:       http://localhost:4002"
echo "  Proep backend:   http://localhost:4001"
echo "  Scraping API:    http://localhost:4000"
echo "  Core job API:    http://localhost:4100"
echo "  Postgres:        localhost:5432 (user=$DB_USER, db=$DB_NAME)"
echo ""
if [[ "${1:-}" == "--nginx" ]]; then
  echo "  Nginx:           http://localhost:80"
  echo "  /etc/hosts:      127.0.0.1  admin.proep.az  proep.az"
  echo ""
fi
echo "  Stop:  $COMPOSE_CMD -f $COMPOSE_FILE down"
echo ""
