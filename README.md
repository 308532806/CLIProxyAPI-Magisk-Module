# CLIProxyAPI-Magisk-Module

[router-for-me/CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) 的 **Magisk / KernelSU 通用模块**自动构建仓库。

本仓库的 GitHub Actions 会**定时轮询上游项目**，一旦上游 `router-for-me/CLIProxyAPI` 发布新版本，
就自动重新交叉编译 arm64 静态二进制并发布新的**模块 zip release**，同时刷新 `update.json`
（供手机端 Magisk 模块卡片做应用内更新检测）。

## 产物
- GitHub **Releases** 页发布：`CLIProxyAPI-magisk-vX.Y.Z-arm64.zip`
- 手机端可直接安装该 zip，或通过模块自带的 `update.sh` 就地升级（保留用户 config.yaml）。
- `update.json` 供 Magisk 应用内「检查更新」使用。

## 自动触发

- ⏰ **每 3 小时**轮询一次（.github/workflows/build.yml 的 schedule）。
- 🖐 **手动**：仓库页面 → **Actions** → 左栏 `Build Module` → **Run workflow**。

## 工作原理（build.sh）
1. 调用 GitHub API 查询上游最新 release tag
2. 与本仓库 `latest_version` 比对；相同则跳过
3. 有新版本 → 克隆上游 tag 源码，`CGO_ENABLED=0 GOARCH=arm64` 静态交叉编译（不依赖 glibc/bionic）
4. 用 `module-src/` 模板组装完整模块（含 config.yaml / service.sh / action.sh / update.sh 等）
5. 更新 `latest_version` 与 `update.json`
6. 创建一个 repo 内 tag release 并上传模块 zip

> 注意：`build.sh` 需要 `GITHUB_TOKEN` 创建 release；已用 GitHub Actions 内置
> `github.token` 授权（`permissions: contents: write`）。

## 手机端使用
请以本仓库最新 release 的 zip 为准，或直接将 release zip 地址给手机端 Magisk 应用安装。
模块开机自动启动 `0.0.0.0:8317`，局域网内其它设备指向 `http://<手机IP>:8317/v1`。

## 模块自更新
模块内的 `update.sh` 以 **上游项目** 的版本为基准，检测到新版后从本仓库对应 release
下载 zip 并就地覆盖更新（保留用户 `config.yaml`，新模板存 `config.yaml.new`）。