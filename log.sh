#!/usr/bin/env bash
#
# log.sh — Stream real-time logs from all currently running processes (no selection).
# Usage:
#   ./log.sh              # monitor and stream logs from all relevant processes
#   ./log.sh -- <cmd>...  # run one command and stream its output with timestamps
#
# Output: [YYYY-MM-DD HH:MM:SS] PID: <pid> | <comm> | <log line>
# Portable: Linux (strace), macOS (dtruss may need sudo; else suggest -- <cmd>).
#
set -e

# Process names we try to attach to (stdout/stderr). Skip kernel/system.
LOG_COMMS="node postgres nginx python python3 java docker containerd npm"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

case "$(uname -s)" in
  Linux)   OS=linux ;;
  Darwin)  OS=macos ;;
  *)       OS=other ;;
esac

get_comm() {
  local pid="$1"
  [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ ]] && { echo "?"; return; }
  ps -p "$pid" -o comm= 2>/dev/null || echo "?"
}

process_exists() {
  kill -0 "$1" 2>/dev/null
}

# Attach to one process and stream write(1)/write(2) with timestamps. Used in background.
attach_one() {
  local pid="$1"
  local comm="$2"
  if ! process_exists "$pid"; then
    return 0
  fi
  if [[ "$OS" != "linux" ]]; then
    return 0
  fi
  if ! command -v strace &>/dev/null; then
    return 1
  fi
  local re='write\(([12]), "(.+)", ([0-9]+)\)'
  strace -p "$pid" -e write -f -s 99999 2>/dev/null | while IFS= read -r line; do
    if [[ "$line" =~ $re ]]; then
      fd="${BASH_REMATCH[1]}"
      content="${BASH_REMATCH[2]}"
      content="${content//\\n/$'\n'}"
      content="${content//\\t/$'\t'}"
      content="${content//\\\\/\\}"
      prefix=""
      [[ "$fd" == "2" ]] && prefix="STDERR: "
      while IFS= read -r ln; do
        [[ -n "$ln" ]] && echo "[$(timestamp)] PID: $pid | $comm | $prefix$ln"
      done <<< "$content"
    fi
  done
  return 0
}

# Discover PIDs for LOG_COMMS (and optionally current user only to reduce noise)
discover_pids() {
  local pids=()
  local self=$$
  for comm in $LOG_COMMS; do
    local list
    list=$(pgrep -x "$comm" 2>/dev/null || true)
    for pid in $list; do
      [[ "$pid" -eq "$self" ]] && continue
      # Skip if we don't have permission (strace will fail anyway)
      kill -0 "$pid" 2>/dev/null || continue
      pids+=("$pid")
    done
  done
  # Dedupe and limit
  printf '%s\n' "${pids[@]}" | sort -nu | head -50
}

# macOS: stream logs from Docker containers and/or common log files
monitor_all_macos() {
  local have_any=0
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

  # Docker Compose (e.g. pro project)
  if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    if [[ -f "$script_dir/docker-compose.unified.yml" ]]; then
      have_any=1
      echo "[$(timestamp)] INFO: Following docker-compose logs (Ctrl+C to stop)." >&2
      ( docker compose -f "$script_dir/docker-compose.unified.yml" logs -f 2>&1 | while IFS= read -r line; do
          echo "[$(timestamp)] docker | $line"
        done
      ) &
    elif [[ -f "$script_dir/docker-compose.yml" ]]; then
      have_any=1
      echo "[$(timestamp)] INFO: Following docker-compose logs (Ctrl+C to stop)." >&2
      ( docker compose -f "$script_dir/docker-compose.yml" logs -f 2>&1 | while IFS= read -r line; do
          echo "[$(timestamp)] docker | $line"
        done
      ) &
    fi
  fi

  # Common log files (if present)
  while IFS= read -r entry; do
    label="${entry%%:*}"
    path="${entry#*:}"
    [[ -z "$path" ]] && continue
    if [[ -f "$path" ]]; then
      have_any=1
      ( tail -F "$path" 2>/dev/null | while IFS= read -r line; do
          echo "[$(timestamp)] $label | $line"
        done
      ) &
    fi
  done <<< "nginx:/usr/local/var/log/nginx/access.log
nginx:/opt/homebrew/var/log/nginx/access.log
postgres:/usr/local/var/log/postgres.log
app:$script_dir/logs/app.log
scraping:$script_dir/scraping/logs/out.log"

  if [[ $have_any -eq 0 ]]; then
    echo "[$(timestamp)] INFO: No Docker or log files found to follow." >&2
    echo "[$(timestamp)] Start your app and run: ./log.sh -- <command>  (e.g. ./log.sh -- node dist/index.js)" >&2
    exit 0
  fi

  trap 'kill 0 2>/dev/null; exit 0' INT TERM
  wait
}

# Monitor all: attach to each discovered process in background, stream to console
monitor_all() {
  if [[ "$OS" == "macos" ]]; then
    monitor_all_macos
    return
  fi
  if [[ "$OS" != "linux" ]]; then
    echo "[$(timestamp)] INFO: All-process monitoring is supported on Linux (strace) or macOS (Docker/logs)." >&2
    echo "[$(timestamp)] On macOS run: ./log.sh   or   ./log.sh -- <command>" >&2
    exit 0
  fi
  if ! command -v strace &>/dev/null; then
    echo "[$(timestamp)] ERROR: strace not found. Install: apt install strace / yum install strace" >&2
    exit 1
  fi

  local pids=()
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    pids+=("$pid")
  done < <(discover_pids)

  if [[ ${#pids[@]} -eq 0 ]]; then
    echo "[$(timestamp)] INFO: No processes found matching: $LOG_COMMS" >&2
    echo "[$(timestamp)] Start a service (e.g. node, postgres) and run ./log.sh again, or use: ./log.sh -- <command>" >&2
    exit 0
  fi

  echo "[$(timestamp)] INFO: Attaching to ${#pids[@]} process(es). Ctrl+C to stop." >&2
  for pid in "${pids[@]}"; do
    comm=$(get_comm "$pid")
    echo "[$(timestamp)] PID: $pid | $comm | (attached)" >&2
    attach_one "$pid" "$comm" &
  done

  trap 'kill 0 2>/dev/null; exit 0' INT TERM
  wait
}

# Run one command and stream its output with timestamps
run_and_stream() {
  if [[ $# -eq 0 ]]; then
    echo "[$(timestamp)] ERROR: No command after --. Usage: ./log.sh -- <command> [args...]" >&2
    exit 1
  fi
  local cmd_name="$1"
  "$@" 2>&1 | while IFS= read -r line; do
    echo "[$(timestamp)] PID: $$ | $cmd_name | $line"
  done
  exit "${PIPESTATUS[0]:-0}"
}

# --- main ---
if [[ "$1" == "--" ]]; then
  shift
  run_and_stream "$@"
  exit 0
fi

monitor_all
