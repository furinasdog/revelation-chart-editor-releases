using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Text.Json;

namespace RevelationHub
{
    public sealed class Release
    {
        public string version { get; set; }
        public string notes { get; set; }
        public string date { get; set; }
        public string sha256 { get; set; }
        public long size { get; set; }
    }

    public sealed class Transfer
    {
        public string Stage { get; }
        public long Bytes { get; }
        public long Total { get; }
        public Transfer(string stage, long bytes = 0, long total = 0) { Stage = stage; Bytes = bytes; Total = total; }
    }

    public sealed partial class Distribution
    {
        public const string Repository = "furinasdog/revelation-chart-editor-releases";
        public const string Editor = "更好的制谱器";
        private const string Proxy = "https://gh-proxy.org/";
        private const string Catalog = "https://raw.githubusercontent.com/" + Repository + "/main/catalog.signed.json";
        private const long MaxPackage = 4L << 30;
        private const long MaxUnpacked = 8L << 30;
        private readonly HttpClient client;
        public string Root { get; }
        public string Versions => Path.Combine(Root, "versions");
        public string CatalogSource { get; private set; }
        public bool CatalogSynced { get; private set; }
        public class Envelope { public string payload { get; set; } public string signature { get; set; } }
        public class Index { public int schema { get; set; } public string product { get; set; } public Release[] releases { get; set; } }

