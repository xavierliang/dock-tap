#!/usr/bin/env bash
set -euo pipefail

MODE="baseline"
DURATION=""
RUN_ID=""
ROOT_DIR="$HOME/Desktop/lid-test"
RUN_DIR=""
HEARTBEAT_PID=""
CAFFEINATE_PID=""
SUDO_KEEPALIVE_PID=""
DISABLESLEEP_ACTIVE=0
INTERVAL_SECONDS=10
SUDO_KEEPALIVE_INTERVAL_SECONDS=60

# dim 模式专用状态
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_SRC="$SCRIPT_DIR/brightness-probe.swift"
PROBE_BIN=""
BRIGHTNESS_SAVED=""
BRIGHTNESS_DIMMED=0
DIM_TARGET="0.0"

usage() {
    cat <<'EOF'
Usage:
  scripts/lid-battery-test.sh [baseline|caffeinate|disablesleep] [duration-seconds]
  scripts/lid-battery-test.sh --mode <mode> --duration <seconds>

Modes:
  baseline      Log battery heartbeat only. Default duration: 180s.
  caffeinate    Log while caffeinate -im is scoped to the heartbeat. Default: 180s.
  disablesleep  Temporarily set sudo pmset -a disablesleep 1. Default: 300s.
  dim           Step 0 spike: sudo pmset -a disablesleep 1 + dim the built-in
                display to DIM_TARGET (default 0.0), then log battery AND
                built-in brightness every interval. Use this to verify whether
                the dimmed brightness survives a closed lid under disablesleep.
                Default: 300s. Restores brightness and disablesleep on exit.

Logs are written under ~/Desktop/lid-test/<run-id>/.
For dim mode, brightness samples are also written to brightness.log.
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
        disablesleep|dim) printf '300' ;;
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
            baseline|caffeinate|disablesleep|dim)
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
        baseline|caffeinate|disablesleep|dim) ;;
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
        dim)
            require_tool sudo
            require_tool swiftc
            [[ -f "$PROBE_SRC" ]] || fail "brightness probe source not found: $PROBE_SRC"
            ;;
    esac
}

# 把亮度探针编译成一次性二进制，避免每次采样都重新编译。
build_probe() {
    PROBE_BIN="$RUN_DIR/brightness-probe"
    if ! swiftc -O "$PROBE_SRC" -o "$PROBE_BIN" 2>"$RUN_DIR/probe-build.log"; then
        fail "failed to compile brightness probe; see $RUN_DIR/probe-build.log"
    fi
}

probe_get() {
    "$PROBE_BIN" get 2>/dev/null
}

probe_set() {
    "$PROBE_BIN" set "$1" >/dev/null 2>&1
}

# 读合盖状态。把 ioreg 输出整体存进变量后再匹配，避免 grep 提前关管道
# 在 pipefail 下触发 SIGPIPE 把命令判成失败。只匹配带引号的精确 key，
# 不会被 AppleClamshellCausesSleep 行干扰。
read_clamshell() {
    local line
    line="$(ioreg -r -k AppleClamshellState 2>/dev/null | grep '"AppleClamshellState"')" || true
    case "$line" in
        *Yes*) printf 'Yes' ;;
        *No*) printf 'No' ;;
        *) printf '?' ;;
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

start_sudo_keepalive() {
    while true; do
        sudo -n -v >/dev/null 2>&1 || exit 0
        sleep "$SUDO_KEEPALIVE_INTERVAL_SECONDS"
    done &
    SUDO_KEEPALIVE_PID=$!
}

warn_manual_disablesleep_restore() {
    cat >&2 <<'EOF'
lid-battery-test: WARNING: could not restore disablesleep automatically because sudo credentials are unavailable.
Run this command manually now to restore normal sleep behavior:
  sudo pmset -a disablesleep 0
EOF
}

