#!/usr/bin/env bash
set -euo pipefail

readonly RUNTIME_ROOT="${XDG_RUNTIME_DIR:-/tmp}/jobo-big-cheese-${UID}"
readonly MARKER_FILE="${RUNTIME_ROOT}/pulse.state"
readonly OUTCOME_FILE="${RUNTIME_ROOT}/pulse.outcome"
readonly LOCK_FILE="${RUNTIME_ROOT}/pulse.lock"
readonly MASK_FILE="${RUNTIME_ROOT}/mask.state"

marker_pid=""
marker_theme_b64=""
marker_theme=""
marker_baseline_size=""
marker_peak_size=""
marker_deadline_ms=""
outcome_name=""
outcome_started_at_ms=""
outcome_completed_at_ms=""
pulse_started_at_ms=""
lock_held=0
cleanup_needed=0
outcome_needed=0
cursor_x=""
cursor_y=""
mask_pid=""
mask_baseline=""
mask_deadline_ms=""
mask_cleanup_needed=0

fail() {
  printf 'cursor-pulse: %s\n' "$*" >&2
  exit 64
}

ensure_runtime() {
  umask 077
  [[ ! -L "$RUNTIME_ROOT" ]] || fail "runtime directory must not be a symlink"
  mkdir -p -- "$RUNTIME_ROOT"
  [[ -d "$RUNTIME_ROOT" && -O "$RUNTIME_ROOT" ]] \
    || fail "runtime directory is not owned by the current user"
  chmod 0700 -- "$RUNTIME_ROOT"
  [[ ! -L "$MARKER_FILE" && ! -L "$OUTCOME_FILE" && ! -L "$LOCK_FILE" \
      && ! -L "$MASK_FILE" ]] || fail "runtime files must not be symlinks"
}

is_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