        public Distribution(string root, HttpClient http)
        {
            Root = root;
            client = http;
            Directory.CreateDirectory(Versions);
            try { using var gate = AcquireLibrary(); } catch (IOException) { /* Another Hub may be installing. */ }
        }
        private static string Embedded(string name)
        {
            using (var stream = typeof(Distribution).Assembly.GetManifestResourceStream("RevelationHub." + name))
            using (var reader = new StreamReader(stream ?? throw new InvalidDataException("缺少内置发行信息。")))
                return reader.ReadToEnd();
        }
        internal static Release[] ReadCatalog(string signed, string product = "editor")
        {
            var doc = ReadSigned<Index>(signed);
            if (doc == null || doc.schema != 1 || (doc.product ?? "editor") != product || doc.releases == null || doc.releases.Length > 1000) throw new InvalidDataException("版本目录格式有误。");
            var seen = new HashSet<string>();
            foreach (var r in doc.releases)
                if (r == null || !ValidVersion(r.version) || !seen.Add(r.version) || r.size <= 0 || r.size > MaxPackage ||
                    !Regex.IsMatch(r.sha256 ?? "", "^[a-fA-F0-9]{64}$")) throw new InvalidDataException("发行条目有误。");
            return doc.releases.OrderByDescending(r => Version.Parse(r.version)).ToArray();
        }
        internal static T ReadSigned<T>(string signed)
        {
            var envelope = JsonSerializer.Deserialize<Envelope>(signed);
            if (envelope?.payload == null || envelope.signature == null) throw new InvalidDataException("版本目录缺少签名。");
            var bytes = Convert.FromBase64String(envelope.payload);
            using (var rsa = RSA.Create())
            {
                rsa.FromXmlString(Embedded("publisher.xml"));
                if (!rsa.VerifyData(bytes, Convert.FromBase64String(envelope.signature), HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1))
                    throw new InvalidDataException("版本目录签名无效。");
            }
            return JsonSerializer.Deserialize<T>(bytes);
        }
        private static bool ValidVersion(string value) =>
            Regex.IsMatch(value ?? "", @"^[0-9]{1,5}\.[0-9]{1,5}\.[0-9]{1,5}$") && Version.TryParse(value, out _);
        private string Cache => Path.Combine(Root, "catalog.signed.json");
        public Release[] Offline()
        {
            if (File.Exists(Cache))
                try { var result = ReadCatalog(File.ReadAllText(Cache)); CatalogSource = "已缓存版本库"; return result; }
                catch (Exception) { /* A verified built-in catalog is always available. */ }
            CatalogSource = "内置版本库";
            return ReadCatalog(Embedded("catalog.signed.json"));
        }
        public async Task<Release[]> Refresh(CancellationToken ct)
        {
            foreach (var url in new[] { Catalog, "https://cdn.jsdelivr.net/gh/" + Repository + "@main/catalog.signed.json", Proxy + Catalog })
            {
                try
                {
                    using (var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct))
                    {
                        timeout.CancelAfter(TimeSpan.FromSeconds(8));
                        using (var response = await client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, timeout.Token).ConfigureAwait(false))
                        using (var data = new MemoryStream())
                        {
                            response.EnsureSuccessStatusCode();
                            await CopyLimited(response, data, 1048576, timeout.Token, null).ConfigureAwait(false);
                            var signed = Encoding.UTF8.GetString(data.ToArray());
                            var items = ReadCatalog(signed);
                            string temporary = Cache + "." + Guid.NewGuid().ToString("N");
                            try
                            {
                                File.WriteAllText(temporary, signed);
                                if (File.Exists(Cache)) File.Replace(temporary, Cache, null); else File.Move(temporary, Cache);
                            }
                            finally { if (File.Exists(temporary)) File.Delete(temporary); }
                            CatalogSynced = true;
                            CatalogSource = url == Catalog ? "已从 GitHub 同步" : "已从镜像同步";
                            return items;
                        }
                    }
                }
                catch (Exception ex) when (ex is HttpRequestException || ex is IOException || ex is OperationCanceledException || ex is InvalidDataException || ex is FormatException || ex is JsonException || ex is CryptographicException || ex is ArgumentException || ex is InvalidOperationException)
                { ct.ThrowIfCancellationRequested(); }
            }
            CatalogSynced = false;
            var fallback = Offline();
            CatalogSource = "在线目录不可用 · " + CatalogSource;
            return fallback;
        }
        internal static async Task<long> CopyLimited(HttpResponseMessage response, Stream to, long limit, CancellationToken ct, Action<long> progress)
        {
            if (response.Content.Headers.ContentLength > limit) throw new InvalidDataException("下载大小超出发行记录。");
            using (var input = await response.Content.ReadAsStreamAsync().ConfigureAwait(false))
            using (var idle = CancellationTokenSource.CreateLinkedTokenSource(ct))
            using (idle.Token.Register(input.Dispose))
            {
                var buffer = new byte[81920];
                long total = 0;
                while (true)
                {
                    idle.CancelAfter(TimeSpan.FromSeconds(20));
                    int count = await input.ReadAsync(buffer, 0, buffer.Length, idle.Token).ConfigureAwait(false);
                    if (count == 0) break;
                    total += count;
                    if (total > limit) throw new InvalidDataException("下载文件过大。");
                    await to.WriteAsync(buffer, 0, count, ct).ConfigureAwait(false);
                    progress?.Invoke(total);
                }
                return total;
            }
        }
        public string Executable(string version)
        {
            if (!ValidVersion(version)) throw new InvalidDataException("版本号无效。");
            return Path.Combine(FindSlot(version) ?? Path.Combine(Versions, version), Editor, Editor + ".exe");
        }
        public bool Installed(string version) => FindSlot(version) != null && File.Exists(Executable(version)) && File.Exists(Path.ChangeExtension(Executable(version), ".pck"));
        public IEnumerable<string> LocalVersions() => Directory.EnumerateDirectories(Versions).Select(SlotVersion).Where(ValidVersion).Distinct();
        public void Launch(string version)
        {
            using var process = StartEditor(version);
        }
        internal Process StartEditor(string version)
        {
            using var gate = AcquireLibrary();
            var running = FindRunningEditor();
            if (running != null)
            {
                running.Process.Dispose();
                throw new InvalidOperationException($"制谱器 v{running.Version} 已在运行。");
            }
            var exe = Executable(version);
            if (!Installed(version)) throw new FileNotFoundException("安装文件缺失，请重新安装该版本。");
            return Process.Start(new ProcessStartInfo(exe) { WorkingDirectory = Path.GetDirectoryName(exe), UseShellExecute = false })
                ?? throw new InvalidOperationException("Windows 未能创建制谱器进程。");
        }
        internal sealed record RunningEditor(string Version, Process Process);
        internal RunningEditor FindRunningEditor()
        {
            RunningEditor found = null;
            foreach (var process in Process.GetProcessesByName(Editor))
            {
                try
                {
                    var exe = found == null ? process.MainModule?.FileName : null;
                    if (exe == null) continue;
                    var slot = Directory.GetParent(exe)?.Parent;
                    if (slot?.Parent == null || !FileNames.Equals(slot.Parent.FullName,Versions) ||
                        !FileNames.Equals(exe, Path.Combine(slot.FullName,Editor,Editor+".exe"))) continue;
                    var version = SlotVersion(slot.FullName);
                    if (ValidVersion(version)) found = new RunningEditor(version,process);
                }
                catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception or IOException) { }
                finally { if (found?.Process != process) process.Dispose(); }
            }
            return found;
        }
        public async Task Install(Release r, IProgress<Transfer> progress, CancellationToken ct)
        {
            using var gate = AcquireLibrary();
            if (!ValidVersion(r.version)) throw new InvalidDataException("版本号无效。");
            if (Installed(r.version)) return;
            if (FindSlot(r.version) != null) throw new IOException("本地版本已损坏，请从已安装页面校验、修复。");
            var destination = Path.Combine(Versions,r.version);
            if (Directory.Exists(destination)) destination += "-" + Guid.NewGuid().ToString("N");
            var scratch = Path.Combine(Root, "staging", Guid.NewGuid().ToString("N"));
            var unpacked = Path.Combine(scratch, "package");
            Directory.CreateDirectory(scratch);
            try
            {
                var asset = "Revelation-Editor-v" + r.version + "-Windows-x64.zip";
                var github = "https://github.com/" + Repository + "/releases/download/v" + r.version + "/" + asset;
                string archive = Path.Combine(scratch, "download.zip");
                string[] sources = { github, Proxy + github, "https://ghfast.top/" + github };
                await new PackageDownload(client, sources, r, progress).Fetch(archive, ct).ConfigureAwait(false);
                progress.Report(new Transfer("正在安装"));
                await Task.Run(() => Extract(archive, unpacked, ct), ct).ConfigureAwait(false);
                ct.ThrowIfCancellationRequested();
                if (!File.Exists(Path.Combine(unpacked, Editor, Editor + ".exe")) || !File.Exists(Path.Combine(unpacked, Editor, Editor + ".pck")))
                    throw new InvalidDataException("发行包缺少主程序或 PCK。");
                File.WriteAllText(Path.Combine(unpacked, Receipt),r.version);
                try { Directory.Move(unpacked, destination); }
                catch (IOException) when (Installed(r.version)) { /* Another Hub completed this version first. */ }
            }
            finally { if (Directory.Exists(scratch)) Directory.Delete(scratch, true); }
        }
        private static void Extract(string zip, string target, CancellationToken ct)
        {
            Directory.CreateDirectory(target);
            var prefix = Path.GetFullPath(target) + Path.DirectorySeparatorChar;
            long total = 0;
            using (var archive = ZipFile.OpenRead(zip))
            {
                if (archive.Entries.Count > 30000) throw new InvalidDataException("发行包项目过多。");
                foreach (var entry in archive.Entries)
                {
                    ct.ThrowIfCancellationRequested();
                    var name = entry.FullName.Replace('\\','/');
                    var parts = name.TrimEnd('/').Split('/');
                    if (parts[0] != Editor || parts.Any(p => p.Length == 0 || p == ".." || p == "." || p.Contains(":") || p.TrimEnd(' ','.') != p) ||
                        (entry.ExternalAttributes & 0x400) != 0 || ((entry.ExternalAttributes >> 16) & 0xf000) == 0xa000)
                        throw new InvalidDataException("发行包包含无效路径。");
                    var path = Path.GetFullPath(Path.Combine(target, name));
                    if (!path.StartsWith(prefix,StringComparison.OrdinalIgnoreCase) || (total += entry.Length) > MaxUnpacked)
                        throw new InvalidDataException("发行包内容超出范围。");
                    if (name.EndsWith("/")) { Directory.CreateDirectory(path); continue; }
                    Directory.CreateDirectory(Path.GetDirectoryName(path));
                    entry.ExtractToFile(path, false);
                }
            }
        }
    }
}
