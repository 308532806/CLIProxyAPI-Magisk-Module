#!/system/bin/sh
# CLIProxyAPI Magisk/KernelSU/APatch 通用安装脚本
# 由模块安装器(update-binary)在解包后 source 执行
# Magisk 提供: $ARCH $MODPATH $API ... ；KernelSU/APatch 同样遵循 Magisk 模块规范

ui_print "- CLIProxyAPI 模块安装中 ..."

# 1) 宿主环境识别（仅提示，不阻断）
if [ -d /data/adb/magisk ]; then
  ui_print "- 宿主: Magisk v$MAGISK_VER"
elif [ -d /data/adb/ksu ] || [ -d /data/adb/ksu-next ]; then
  ui_print "- 宿主: KernelSU(-Next)"
  ui_print "- 提示: KernelSU 下若需开机自启，请确认已授予模块 root 权限"
elif [ -e /data/adb/apatch ] || [ -n "$APATCH" ]; then
  ui_print "- 宿主: APatch"
else
  ui_print "- 宿主: 未知(非标准模块环境)，若无法自启请检查宿主支持"
fi

# 2) 架构检查：本项目仅发布 arm64 构建
case "$ARCH" in
  arm64|aarch64)
    ui_print "- 设备架构: $ARCH  (支持 ✓)"
    ;;
  *)
    ui_print "!! 设备架构: $ARCH"
    ui_print "!! 本模块仅支持 arm64(64 位) 安卓设备"
    abort "! 安装中止：架构不受支持"
    ;;
esac

# 3) 确保二进制可执行权限
set_perm "$MODPATH/bin/cli-proxy-api" 0 0 0755

ui_print "- 安装完成:"
ui_print "   * 服务地址: 0.0.0.0:8317 (局域网可访问)"
ui_print "   * 局域网设备使用: http://<本机IP>:8317/v1"
ui_print "   * 开机自启: 重启后自动启动"
ui_print "   * 手动控制: 模块卡片 → 闪电按钮(停/启)"
ui_print "   * 更新检查: Magisk 应用内可检测更新；或 sh $MODPATH/update.sh check"