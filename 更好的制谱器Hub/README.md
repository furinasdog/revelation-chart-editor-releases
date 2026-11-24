# 更好的制谱器 Hub

Windows x64 版本管理器，使用 C#、WPF 和 .NET 10 LTS。MSI 按用户安装，完成页分别提供开始菜单和桌面快捷方式选项，随附所需运行时。编辑器的不同版本安装在 `%LOCALAPPDATA%\RevelationHub\versions`，可在「版本库」安装，在「已安装」中离线启动。

## 安装与下载

从 [GitHub Releases](https://github.com/furinasdog/revelation-chart-editor-releases/releases) 下载 `Revelation-Hub-v1.3.0-x64.msi`。打开 Hub，选版本并点击「安装」。底栏显示下载来源和进度；校验和解压完成后按钮变为「启动」。取消下载会清理本次临时文件。卸载 Hub 会保留已安装的编辑器和用户谱面。

Hub 优先从 GitHub 读取版本目录和发行附件。目录不可达时尝试 CDN 和代理，再使用签名缓存；安装包采用并行分段下载。传输中断时会在同一次安装中从已收到的位置继续，必要时切换镜像。每个版本的大小和 SHA-256 都来自用发行公钥验证的目录。通过校验后才解压到独立版本目录。

## Hub 更新与公告

双击 MSI 会打开中文安装向导。点击「安装」后可查看当前步骤和进度，完成页可以选择开始菜单和桌面快捷方式。再次运行修订安装器可以覆盖已安装的 v1.3.0。

Hub 启动时、每隔 6 小时以及点击「刷新版本」时检查更新。发现新版后会自动下载并校验，点击「重启并更新」可立即安装，也可在本次退出时安装。静默升级沿用已选的快捷方式。v1.1.2 及后续版本可以自动升级至 v1.3.0。使用 v1.1.1 或更早版本的用户需手动安装一次新版。左侧「问题反馈」在 Hub 内显示群内反馈方式。

右侧气泡显示操作结果和发行公告。Hub 从发行仓库 main 分支根目录的 `announcements.json` 读取纯文本公告。更新该文件即可发布公告，`items` 设为空数组即可撤下。离线时显示最近成功读取的公告。

```json
{"schema": 1, "items": [{"title": "编辑器更新", "body": "可在版本库安装新版。"}]}
```

## 编辑器与资料管理

「已安装」页面可在原安装位置更新、校验、修复或移除选中的版本。有配套增量包时优先传输变更文件，验证成功后切换目录。每个原位升级的版本保留原启动路径。独立安装仍可用于并行维护多个版本。

顶部按启动、下载、设置、更多分组。下载下的模型管理、设置下的编辑器配置、更多下的参考工程共用编辑器的用户资料目录。内置离线文档支持标题与正文搜索。操作说明见 [Hub 使用手册](guides/hub.md)、[编辑器教程](guides/editor.md) 和 [模块入口](guides/modules.md)。

## 构建

在 Windows 上安装 .NET 10 SDK 和 WiX 4。以下命令从本目录运行，`LICENSE` 是仓库根目录的 GPLv3 许可文件。

```powershell
dotnet publish RevelationHub.csproj -c Release -r win-x64 --self-contained true -o bin/publish
wix build Installer.wxs -arch x64 -d "PublishDir=$PWD/bin/publish" -d "LicenseFile=$PWD/../LICENSE" -o bin/Revelation-Hub-v1.3.0-x64.msi
```

## 维护发行目录

将编辑器附件命名为 `Revelation-Editor-vX.Y.Z-Windows-x64.zip`，上传到标签 `vX.Y.Z` 的 Release。用 `Sign-Catalog.ps1` 签署对应版本、大小、摘要及更新说明。签名私钥由 Windows 当前用户的 DPAPI 保护，应另行妥善备份；仓库中只保留公钥。将签名后的 `catalog.signed.json` 同步至发行仓库根目录并保留旧版本，旧 Hub 即可发现新版本。编译 Hub 时也会嵌入一份已签名目录供离线使用。

发布 Hub 时，将 Windows 安装包命名为 `Revelation-Hub-vX.Y.Z-x64.msi`，发布到 `hub-vX.Y.Z` 标签。用同一签名工具加 `-Product hub` 参数签署安装包，再把生成的 `hub-update.signed.json` 发布到发行仓库根目录。应先发布 MSI，再更新目录，确保客户端发现新版本时已经可以下载。

维护文件校验清单时，使用 PowerShell 7 运行 `Publish-EditorFiles.ps1 -Archive <完整包> -Version X.Y.Z -KeyFile <本地签名密钥> -OutputDirectory <产物目录>`。生成的 `manifests/editor-vX.Y.Z.signed.json` 应同步至发行仓库根目录的 `manifests/`。要为已有版本生成增量，请先生成基础版本清单，再对目标版本加 `-FromVersion A.B.C -PatchTag <发行标签>`，将生成的增量 ZIP 上传到该标签的 Release。

Hub 自有代码使用 GPL-3.0-only。发行仓库仅公开获授权开放的源代码，完整便携版中独立组件和上游作品的权利归各自权利人。