warn_manual_brightness_restore() {
    cat >&2 <<EOF
lid-battery-test: WARNING: could not restore built-in display brightness automatically.
Restore it manually with the brightness slider or:
  swift "$PROBE_SRC" set ${BRIGHTNESS_SAVED:-0.5}
EOF
}

cleanup() {
    local status=$?
    trap - EXIT HUP INT TERM

    stop_child "$CAFFEINATE_PID"
    stop_child "$HEARTBEAT_PID"

    if [[ "$BRIGHTNESS_DIMMED" == "1" ]]; then
        if [[ -n "$BRIGHTNESS_SAVED" && -n "$PROBE_BIN" && -x "$PROBE_BIN" ]] && probe_set "$BRIGHTNESS_SAVED"; then
            :
        else
            warn_manual_brightness_restore
        fi
        BRIGHTNESS_DIMMED=0
    fi

    if [[ "$DISABLESLEEP_ACTIVE" == "1" ]]; then
        if ! sudo -n pmset -a disablesleep 0 >/dev/null 2>&1; then
            warn_manual_disablesleep_restore
        fi
        DISABLESLEEP_ACTIVE=0
    fi

    stop_child "$SUDO_KEEPALIVE_PID"

    if [[ -n "$RUN_DIR" ]]; then
        record_pmset "$RUN_DIR/pmset-after.txt"
    fi

    exit "$status"
}

heartbeat_loop() {
    local duration="$1"
    local log_file="$2"
    local brightness_log="${3:-}"
    local end_time=$((SECONDS + duration))

    while (( SECONDS < end_time )); do
        local timestamp=""
        local battery_line=""
        timestamp="$(date '+%F %T')"
        battery_line="$(pmset -g batt 2>&1 | tail -1)" || battery_line="pmset -g batt failed"
        printf '%s | %s\n' "$timestamp" "$battery_line" >> "$log_file"

        if [[ -n "$brightness_log" ]]; then
            local b=""
            local clam=""
            b="$(probe_get)" || b="get-failed"
            clam="$(read_clamshell)"
            printf '%s | brightness=%s | clamshell=%s\n' "$timestamp" "${b:-empty}" "${clam:-?}" >> "$brightness_log"
        fi

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

start_heartbeat_with_brightness() {
    heartbeat_loop "$DURATION" "$RUN_DIR/heartbeat.log" "$RUN_DIR/brightness.log" &
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
    start_sudo_keepalive
    sudo pmset -a disablesleep 1
    DISABLESLEEP_ACTIVE=1
    run_baseline
}

run_dim() {
    build_probe

    BRIGHTNESS_SAVED="$(probe_get)" || fail "could not read current built-in brightness"
    [[ -n "$BRIGHTNESS_SAVED" ]] || fail "built-in brightness read returned empty"
    printf 'Saved current brightness: %s\n' "$BRIGHTNESS_SAVED"

    sudo -v
    start_sudo_keepalive
    sudo pmset -a disablesleep 1
    DISABLESLEEP_ACTIVE=1

    probe_set "$DIM_TARGET" || fail "could not set dimmed brightness"
    BRIGHTNESS_DIMMED=1
    printf 'Dimmed built-in display to: %s\n' "$DIM_TARGET"

    cat <<EOF

>>> Now CLOSE THE LID for the test duration (${DURATION}s).
>>> The script logs brightness + clamshell state every ${INTERVAL_SECONDS}s.
>>> When you reopen, check $RUN_DIR/brightness.log :
>>>   - clamshell=Yes rows confirm the lid was detected as closed
>>>   - brightness=$DIM_TARGET held throughout = dim survives disablesleep (PASS)
>>>   - brightness bouncing back up = system reset it (FAIL)
>>> heartbeat.log continuing = system stayed awake.

EOF

    start_heartbeat_with_brightness
    wait "$HEARTBEAT_PID"
    HEARTBEAT_PID=""
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
        dim) run_dim ;;
    esac

    printf 'Done. Results: %s\n' "$RUN_DIR"
}

main "$@"
