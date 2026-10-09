#!/bin/zsh
set -u
umask 077
MODE="${1:-}"
TESTDIR="${2:-}"
fallback_log="${HOME:-/private/tmp}/Library/Logs/CodexSwitcher/launcher.log"
report_error() {
  local stage_name="$1" message="$2"
  /bin/mkdir -p "${fallback_log:h}" 2>/dev/null || true
  /usr/bin/printf '%s mode=%s stage=%s\n' "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z')" "${MODE:-unknown}" "$stage_name" >> "$fallback_log" 2>/dev/null || true
  print -u2 "$message"
}
if [[ -z "$TESTDIR" ]]; then
  report_error missing_testdir "启动参数错误：缺少 TESTDIR 路径参数。"
  exit 64
fi
if [[ ! -d "$TESTDIR" ]]; then
  report_error missing_directory "启动参数错误：TESTDIR 目录不存在：$TESTDIR"
  exit 66
fi
ROOT="$TESTDIR"
LOG="$ROOT/logs/applet-selftest.log"
REQUEST="$ROOT/.applet-selftest.request"
MARKER="$ROOT/.applet-selftest.marker"
if [[ "$MODE" != go && "$MODE" != deepseek ]]; then
  report_error invalid_mode "启动参数错误：模式必须为 go 或 deepseek。"
  exit 64
fi
stage() { /usr/bin/printf '%s mode=%s stage=%s\n' "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z')" "$MODE" "$1" >> "$LOG"; }
stage applet_helper_entered
if [[ -f "$REQUEST" ]]; then
  stage selftest_request_detected
  /usr/bin/touch "$MARKER" || { stage marker_write_failed; exit 1; }
  [[ -f "$MARKER" ]] || { stage marker_check_failed; exit 1; }
  stage marker_verified
  print -n "CODEX_SWITCHER_SELFTEST_OK"
  exit 0
fi
stage normal_dispatch
exec /bin/zsh "$ROOT/scripts/launch-$MODE.command"
