#!/system/bin/sh
# CLIProxyAPI — Magisk / KernelSU / APatch 通用动作脚本
# 点击模块卡片上的闪电按钮即执行(默认 toggle 停/启)，也可在终端手动：
#   sh /data/adb/modules/cliproxyapi/action.sh [status|start|stop|restart|update|autoupdate]

MODDIR=${0%/*}
# 兜底：手动 sh xxx.sh 运行时 $0 无路径
[ "$MODDIR" = "$0" ] && MODDIR="$(dirname "$0")"
BIN="$MODDIR/bin/cli-proxy-api"
CONFIG="$MODDIR/config.yaml"
LOG="$MODDIR/logs/service.log"
# 与 service.sh 一致：模块自带数据目录作为 HOME（Android 上通常无 $HOME）
HOMEDIR="$MODDIR/data"
mkdir -p "$MODDIR/logs" "$HOMEDIR" 2>/dev/null
export HOME="$HOMEDIR"

is_run() { pidof cli-proxy-api >/dev/null 2>&1; }

do_start() {
  if is_run; then
    echo "CLIProxyAPI 已在运行"
  else
    cd "$MODDIR"
    setsid "$BIN" -config "$CONFIG" -local-model >/dev/null 2>&1 &
    sleep 2
    is_run && echo "CLIProxyAPI 已启动" || echo "启动失败，请查看 $LOG"
  fi
}

do_stop() {
  if is_run; then
    kill $(pidof cli-proxy-api) 2>/dev/null
    sleep 1
    echo "CLIProxyAPI 已停止"
  else
    echo "CLIProxyAPI 未在运行"
  fi
}

do_status() {
  if is_run; then
    PIDS=$(pidof cli-proxy-api)
    echo "CLIProxyAPI 运行中 (pid: $PIDS)"
    # 从配置读取监听地址，自动识别局域网 IP
    HOST=$(sed -n 's/^host:[[:space:]]*"*\([^"]*\)"*.*/\1/p' "$CONFIG" 2>/dev/null | head -1)
    PORT=$(sed -n 's/^port:[[:space:]]*\([0-9]*\).*/\1/p' "$CONFIG" 2>/dev/null | head -1)
    [ -z "$PORT" ] && PORT=8317
    if command -v ip >/dev/null 2>&1; then
      LANIP=$(ip route get 1 2>/dev/null | sed -n 's/.*src \([0-9.]*\).*/\1/p' | head -1)
      [ -z "$LANIP" ] && LANIP=$(ip addr show 2>/dev/null | sed -n 's/.*inet \(192\.168\.[0-9.]*\).*/\1/p' | head -1)
    fi
    if [ "$HOST" = "0.0.0.0" ] || [ -z "$HOST" ]; then
      echo "监听: 0.0.0.0（局域网共享，所有接口）"
      [ -n "$LANIP" ] && echo "局域网访问地址: http://$LANIP:$PORT/v1"
    else
      echo "监听: $HOST:$PORT (仅本机)"
    fi
    if command -v ss >/dev/null 2>&1; then ss -ltn 2>/dev/null | grep -q ":$PORT" && echo "端口 $PORT: 已监听"; fi
  else
    echo "CLIProxyAPI 未在运行"
  fi
}

do_update() {
  echo "== 版本检测 =="
  sh "$MODDIR/update.sh" check
  echo
  echo "== 手动更新（如果有新版）=="
  sh "$MODDIR/update.sh" now
}

do_autoupdate() {
  case "$1" in
    on)
      sed -i 's/^CF_AUTO=.*/CF_AUTO=1/' "$MODDIR/update.conf" 2>/dev/null
      echo "自动更新: 已开启（开机时自动检测并安装新模块版）"
      ;;
    off)
      sed -i 's/^CF_AUTO=.*/CF_AUTO=0/' "$MODDIR/update.conf" 2>/dev/null
      echo "自动更新: 已关闭（仅手动 update）"
      ;;
    *)
      grep '^CF_AUTO=' "$MODDIR/update.conf" 2>/dev/null | tail -1
      echo "用法: action.sh autoupdate on|off"
      ;;
  esac
}

case "${1:-toggle}" in
  status)     do_status ;;
  start)      do_start ;;
  stop)       do_stop ;;
  restart)    do_stop; do_start ;;
  update)     do_update ;;
  autoupdate) do_autoupdate "$2" ;;
  toggle)
    if is_run; then do_stop; else do_start; fi
    ;;
  *) echo "用法: $0 [status|start|stop|restart|update|autoupdate on|off]"; exit 1 ;;
esac