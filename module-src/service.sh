#!/system/bin/sh
# CLIProxyAPI — 开机后台自动启动 (late_start 阶段执行)
# 兼容 Magisk / KernelSU(-Next) / APatch（三者均为 /data/adb/modules 模块格式）
# 仅支持已 root 的 arm64 设备

MODDIR=${0%/*}
# 兜底：手动 sh xxx.sh 运行时 $0 无路径
[ "$MODDIR" = "$0" ] && MODDIR="$(dirname "$0")"
BIN="$MODDIR/bin/cli-proxy-api"
CONFIG="$MODDIR/config.yaml"
LOGDIR="$MODDIR/logs"
LOG="$LOGDIR/service.log"
# 模块自带的数据目录（可写、持久、跨更新保留）用作 HOME，
# 解决 Android 上 Magisk/KernelSU service 环境 $HOME 未定义导致的
# "~/.cli-proxy-api 被展开成根目录" 只读文件系统崩溃。
HOMEDIR="$MODDIR/data"
mkdir -p "$LOGDIR" "$HOMEDIR" 2>/dev/null
export HOME="$HOMEDIR"

# 等待系统完全启动（网络已就绪）
until [ "$(getprop sys.boot_completed)" = "1" ]; do
  sleep 2
done

# ===== Android 平台 DNS+CA 固化（Go 静态二进制必需，每台设备都要）=====
# Android 上 /etc -> /system/etc 且 /system 只读：
#   1) /etc/resolv.conf 不存在 → Go 静态二进制回退 [::1]:53 stub → DNS 全挂
#   2) /etc/ssl/certs/ca-certificates.crt 不存在 → Go x509 校验失败 → TLS 全挂
# 方案：overlay 挂载 /system/etc（upper 持久存于模块内），写入 resolv.conf + 合并 CA。
OVLDIR="$MODDIR/ovl"
OVL_UP="$OVLDIR/up"
OVL_WORK="$OVLDIR/work"

# 检查 resolv.conf 是否有效（缺失 / 空 / 仅回环 stub 视为无效）
chk_dns() {
  [ -s /system/etc/resolv.conf ] || return 1
  ! grep -qE '^nameserver[[:space:]]+(\[?::|127\.0\.0\.1)' /system/etc/resolv.conf 2>/dev/null
}
# Go 的 x509 包可显式读取该文件；同时这也是 Linux 常规默认路径。
export SSL_CERT_FILE="/system/etc/ssl/certs/ca-certificates.crt"
# 检查 CA 证书库是否已合并
chk_ca() {
  [ -s "$SSL_CERT_FILE" ] 2>/dev/null
}
# Android 版本不同，系统 CA 目录可能在 system 或 Conscrypt APEX。
find_ca_dir() {
  for d in /system/etc/security/cacerts /apex/com.android.conscrypt/cacerts /apex/com.android.runtime/cacerts; do
    if [ -d "$d" ] && ls "$d"/* >/dev/null 2>&1; then
      echo "$d"
      return 0
    fi
  done
  return 1
}
# /proc/mounts 格式固定为：source mountpoint filesystem ...
# 比解析 mount 命令输出更可靠（Android 常见输出为 "overlay on /system/etc"）。
is_system_etc_overlay() {
  grep -qE '^[^[:space:]]+[[:space:]]+/system/etc[[:space:]]+overlay[[:space:]]' /proc/mounts 2>/dev/null
}

if ! chk_dns || ! chk_ca; then
  # 若尚未 overlay，则挂载 /system/etc（upper 持久，重启后可复用）
  if ! is_system_etc_overlay; then
    # overlay workdir 必须为空；异常关机后先安全重建它，保留上层数据。
    rm -rf "$OVL_WORK" 2>/dev/null
    mkdir -p "$OVL_UP" "$OVL_WORK" 2>/dev/null
    if mount -t overlay -o "lowerdir=/system/etc,upperdir=$OVL_UP,workdir=$OVL_WORK" overlay /system/etc 2>/dev/null; then
      echo "$(date '+%F %T') overlay /system/etc 已挂载（DNS/CA 固化）" >> "$LOG"
    else
      echo "$(date '+%F %T') !! overlay 挂载失败，尝试 bind 兜底" >> "$LOG"
      # 兜底：直接 bind 模块 resolv.conf（若目标可写）
      [ -f "$MODDIR/resolv.conf" ] && mount --bind "$MODDIR/resolv.conf" /system/etc/resolv.conf 2>/dev/null
    fi
  fi

  # DNS：写入有效 resolver
  if ! chk_dns && [ -f "$MODDIR/resolv.conf" ] && [ -s "$MODDIR/resolv.conf" ]; then
    if cp -f "$MODDIR/resolv.conf" /system/etc/resolv.conf 2>/dev/null; then
      echo "$(date '+%F %T') DNS 固化：写入 resolv.conf ($(tr '\n' ' ' < "$MODDIR/resolv.conf"))" >> "$LOG"
    else
      echo "$(date '+%F %T') !! DNS 写入失败" >> "$LOG"
    fi
  fi

  # CA：把 Android 系统证书合并到 Go 默认查找路径（原子替换，避免半写入文件）
  if ! chk_ca; then
    CA_DIR=$(find_ca_dir)
    mkdir -p /system/etc/ssl/certs 2>/dev/null
    if [ -n "$CA_DIR" ] \
      && cat "$CA_DIR"/* > "${SSL_CERT_FILE}.tmp" 2>/dev/null \
      && [ -s "${SSL_CERT_FILE}.tmp" ] \
      && mv -f "${SSL_CERT_FILE}.tmp" "$SSL_CERT_FILE" \
      && chk_ca; then
      echo "$(date '+%F %T') CA 固化：合并 $(ls "$CA_DIR" 2>/dev/null | wc -l) 个根证书 → ca-certificates.crt" >> "$LOG"
    else
      rm -f "${SSL_CERT_FILE}.tmp" 2>/dev/null
      echo "$(date '+%F %T') !! CA 合并失败（未找到 Android 系统 CA 目录或 overlay 写入失败）" >> "$LOG"
    fi
  fi
fi
# ===== DNS+CA 固化结束 =====

# 若开启自动更新，先异步检查并应用新模块版（失败不阻塞启动）
CF_AUTO=0
[ -f "$MODDIR/update.conf" ] && . "$MODDIR/update.conf"
if [ "$CF_AUTO" = "1" ]; then
  sh "$MODDIR/update.sh" auto >> "$LOG" 2>&1 &
fi

if [ ! -x "$BIN" ]; then
  echo "$(date '+%F %T') ERR: 找不到可执行二进制 $BIN" >> "$LOG"
  exit 1
fi

# 已运行则直接跳过
if pidof cli-proxy-api >/dev/null 2>&1; then
  echo "$(date '+%F %T') 已在运行，跳过" >> "$LOG"
  exit 0
fi

cd "$MODDIR"
# setsid 开新会话 + 重定向，防止随脚本退出被回收
setsid "$BIN" -config "$CONFIG" -local-model >/dev/null 2>&1 &
sleep 2

if pidof cli-proxy-api >/dev/null 2>&1; then
  echo "$(date '+%F %T') 已启动 (pid: $(pidof cli-proxy-api))" >> "$LOG"
else
  echo "$(date '+%F %T') 启动失败，请检查 $LOGDIR 下日志" >> "$LOG"
fi