is_bounded_integer() {
  local value=$1 minimum=$2 maximum=$3
  is_integer "$value" || return 1
  # Reject unsafe decimal forms before Bash arithmetic can wrap.
  (( ${#value} <= ${#maximum} )) || return 1
  (( 10#$value >= minimum && 10#$value <= maximum ))
}

validate_integer() {
  local name=$1 value=$2 minimum=$3 maximum=$4
  is_bounded_integer "$value" "$minimum" "$maximum" \
    || fail "$name must be between $minimum and $maximum"
}

validate_marker_integer() {
  is_bounded_integer "$1" "$2" "$3"
}

is_coordinate() {
  local value=$1
  [[ "$value" =~ ^-?(0|[1-9][0-9]*)$ ]] || return 1
  (( ${#value} <= 11 )) || return 1
  (( value >= -2147483648 && value <= 2147483647 ))
}

read_cursor_position() {
  local output
  output=$(hyprctl cursorpos) || return 1
  [[ "$output" =~ ^[[:space:]]*(-?[0-9]+),[[:space:]]*(-?[0-9]+)[[:space:]]*$ ]] \
    || return 1
  cursor_x=${BASH_REMATCH[1]}
  cursor_y=${BASH_REMATCH[2]}
  is_coordinate "$cursor_x" && is_coordinate "$cursor_y"
}

refresh_cursor_image() {
  read_cursor_position || return 1

  # Hyprland can retain the old active cursor surface after setcursor. Warping
  # to the already-current position refreshes the image without visible motion.
  local lua_dispatch="hl.dsp.cursor.move({ x = ${cursor_x}, y = ${cursor_y} })"
  if hyprctl dispatch "$lua_dispatch" >/dev/null 2>&1; then
    return 0
  fi
  hyprctl dispatch movecursor "$cursor_x" "$cursor_y" >/dev/null 2>&1
}

now_ms() {
  date +%s%3N
}

encode_theme() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

decode_theme() {
  printf '%s' "$1" | base64 --decode
}

write_marker() {
  local pid=$1 theme=$2 baseline_size=$3 peak_size=$4 deadline_ms=$5
  local temporary theme_b64
  temporary="${MARKER_FILE}.tmp.${pid}"
  theme_b64=$(encode_theme "$theme")
  {
    printf 'version=1\n'
    printf 'pid=%s\n' "$pid"
    printf 'theme_b64=%s\n' "$theme_b64"
    printf 'baseline_size=%s\n' "$baseline_size"
    printf 'peak_size=%s\n' "$peak_size"
    printf 'deadline_ms=%s\n' "$deadline_ms"
  } >"$temporary"
  chmod 0600 -- "$temporary"
  mv -f -- "$temporary" "$MARKER_FILE"
}

write_mask_marker() {
  local pid=$1 baseline=$2 deadline_ms=$3 temporary
  temporary="${MASK_FILE}.tmp.${pid}"
  {
    printf 'version=1\n'
    printf 'pid=%s\n' "$pid"
    printf 'baseline=%s\n' "$baseline"
    printf 'deadline_ms=%s\n' "$deadline_ms"
  } >"$temporary"
  chmod 0600 -- "$temporary"
  mv -f -- "$temporary" "$MASK_FILE"
}

read_mask_marker() {
  [[ -f "$MASK_FILE" ]] || return 1

  local version="" key value
  mask_pid=""
  mask_baseline=""
  mask_deadline_ms=""
  while IFS='=' read -r key value; do
    case "$key" in
      version) version=$value ;;
      pid) mask_pid=$value ;;
      baseline) mask_baseline=$value ;;
      deadline_ms) mask_deadline_ms=$value ;;
    esac
  done <"$MASK_FILE"

  [[ "$version" == "1" ]] || return 2
  validate_marker_integer "$mask_pid" 1 4194304 || return 2
  [[ "$mask_baseline" == true || "$mask_baseline" == false ]] || return 2
  validate_marker_integer "$mask_deadline_ms" 1 99999999999999 || return 2
}

read_cursor_invisible() {
  local output
  output=$(hyprctl -j getoption cursor:invisible) || return 1
  [[ "$output" =~ \"bool\"[[:space:]]*:[[:space:]]*(true|false) ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

set_cursor_invisible() {
  local value=$1
  [[ "$value" == true || "$value" == false ]] || return 1
  hyprctl eval "hl.config { cursor = { invisible = ${value} } }" >/dev/null
}

restore_mask_baseline() {
  set_cursor_invisible "$mask_baseline" || return 1
  refresh_cursor_image
}

restore_mask_marker() {
  restore_mask_baseline || return 1
  rm -f -- "$MASK_FILE"
}

read_marker() {
  [[ -f "$MARKER_FILE" ]] || return 1

  local version="" key value
  marker_pid=""
  marker_theme_b64=""
  marker_theme=""
  marker_baseline_size=""
  marker_peak_size=""
  marker_deadline_ms=""

  while IFS='=' read -r key value; do
    case "$key" in
      version) version=$value ;;
      pid) marker_pid=$value ;;
      theme_b64) marker_theme_b64=$value ;;
      baseline_size) marker_baseline_size=$value ;;
      peak_size) marker_peak_size=$value ;;
      deadline_ms) marker_deadline_ms=$value ;;
    esac
  done <"$MARKER_FILE"

  [[ "$version" == "1" ]] || return 2
  validate_marker_integer "$marker_pid" 1 4194304 || return 2
  validate_marker_integer "$marker_baseline_size" 1 512 || return 2
  validate_marker_integer "$marker_peak_size" 1 512 || return 2
  validate_marker_integer "$marker_deadline_ms" 1 99999999999999 || return 2
  [[ -n "$marker_theme_b64" && ${#marker_theme_b64} -le 4096 ]] || return 2
  marker_theme=$(decode_theme "$marker_theme_b64" 2>/dev/null) || return 2
  [[ -n "$marker_theme" && ${#marker_theme} -le 512 ]] || return 2
}

write_outcome() {
  local outcome=$1 started_at_ms=$2 completed_at_ms=$3 temporary
  temporary="${OUTCOME_FILE}.tmp.$$"
  {
    printf 'version=1\n'
    printf 'outcome=%s\n' "$outcome"
    printf 'started_at_ms=%s\n' "$started_at_ms"
    printf 'completed_at_ms=%s\n' "$completed_at_ms"
  } >"$temporary"
  chmod 0600 -- "$temporary"
  mv -f -- "$temporary" "$OUTCOME_FILE"
}

read_outcome() {
  [[ -f "$OUTCOME_FILE" ]] || return 1

  local version="" key value
  outcome_name=""
  outcome_started_at_ms=""
  outcome_completed_at_ms=""
  while IFS='=' read -r key value; do
    case "$key" in
      version) version=$value ;;
      outcome) outcome_name=$value ;;
      started_at_ms) outcome_started_at_ms=$value ;;
      completed_at_ms) outcome_completed_at_ms=$value ;;
    esac
  done <"$OUTCOME_FILE"

  [[ "$version" == "1" ]] || return 2
  [[ "$outcome_name" == "success" || "$outcome_name" == "failed" ]] || return 2
  validate_marker_integer "$outcome_started_at_ms" 1 99999999999999 || return 2
  validate_marker_integer "$outcome_completed_at_ms" 1 99999999999999 || return 2
  (( 10#$outcome_completed_at_ms >= 10#$outcome_started_at_ms )) || return 2
}

print_idle_status() {
  local recovered=${1:-} outcome_result
  if read_outcome; then
    printf '{"state":"idle"'
    [[ -z "$recovered" ]] || printf ',"recovered":%s' "$recovered"
    printf ',"outcome":"%s","startedAtMs":%s,"completedAtMs":%s}\n' \
      "$outcome_name" "$outcome_started_at_ms" "$outcome_completed_at_ms"
    return 0
  else
    outcome_result=$?
  fi
  (( outcome_result == 1 )) || return 1
  if [[ -z "$recovered" ]]; then
    printf '{"state":"idle"}\n'
  else
    printf '{"state":"idle","recovered":%s}\n' "$recovered"
  fi
}

owner_alive() {
  kill -0 "$marker_pid" 2>/dev/null
}

restore_loaded_marker() {
  if hyprctl setcursor "$marker_theme" "$marker_baseline_size" \
      && refresh_cursor_image; then
    rm -f -- "$MARKER_FILE"
    return 0
  fi
  return 1
}

acquire_lock() {
  if (( ! lock_held )); then
    flock 9
    lock_held=1
  fi
}

release_lock() {
  if (( lock_held )); then
    flock -u 9
    lock_held=0
  fi
}

restore_owned_marker() {
  local expected_pid=$1 marker_result
  acquire_lock
  if read_marker; then
    :
  else
    marker_result=$?
    if (( marker_result == 1 )); then
      cleanup_needed=0
      return 0
    fi
    return 1
  fi
  if [[ "$marker_pid" != "$expected_pid" ]]; then
    cleanup_needed=0
    return 0
  fi
  if restore_loaded_marker; then
    cleanup_needed=0
    return 0
  fi
  return 1
}

cleanup_mask() {
  local exit_code=$? marker_result
  trap - EXIT
  trap '' INT TERM HUP
  if (( mask_cleanup_needed )); then
    acquire_lock
    if read_mask_marker; then
      if [[ "$mask_pid" == "$$" ]] && ! restore_mask_marker; then
        exit_code=1
      fi
    else
      marker_result=$?
      # The process retains its validated baseline in memory. Restore from it
      # even if its marker was removed or corrupted while the cursor was hidden.
      if ! restore_mask_baseline; then
        exit_code=1
      elif [[ "$marker_result" != 1 && -f "$MASK_FILE" && ! -L "$MASK_FILE" ]]; then
        rm -f -- "$MASK_FILE"
      fi
    fi
    release_lock
  fi
  exit "$exit_code"
}

cleanup_pulse() {
  local exit_code=$? outcome=failed completed_at_ms
  trap - EXIT
  # Restoration is the last safety boundary. A second signal must not interrupt it.
  trap '' INT TERM HUP
  if (( cleanup_needed )) && ! restore_owned_marker "$$"; then
    exit_code=1
  fi
  if (( outcome_needed )); then
    (( exit_code == 0 && cleanup_needed == 0 )) && outcome=success
    completed_at_ms=$(now_ms)
    acquire_lock
    write_outcome "$outcome" "$pulse_started_at_ms" "$completed_at_ms"
  fi
  release_lock
  exit "$exit_code"
}

print_status() {
  local state=$1 alive=$2
  printf '{"state":"%s","pid":%s,"themeBase64":"%s","baselineSize":%s,"peakSize":%s,"deadlineMs":%s,"ownerAlive":%s}\n' \
    "$state" "$marker_pid" "$marker_theme_b64" "$marker_baseline_size" \
    "$marker_peak_size" "$marker_deadline_ms" "$alive"
}

status_command() {
  local marker_result current state alive=false
  if read_marker; then
    :
  else
    marker_result=$?
    if (( marker_result == 1 )); then
      print_idle_status || {
        printf '{"state":"invalid"}\n'
        return 1
      }
      return 0
    fi
    printf '{"state":"invalid"}\n'
    return 1
  fi

  current=$(now_ms)
  if owner_alive; then alive=true; fi
  state=stale
  if [[ "$alive" == true ]] && (( 10#$current <= 10#$marker_deadline_ms )); then
    state=active
  fi
  print_status "$state" "$alive"
}

recover_command() {
  local marker_result current alive=false
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    printf '{"state":"busy"}\n'
    return 75
  fi
  lock_held=1

  if read_marker; then
    :
  else
    marker_result=$?
    if (( marker_result == 1 )); then
      if read_mask_marker; then
        current=$(now_ms)
        if kill -0 "$mask_pid" 2>/dev/null; then alive=true; fi
        if [[ "$alive" == true ]] && (( 10#$current <= 10#$mask_deadline_ms )); then
          printf '{"state":"active","kind":"mask","pid":%s,"deadlineMs":%s}\n' \
            "$mask_pid" "$mask_deadline_ms"
          return 0
        fi
        if restore_mask_marker; then
          printf '{"state":"idle","recovered":true}\n'
          return 0
        fi
        printf '{"state":"recovery-failed","recovered":false}\n'
        return 1
      else
        local mask_result=$?
        if (( mask_result != 1 )); then
          printf '{"state":"invalid","recovered":false}\n'
          return 1
        fi
      fi
      if print_idle_status false; then
        return 0
      fi
      # Outcome telemetry must never block restoration readiness.
      rm -f -- "$OUTCOME_FILE"
      printf '{"state":"idle","recovered":false}\n'
      return 0
    fi
    printf '{"state":"invalid","recovered":false}\n'
    return 1
  fi

  current=$(now_ms)
  if owner_alive; then alive=true; fi
  if [[ "$alive" == true ]] && (( 10#$current <= 10#$marker_deadline_ms )); then
    print_status active true
    return 0
  fi

  rm -f -- "$OUTCOME_FILE"
  if restore_loaded_marker; then
    printf '{"state":"idle","recovered":true}\n'
    return 0
  fi
  printf '{"state":"recovery-failed","recovered":false}\n'
  return 1
}

mask_command() {
  (( $# == 1 )) || fail "mask requires duration"
  local duration_ms=$1 current deadline marker_result alive=false stop_requested=false
  validate_integer "duration" "$duration_ms" 1 60000

  exec 9>"$LOCK_FILE"
  flock -n 9 || fail "another cursor operation is active"
  lock_held=1

  if read_mask_marker; then
    current=$(now_ms)
    if kill -0 "$mask_pid" 2>/dev/null; then alive=true; fi
    if [[ "$alive" == true ]] && (( 10#$current <= 10#$mask_deadline_ms )); then
      fail "another cursor mask is active"
    fi
    restore_mask_marker || fail "could not recover the previous cursor mask"
  else
    marker_result=$?
    (( marker_result == 1 )) || fail "cursor mask marker is invalid"
  fi

  mask_baseline=$(read_cursor_invisible) || fail "could not read cursor visibility"
  current=$(now_ms)
  deadline=$((10#$current + 10#$duration_ms + 300))
  write_mask_marker "$$" "$mask_baseline" "$deadline"
  mask_cleanup_needed=1
  trap cleanup_mask EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  trap 'stop_requested=true' USR1

  set_cursor_invisible true
  # Active clients may retain their last cursor surface until the compositor
  # receives pointer motion. A same-position refresh applies invisibility
  # without moving the hotspot.
  refresh_cursor_image
  release_lock
  # Leave two compositor frames between the native refresh and overlay reveal.
  sleep 0.04
  printf 'masked\n'
  while [[ "$stop_requested" == false ]]; do
    current=$(now_ms)
    (( 10#$current < 10#$deadline - 300 )) || break
    sleep 0.05
  done
  # Tell QML to unmap the overlay, then allow two compositor frames before
  # revealing the native cursor. This mirrors the guarded startup transition.
  printf 'restoring\n'
  sleep 0.04

  acquire_lock
  read_mask_marker
  if [[ "$mask_pid" == "$$" ]]; then
    restore_mask_marker
    mask_cleanup_needed=0
  fi
}

unmask_command() {
  (( $# == 0 )) || fail "unmask takes no arguments"
  local marker_result
  if read_mask_marker; then
    :
  else
    marker_result=$?
    (( marker_result == 1 )) && printf '{"state":"idle"}\n' && return 0
    fail "cursor mask marker is invalid"
  fi
  kill -USR1 "$mask_pid" 2>/dev/null || fail "cursor mask owner is not running"
  printf '{"state":"stopping"}\n'
}

pulse_command() {
  (( $# == 4 )) || fail "pulse requires theme, baseline size, peak size, and duration"
  local theme=$1 baseline_size=$2 peak_size=$3 duration_ms=$4
  local current deadline sleep_seconds marker_result alive=false

  [[ -n "$theme" ]] || fail "theme must not be empty"
  (( ${#theme} <= 512 )) || fail "theme is too long"
  validate_integer "baseline size" "$baseline_size" 1 512
  validate_integer "peak size" "$peak_size" 1 512
  validate_integer "duration" "$duration_ms" 1 60000

  exec 9>"$LOCK_FILE"
  flock -n 9 || fail "another cursor operation is active"
  lock_held=1

  if read_marker; then
    current=$(now_ms)
    if owner_alive; then alive=true; fi
    if [[ "$alive" == true ]] && (( 10#$current <= 10#$marker_deadline_ms )); then
      fail "another cursor pulse is active"
    fi
    restore_loaded_marker || fail "could not recover the previous cursor pulse"
  else
    marker_result=$?
    (( marker_result == 1 )) || fail "recovery marker is invalid"
  fi

  rm -f -- "$OUTCOME_FILE"
  current=$(now_ms)
  pulse_started_at_ms=$current
  deadline=$((10#$current + 10#$duration_ms + 300))
  write_marker "$$" "$theme" "$baseline_size" "$peak_size" "$deadline"
  cleanup_needed=1
  outcome_needed=1
  trap cleanup_pulse EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP

  hyprctl setcursor "$theme" "$peak_size"
  refresh_cursor_image
  release_lock

  printf -v sleep_seconds '%d.%03d' "$((10#$duration_ms / 1000))" "$((10#$duration_ms % 1000))"
  sleep "$sleep_seconds"

  # restore_owned_marker acquires and retains the lock. The EXIT trap publishes
  # the terminal outcome before releasing it, so no newer pulse can be
  # overwritten by this pulse's result.
  restore_owned_marker "$$"
}

main() {
  (( $# >= 1 )) || fail "expected mask, unmask, pulse, recover, or status"
  local command=$1
  shift
  ensure_runtime

  case "$command" in
    mask) mask_command "$@" ;;
    unmask) unmask_command "$@" ;;
    pulse) pulse_command "$@" ;;
    recover)
      (( $# == 0 )) || fail "recover takes no arguments"
      recover_command
      ;;
    status)
      (( $# == 0 )) || fail "status takes no arguments"
      status_command
      ;;
    *) fail "unknown command: $command" ;;
  esac
}

main "$@"
