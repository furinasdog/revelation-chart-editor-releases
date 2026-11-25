# 更好的制谱器 Hub

Windows x64 版本管理器。下载并安装 Hub 后，可在「版本库」选择制谱器版本、查看下载进度和启动已安装的编辑器。[下载 Hub 安装器](https://github.com/furinasdog/revelation-chart-editor-releases/releases/download/hub-v1.5.0/Revelation-Hub-v1.5.0-x64.msi) · [所有版本](https://github.com/furinasdog/revelation-chart-editor-releases/releases)

Hub 使用 C#、WPF 和 .NET 10 LTS。安装器自带运行时。它优先从 GitHub 获取发行包，连接失败时尝试镜像，以发行签名和 SHA-256 校验内容。各编辑器版本独立安装，可离线启动。[Hub 源码及构建说明](更好的制谱器Hub/README.md)

## Hub v1.5.0 与制谱器 v1.4.0

编辑器支持按模型单项采音、复用缓存和 HTDemucs 四轨试听。播放中切换音源可保留当前位置和循环区间。Hub 统一管理 madmom、Music2Emo 和 HTDemucs，已有 v1.3.0 编辑器可在「已安装」中增量更新。[编辑器发行说明](https://github.com/furinasdog/revelation-chart-editor-releases/releases/tag/v1.4.0) · [Hub 发行说明](https://github.com/furinasdog/revelation-chart-editor-releases/releases/tag/hub-v1.5.0)

## Hub v1.4.0 与制谱器 v1.3.0

Hub 支持最多 8 路并行下载，GitHub 或镜像连接中断时会尝试其他来源。制谱器默认安装 CPU 版，需要 GPU 推理时可在「启动 → 已安装」的版本卡片上添加 CUDA 支持。[Hub 发行说明](https://github.com/furinasdog/revelation-chart-editor-releases/releases/tag/hub-v1.4.0)

制谱器新增草稿续编、分段 BPM 恢复、跨工程复制、选区改谱与试听对比、手序预览和 8 拍练习。视频导出可自定义分辨率、帧率和画质，并使用多线程并行渲染及 NVIDIA 硬件编码。已安装 v1.2.0 可在 Hub 原位增量更新。[制谱器发行说明](https://github.com/furinasdog/revelation-chart-editor-releases/releases/tag/v1.3.0)

## Hub v1.3.2

切换页面时，卡片连同文字、输入框和按钮一起滑入。侧栏导航项依次入场，公告和更新弹窗轻弹展开。 [发行说明](https://github.com/furinasdog/revelation-chart-editor-releases/releases/tag/hub-v1.3.2)

## Hub v1.3.1

新公告和可用版本在窗口中央提示，历史消息可从左侧「公告」重看。主导航和编辑器配置页签恢复原位淡入，下载进度继续显示在底栏。[本版发行说明](https://github.com/furinasdog/revelation-chart-editor-releases/releases/tag/hub-v1.3.1)

## Hub v1.3.0

操作结果和发行公告从右侧弹出。下载、安装、校验和更新进度固定在底栏，切换页面仍可查看。[本版发行说明](https://github.com/furinasdog/revelation-chart-editor-releases/releases/tag/hub-v1.3.0)

## Hub v1.2.1

从顶部「启动、下载、设置、更多」进入对应分类。快速校验保留当前页面和焦点，配置表单统一为浅色，按钮悬停反馈位于边框内。[本版发行说明](https://github.com/furinasdog/revelation-chart-editor-releases/releases/tag/hub-v1.2.1)

## Hub v1.2.0

在「已安装」中原位更新、检查文件、修复或移除版本。v1.1.0 至 v1.1.1 提供编辑器增量包。左栏可管理模型、参考工程和编辑器配置，也可查阅离线使用文档。Hub v1.1.2 能自动升级；更早版本请手动运行本页安装器。[Hub 使用手册](更好的制谱器Hub/guides/hub.md)

## Hub v1.1.2

从 v1.1.2 起支持 Hub 自动更新。后续版本由 Hub 自动下载并在退出时安装。安装完成后可分别勾选开始菜单和桌面快捷方式。版本库会显示发行公告，侧栏「问题反馈」可直接打开 GitHub Issues。

## 制谱器 v1.2.0

Co-pilot 新增独立自动审批与 Markdown 显示，完善浮现式制谱的手序与跨屏引导，移除废弃的预览设置页。 打开 Hub 的「已安装」，可将 v1.1.1 原位更新到 v1.2.0。首次安装可在「下载 → 版本库」选择本版。[制谱器发行页](https://github.com/furinasdog/revelation-chart-editor-releases/releases/tag/v1.2.0)

## 编辑器 v1.1.1

v1.1.1 修复 Agent 设置窗口异常增高及高 DPI 下操作按钮超出可用区域的问题。打开 Hub 的「版本库」，点击「刷新版本」即可选择安装。[编辑器发行页](https://github.com/furinasdog/revelation-chart-editor-releases/releases/tag/v1.1.1)

从「工具 → Agent 设置」配置兼容服务。从「工具 → Revelation Co-pilot」打开侧栏，点「一键制谱」，选难度并填写整曲或局部补谱要求。助手提交改动供你确认，写入后可整轮撤销。首次制谱引导可直接打开配置和助手。

## 源码与许可

公开部分包括 Hub、原创桌面功能、制谱 Agent、MCP、命令行、节奏扩展与相关测试。自有代码采用 GPL-3.0-only。编辑器二进制包含上游制谱器的改进版本，使用 GDSO 混淆和 PCK 加密。公开源码树限于可单独开放的部分，完整编辑器的构建还需要独立获授权的上游工程和素材。[GPL 全文](LICENSE) · [第三方声明](THIRD_PARTY.md)

提交问题时请附 Windows 版本、软件版本、复现步骤及预期结果。可分享最小测试谱面。请先移除 API Key、本机路径和私有音乐素材。
