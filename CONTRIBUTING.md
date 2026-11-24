# 参与开发

Hub 在 Windows x64 上使用 .NET 10 SDK 和 WiX 4 构建。界面入口是 `MainWindow.xaml`，目录签名和安装逻辑在 `Distribution.cs`，网络传输在 `PackageDownload.cs`。[构建命令](更好的制谱器Hub/README.md)

改动下载逻辑时，从仓库根目录运行下列验证，把路径换成 GitHub Release 下载的原版便携 ZIP。它会在临时目录模拟主站故障、连接中断和内容损坏，安装并启动编辑器。附加 `--live` 会额外从公开地址下载整份发行包。

```powershell
dotnet run --project 更好的制谱器Hub/tests/LibrarySmoke.csproj -c Release -- C:/Downloads/Revelation-Editor-v1.1.0-Windows-x64.zip catalog.signed.json
```

修改编辑器组件时，请说明对应的工具入口、复现步骤和测试结果。运行 Godot 集成测试需要另行取得上游工程。原生节奏扩展的依赖见根目录 CMake 配置。[原生音频工具源码](https://github.com/furinasdog/revelation-audio-native/tree/33675b002efd4f88b270fa60a4acdf81bd4fad36) · [情绪分析工具源码](https://github.com/furinasdog/music2emo-native/tree/98277fc4464d975b0d61a7e82fc68f045a283291)

请提交可以公开分发的测试素材。提交日志前应清除 API Key、MCP 令牌和个人路径。自有贡献沿用 GPL-3.0-only，引入第三方内容时注明来源和适用许可。[许可范围](THIRD_PARTY.md)
