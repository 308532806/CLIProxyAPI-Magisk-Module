#!/usr/bin/env bash
# CLIProxyAPI 模块自动重建脚本（跑在 GitHub Actions 上）
# 流程:
#   1) 查上游 router-for-me/CLIProxyAPI 最新 release tag
#   2) 与 repo 内 latest_version 比对；相同则跳过
#   3) 新版 → 克隆上游源码 → 交叉编译 arm64 静态二进制
#   4) 用 module-src/ 模板组装 Magisk/KernelSU 模块 zip
#   5) 更新 latest_version + update.json 并推送回本 repo
#   6) 用 GitHub API 创建同名 release 并上传模块 zip
set -e

UPSTREAM="router-for-me/CLIProxyAPI"
REPO_ROOT="$(pwd)"                     # Actions checkout 根
OWNER=$(echo "$GITHUB_REPOSITORY" | cut -d/ -f1)
REPO_NAME=$(echo "$GITHUB_REPOSITORY" | cut -d/ -f2)
THIS_REPO="${OWNER}/${REPO_NAME}"
API="https://api.github.com"
GH_TOKEN="${GITHUB_TOKEN}"
[ -z "$GH_TOKEN" ] && { echo "!! 无 GITHUB_TOKEN"; exit 1; }

CUR=""; [ -f latest_version ] && CUR=$(cat latest_version)
echo ">> 本仓库: $THIS_REPO   当前已构建: ${CUR:-<无>}"

# 1) 上游最新 tag
TAG=$(curl -fsS -m 30 "$API/repos/$UPSTREAM/releases/latest" | jq -r '.tag_name' 2>/dev/null | sed 's/^v//')
if [ -z "$TAG" ] || [ "$TAG" = "null" ]; then
  echo "!! 无法获取上游 release，跳过"; exit 0
fi
echo ">> 上游最新: v$TAG"

# 2) 无更新 → 跳过
if [ -n "$CUR" ] && [ "$CUR" = "$TAG" ]; then echo ">> 已是最新 v$TAG"; exit 0; fi
echo ">> 检测到新版 $CUR -> $TAG，开始构建 ..."

# 3) 工具链
echo ">> 准备 Go 工具链"
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y golang-go jq >/dev/null 2>&1 || true
export GOTOOLCHAIN=auto GOOS=linux GOARCH=arm64 CGO_ENABLED=0
go version >/dev/null 2>&1 || true

# 4) 克隆上游 + 交叉编译
WORK=/tmp/cpa_work
rm -rf "$WORK" /tmp/cpa_module; mkdir -p "$WORK"; mkdir -p /tmp/cpa_module/bin
cd "$WORK"
git clone --depth 1 --branch "v$TAG" "https://github.com/$UPSTREAM.git" src 2>/dev/null \
  || git clone --depth 1 "https://github.com/$UPSTREAM.git" src
cd src
echo ">> 交叉编译 arm64 静态二进制 ..."
go build -buildvcs=false -trimpath \
  -ldflags "-s -w -X 'main.Version=${TAG}-android' -X 'main.Commit=auto-build' -X 'main.BuildDate=$(date +%F)'" \
  -o /tmp/cpa_module/bin/cli-proxy-api ./cmd/server/ 2>&1 | tail -20
[ -s /tmp/cpa_module/bin/cli-proxy-api ] || { echo "!! 编译失败"; exit 1; }
cd "$WORK"

# 5) 组装模块
echo ">> 组装模块"
cp -a "$REPO_ROOT/module-src/." /tmp/cpa_module/
VER=$(printf '%03d%03d%03d' $(echo "$TAG" | tr '.' ' '))
for f in module.prop README.md update.conf; do
  p="/tmp/cpa_module/$f"; [ -f "$p" ] || continue
  sed -i "s/__VERSION__/$TAG/g; s/__VERSIONCODE__/$VER/g; s#__REPO__#$THIS_REPO#g" "$p"
done
# 加 update.json（供 Magisk 应用内检测）
cat > /tmp/cpa_module/update.json <<EOF
{
  "version": "v$TAG",
  "versionCode": ${VER},
  "zipUrl": "https://github.com/$THIS_REPO/releases/download/v$TAG/CLIProxyAPI-magisk-v$TAG-arm64.zip",
  "changelog": "https://github.com/$THIS_REPO/releases/tag/v$TAG"
}
EOF

# 6) 打包 zip（模块根结构）
ZIPNAME="CLIProxyAPI-magisk-v${TAG}-arm64.zip"
python3 - "$ZIPNAME" <<'PYZ'
import zipfile, os, sys
name=sys.argv[1]; root="/tmp/cpa_module"; out="/tmp/"+name
if os.path.exists(out): os.remove(out)
z=zipfile.ZipFile(out,"w",zipfile.ZIP_DEFLATED,9)
for r,_,fs in os.walk(root):
    for f in fs:
        p=os.path.join(r,f); z.write(p, os.path.relpath(p,root))
z.close()
PYZ
echo ">> zip 就绪: $ZIPNAME ($(du -h "/tmp/$ZIPNAME" | cut -f1))"

# 7) 本地更新标记文件，并在 Actions 内推送
echo "$TAG" > "$REPO_ROOT/latest_version"
cp /tmp/cpa_module/update.json "$REPO_ROOT/update.json"
cd "$REPO_ROOT"
git config user.email "actions@github.com" 2>/dev/null || true
git config user.name "github-actions" 2>/dev/null || true
git add latest_version update.json 2>/dev/null
git commit -m "chore: built module for v$TAG" 2>/dev/null || true
git push --force "https://x-access-token:${GH_TOKEN}@github.com/${THIS_REPO}.git" HEAD:$(git branch --show-current 2>/dev/null || echo main) >/dev/null 2>&1 || true

# 8) 创建/复用 release + 上传 zip 资产（重复 tag 安全）
echo ">> 准备 release v$TAG"
# 若该 tag 已有 release 则直接取 id，否则新建
RID=$(curl -fsS -m 30 "$API/repos/$THIS_REPO/releases/tags/v$TAG" \
  -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" | jq -r '.id' 2>/dev/null)
if [ -z "$RID" ] || [ "$RID" = "null" ]; then
  RID=$(curl -fsS -X POST \
    -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" \
    -d "{\"tag_name\":\"v$TAG\",\"name\":\"v$TAG\",\"body\":\"CLIProxyAPI Magisk/KernelSU 模块 (v$TAG, GitHub Actions 自动构建)\",\"draft\":false,\"prerelease\":false}" \
    "$API/repos/$THIS_REPO/releases" | jq -r '.id')
fi
echo "   release id=$RID"
# 若资产尚未上传才上传
REUSE=$(curl -fsS -m 30 "$API/repos/$THIS_REPO/releases/$RID" \
  -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" | jq -e --arg n "$ZIPNAME" '.assets[]|select(.name==$n)' 2>/dev/null)
[ -z "$REUSE" ] && curl -fsS -X POST \
  -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" -H "Content-Type: application/octet-stream" \
  --data-binary "@/tmp/$ZIPNAME" \
  "$API/repos/$THIS_REPO/releases/$RID/assets?name=$ZIPNAME" >/dev/null && echo "   资产上传成功"
echo ">> 完成 v$TAG"