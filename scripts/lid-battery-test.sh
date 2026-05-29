#!/usr/bin/env bash
set -euo pipefail

MODE="baseline"
DURATION=""
RUN_ID=""
ROOT_DIR="$HOME/Desktop/lid-test"
RUN_DIR=""
HEARTBEAT_PID=""
CAFFEINATE_PID=""
DISABLESLEEP_ACTIVE=0
INTERVAL_SECONDS=10

usage() {
    cat <<'EOF'
Usage:
  scripts/lid-battery-test.sh [baseline|caffeinate|disablesleep] [duration-seconds]
  scripts/lid-battery-test.sh --mode <mode> --duration <seconds>

Modes:
  baseline      Log battery heartbeat only. Default duration: 180s.
  caffeinate    Log while caffeinate -im is scoped to the heartbeat. Default: 180s.
  disablesleep  Temporarily set sudo pmset -a disablesleep 1. Default: 300s.

Logs are written under ~/Desktop/lid-test/<run-id>/.
EOF
}

fail() {
    printf 'lid-battery-test: ERROR: %s\n' "$*" >&2
    exit 1
}

require_tool() {
    command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"
}

is_positive_integer() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

default_duration_for_mode() {
    case "$1" in
        baseline|caffeinate) printf '180' ;;
        disablesleep) printf '300' ;;
        *) fail "unknown mode: $1" ;;
    esac
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -m|--mode)
                [[ $# -ge 2 ]] || fail "$1 requires a value"
                MODE="$2"
                shift 2
                ;;
            -d|--duration)
                [[ $# -ge 2 ]] || fail "$1 requires a value"
                DURATION="$2"
                shift 2
                ;;
            --run-id)
                [[ $# -ge 2 ]] || fail "$1 requires a value"
                RUN_ID="$2"
                shift 2
                ;;
            baseline|caffeinate|disablesleep)
                MODE="$1"
                shift
                ;;
            *)
                if [[ -z "$DURATION" && "$1" =~ ^[0-9]+$ ]]; then
                    DURATION="$1"
                    shift
                else
                    fail "unknown argument: $1"
                fi
                ;;
        esac
    done

    case "$MODE" in
        baseline|caffeinate|disablesleep) ;;
        *) fail "unknown mode: $MODE" ;;
    esac

    if [[ -z "$DURATION" ]]; then
        DURATION="$(default_duration_for_mode "$MODE")"
    fi

    is_positive_integer "$DURATION" || fail "duration must be a positive integer number of seconds"
    [[ "$RUN_ID" != */* ]] || fail "run id must not contain slashes"
}

check_prerequisites() {
    require_tool pmset
    case "$MODE" in
        caffeinate) require_tool caffeinate ;;
        disablesleep) require_tool sudo ;;
    esac
}

record_pmset() {
    local output_file="$1"
    if ! pmset -g custom > "$output_file" 2>&1; then
        printf 'pmset -g custom failed; see output above\n' >> "$output_file"
    fi
}

stop_child() {
    local pid="$1"
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
        kill "$pid" >/dev/null 2>&1 || true
        wait "$pid" >/dev/null 2>&1 || true
    fi
}

cleanup() {
    local status=$?
    trap - EXIT HUP INT TERM

    stop_child "$CAFFEINATE_PID"
    stop_child "$HEARTBEAT_PID"

    if [[ "$DISABLESLEEP_ACTIVE" == "1" ]]; then
        if ! sudo -n pmset -a disablesleep 0 >/dev/null 2>&1; then
            sudo pmset -a disablesleep 0 >/dev/null || printf 'lid-battery-test: WARNING: failed to restore disablesleep 0\n' >&2
        fi
        DISABLESLEEP_ACTIVE=0
    fi

    if [[ -n "$RUN_DIR" ]]; then
        record_pmset "$RUN_DIR/pmset-after.txt"
    fi

    exit "$status"
}

heartbeat_loop() {
    local duration="$1"
    local log_file="$2"
    local end_time=$((SECONDS + duration))

    while (( SECONDS < end_time )); do
        local timestamp=""
        local battery_line=""
        timestamp="$(date '+%F %T')"
        battery_line="$(pmset -g batt 2>&1 | tail -1)" || battery_line="pmset -g batt failed"
        printf '%s | %s\n' "$timestamp" "$battery_line" >> "$log_file"

        local remaining=$((end_time - SECONDS))
        if (( remaining <= 0 )); then
            break
        elif (( remaining < INTERVAL_SECONDS )); then
            sleep "$remaining"
        else
            sleep "$INTERVAL_SECONDS"
        fi
    done
}

start_heartbeat() {
    heartbeat_loop "$DURATION" "$RUN_DIR/heartbeat.log" &
    HEARTBEAT_PID=$!
}

run_caffeinate() {
    start_heartbeat
    caffeinate -im -w "$HEARTBEAT_PID" &
    CAFFEINATE_PID=$!
    wait "$HEARTBEAT_PID"
    HEARTBEAT_PID=""
    wait "$CAFFEINATE_PID" || true
    CAFFEINATE_PID=""
}

run_baseline() {
    start_heartbeat
    wait "$HEARTBEAT_PID"
    HEARTBEAT_PID=""
}

run_disablesleep() {
    sudo -v
    sudo pmset -a disablesleep 1
    DISABLESLEEP_ACTIVE=1
    run_baseline
}

main() {
    parse_args "$@"
    check_prerequisites

    RUN_ID="${RUN_ID:-$(date '+%Y%m%d-%H%M%S')-$MODE}"
    RUN_DIR="$ROOT_DIR/$RUN_ID"
    mkdir -p "$RUN_DIR"

    trap cleanup EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    record_pmset "$RUN_DIR/pmset-before.txt"

    printf 'Mode: %s\n' "$MODE"
    printf 'Duration: %ss\n' "$DURATION"
    printf 'Log: %s\n' "$RUN_DIR/heartbeat.log"

    case "$MODE" in
        baseline) run_baseline ;;
        caffeinate) run_caffeinate ;;
        disablesleep) run_disablesleep ;;
    esac

    printf 'Done. Results: %s\n' "$RUN_DIR"
}

main "$@"
