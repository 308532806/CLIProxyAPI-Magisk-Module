#!/system/bin/sh
# CLIProxyAPI 模块 — 版本检测与自动更新
# 用法:
#   sh update.sh check         仅检测，有新版时打印信息（不下载）
#   sh update.sh now           检测并立即下载/安装最新模块版（保留用户配置）
#   sh update.sh auto          静默自动更新（供 service.sh 开机调用，受 update.conf 控制）
#
# 版本判断基准: 上游 GitHub 项目 (router-for-me/CLIProxyAPI) 的最新 release tag。
# 检测到上游发布新版本后，模块从自动构建仓库 (UPDATE_REPO) 的对应 release
# 下载 arm64 模块 zip 并就地覆盖更新（保留用户 config.yaml）。

MODDIR=${0%/*}
[ "$MODDIR" = "$0" ] && MODDIR="$(dirname "$0")"

LOGD="$MODDIR/logs"; mkdir -p "$LOGD" 2>/dev/null
LOG="$LOGD/update.log"
TMP=/data/local/tmp/cpa_update
mkdir -p "$TMP" 2>/dev/null

UPDATE_REPO="308532806/CLIProxyAPI-Magisk-Module"   # 自动构建模块的仓库
SOURCE_REPO="router-for-me/CLIProxyAPI"             # 上游源项目
AUTO_UPDATE="0"                                     # 默认不自动更新

[ -f "$MODDIR/update.conf" ] && . "$MODDIR/update.conf"

# CF_API 可覆盖 API 端点（重写为本地 mock 服务器可用于测试）
API="${CF_API:-https://api.github.com}"
UA="CLIProxyAPI-Module/7.2.138 (Android)"

ts() { date '+%F %T'; }

# 读取 module.prop 中当前版本号，归一为 "maj.min.pat"
get_cur() {
  local v t
  t=$(grep -m1 '^version=' "$MODDIR/module.prop" 2>/dev/null | sed 's/^version=//')
  t=$(echo "$t" | tr -d ' \r')
  t=$(echo "$t" | sed 's/^[vV]//')
  v=$(echo "$t" | sed -E 's/^([0-9]+)\.([0-9]+)\.([0-9]+).*/\1.\2.\3/')
  if [ "$v" = "$t" ] && ! echo "$v" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then v="0.0.0"; fi
  [ -z "$(echo "$v" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$')" ] && v="0.0.0"
  echo "$v"
}

