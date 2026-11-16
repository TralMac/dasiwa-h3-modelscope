#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT=/mnt/workspace/ComfyUI
PIP_INDEX=https://mirrors.aliyun.com/pypi/simple/
[[ -d /mnt/workspace ]] || { echo '错误：未找到 /mnt/workspace'; exit 1; }
cd /mnt/workspace
clone_repo() {
  local repo="$1" dest="$2" temp="${2}.clone-tmp"
  if [[ -d "$dest/.git" ]]; then echo "已存在：$dest"; return; fi
  [[ ! -e "$dest" && ! -e "$temp" ]] || { echo "目标或临时目录已存在，请检查：$dest $temp"; exit 1; }
  echo "克隆 $repo"
  if ! git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 clone --depth 1 "https://github.com/$repo.git" "$temp"; then
    rm -rf -- "$temp"
    git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 clone --depth 1 "https://ghfast.top/https://github.com/$repo.git" "$temp"
  fi
  mv -- "$temp" "$dest"
}
echo '【1/5】安装 ComfyUI 与插件'
clone_repo Comfy-Org/ComfyUI "$ROOT"
mkdir -p "$ROOT/custom_nodes" "$ROOT/models/text_encoders" "$ROOT/models/vae" "$ROOT/models/diffusion_models" "$ROOT/user/default/workflows"
for spec in 'ltdrdata/ComfyUI-Manager' 'kijai/ComfyUI-KJNodes' 'Kosinkadink/ComfyUI-VideoHelperSuite'; do
  clone_repo "$spec" "$ROOT/custom_nodes/${spec##*/}"
done
python -m venv --system-site-packages "$ROOT/.venv"
PY="$ROOT/.venv/bin/python"
"$PY" -m pip install -i "$PIP_INDEX" -r "$ROOT/requirements.txt" modelscope 'huggingface_hub[cli]' hf_transfer
for dir in "$ROOT"/custom_nodes/{ComfyUI-Manager,ComfyUI-KJNodes,ComfyUI-VideoHelperSuite}; do
  [[ ! -f "$dir/requirements.txt" ]] || "$PY" -m pip install -i "$PIP_INDEX" -r "$dir/requirements.txt"
done
echo '【2/5】下载 ModelScope 权重'
export HF_HOME="$ROOT/.cache/huggingface" MODELSCOPE_CACHE="$ROOT/.cache/modelscope" XDG_CACHE_HOME="$ROOT/.cache"
"$ROOT/.venv/bin/modelscope" download --model Comfy-Org/MiniMax-H3 --local_dir "$ROOT/models" \
  vae/minimax_h3_video_vae_fp16.safetensors vae/minimax_h3_audio_vae_fp32.safetensors
echo '【3/5】下载 DaSiWa 主模型'
export HF_ENDPOINT=https://hf-mirror.com HF_HUB_ENABLE_HF_TRANSFER=1
# Comfy-Org 官方仓库未列出该 INT4 编码器；使用其已公开的 Merserk 来源。
"$ROOT/.venv/bin/hf" download Merserk/MiniMax-H3-INT4-ConvRot qwen3vl_32b_minimax_h3_int4_convrot.safetensors --local-dir "$ROOT/models/text_encoders"
"$ROOT/.venv/bin/hf" download releaseworthy/dasiwa-minimax-h3-turbo-int8 --include '*.safetensors' --local-dir "$ROOT/models/diffusion_models"
target="$ROOT/models/diffusion_models/DasiwaMinimaxH3_dasiwaHybridV4_int8.safetensors"
turbo="$ROOT/models/diffusion_models/DasiwaMinimaxH3_dasiwaHybridV4Turbo_int8.safetensors"
if [[ ! -e "$target" && -s "$turbo" ]]; then ln -s "${turbo##*/}" "$target"; fi
if [[ ! -s "$target" ]]; then
  echo "错误：下载结果缺少 $target；请核对仓库中的文件名，不会自动链接不明模型。"; exit 1
fi
echo '【4/5】安装工作流'
cp "$SCRIPT_DIR/DaSiWa_H3_v4_Turbo_Workflow.json" "$ROOT/user/default/workflows/DaSiWa_H3_v4_Turbo.json"
echo '【5/5】检查文件大小并清理本工程缓存'
for f in "$target" "$ROOT/models/text_encoders/qwen3vl_32b_minimax_h3_int4_convrot.safetensors" "$ROOT/models/vae/minimax_h3_video_vae_fp16.safetensors" "$ROOT/models/vae/minimax_h3_audio_vae_fp32.safetensors"; do
  [[ -s "$f" ]] || { echo "文件缺失或为空：$f"; exit 1; }
  ls -lh "$f"
done
rm -rf -- "$ROOT/.cache" "$ROOT/models/.cache"
echo '完成。请确认切换实例后 /mnt/workspace 仍指向同一持久化存储。'
