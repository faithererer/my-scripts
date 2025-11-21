这是一个为你定制的 **Gost v3 一键安装/管理脚本**。

它设计为 **交互式**，风格模仿 1Panel/宝塔的安装体验，具备以下特点：

  * **健壮性**：自动检测系统架构（amd64/arm64）、自动获取 GitHub 最新版本、错误捕获。
  * **优雅**：带有颜色输出、清晰的进度提示、自动生成 systemd 服务文件。
  * **易用**：支持安装、更新配置、卸载、查看状态。
  * **轻量**：纯 Shell 编写，无多余依赖，非常适合你的 200MB 小鸡。

### 使用方法

**请在你的 VPS 上执行以下步骤：**

```
https://raw.githubusercontent.com/faithererer/my-scripts/refs/heads/main/gost%E4%BB%A3%E7%90%86/gost.sh
```

### 脚本功能说明

1.  **自动架构识别**：脚本会自动判断你是 `x86_64` 还是 `ARM` (aarch64)，这对于很多廉价 VPS (如 Oracle ARM 或一些 NAT 小鸡) 非常重要。
2.  **Systemd 守护**：按照你的要求，使用 `Type=simple` 和 `Restart=always`，保证进程挂掉（虽然 Gost 极少挂）会自动重启。
3.  **安全配置**：
      * 服务路径：`/etc/systemd/system/gost.service`
      * 二进制路径：`/usr/local/bin/gost`
4.  **配置覆写**：如果你想修改端口或密码，直接再次运行脚本选择 `1` (安装/重装)，输入新参数即可自动覆盖旧配置并重启。

### 常见问题

如果安装完无法连接，请务必运行脚本选择 `3` 查看状态。如果状态是 `running`，请检查防火墙：

```bash
# Ubuntu 放行端口 (假设你设置的是 45654)
ufw allow 45654/tcp
```