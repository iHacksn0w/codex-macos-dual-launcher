#!/bin/zsh
set -u
umask 077
ROOT="$HOME/.codex-switcher"
ACTIVE="$HOME/.codex/config.toml"
PYTHON="$ROOT/python"
TX="$ROOT/scripts/config_transaction.py"
MANIFEST="$ROOT/install-state.json"
APP_STATE="$ROOT/scripts/app-state"
LOCK="$ROOT/.switch.lock"
[[ -d "$ROOT" && -f "$ACTIVE" && -x "$PYTHON" && -x "$APP_STATE" && -f "$TX" && -f "$MANIFEST" ]] || { print -u2 "卸载检查失败；恢复文件未改动。"; exit 1; }
for pair in "go:$HOME/Desktop/Codex - GO.app" "deepseek:$HOME/Desktop/Codex - DeepSeek.app"; do
  mode="${pair%%:*}"; app="${pair#*:}"
  if [[ -e "$app" ]]; then
    expected="$("$PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1]))["app_hashes"][sys.argv[2]])' "$MANIFEST" "$mode" 2>/dev/null)" || { print -u2 "无法确认 $mode.app 安装指纹；卸载停止。"; exit 1; }
    /usr/bin/codesign --verify --deep "$app" >/dev/null 2>&1 || { print -u2 "$mode.app 签名校验失败；卸载停止：$app"; exit 1; }
    actual="$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1 | /usr/bin/sed -n 's/^CDHash=//p')"
    [[ -n "$expected" && "$actual" == "$expected" ]] || { print -u2 "$mode.app 与此安装记录不匹配；卸载停止：$app"; exit 1; }
  fi
done
[[ ! -e "$LOCK" ]] || { print -u2 "切换器正在运行；卸载已停止。"; exit 1; }
/bin/mkdir "$LOCK" 2>/dev/null || { print -u2 "无法取得切换锁；卸载已停止。"; exit 1; }
trap '/bin/rmdir "$LOCK" 2>/dev/null || true' EXIT
state="$("$APP_STATE" 2>/dev/null)" || { print -u2 "无法确认 ChatGPT.app 状态；没有修改配置。"; exit 1; }
[[ "$state" == stopped ]] || { print -u2 "ChatGPT.app 正在运行或状态异常；请正常退出后再卸载。"; exit 1; }
/usr/bin/osascript -e 'display dialog "将恢复安装前的官方路由，并移除两个桌面入口。所有配置备份及 Keychain 项都会保留。继续吗？" buttons {"取消", "卸载"} default button "取消" cancel button "取消" with icon caution' >/dev/null || { print "已取消。"; exit 0; }
before="$(/usr/bin/shasum -a 256 "$ACTIVE" | /usr/bin/awk '{print $1}')" || { print -u2 "无法计算配置指纹。"; exit 1; }
"$PYTHON" "$TX" restore --config "$ACTIVE" --manifest "$MANIFEST" --backup-dir "$ROOT/backups" --expected-sha "$before" >/dev/null || { print -u2 "路由恢复失败；入口与恢复文件保留。"; exit 1; }
stamp="$(/bin/date +%Y%m%d-%H%M%S)"
for app in "$HOME/Desktop/Codex - GO.app" "$HOME/Desktop/Codex - DeepSeek.app"; do
  [[ ! -e "$app" ]] || /bin/rm -rf "$app" || { print -u2 "删除入口失败：$app；恢复文件保留在 $ROOT。"; exit 1; }
done
archive="$HOME/.codex-switcher-uninstalled-$stamp"
/bin/mv "$ROOT" "$archive" || { print -u2 "入口已移除但无法归档切换器；恢复文件仍在 $ROOT。"; exit 1; }
print "已恢复安装前路由，移除桌面入口。配置备份与切换器归档保留在：$archive"
