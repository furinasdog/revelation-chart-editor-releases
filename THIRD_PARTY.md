# 许可范围与第三方来源

本分支作者对其原创桌面功能、原生扩展、命令行及 MCP 适配器、测试、构建脚本和相应修改授予 GPL-3.0-only 许可。混合来源文件中，分支作者的许可覆盖其有权授权的贡献。[GPL 全文](LICENSE)

| 内容 | 来源与适用条款 |
| --- | --- |
| 原制谱器与游戏预览 | `editor/main`、`editor/game_preview`、恢复的脚本缓存及部分图像和音效来自 Revelation 1.9.2／1.10.1。保留原权利人的权利。仓库未附上游对全部代码和素材的统一再许可声明。对外分发相关部分须依据上游授权。[上游同步记录](docs/上游1.10.1同步.md) |
| 字体、美术与歌曲 | 随原制谱器提供的字体（含 `Deng.ttf`）、美术、音效沿用原权利人的条款。用户导入的音乐和谱面由各自权利人授权。 |
| 参考练习谱 | 内置原创练习谱的授权记录随谱面文件提供。[参考谱目录](editor/references) |
| 引擎和运行库 | Godot、Grit、ONNX Runtime、CPython、NumPy、Pillow 和 FFmpeg 各自的许可随便携包提供。FFmpeg 的对应源码信息见 [FFmpeg 来源](editor/licenses/FFmpeg-Source.txt)。 |
| 音频分析和模型 | Beat This!、madmom、Essentia、Music2Emo、RMVPE 使用各自许可。部分可选模型附有非商业条款。原生分析适配器和模型的声明见 [组件许可目录](editor/licenses) 和 [原生组件出处](editor/licenses/Revelation-Native-Audio-NOTICE.md)。 |

本地交付的可编辑工程源码和 Windows 便携包使用同一版本号。在重新发布上游素材、独立程序或模型时，请一并保留其许可和来源声明。
