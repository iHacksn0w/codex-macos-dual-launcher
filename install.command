#!/bin/zsh
set -eu
umask 077

PROJECT="${0:A:h}"
ROOT="$HOME/.codex-switcher"
ACTIVE="$HOME/.codex/config.toml"
CATALOG="$HOME/.codex/model-catalog.local.json"
CHATGPT="/Applications/ChatGPT.app"
DESKTOP="$HOME/Desktop"
STAGE="$HOME/.codex-switcher.installing.$$.${RANDOM}"

fail() { print -u2 -- "安装停止：$1"; exit 1; }
[[ "$(/usr/bin/uname -s)" == Darwin ]] || fail "此安装器只支持 macOS。"
[[ -d "$CHATGPT" ]] || fail "未找到 /Applications/ChatGPT.app。"
[[ -f "$ACTIVE" ]] || fail "未找到 ~/.codex/config.toml。"
[[ -f "$CATALOG" ]] || fail "未找到 ~/.codex/model-catalog.local.json；安装不会创建或覆盖它。"
[[ ! -e "$ROOT" ]] || fail "~/.codex-switcher 已存在；为保护现有安装与备份，本安装器不覆盖它。"
[[ ! -e "$DESKTOP/Codex - GO.app" && ! -e "$DESKTOP/Codex - DeepSeek.app" ]] || fail "目标桌面入口已存在；安装器不会覆盖或删除现有 App。请先人工检查并处理旧入口。"

PYTHON_BIN=""
for candidate in /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3.11 /usr/local/bin/python3.13 /usr/local/bin/python3.12 /usr/local/bin/python3.11 /usr/bin/python3; do
  [[ -x "$candidate" ]] || continue
  if "$candidate" -c 'import sys,tomllib; raise SystemExit(0 if sys.version_info >= (3,11) else 1)' >/dev/null 2>&1; then PYTHON_BIN="$candidate"; break; fi
done
[[ -n "$PYTHON_BIN" ]] || fail "需要 Python 3.11 或更高版本（内置 tomllib）；不会自动安装依赖。"

for file in scripts/config_transaction.py scripts/app-state.m scripts/applet-dispatch.command scripts/switch.command scripts/launch-go.command scripts/launch-deepseek.command scripts/restore-go.command scripts/uninstall.command scripts/launcher-go.js scripts/launcher-deepseek.js; do
  [[ -f "$PROJECT/$file" ]] || fail "项目文件缺失：$file"
done

"$PYTHON_BIN" - "$ACTIVE" "$CATALOG" <<'PY'
import json, sys, tomllib
from pathlib import Path
cfg = tomllib.loads(Path(sys.argv[1]).read_text())
catalog = json.loads(Path(sys.argv[2]).read_text())
models = catalog.get("models", []) if isinstance(catalog, dict) else []
if not any(isinstance(m, dict) and m.get("slug") == "deepseek-v4.1-flash" for m in models):
    raise SystemExit("模型目录中没有 deepseek-v4.1-flash；安装不会修改配置。")
PY
"$PYTHON_BIN" -m unittest discover -s "$PROJECT/tests" -v || fail "自动化测试失败；未安装。"
[[ -d "$DESKTOP" && -w "$DESKTOP" ]] || fail "桌面目录不可写。"

print -- "将执行："
print -- "  - 在 ~/.codex-switcher 安装脚本并保留初始 config.toml 备份"
print -- "  - 编译 app-state helper 并生成两个原生 Applet"
print -- "  - 创建两个桌面入口"
print -- "不会切换活动路由、启动/退出 ChatGPT.app、读取 auth.json 或访问网络。"
read "answer?在 Terminal 输入 INSTALL 继续，其他输入取消："
[[ "$answer" == INSTALL ]] || { print -- "已取消，未安装。"; exit 0; }

mkdir -m 700 "$STAGE"
trap 'if [[ -d "$STAGE" ]]; then /bin/rm -rf "$STAGE"; fi' EXIT
mkdir -m 700 "$STAGE/scripts" "$STAGE/configs" "$STAGE/backups" "$STAGE/logs" "$STAGE/candidate-apps"
for file in scripts/config_transaction.py scripts/app-state.m scripts/applet-dispatch.command scripts/switch.command scripts/launch-go.command scripts/launch-deepseek.command scripts/restore-go.command scripts/uninstall.command; do
  /usr/bin/ditto "$PROJECT/$file" "$STAGE/$file"
