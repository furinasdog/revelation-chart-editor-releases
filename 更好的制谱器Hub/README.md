# 更好的制谱器 Hub

Windows x64 版本管理器，使用 C#、WPF 和 .NET 10 LTS。MSI 按用户安装并创建开始菜单快捷方式，随附所需运行时。编辑器的不同版本安装在 `%LOCALAPPDATA%\RevelationHub\versions`，可在「版本库」安装，在「已安装」中离线启动。

## 安装与下载

从 [GitHub Releases](https://github.com/furinasdog/revelation-chart-editor-releases/releases) 下载 `Revelation-Hub-v1.1.0-x64.msi`。打开 Hub，选版本并点击「安装」。进度条显示来源、百分比和字节数；校验和解压完成后按钮变为「启动」。取消下载会清理本次临时文件。卸载 Hub 会保留已安装的编辑器和用户谱面。

Hub 优先从 GitHub 读取版本目录和发行附件。目录不可达时尝试 CDN 和代理，再使用签名缓存；安装包不可达时切换镜像。每个版本的大小和 SHA-256 都来自用发行公钥验证的目录。通过校验后才解压到独立版本目录。

## 构建

在 Windows 上安装 .NET 10 SDK 和 WiX 4。以下命令从本目录运行，`LICENSE` 是仓库根目录的 GPLv3 许可文件。

```powershell
dotnet publish RevelationHub.csproj -c Release -r win-x64 --self-contained true -o bin/publish
wix build Installer.wxs -arch x64 -d "PublishDir=$PWD/bin/publish" -d "LicenseFile=$PWD/../LICENSE" -o bin/Revelation-Hub-v1.1.0-x64.msi
```

## 维护发行目录

将编辑器附件命名为 `Revelation-Editor-vX.Y.Z-Windows-x64.zip`，上传到标签 `vX.Y.Z` 的 Release。用 `Sign-Catalog.ps1` 签署对应版本、大小、摘要及更新说明。签名私钥由 Windows 当前用户的 DPAPI 保护，应另行妥善备份；仓库中只保留公钥。将签名后的 `catalog.signed.json` 同步至发行仓库根目录并保留旧版本，旧 Hub 即可发现新版本。编译 Hub 时也会嵌入一份已签名目录供离线使用。

Hub 自有代码使用 GPL-3.0-only。发行仓库仅公开获授权开放的源代码，完整便携版中独立组件和上游作品的权利归各自权利人。
