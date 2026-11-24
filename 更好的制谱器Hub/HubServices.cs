using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace RevelationHub;

internal sealed record Notice(string title, string body);
internal sealed record NoticeFeed(int schema, Notice[] items);

internal sealed class HubServices(string root, HttpClient http)
{
    internal const string IssuesUrl = "https://github.com/" + Distribution.Repository + "/issues";
    private const string Manifest = "hub-update.signed.json";
    internal static Version Current => typeof(HubServices).Assembly.GetName().Version;
    internal static string UserRoot => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RevelationHub");
    private string Updates => Path.Combine(root, "updates");
    private string Installer(string version) => Path.Combine(Updates, $"Revelation-Hub-v{version}-x64.msi");

    private static void Save(string path, string value)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        string temp = path + "." + Guid.NewGuid().ToString("N");
        try { File.WriteAllText(temp, value); File.Move(temp, path, true); }
        finally { File.Delete(temp); }
    }

    private async Task<T> ReadFeed<T>(string name, Func<string,T> parse, CancellationToken ct)
    {
        string cache = Path.Combine(root, name);
        string raw = $"https://raw.githubusercontent.com/{Distribution.Repository}/main/{name}";
        foreach (string url in new[] { raw, $"https://cdn.jsdelivr.net/gh/{Distribution.Repository}@main/{name}" })
        {
            try
            {
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
                timeout.CancelAfter(TimeSpan.FromSeconds(9));
                using var response = await http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, timeout.Token).ConfigureAwait(false);
                response.EnsureSuccessStatusCode();
                using var buffer = new MemoryStream();
                await Distribution.CopyLimited(response, buffer, 128 * 1024, timeout.Token, null).ConfigureAwait(false);
                string json = Encoding.UTF8.GetString(buffer.ToArray());
                T result = parse(json);
                Save(cache, json);
                return result;
            }
            catch (Exception ex) when (ex is IOException or HttpRequestException or InvalidDataException or JsonException or FormatException or CryptographicException or OperationCanceledException or ObjectDisposedException)
            { ct.ThrowIfCancellationRequested(); }
        }
        ct.ThrowIfCancellationRequested();
        return parse(await File.ReadAllTextAsync(cache, ct).ConfigureAwait(false));
    }

    internal Task<Notice[]> Notices(CancellationToken ct) => ReadFeed("announcements.json", json =>
    {
        var feed = JsonSerializer.Deserialize<NoticeFeed>(json);
        if (feed?.schema != 1 || feed.items == null || feed.items.Length > 12 ||
            feed.items.Any(n => n == null || string.IsNullOrWhiteSpace(n.title) || n.title.Length > 120 || string.IsNullOrWhiteSpace(n.body) || n.body.Length > 1500))
            throw new InvalidDataException("公告格式有误。");
        return feed.items;
    }, ct);

    private static Release Latest(string signed) => Distribution.ReadCatalog(signed, "hub").FirstOrDefault()
        ?? throw new InvalidDataException("Hub 更新目录为空。");

    internal async Task<string> Prepare(Version installed, IProgress<Transfer> progress, CancellationToken ct)
    {
        var entry = await ReadFeed(Manifest, text => (Signed:text, Newest:Latest(text)), ct).ConfigureAwait(false);
        Release r = entry.Newest;
        if (Version.Parse(r.version).CompareTo(new Version(installed.Major, installed.Minor, installed.Build)) <= 0) return null;
        Directory.CreateDirectory(Updates);
        string target = Installer(r.version);
        if (!await Matches(target, r, ct).ConfigureAwait(false))
        {
            string primary = $"https://github.com/{Distribution.Repository}/releases/download/hub-v{r.version}/{Path.GetFileName(target)}";
            string temporary = target + "." + Guid.NewGuid().ToString("N");
            try
            {
                await new PackageDownload(http, new[] { primary, "https://gh-proxy.org/" + primary, "https://ghfast.top/" + primary }, r, progress).Fetch(temporary, ct).ConfigureAwait(false);
                File.Move(temporary, target, true);
            }
            finally { File.Delete(temporary); }
        }
        Save(target + ".json", entry.Signed);
        return r.version;
    }

    private static async Task<bool> Matches(string file, Release r, CancellationToken ct)
    {
        if (!File.Exists(file)) return false;
        using var stream = File.OpenRead(file);
        if (stream.Length != r.size) return false;
        return Convert.ToHexString(await SHA256.HashDataAsync(stream, ct).ConfigureAwait(false)).Equals(r.sha256, StringComparison.OrdinalIgnoreCase);
    }

    internal void StartUpdater(string version, bool reopen)
    {
        string helper = Path.Combine(Updates, "apply-" + Guid.NewGuid().ToString("N") + ".exe");
        File.Copy(Environment.ProcessPath, helper);
        var start = new ProcessStartInfo(helper) { UseShellExecute = false, WorkingDirectory = Updates };
        foreach (var arg in new[] { "--apply-update", Environment.ProcessId.ToString(), version, reopen ? "reopen" : "close" })
            start.ArgumentList.Add(arg);
        try { using var process = Process.Start(start); }
        catch { File.Delete(helper); throw; }
    }

    internal static async Task<int> Apply(string root, int parent, string version, bool reopen)
    {
        if (!Version.TryParse(version, out var requested) || requested.Build < 0 || requested.ToString(3) != version || requested <= new Version(Current.Major, Current.Minor, Current.Build)) return 2;
        try { using var old = Process.GetProcessById(parent); using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(90)); await old.WaitForExitAsync(timeout.Token); }
        catch (ArgumentException) { /* The previous Hub already closed. */ }
        string path = Path.Combine(root, "updates", $"Revelation-Hub-v{version}-x64.msi");
        int result = await InstallVerified(path, version);
        if (result == 0 && reopen) Process.Start(new ProcessStartInfo(Shortcuts.InstalledExecutable) { UseShellExecute = true });
        return result;
    }

    internal static async Task<int> InstallVerified(string path, string version)
    {
        Release entry = Latest(await File.ReadAllTextAsync(path + ".json"));
        if (entry.version != version) return 3;
        // Keep the verified MSI read-locked until Windows Installer finishes.
        using var locked = File.OpenRead(path);
        if (locked.Length != entry.size || !Convert.ToHexString(await SHA256.HashDataAsync(locked)).Equals(entry.sha256, StringComparison.OrdinalIgnoreCase)) return 3;
        var start = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "msiexec.exe")) { UseShellExecute = false };
        foreach (string arg in new[] { "/i", path, "/qn", "/norestart", "/L*v", Path.Combine(Path.GetDirectoryName(path), "install.log") }) start.ArgumentList.Add(arg);
        using var install = Process.Start(start);
        await install.WaitForExitAsync();
        if (install.ExitCode != 0 && install.ExitCode != 3010) return install.ExitCode;
        return 0;
    }

    internal void CleanApplied()
    {
        if (!Directory.Exists(Updates)) return;
        foreach (string path in Directory.EnumerateFiles(Updates))
        {
            string name = Path.GetFileName(path);
            const string prefix = "Revelation-Hub-v";
            int end = name.IndexOf("-x64.msi", StringComparison.Ordinal);
            bool oldPackage = name.StartsWith(prefix) && end > prefix.Length &&
                Version.TryParse(name[prefix.Length..end], out Version version) && version <= Current;
            if (oldPackage || (name.StartsWith("apply-") && name.EndsWith(".exe")))
                try { File.Delete(path); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }
}
