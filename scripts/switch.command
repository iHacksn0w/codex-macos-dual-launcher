#!/bin/zsh
set -u
umask 077
MODE="${1:-}"
ROOT="$HOME/.codex-switcher"
ACTIVE="$HOME/.codex/config.toml"
CATALOG="$HOME/.codex/model-catalog.local.json"
APP="/Applications/ChatGPT.app"
PYTHON="$ROOT/python"
APP_STATE="$ROOT/scripts/app-state"
TX="$ROOT/scripts/config_transaction.py"
LOG="$ROOT/logs/switch.log"
MANIFEST="$ROOT/install-state.json"
LOCK="$ROOT/.switch.lock"
[[ "$MODE" == go || "$MODE" == deepseek ]] || { print -u2 "无效模式；请从桌面入口启动。"; exit 2; }
log() { /usr/bin/printf '%s mode=%s stage=%s %s\n' "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z')" "$MODE" "$1" "${2:-}" >> "$LOG"; }
fail() { log "$1" "failed"; /usr/bin/osascript -e "display dialog \"Codex ${MODE} 切换失败：$2\" buttons {\"好\"} default button \"好\" with icon stop" >/dev/null 2>&1 || true; exit 1; }
[[ -f "$ACTIVE" && -f "$MANIFEST" && -x "$PYTHON" && -x "$APP_STATE" && -f "$TX" && -d "$APP" ]] || fail preflight "配置、安装状态、运行状态 helper 或 ChatGPT.app 不完整；未修改配置。"
[[ ! -e "$LOCK" ]] || fail lock "另一个切换操作正在执行；请稍后重试。"
/bin/mkdir "$LOCK" 2>/dev/null || fail lock "无法取得切换锁；已有操作或锁状态异常。"
trap '/bin/rm -f "$LOCK/pid"; /bin/rmdir "$LOCK" 2>/dev/null || true' EXIT
/usr/bin/printf '%s\n' "$$" > "$LOCK/pid" || fail lock "锁初始化失败。"
log start

# Query LaunchServices by bundle identifier. Any interpreter/query failure is unknown.
app_state() {
  local result
  result="$("$APP_STATE" 2>/dev/null)" || return 2
  case "$result" in running) return 0;; stopped) return 1;; *) return 2;; esac
}
app_state; state=$?
(( state == 2 )) && fail app_state "无法可靠确认应用运行状态；配置保持不变。"
if (( state == 0 )); then
  /usr/bin/osascript -e 'display dialog "ChatGPT.app 正在运行。请保存工作并正常退出 ChatGPT，然后再次双击此入口。切换器不会关闭应用。" buttons {"好"} default button "好" with icon caution' >/dev/null 2>&1 || true
  fail app_running "ChatGPT.app 正在运行；请正常退出后再次双击。配置保持不变。"
fi
app_state; state=$?
(( state == 1 )) || fail app_state "应用状态发生变化或无法确认；配置保持不变。"

if [[ "$MODE" == deepseek && -z "${OPENAI_API_KEY:-}" ]]; then
  log environment_missing "failed"
  print -r -- "当前启动环境没有 OPENAI_API_KEY；未修改配置。请确认 ~/.zshrc 中的现有设置可加载。"
  exit 0
fi

before_sha="$(/usr/bin/shasum -a 256 "$ACTIVE" | /usr/bin/awk '{print $1}')" || fail fingerprint "无法计算配置指纹。"
app_state; state=$?
(( state == 1 )) || fail app_state "应用状态无法确认；配置保持不变。"
args=("$MODE" --config "$ACTIVE" --manifest "$MANIFEST" --backup-dir "$ROOT/backups" --expected-sha "$before_sha")
if [[ "$MODE" == deepseek ]]; then
  args+=(--catalog "$CATALOG")
fi
backup="$("$PYTHON" "$TX" "${args[@]}")" || fail transaction "路由更新、并发保护或 TOML 校验失败；请检查日志及备份。"
after_sha="$(/usr/bin/shasum -a 256 "$ACTIVE" | /usr/bin/awk '{print $1}')" || fail fingerprint "更新后无法计算配置指纹；保留备份：$backup"
log configured "backup=$(/usr/bin/basename "$backup")"

# Ask LaunchServices to start the official app only after a validated commit.
if [[ "$MODE" == deepseek ]]; then
  # `--env NAME` forwards the existing process value without placing it in argv.
  /usr/bin/open --env OPENAI_API_KEY -a "$APP" >/dev/null 2>&1
  open_status=$?
else
  /usr/bin/open -a "$APP" >/dev/null 2>&1
  open_status=$?
fi
if (( open_status != 0 )); then
  app_state; state=$?
  if (( state == 1 )); then
    "$PYTHON" "$TX" rollback --config "$ACTIVE" --backup "$backup" --expected-sha "$after_sha" --backup-dir "$ROOT/backups" >/dev/null 2>&1 || fail rollback "启动失败，且无法安全自动回滚。请保留配置和备份：$backup"
    fail launch "ChatGPT.app 启动失败；已自动恢复切换前配置。备份：$(/usr/bin/basename "$backup")"
  fi
  fail launch_uncertain "启动命令失败且应用状态不确定；未自动覆盖配置。当前备份：$backup"
fi
for _ in {1..15}; do
  app_state; state=$?
  (( state == 0 )) && break
  (( state == 2 )) && fail launch_uncertain "启动已请求，但无法确认应用状态；当前模式和备份均保留：$backup"
  /bin/sleep 1
done
app_state; state=$?
if (( state == 1 )); then
  "$PYTHON" "$TX" rollback --config "$ACTIVE" --backup "$backup" --expected-sha "$after_sha" --backup-dir "$ROOT/backups" >/dev/null 2>&1 || fail rollback "应用未启动且无法安全自动回滚。请保留备份：$backup"
  fail launch "ChatGPT.app 未显示为运行；已恢复切换前配置。备份：$(/usr/bin/basename "$backup")"
elif (( state == 2 )); then
  fail launch_uncertain "启动已请求，但运行状态无法确认；配置与备份均保留：$backup"
fi
log success
/usr/bin/osascript -e "display dialog \"已切换到 ${MODE} 模式并启动 ChatGPT.app。模型调用结果需在应用内确认。\" buttons {\"好\"} default button \"好\"" >/dev/null 2>&1 || true
