#!/system/bin/sh
# CLIProxyAPI — 卸载时清理
# 注意：登录凭证保存在模块 data 目录（$MODDIR/data/.cli-proxy-api），此处不自动删除
# 如需彻底清除数据，卸载后手动执行: rm -rf /data/adb/modules/cliproxyapi/data

PIDS=$(pidof cli-proxy-api)
if [ -n "$PIDS" ]; then
  kill $PIDS 2>/dev/null
fi

# 解除 DNS/CA 固化的 overlay 挂载（若存在）
UMOUNTED=0
while mount | grep -q "overlay /system/etc"; do
  umount /system/etc 2>/dev/null && UMOUNTED=1 || break
done
[ "$UMOUNTED" = "1" ] && echo "已解除 /system/etc overlay（DNS/CA 固化）"