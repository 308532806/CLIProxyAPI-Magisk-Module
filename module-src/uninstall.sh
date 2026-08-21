#!/system/bin/sh
# CLIProxyAPI — 卸载时清理
# 注意：登录凭证保存在 ~/.cli-proxy-api （即 /root/.cli-proxy-api），此处不自动删除
# 如需彻底清除数据，卸载后手动执行: rm -rf /root/.cli-proxy-api

PIDS=$(pidof cli-proxy-api)
if [ -n "$PIDS" ]; then
  kill $PIDS 2>/dev/null
fi