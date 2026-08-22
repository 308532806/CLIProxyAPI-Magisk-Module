# CLIProxyAPI-Magisk-Module

把 [router-for-me/CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) 打包为 **Magisk / KernelSU(-Next) / APatch 通用模块**（仅 arm64），并**自动跟随上游发布新版本**的构建仓库。

上游发布新版本后，本仓库的 GitHub Actions 会自动交叉编译 arm64 静态二进制、组装模块、
发布 zip release，并刷新 `update.json`（供手机端 Magisk 应用内检测更新）。

---

## ✨ 模块特性（当前 v7.2.139）

- **多宿主兼容**：Magisk（≥20.4）、KernelSU / KernelSU-Next、APatch（同一 zip）
- **局域网共享**：默认监听 `0.0.0.0:8317`，局域网其它设备可用 `http://<手机IP>:8317/v1`
- **管理面板（内置）**：`http://<手机IP>:8317/management.html`
  - 默认管理密钥：`admin`（修改文件 `config.yaml` 的 `remote-management.secret-key`）
  - 默认允许远程管理（`allow-remote: true`）
- **Android 平台 DNS + CA 自动固化**（`service.sh` 开机自动执行）：
  - 自动 overlay 挂载 `/system/etc`，写入可用 `resolv.conf`
  - 自动合并系统 CA 证书到 Go 静态二进制默认查找路径 `/etc/ssl/certs/ca-certificates.crt`
  - 解决「纯 Go 静态二进制在 Android 上 DNS 解析失败 / TLS 证书校验失败」问题
  - 幂等：已生效则跳过；卸载时自动解除挂载
- **插件商店**：`plugins.enabled: true` 默认开启（官方原版默认关闭）
  - 服务端 API：`GET /v0/management/plugin-store`、`POST /v0/management/plugin-store/:id/install`
  - 经真实设备验证安装 `jshandler` 插件成功
  - 当前管理面板版本可能未暴露插件商店导航页；这是 UI 限制，不影响服务端商店 API
- **自带更新能力**：
  - Magisk 应用内「检查更新」（module.prop 的 `updateJson` 指向本仓库）
  - `update.sh`（检测上游版本并就地升级，保留用户 config.yaml）
  - 自动/手动开关注 `update.conf`（`CF_AUTO=1` 开机自动检查更新）

## 产物
- GitHub **Releases**：`CLIProxyAPI-magisk-vX.Y.Z-arm64.zip`
- 手机端直接安装该 zip；或使用模块内 `update.sh` 就地升级
- 根目录 `update.json` 供 Magisk 应用内更新检测

## 自动触发
- ⏰ 每 3 小时 cron 轮询上游（.github/workflows/build.yml）
- 🖐 手动：仓库 → Actions → `Build Module` → Run workflow

## 工作原理（build.sh）
1. 查询上游最新 release tag
2. 与本仓库 `latest_version` 比对；相同则跳过
3. 有新版 → 克隆上游源码 → `CGO_ENABLED=0 GOARCH=arm64` 静态交叉编译
4. 用 `module-src/` 模板组装模块（config.yaml / service.sh / action.sh / update.sh 等）
5. 更新 `latest_version` 与 `update.json`
6. 创建 release 并上传 zip 资产（`uploads.github.com`）

> 需要 `GITHUB_TOKEN`；已用 Actions 内置 `github.token`（`permissions: contents: write`）。

## 手机端快速开始
1. 下载最新 release 的 zip，在 Magisk/KernelSU 里本地安装
2. 重启后服务自动启动于 `0.0.0.0:8317`
3. 浏览器打开 `http://<手机IP>:8317/management.html`，管理密钥：`admin`
4. 在「OAuth 登录」页授权（如 Antigravity = 订阅版 Gemini），或配置 API Key
   - Antigravity 的回调为 `localhost:51121`，授权链接必须在**运行模块的手机本机浏览器**打开
5. AI 客户端 API base 指向 `http://<手机IP>:8317`

> 首次打开面板若为空白：强制刷新（浏览器缓存旧面板）。面板文件位于模块 `static/`，可手动替换。

## 模块自更新
模块内 `update.sh` 以上游项目版本为基准，检测新版本从本仓库对应 release 下载并就地更新
（保留用户 `config.yaml`，新模板存 `config.yaml.new`）。