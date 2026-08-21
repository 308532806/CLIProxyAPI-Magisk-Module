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
同 Wi-Fi 下其它人都能访问，请务必在 `config.yaml` 里设置 `api-keys` 鉴权。

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

## DNS 兜底
若发现解析不了域名，模块开机时会尝试把自带的 `resolv.conf` 挂载到 `/etc/resolv.conf`，
可直接编辑该文件更换解析。

## 卸载
登录凭证（模块 data 目录）不会随卸载删除；若需彻底清除：
`rm -rf /data/adb/modules/cliproxyapi/data`

## 构建
- 二进制自 GitHub 源码 + 依赖静态交叉编译（`CGO_ENABLED=0 GOARCH=arm64`），不随官方 glibc 版
  (安卓用 bionic 无 glibc，官方版无法直接运行)。
- `META-INF/…/update-binary` 取自 Magisk 官方 `scripts/module_installer.sh`。
- config.example.yaml 取自官方仓库。自动生成流程见「自动构建仓库」模板。