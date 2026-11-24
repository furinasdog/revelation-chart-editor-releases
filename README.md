# 更好的制谱器 Hub

Windows x64 版本管理器。下载并安装 Hub 后，可在「版本库」选择制谱器版本、查看下载进度和启动已安装的编辑器。[下载 Hub 安装器](https://github.com/furinasdog/revelation-chart-editor-releases/releases/download/hub-v1.1.1/Revelation-Hub-v1.1.1-x64.msi) · [所有版本](https://github.com/furinasdog/revelation-chart-editor-releases/releases)

Hub 使用 C#、WPF 和 .NET 10 LTS。安装器自带运行时。它优先从 GitHub 获取发行包，连接失败时尝试镜像，以发行签名和 SHA-256 校验内容。各编辑器版本独立安装，可离线启动。[Hub 源码及构建说明](更好的制谱器Hub/README.md)

## 编辑器 v1.1.0

从「工具 → Agent 设置」配置兼容服务。从「工具 → Revelation Co-pilot」打开侧栏，点「一键制谱」，选难度并填写整曲或局部补谱要求。助手提交改动供你确认，写入后可整轮撤销。首次制谱引导可直接打开配置和助手。

## 源码与许可

公开部分包括 Hub、原创桌面功能、制谱 Agent、MCP、命令行、节奏扩展与相关测试。自有代码采用 GPL-3.0-only。编辑器二进制包含上游制谱器的改进版本，使用 GDSO 混淆和 PCK 加密。公开源码树限于可单独开放的部分，完整编辑器的构建还需要独立获授权的上游工程和素材。[GPL 全文](LICENSE) · [第三方声明](THIRD_PARTY.md)

提交问题时请附 Windows 版本、软件版本、复现步骤及预期结果。可分享最小测试谱面。请先移除 API Key、本机路径和私有音乐素材。