done
/usr/bin/ditto "$PROJECT/configs/config.deepseek.example.toml" "$STAGE/configs/config.deepseek.example.toml"
/usr/bin/ditto "$PROJECT/configs/config.go.example.toml" "$STAGE/configs/config.go.example.toml"
chmod 700 "$STAGE" "$STAGE/scripts" "$STAGE/backups" "$STAGE/logs"
chmod 700 "$STAGE/scripts"/*.command
chmod 600 "$STAGE/scripts/config_transaction.py"
ln -s "$PYTHON_BIN" "$STAGE/python"
"$PYTHON_BIN" "$STAGE/scripts/config_transaction.py" capture --config "$ACTIVE" --manifest "$STAGE/install-state.json"
cp -p "$ACTIVE" "$STAGE/backups/config.install-time.bak"
chmod 600 "$STAGE/install-state.json" "$STAGE/backups/config.install-time.bak"

/usr/bin/xcrun --sdk macosx clang -fobjc-arc -framework AppKit "$STAGE/scripts/app-state.m" -o "$STAGE/scripts/app-state" || fail "无法编译 app-state helper；需要可用的 Xcode Command Line Tools。"
chmod 700 "$STAGE/scripts/app-state"
for script in applet-dispatch.command switch.command launch-go.command launch-deepseek.command restore-go.command uninstall.command; do
  /bin/zsh -n "$STAGE/scripts/$script" || fail "Zsh 语法检查失败：$script"
done

/usr/bin/osacompile -l JavaScript -o "$STAGE/candidate-apps/Codex - GO.app" "$PROJECT/scripts/launcher-go.js" || fail "GO Applet 编译失败。"
/usr/bin/osacompile -l JavaScript -o "$STAGE/candidate-apps/Codex - DeepSeek.app" "$PROJECT/scripts/launcher-deepseek.js" || fail "DeepSeek Applet 编译失败。"
for app in "$STAGE/candidate-apps/Codex - GO.app" "$STAGE/candidate-apps/Codex - DeepSeek.app"; do
  /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist" >/dev/null || fail "Applet 缺少 CFBundleExecutable。"
  /usr/bin/codesign --verify --deep "$app" >/dev/null 2>&1 || fail "Applet 签名完整性检查失败。"
done

"$PYTHON_BIN" - "$STAGE/install-state.json" "$STAGE/candidate-apps/Codex - GO.app" "$STAGE/candidate-apps/Codex - DeepSeek.app" <<'PY'
import json, os, subprocess, sys
manifest, go, ds = sys.argv[1:]
def cdhash(path):
    out = subprocess.run(["/usr/bin/codesign", "-dv", "--verbose=4", path], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False).stdout
    return next((line.split("=",1)[1] for line in out.splitlines() if line.startswith("CDHash=")), None)
data = json.load(open(manifest))
data["app_hashes"] = {"go": cdhash(go), "deepseek": cdhash(ds)}
if not all(data["app_hashes"].values()): raise SystemExit("无法记录 Applet 签名指纹。")
data["install_id"] = subprocess.check_output(["/bin/date", "+%Y%m%d-%H%M%S"], text=True).strip()
with open(manifest, "w") as f: json.dump(data, f, indent=2); f.write("\n")
PY

/bin/mv "$STAGE" "$ROOT"
trap - EXIT
/usr/bin/ditto "$ROOT/candidate-apps/Codex - GO.app" "$DESKTOP/Codex - GO.app" || fail "GO 入口发布失败；已保留 ~/.codex-switcher 与完整备份。"
/usr/bin/ditto "$ROOT/candidate-apps/Codex - DeepSeek.app" "$DESKTOP/Codex - DeepSeek.app" || fail "DeepSeek 入口发布失败；已保留 ~/.codex-switcher 与完整备份。"
print -- "安装完成。当前活动配置没有切换；备份位于 $ROOT/backups。首次使用请双击所需桌面入口。"
