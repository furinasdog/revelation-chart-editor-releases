using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace RevelationHub;

internal sealed class EditorModels(EditorProfile profile, HttpClient http)
{
    private const string EmotionUrl = "https://github.com/furinasdog/music2emo-native/releases/download/models-v1/Music2Emo-ONNX-v1.zip";
    private const string MadmomUrl = "https://raw.githubusercontent.com/alumkal/madmom_models/1491c42703e177b812a8eb49a78e49438861ae36/";
    private const string HTDemucsUrl = "https://huggingface.co/StemSplitio/htdemucs-onnx/resolve/d54ed9eb60e258ea82131c6ee14578628816456a/";
    private static readonly PackageFile EmotionArchive = new(
        "models.zip", 159258931, "3048c7ff326523812cab440f1d086f754d074f663e6cb193a0823dbe65cf6ce0");
    private static readonly Dictionary<string, PackageFile[]> Assets = ReadManifest();

    private static Dictionary<string, PackageFile[]> ReadManifest()
    {
        using var stream = HubResources.Open("RevelationHub.assets.model-files.json");
        return JsonSerializer.Deserialize<Dictionary<string, PackageFile[]>>(stream);
    }

    internal PackageFile[] Files(string model) => Assets[model];

    internal string Location(string model)
    {
        string path = model switch
        {
            "music2emo" => profile.Config(EditorProfile.Prefs).Get(EditorProfile.Fields.Single(field => field.Key == "music2emo_models")),
            "madmom" => profile.Config(EditorProfile.Prefs).MadmomPath(),
            "htdemucs" => null,
            _ => throw new ArgumentOutOfRangeException(nameof(model))
        };

        if (string.IsNullOrWhiteSpace(path))
            path = Environment.GetEnvironmentVariable($"AUTOREVELATION_{model.ToUpperInvariant()}_MODELS");
        if (string.IsNullOrWhiteSpace(path))
            path = DefaultLocation(model);
        if (path.StartsWith("user://", StringComparison.Ordinal))
            path = Path.Combine(profile.Root, path["user://".Length..]);
        if (!Path.IsPathFullyQualified(path))
            throw new IOException("请在编辑器配置中指定绝对模型路径。");
        return Path.GetFullPath(path);
    }

    private string DefaultLocation(string model)
    {
        string root = Path.Combine(profile.Root, model + "-models");
        if (model == "madmom")
            return root;
        string versioned = Path.Combine(root, "v1");
        if (model == "music2emo" && !File.Exists(Path.Combine(versioned, "mert.onnx")) && File.Exists(Path.Combine(root, "mert.onnx")))
            return root;
        return versioned;
    }

    internal int Count(string model)
    {
        var files = Files(model);
        string root = Location(model);
        return files.Count(file => File.Exists(Path.Combine(root, file.path)));
    }

    internal List<string> Verify(string model, CancellationToken ct) =>
        FindMissing(Location(model), Files(model), ct).Select(file => file.path).ToList();

    private static List<PackageFile> FindMissing(string root, PackageFile[] files, CancellationToken ct)
    {
        var missing = new List<PackageFile>();
        foreach (var file in files)
        {
            ct.ThrowIfCancellationRequested();
            var local = new FileInfo(Path.Combine(root, file.path));
            if (local.Exists && local.Length == file.size)
            {
                using var stream = local.OpenRead();
                string hash = Convert.ToHexString(SHA256.HashData(stream));
                if (hash.Equals(file.sha256, StringComparison.OrdinalIgnoreCase))
                    continue;
            }
            missing.Add(file);
        }
        return missing;
    }

    internal async Task Install(string model, IProgress<Transfer> progress, CancellationToken ct)
    {
        string root = Location(model);
        CheckPath(root);
        Directory.CreateDirectory(root);
        using var gate = LockModelDirectory(root);
        var missing = await Task.Run(() => FindMissing(root, Files(model), ct), ct).ConfigureAwait(false);
        string staging = Path.Combine(root, ".hub-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(staging);
        try
        {
            if (missing.Count > 0)
            {
                Task fetch = model == "music2emo"
                    ? StageEmotionArchive(staging, missing, progress, ct)
                    : StageWeights(model, staging, missing, progress, ct);
                await fetch.ConfigureAwait(false);
            }

            foreach (var file in missing)
            {
                ct.ThrowIfCancellationRequested();
                string destination = Path.Combine(root, file.path);
                CheckPath(destination);
                Directory.CreateDirectory(Path.GetDirectoryName(destination));
                File.Move(Path.Combine(staging, file.path), destination, true);
            }
            if (model == "music2emo")
                EditorProfile.Atomic(Path.Combine(root, ".archive-sha256"), EmotionArchive.sha256 + "\n");
        }
        finally
        {
            Directory.Delete(staging, true);
        }
    }

    private async Task StageEmotionArchive(string staging, List<PackageFile> missing, IProgress<Transfer> progress, CancellationToken ct)
    {
        string zip = Path.Combine(staging, EmotionArchive.path);
        await Download(DownloadSource.GitHubAsset(EmotionUrl), zip, EmotionArchive, progress, ct).ConfigureAwait(false);
        using var archive = ZipFile.OpenRead(zip);
        foreach (var file in missing)
        {
            ct.ThrowIfCancellationRequested();
            var entry = archive.GetEntry("Music2Emo-ONNX/" + file.path);
            if (entry?.Length != file.size)
                throw new InvalidDataException("模型包缺少 " + file.path);
            entry.ExtractToFile(Path.Combine(staging, file.path));
        }
    }

    private async Task StageWeights(string model, string staging, List<PackageFile> missing, IProgress<Transfer> progress, CancellationToken ct)
    {
        foreach (var file in missing)
        {
            string[] urls = model switch
            {
                "madmom" => DownloadSource.GitHubAsset(MadmomUrl + file.path),
                "htdemucs" => [HTDemucsUrl + file.path],
                _ => throw new ArgumentOutOfRangeException(nameof(model))
            };
            string destination = Path.Combine(staging, file.path);
            Directory.CreateDirectory(Path.GetDirectoryName(destination));
            await Download(urls, destination, file, progress, ct).ConfigureAwait(false);
        }
    }

    private Task Download(string[] urls, string destination, PackageFile file, IProgress<Transfer> progress, CancellationToken ct)
    {
        var release = new Release { size = file.size, sha256 = file.sha256 };
        return new PackageDownload(http, urls, release, progress).Fetch(destination, ct);
    }

    internal void Remove(string model)
    {
        string root = Location(model);
        CheckPath(root);
        if (!Directory.Exists(root))
            return;
        using var gate = LockModelDirectory(root);
        foreach (var file in Files(model))
        {
            string path = Path.Combine(root, file.path);
            CheckPath(path);
            if (File.Exists(path))
                File.Delete(path);
        }
        if (model == "music2emo")
            File.Delete(Path.Combine(root, ".archive-sha256"));
    }

    private static FileStream LockModelDirectory(string root) =>
        new(Path.Combine(root, ".hub-model.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite,
            FileShare.None, 1, FileOptions.DeleteOnClose);

    private static void CheckPath(string path)
    {
        for (string current = Path.GetFullPath(path); current != null; current = Path.GetDirectoryName(current))
        {
            if ((File.Exists(current) || Directory.Exists(current)) && File.GetAttributes(current).HasFlag(FileAttributes.ReparsePoint))
                throw new IOException("模型路径包含文件链接。");
        }
    }
}
