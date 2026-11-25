using System;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace RevelationHub;

internal sealed record CudaSupport(string Hash, long Size, bool Installed);

public sealed partial class Distribution
{
    private const string CudaDescriptor = "cuda-addon.signed.json";
    private const string CudaReceipt = ".hub-addon";
    private string CudaStage => Path.Combine(Root, "cuda-staging");
    private static string CudaDirectory(string slot) => Path.Combine(slot, Editor, "cuda");

    internal CudaSupport CudaFor(string version)
    {
        string slot = FindSlot(version);
        if (slot == null) return null;
        string app = Path.Combine(slot, Editor);
        string descriptor = Path.Combine(app, CudaDescriptor);
        if (!File.Exists(descriptor) || Linked(app) || Linked(descriptor) || new FileInfo(descriptor).Length > 16384) return null;
        try
        {
            var items = ReadCatalog(File.ReadAllText(descriptor), "cuda");
            if (items.Length != 1 || items[0].version != version) return null;
            var package = items[0];
            string dir = CudaDirectory(slot), receipt = Path.Combine(dir, CudaReceipt);
            bool installed = Directory.Exists(dir) && !Linked(dir) && File.Exists(receipt) && !Linked(receipt)
                && new FileInfo(receipt).Length <= 64 && FileNames.Equals(File.ReadAllText(receipt), package.sha256);
            return new CudaSupport(package.sha256, package.size, installed);
        }
        catch (Exception e) when (e is IOException or InvalidDataException or CryptographicException or JsonException or FormatException or ArgumentException)
        { return null; }
    }

    private void ClearCudaStage()
    {
        if (!Directory.Exists(CudaStage)) return;
        foreach (var _ in SafeFiles(CudaStage)) { }
        Directory.Delete(CudaStage, true);
    }

    internal async Task ChangeCuda(string version, bool install, IProgress<Transfer> progress, CancellationToken ct)
    {
        using var gate = AcquireLibrary();
        var support = CudaFor(version) ?? throw new InvalidDataException("此版本没有可用的 CUDA 附加包。");
        string slot = FindSlot(version), target = CudaDirectory(slot);
        CheckClosed(slot);
        if (install == support.Installed) return;
        Directory.CreateDirectory(CudaStage);
        try
        {
            ct.ThrowIfCancellationRequested();
            if (!install)
            {
                foreach (var _ in SafeFiles(target)) ct.ThrowIfCancellationRequested();
                Directory.Move(target, Path.Combine(CudaStage, "removed"));
                return;
            }
            if (Directory.Exists(target)) throw new IOException("已有未受 Hub 管理的 cuda 目录，请先移出。");
            string name = $"Revelation-Editor-v{version}-CUDA-Windows-x64.zip";
            string local = Path.Combine(AppContext.BaseDirectory, name);
            string archive = Path.Combine(CudaStage, "download.zip");
            var package = new Release { size = support.Size, sha256 = support.Hash };
            if (File.Exists(local))
            {
                progress.Report(new Transfer("正在校验本地 CUDA 附加包"));
                await using var input = File.OpenRead(local);
                if (input.Length != support.Size || !FileNames.Equals(Convert.ToHexString(await SHA256.HashDataAsync(input, ct)), support.Hash))
                    throw new InvalidDataException("本地 CUDA 附加包校验失败。");
                // Keep the verified bytes private until extraction completes.
                input.Position = 0;
                await using var copy = File.Create(archive);
                await input.CopyToAsync(copy, ct);
            }
            else await FetchAsset("v" + version, name, package, archive, progress, ct).ConfigureAwait(false);
            progress.Report(new Transfer("正在安装 CUDA 支持"));
            string unpack = Path.Combine(CudaStage, "unpacked");
            await Task.Run(() => Extract(archive, unpack, ct), ct).ConfigureAwait(false);
            string payload = CudaDirectory(unpack);
            if (!Directory.Exists(payload) || SafeFiles(unpack).Any(p => !p.StartsWith(payload + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) ||
                !new[] { "onnxruntime.dll", "onnxruntime_providers_cuda.dll", "onnxruntime_providers_shared.dll" }.All(n => File.Exists(Path.Combine(payload, n))))
                throw new InvalidDataException("CUDA 附加包的目录或运行库不完整。");
            File.WriteAllText(Path.Combine(payload, CudaReceipt), support.Hash);
            ct.ThrowIfCancellationRequested();
            CheckClosed(slot);
            Directory.Move(payload, target);
        }
        finally { ClearCudaStage(); }
    }
}
