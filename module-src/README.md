# CLIProxyAPI · Magisk / KernelSU 通用模块

把 [router-for-me/CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) 的 `__VERSION__` 服务
打包为 Magisk / KernelSU 通用模块，在**已 root 的 arm64（64 位）安卓设备**上开机自启，为 AI CLI
（Codex / Claude Code / Gemini CLI 等）提供本地 OpenAI / Claude / Gemini 兼容代理 API。

- **宿主兼容**：Magisk（≥20.4）、KernelSU / KernelSU-Next、APatch（模块格式一致）
- **局域网共享**：默认绑定 `0.0.0.0`，局域网内其它设备/手机可直接使用本机做代理
- **自动更新**：模块会自动检测上游项目新版本；可从 GitHub 自动构建仓库拉取新模块版并就地升级
- 版本：CLIProxyAPI `__VERSION__`（commit `1d5b7612`），为**静态编译 arm64 ELF**，不依赖 glibc / bionic

## 互动界面
```
服务地址   →  本机 http://0.0.0.0:8317 ，局域网 http://<本机IP>:8317/v1
开机自启   →  late_start 阶段自动拉起
闪电按钮   →  停/启切换（toggle）
更新       →  自动检测上游新版，可从 __REPO__ 拉新模块并就地升级
```

## 安装

1. 设备需已 **root 并安装 Magisk / KernelSU(-Next) / APatch**。
2. 把本 zip 拷贝到手机存储。
3. 应用 → **模块(Modules)** → **安装来自存储 / 本地安装** → 选择本 zip。
4. 重启后服务随系统自动启动。

> 若提示「架构不支持」，说明设备非 arm64（本项目官方未发布 32 位 / x86 安卓构建）。

## 使用

### 配置提供商
编辑 `/data/adb/modules/cliproxyapi/config.yaml` 填凭证后执行：
```sh
sh /data/adb/modules/cliproxyapi/action.sh restart
```

### 客户端指向
AI CLI / 客户端把 API base 指向：
```
本机:   http://127.0.0.1:8317/v1
局域网: http://<手机IP>:8317/v1    (0.0.0.0 可被局域网访问)
```
（Claude / OpenAI / Gemini 兼容端点以 curl `http://<手机IP>:8317/` 返回的 `endpoints` 为准。）

### 局域网安全
默认管理密钥为 `admin`，仅适合首次部署；请尽快在 `config.yaml` 中修改
`remote-management.secret-key` 后重启服务。局域网 API 本身也建议配置 `api-keys` 鉴权。

### Antigravity OAuth（订阅版 Gemini）
面板 → **OAuth 登录** → **开始 Antigravity 登录**。授权链接的回调地址固定为
`localhost:51121`，因此必须在**运行模块的那台手机本机浏览器**中打开授权链接；
在另一台电脑打开会回调到电脑自己的 localhost，无法完成。

### 插件商店
本模块默认 `plugins.enabled: true`，服务端插件商店 API 已启用：
`GET /v0/management/plugin-store`、`POST /v0/management/plugin-store/:id/install`。
插件是进程内动态库代码，仅安装可信来源的插件。当前管理面板版本可能没有暴露插件商店导航页；
此时可通过管理 API 或后续面板更新使用。

## 更新功能

模块会以**上游 `router-for-me/CLIProxyAPI` 的最新 release 版本**为基准判断是否有新版。
发现新版后，从自动构建仓库（`UPDATE_REPO`）的对应 release 下载 arm64 模块 zip 并**就地覆盖更新**，
**保留用户 config.yaml**（新配置模板另存 `config.yaml.new`）。

- **手动检查**：
  ```sh
  /data/adb/modules/cliproxyapi/action.sh update
  # 或
  sh /data/adb/modules/cliproxyapi/update.sh check   # 仅检查
  sh /data/adb/modules/cliproxyapi/update.sh now     # 检查并立即更新
  ```
- **自动更新**（默认关闭）：编辑 `update.conf`：
  ```ini
  CF_AUTO=1
  ```
  开机时自动检测并应用；也可随时：
  ```sh
  sh action.sh autoupdate on     # 开启
  sh action.sh autoupdate off    # 关闭
  ```

## Android DNS + TLS 证书自动修复

本模块的 Go 二进制是静态构建；Android 通常没有标准 Linux 的 `/etc/resolv.conf` 和
`/etc/ssl/certs/ca-certificates.crt`，会导致域名解析失败或 TLS 报
`x509: certificate signed by unknown authority`。

`service.sh` 在每次开机时会自动：
1. overlay 挂载 `/system/etc`，写入模块自带的有效 `resolv.conf`；
2. 把 Android 系统 CA 证书合并到 Go 默认读取的 `ca-certificates.crt`；
3. 设置 `SSL_CERT_FILE`，让服务明确使用该证书库。

该过程幂等，已修复则跳过；模块卸载时会解除本模块创建的 overlay。

## 卸载
登录凭证（模块 data 目录）不会随卸载删除；若需彻底清除：
`rm -rf /data/adb/modules/cliproxyapi/data`

## 构建
- 二进制自 GitHub 源码 + 依赖静态交叉编译（`CGO_ENABLED=0 GOARCH=arm64`），不随官方 glibc 版
  (安卓用 bionic 无 glibc，官方版无法直接运行)。
- `META-INF/…/update-binary` 取自 Magisk 官方 `scripts/module_installer.sh`。
- config.example.yaml 取自官方仓库。自动生成流程见「自动构建仓库」模板。