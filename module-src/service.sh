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

# DNS 兜底：若系统 resolv.conf 缺失/为空/不可用，则挂载模块自带的 resolver（单文件 bind）
if [ -f "$MODDIR/resolv.conf" ] && [ -s "$MODDIR/resolv.conf" ]; then
  # 系统解析配置若缺失或明显不可用(仅为回环 stub)才覆盖
  if [ ! -s /etc/resolv.conf ] || grep -qE '^nameserver[[:space:]]+(\[?::|127\.0\.0\.1)' /etc/resolv.conf 2>/dev/null; then
    mount --bind "$MODDIR/resolv.conf" /etc/resolv.conf 2>/dev/null && \
      echo "$(date '+%F %T') resolv.conf DNS 兜底已挂载" >> "$LOG"
  fi
fi

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