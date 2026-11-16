#!/usr/bin/env bash
set -euo pipefail
ROOT=/mnt/workspace/ComfyUI
if ! command -v nvidia-smi >/dev/null || ! nvidia-smi; then
  printf '\033[31m未检测到 GPU，请在魔搭控制台切换为 A10 GPU 实例。\033[0m\n' >&2; exit 1
fi
[[ -x "$ROOT/.venv/bin/python" ]] || { echo '未找到持久化 Python 环境，请先运行 1_install_cpu.sh'; exit 1; }
cd "$ROOT"
PY="$ROOT/.venv/bin/python"
if ! "$PY" -c 'import sageattention' >/dev/null 2>&1; then
  echo '安装 SageAttention 与 Triton（可能需要 CUDA 编译环境）'
  "$PY" -m pip install triton sageattention -i https://mirrors.aliyun.com/pypi/simple/
fi
echo '请复制当前浏览器地址栏的网址，将末尾的 /lab 替换为 /proxy/8188/ 并在新标签页打开'
echo '若代理不可用，请检查当前 Jupyter 服务是否启用 jupyter-server-proxy。'
exec "$PY" main.py --listen 0.0.0.0 --port 8188 --use-sage-attention
