#!/usr/bin/env bash
# CLIProxyAPI 模块自动重建脚本（跑在 GitHub Actions 上）
# 流程:
#   1) 查上游 router-for-me/CLIProxyAPI 最新 release tag
#   2) 与 repo 内 latest_version 比对；相同则跳过
#   3) 新版 → 克隆上游源码 → 交叉编译 arm64 静态二进制
#   4) 用 module-src/ 模板组装 Magisk/KernelSU 模块 zip
#   5) 更新 latest_version + update.json 并推送回本 repo（尽力）
#   6) 用 GitHub API 创建/复用 release 并上传模块 zip
set -e

UPSTREAM="router-for-me/CLIProxyAPI"
REPO_ROOT="$(pwd)"
OWNER=$(echo "$GITHUB_REPOSITORY" | cut -d/ -f1)
REPO_NAME=$(echo "$GITHUB_REPOSITORY" | cut -d/ -f2)
THIS_REPO="${OWNER}/${REPO_NAME}"
API="https://api.github.com"
GH_TOKEN="${GITHUB_TOKEN}"
[ -z "$GH_TOKEN" ] && { echo "!! 无 GITHUB_TOKEN"; exit 1; }

# 用 python3 解析 JSON（runner 必有 python3，比 jq 稳；容错：空输入/异常输出空且 exit 0）
jget(){ python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(d$1)
except Exception:
    pass
" 2>/dev/null; }

CUR=""; [ -f latest_version ] && CUR=$(cat latest_version 2>/dev/null)
echo ">> 本仓库: $THIS_REPO   当前已构建版本: ${CUR:-<无>}"

# 1) 上游最新 tag
RAW=$(curl -fsS -m 30 "$API/repos/$UPSTREAM/releases/latest" 2>/dev/null)
TAG=$( [ -n "$RAW" ] && python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("tag_name",""))' "$RAW" 2>/dev/null | sed 's/^v//' )
[ "$TAG" = "" ] && { echo "!! 无法获取上游 release，跳过"; exit 0; }
echo ">> 上游最新: v$TAG"

# 2) 无更新 → 退出
if [ -n "$CUR" ] && [ "$CUR" = "$TAG" ]; then echo ">> 已是最新 v$TAG，无需重建"; exit 0; fi
echo ">> 检测到新版: ${CUR:-<none>} -> $TAG，开始构建 ..."

# 3) 准备 Go 工具链（先 apt，失败则下载官方 go1.26 增量包）
export GOTOOLCHAIN=auto GOOS=linux GOARCH=arm64 CGO_ENABLED=0
command -v go >/dev/null 2>&1 || { apt-get update -y >/dev/null 2>&1; apt-get install -y golang-go >/dev/null 2>&1; }
if ! command -v go >/dev/null 2>&1; then
  echo "   - 下载官方 Go 工具链 (go1.26.0, linux-x86_64) ..."
  curl -fsSL -o /tmp/go.tgz "https://go.dev/dl/go1.26.0.linux-x86_64.tar.gz" || exit 1
  tar -C /tmp -xzf /tmp/go.tgz 2>/dev/null || exit 1
  export PATH="/tmp/go/bin:$PATH"
  export GOROOT=/tmp/go
fi
GV=$(go version 2>&1); echo "   >> go: $GV"
echo "$GV" | grep -q 'go1\.' || { echo "!! go 工具链不可用"; exit 1; }

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
  -o /tmp/cpa_module/bin/cli-proxy-api ./cmd/server/ 2>&1 | tail -25
if [ ! -s /tmp/cpa_module/bin/cli-proxy-api ]; then echo "!! 编译失败"; exit 1; fi
echo "   二进制: $(du -h /tmp/cpa_module/bin/cli-proxy-api | cut -f1)"
cd "$WORK"

# 5) 组装模块
echo ">> 组装模块 (从 module-src 模板)"
cp -a "$REPO_ROOT/module-src/." /tmp/cpa_module/
VER=$(printf '%03d%03d%03d' $(echo "$TAG" | tr '.' ' '))
for f in module.prop README.md update.conf; do
  p="/tmp/cpa_module/$f"; [ -f "$p" ] || continue
  sed -i "s/__VERSION__/$TAG/g; s/__VERSIONCODE__/$VER/g; s#__MODULE_REPO__#$THIS_REPO#g; s#__REPO__#$THIS_REPO#g" "$p"
done
cat > /tmp/cpa_module/update.json <<EOF
{
  "version": "v$TAG",
  "versionCode": $VER,
  "zipUrl": "https://github.com/$THIS_REPO/releases/download/v$TAG/CLIProxyAPI-magisk-v$TAG-arm64.zip",
  "changelog": "https://github.com/$THIS_REPO/releases/tag/v$TAG"
}
EOF

# 6) 打包 zip
ZIPNS="CLIProxyAPI-magisk-v$TAG-arm64.zip"
python3 - "$ZIPNS" <<'PYZ'
import zipfile, os, sys
name=sys.argv[1]; root="/tmp/cpa_module"; out="/tmp/"+name
if os.path.exists(out): os.remove(out)
z=zipfile.ZipFile(out,"w",zipfile.ZIP_DEFLATED,9)
for r,_,fs in os.walk(root):
    for f in fs:
        p=os.path.join(r,f); z.write(p,os.path.relpath(p,root))
z.close()
PYZ
echo ">> zip 就绪: $ZIPNS ($(du -h "/tmp/$ZIPNS" | cut -f1))"

# 7) 提交最新版本标记并尽力推送
echo "$TAG" > "$REPO_ROOT/latest_version"
cp /tmp/cpa_module/update.json "$REPO_ROOT/update.json"
cd "$REPO_ROOT"
git config user.email "actions@github.com" 2>/dev/null || true
git config user.name "github-actions" 2>/dev/null || true
git add latest_version update.json 2>/dev/null
git commit -m "chore: built module for v$TAG" 2>/dev/null || true
BR=$(git branch --show-current 2>/dev/null || echo main)
git push --force "https://x-access-token:${GH_TOKEN}@github.com/${THIS_REPO}.git" "HEAD:$BR" >/dev/null 2>&1 || true

# 8) 创建/复用 release + 上传 zip（资产必须 POST 到 uploads.github.com）
echo ">> 准备 release v$TAG"
RID=""; RAW=""
# 先查是否已有该 tag 的 release（404=无，正常；不用 -f 避免空输出崩 set -e）
RAW=$(curl -sS -m 30 -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
  "$API/repos/$THIS_REPO/releases/tags/v$TAG" 2>/dev/null || true)
if [ -n "$RAW" ]; then RID=$(echo "$RAW" | jget "['id']"); fi
if [ -z "$RID" ]; then
  RAW=$(curl -sS -X POST -m 30 \
    -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" \
    -d "{\"tag_name\":\"v$TAG\",\"name\":\"v$TAG\",\"body\":\"CLIProxyAPI Magisk/KernelSU 模块 (v$TAG, GitHub Actions 自动构建)\",\"draft\":false,\"prerelease\":false}" \
    "$API/repos/$THIS_REPO/releases" 2>/dev/null || true)
  RID=$(echo "$RAW" | jget "['id']")
fi
if [ -z "$RID" ]; then
  echo "!! 创建/查找 release 失败（响应: $(echo "$RAW" | head -c 300)）"
  exit 1
fi
echo "   release id=$RID"
HAS=$(curl -sS -m 20 "$API/repos/$THIS_REPO/releases/$RID" -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(1 if any(a.get('name')=='$ZIPNS' for a in d.get('assets',[])) else 0)" 2>/dev/null || echo 0)
if [ "$HAS" != "1" ]; then
  echo "   上传资产到 uploads.github.com ..."
  curl -sS -X POST -m 600 \
    -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" -H "Content-Type: application/octet-stream" \
    --data-binary "@/tmp/$ZIPNS" \
    "https://uploads.github.com/repos/$THIS_REPO/releases/$RID/assets?name=$ZIPNS" >/dev/null || { echo "!! 资产上传失败"; exit 1; }
  echo "   资产上传成功"
fi
echo ">> 完成 v$TAG"