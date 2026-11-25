# HTDemucs native separation

The Revelation editor invokes the [Revelation HTDemucs C++ executable](https://github.com/furinasdog/revelation-htdemucs-native). Its source uses GPL-3.0-only. The matching editor license is included at the root of the distribution.

The original HTDemucs model is by Meta Platforms, Inc. and affiliates. See [Demucs](https://github.com/facebookresearch/demucs) and the accompanying [MIT notice](HTDemucs-MIT.txt).

The [StemSplit ONNX conversion](https://huggingface.co/StemSplitio/htdemucs-onnx/blob/d54ed9eb60e258ea82131c6ee14578628816456a/README.md) is published under the MIT license. The Hub separately downloads `htdemucs_fp16weights.onnx`, 165,612,636 bytes, SHA-256 `d05c269d0178d2a72ad484b10b11dd370193fc923201c3b27a99f848745db70a`.

The executable uses the shared ONNX Runtime library. Its [MIT license](ONNXRuntime-LICENSE.txt) and [third-party notices](ONNXRuntime-ThirdPartyNotices.txt) are included here. The editor's external FFmpeg decoder has a separate [source notice](FFmpeg-Source.txt).