# 获取上游最新 release tag (轴 x.y.z)，失败返回空
fetch_upstream_tag() {
  local raw tag
  raw=$(curl -fsS -A "$UA" -m 30 "$API/repos/$SOURCE_REPO/releases/latest" 2>/dev/null)
  [ -z "$raw" ] && return
  tag=$(echo "$raw" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  tag=$(echo "$tag" | sed 's/^[vV]//' | tr -d ' ')
  if echo "$tag" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then echo "$tag"; fi
}

# 从自动构建仓库取对应版本 zip 的下载地址
get_module_zip_url() {
  local tag="$1" raw url
  raw=$(curl -fsS -A "$UA" -m 30 "$API/repos/$UPDATE_REPO/releases/tags/v$tag" 2>/dev/null)
  [ -z "$raw" ] && return 1
  # 取第一个含 arm64 且 .zip 的 browser_download_url
  url=$(echo "$raw" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*arm64[^"]*\.zip\)".*/\1/p' | head -1)
  echo "$url"
}

# 版本比较 a，b：输出 1 (a>b) / -1 (a<b) / 0 (相等)
ver_cmp() {
  local a="$1" b="$2" av bv i
  for i in 1 2 3; do
    av=$(echo "$a" | cut -d. -f"$i")
    bv=$(echo "$b" | cut -d. -f"$i")
    if [ "$av" -gt "$bv" ] 2>/dev/null; then echo 1; return 0; fi
    if [ "$av" -lt "$bv" ] 2>/dev/null; then echo -1; return 0; fi
  done
  echo 0
}

apply_update() {
  local tag="$1" zipurl="$2" stg zipname item cur
  zipname=$(basename "$zipurl")
  echo "$(ts) 下载新模块版 v$tag ..." >> "$LOG"
  curl -fsSL -A "$UA" -m 300 -o "$TMP/$zipname" "$zipurl" 2>/dev/null
  if [ ! -s "$TMP/$zipname" ]; then echo "$(ts) !! 下载失败" >> "$LOG"; return 1; fi
  rm -rf "$TMP/stage" 2>/dev/null; mkdir -p "$TMP/stage"
  if ! unzip -qo "$TMP/$zipname" -d "$TMP/stage" 2>/dev/null; then
    echo "$(ts) !! 解包失败" >> "$LOG"; return 1
  fi
  if ! { [ -x "$TMP/stage/bin/cli-proxy-api" ] && [ -f "$TMP/stage/module.prop" ]; } then
    echo "$(ts) !! 解包校验失败（缺 bin/cli-proxy-api 或 module.prop）" >> "$LOG"; return 1
  fi
  # 备份用户配置
  [ -f "$MODDIR/config.yaml" ] && cp -f "$MODDIR/config.yaml" "$TMP/config.yaml.bak" 2>/dev/null
  # 覆盖安装（保留 config.yaml / logs / update.conf）
  for item in module.prop customize.sh service.sh uninstall.sh action.sh update.sh resolv.conf README.md LICENSE bin META-INF; do
    if [ -e "$TMP/stage/$item" ]; then
      rm -rf "$MODDIR/$item"
      cp -a "$TMP/stage/$item" "$MODDIR/$item" 2>/dev/null
    fi
  done
  [ -e "$TMP/stage/config.yaml" ] && cp -f "$TMP/stage/config.yaml" "$MODDIR/config.yaml.new" 2>/dev/null
  echo "$(ts) 更新完成 → $tag（新配置模板存为 config.yaml.new；你的 config.yaml 已保留）" >> "$LOG"
  sh "$MODDIR/action.sh" restart 2>/dev/null
  echo "$(ts) 服务已重启" >> "$LOG"
  return 0
}

mode="${1:-check}"

cur=$(get_cur)
tag=$(fetch_upstream_tag)
# 无上游则直接失败退出（不干扰启动流程）
if [ -z "$tag" ]; then
  [ "$mode" != "auto" ] && echo "无法联系上游 GitHub（离线或受限），跳过更新检测"
  exit 1
fi

up=$(ver_cmp "$tag" "$cur")
if [ "$up" != "1" ]; then
  [ "$mode" != "auto" ] && echo "当前模块版本 $cur，上游最新 $tag —— 已经是最新。"
  exit 0
fi

echo "上游有新版本: 当前 $cur → 最新 $tag"

if [ "$mode" = "check" ]; then
  url=$(get_module_zip_url "$tag")
  echo "  * 模块版将由自动构建仓库发布: $UPDATE_REPO"
  [ -n "$url" ] && echo "  * 下载地址已就绪: $url" || echo "  * 下载压缩包尚未发布（等待 GitHub Actions 构建），请稍后再试"
  echo "  · 手动更新任意时候执行:  sh $MODDIR/update.sh now"
  exit 0
fi

# mode now / auto —— 直接下载并原地更新
url=$(get_module_zip_url "$tag")
if [ -z "$url" ]; then
  if [ "$mode" = "now" ]; then
    echo "自动构建仓库还没有发布 v$tag 对应的模块压缩包，稍后重试（或先看 GitHub Actions 是否完成）。"
  else
    echo "$(ts) 检测到 v$tag 但发布未就绪，跳过本次自动更新" >> "$LOG"
  fi
  exit 1
fi

apply_update "$tag" "$url"
exit 0