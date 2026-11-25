"""Create the optional Windows x64 ONNX CUDA 12.8/cuDNN 9 release asset."""

import argparse
import shutil
import tempfile
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

NVIDIA_DLLS = (
    "cudart64_12.dll", "cublasLt64_12.dll", "cublas64_12.dll", "cufft64_11.dll",
    "nvrtc-builtins64_128.dll", "nvrtc64_120_0.dll", "nvJitLink_120_0.dll",
    "cudnn64_9.dll", "cudnn_graph64_9.dll", "cudnn_ops64_9.dll", "cudnn_adv64_9.dll",
    "cudnn_cnn64_9.dll", "cudnn_heuristic64_9.dll", "cudnn_engines_precompiled64_9.dll",
    "cudnn_engines_runtime_compiled64_9.dll", "zlibwapi.dll",
)
ORT_DLLS = ("onnxruntime.dll", "onnxruntime_providers_shared.dll", "onnxruntime_providers_cuda.dll")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for argument in ("ort-nupkg", "nvidia-bin", "cuda-license", "cudnn-license", "zlib-license", "output"):
        parser.add_argument("--" + argument, type=Path, required=True)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    destination = args.output / f"Revelation-Editor-v{args.version}-CUDA-Windows-x64.zip"
    with tempfile.TemporaryDirectory(dir=args.output) as temp:
        archive = Path(temp) / destination.name
        prefix = "更好的制谱器/cuda/"
        with ZipFile(archive, "w", ZIP_DEFLATED, compresslevel=2) as result, ZipFile(args.ort_nupkg) as ort:
            for name in ORT_DLLS:
                with ort.open("runtimes/win-x64/native/" + name) as source, result.open(prefix + name, "w") as target:
                    shutil.copyfileobj(source, target, 1024 * 1024)
            for name in NVIDIA_DLLS:
                result.write(args.nvidia_bin / name, prefix + name)
            for source, name in ((args.cuda_license, "CUDA"), (args.cudnn_license, "cuDNN"), (args.zlib_license, "zlib")):
                result.write(source, prefix + "licenses/" + name + ".txt")
            for name in ("LICENSE", "ThirdPartyNotices.txt"):
                result.writestr(prefix + "licenses/ONNXRuntime-" + name, ort.read(name))
        archive.replace(destination)
    print(destination)


if __name__ == "__main__":
    main()
