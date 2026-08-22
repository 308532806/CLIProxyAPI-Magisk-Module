#!/system/bin/sh
# CLIProxyAPI — 卸载时清理
# 注意：登录凭证保存在模块 data 目录（$MODDIR/data/.cli-proxy-api），此处不自动删除
# 如需彻底清除数据，卸载后手动执行: rm -rf /data/adb/modules/cliproxyapi/data

PIDS=$(pidof cli-proxy-api)
if [ -n "$PIDS" ]; then
  kill $PIDS 2>/dev/null
fi

# 解除 DNS/CA 固化的 overlay 挂载（仅当它使用本模块的 upperdir 时）
# 避免误影响其它模块可能创建的 /system/etc overlay。
MODDIR=${0%/*}
OVL_UP="$MODDIR/ovl/up"
if grep -qE "^[^[:space:]]+[[:space:]]+/system/etc[[:space:]]+overlay" /proc/mounts 2>/dev/null \
  && mount | grep -Fq "upperdir=$OVL_UP"; then
  umount /system/etc 2>/dev/null && echo "已解除 CLIProxyAPI 的 /system/etc overlay（DNS/CA 固化）"
fi