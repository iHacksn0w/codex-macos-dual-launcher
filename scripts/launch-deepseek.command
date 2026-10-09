#!/bin/zsh
set -u
# Finder/AppleScript does not source interactive zsh startup files. Load the
# existing user environment without printing it; never persist the key here.
if [[ ! -r "$HOME/.zshrc" ]]; then
  print -r -- "无法读取 ~/.zshrc，未找到现有的 OPENAI_API_KEY 环境设置；未修改配置。"
  exit 0
fi
source "$HOME/.zshrc" >/dev/null 2>&1 || {
  print -r -- "加载 ~/.zshrc 失败，未修改配置。"
  exit 0
}
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  print -r -- "当前启动环境没有 OPENAI_API_KEY；请检查 ~/.zshrc 中已有的环境变量设置；未修改配置。"
  exit 0
fi
exec "$HOME/.codex-switcher/scripts/switch.command" deepseek
