using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualBasic.FileIO;

namespace RevelationHub;

internal sealed record PackageFile(string path, long size, string sha256);
internal sealed record PackagePatch(string from, string tag, long size, string sha256);
internal sealed record FileIndex(int schema, string product, string version, string archive, PackageFile[] files, PackagePatch[] patches);

public sealed partial class Distribution
{
    private const string Receipt = ".hub-version";
    private string Transaction => Path.Combine(Root, "maintenance");
    private static readonly StringComparer FileNames = StringComparer.OrdinalIgnoreCase;
    private static bool Linked(string path) => (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0;
    private static bool ValidSlot(string name) => Regex.IsMatch(name ?? "", @"^\d{1,5}\.\d{1,5}\.\d{1,5}(-[a-f0-9]{32})?$");
    private static string SlotVersion(string path)
    {
        if (!ValidSlot(Path.GetFileName(path)) || Linked(path)) return null;
        var marker = Path.Combine(path, Receipt);
        if (!File.Exists(marker)) return Path.GetFileName(path);
        if (Linked(marker) || new FileInfo(marker).Length > 64) return null;
        return File.ReadAllText(marker).Trim();
    }
    private string FindSlot(string version) => ValidVersion(version) ? Directory.EnumerateDirectories(Versions).FirstOrDefault(p => SlotVersion(p) == version) : null;
    private FileStream AcquireLibrary()
    {
        FileStream gate;
        try { gate = new FileStream(Path.Combine(Root,"library.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None); }
        catch (IOException ex) when ((ex.HResult & 0xffff) is 32 or 33)
        { throw new IOException("版本库正在执行其他操作，请等待任务结束。",ex); }
        try { Recover(); return gate; } catch { gate.Dispose(); throw; }
    }
    private void Recover()
    {
        ClearCudaStage();
        if (!Directory.Exists(Transaction)) return;
        var backup = Path.Combine(Transaction,"previous");
        if (Directory.Exists(backup))
        {
            string slot = File.ReadAllText(Path.Combine(Transaction,"slot"));
            if (!ValidSlot(slot)) throw new IOException("恢复更新时遇到无效的版本目录。");
            string dest = Path.Combine(Versions,slot);
            if (!Directory.Exists(dest)) Directory.Move(backup,dest);
            else Directory.Delete(backup,true);
        }
        Directory.Delete(Transaction,true);
    }
    internal static IEnumerable<string> SafeFiles(string root)
    {
        if (Linked(root)) throw new IOException("此目录是链接，无法在此修改文件。");
        foreach (var path in Directory.EnumerateFileSystemEntries(root))
        {
            if (Linked(path)) throw new IOException("目录中有文件链接，无法安全继续：" + Path.GetFileName(path));
            if (Directory.Exists(path)) { foreach (var f in SafeFiles(path)) yield return f; }
            else yield return path;
        }
    }
    private static void CheckClosed(string slot)
    {
        foreach (var process in Process.GetProcessesByName(Editor))
        {
            using (process)
            {
                string file;
                try { file = process.MainModule?.FileName; } catch (System.ComponentModel.Win32Exception) { continue; } catch (InvalidOperationException) { continue; }
                if (file != null && file.StartsWith(slot + Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))
                    throw new IOException("请先保存谱面并关闭此版本的编辑器。");
            }
        }
    }
    private static bool Digest(string s) => s != null && Regex.IsMatch(s, "^[a-fA-F0-9]{64}$");
    private async Task<FileIndex> IndexFor(Release release,CancellationToken ct)
    {
        FileIndex Parse(string json)
        {
            var x = ReadSigned<FileIndex>(json);
            if (x?.schema != 1 || x.product != "editor-files" || x.version != release.version || !Digest(x.archive) ||
                (release.sha256 != null && !FileNames.Equals(release.sha256,x.archive)) || x.files is not {Length: >0 and <=30000} || x.patches == null) throw new InvalidDataException("不匹配的文件清单。");
            var names = new HashSet<string>(FileNames);
            foreach (var f in x.files)
                if (f == null || !Digest(f.sha256) || f.size < 0 || !f.path.StartsWith(Editor + "/",StringComparison.Ordinal) ||
                    f.path.Split('/').Any(p => p.Length == 0 || p is "." or ".." || p.TrimEnd(' ','.') != p || p.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0) || !names.Add(f.path)) throw new InvalidDataException("文件清单包含无效项目。");
            if (x.files.Sum(f=>f.size)>MaxUnpacked || x.patches.Any(p=>p==null || !ValidVersion(p.from) || !Digest(p.sha256) || p.size<=0 || p.size>MaxPackage || !Regex.IsMatch(p.tag??"", @"^(hub-)?v\d+\.\d+\.\d+$"))) throw new InvalidDataException("无效的增量更新记录。");
            return x;
        }
        if (!ValidVersion(release.version)) throw new InvalidDataException("版本号无效。");
        string name = "editor-v" + release.version + ".signed.json";
        using var embedded = typeof(Distribution).Assembly.GetManifestResourceStream("RevelationHub.manifests."+name);
        if (embedded != null) { using var reader = new StreamReader(embedded); return Parse(reader.ReadToEnd()); }
        return await new HubServices(Root,client).ReadFeed("manifests/"+name, Parse, ct, 8<<20).ConfigureAwait(false);
    }
    private static bool MatchesFile(string path,PackageFile file,CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        if (!File.Exists(path) || new FileInfo(path).Length != file.size) return false;
        using var stream = File.OpenRead(path);
        return FileNames.Equals(Convert.ToHexString(SHA256.HashData(stream)),file.sha256);
    }
    internal async Task<List<string>> Verify(Release release,IProgress<Transfer> progress,CancellationToken ct)
    {
        using var gate = AcquireLibrary();
        var slot=FindSlot(release.version) ?? throw new IOException("本地版本不存在。");
        CheckClosed(slot);
        var index=await IndexFor(release,ct).ConfigureAwait(false);
        return await Task.Run(()=> {
            foreach (var f in SafeFiles(slot)) ct.ThrowIfCancellationRequested();
            var failed=new List<string>();
            int i=0;
            foreach (var f in index.files)
            {
                if (!MatchesFile(Path.Combine(slot,f.path),f,ct)) failed.Add(f.path);
                if (++i%32==0 || i==index.files.Length) progress.Report(new Transfer("校验文件",i,index.files.Length));
            }
            return failed;
        },ct).ConfigureAwait(false);
    }
    internal async Task Update(Release current,Release target,IProgress<Transfer> progress,CancellationToken ct,bool incremental = true)
    {
        using var gate = AcquireLibrary();
        var slot=FindSlot(current.version) ?? throw new IOException("本地版本不存在。");
        if (target.version!=current.version && FindSlot(target.version)!=null) throw new IOException("目标版本已安装。");
        CheckClosed(slot);
        var before=await IndexFor(current,ct).ConfigureAwait(false);
        var after=await IndexFor(target,ct).ConfigureAwait(false);
        var patch=incremental ? after.patches.FirstOrDefault(p=>p.from==current.version) : null;
        Directory.CreateDirectory(Transaction);
        string next=Path.Combine(Transaction,"next"), zip=Path.Combine(Transaction,"download.zip");
        try
        {
            var prior=before.files.Select(f=>f.path).ToHashSet(FileNames);
            var supplied=after.files.Select(f=>f.path).ToHashSet(FileNames);
            // CUDA runtime files belong to the specific signed add-on for this version.
            string oldCuda = current.version != target.version && CudaFor(current.version)?.Installed == true
                ? CudaDirectory(slot) + Path.DirectorySeparatorChar : null;
            var extras=SafeFiles(slot).Where(f=>!prior.Contains(Path.GetRelativePath(slot,f).Replace('\\','/')) && !FileNames.Equals(f,Path.Combine(slot,Receipt))).ToArray();
            bool complete=false;
            if (patch != null)
            {
                try
                {
                    await FetchAsset(patch.tag,$"Revelation-Editor-v{current.version}-to-v{target.version}.zip",new Release{size=patch.size,sha256=patch.sha256},zip,progress,ct).ConfigureAwait(false);
                    await Task.Run(()=> {
                        Extract(zip,next,ct);
                        foreach (var f in after.files)
                        {
                            var dest=Path.Combine(next,f.path);
                            if (!File.Exists(dest)) { Directory.CreateDirectory(Path.GetDirectoryName(dest)); File.Copy(Path.Combine(slot,f.path),dest); }
                            if (!MatchesFile(dest,f,ct)) throw new InvalidDataException("原文件已变动。");
                        }
                    },ct).ConfigureAwait(false);
                    complete=true;
                }
                catch (Exception ex) when (ex is IOException or InvalidDataException or HttpRequestException)
                { ct.ThrowIfCancellationRequested(); progress.Report(new Transfer("增量不可用，改用完整包")); if (Directory.Exists(next)) Directory.Delete(next,true); File.Delete(zip); }
            }
            if (!complete)
            {
                await FetchAsset("v"+target.version,$"Revelation-Editor-v{target.version}-Windows-x64.zip",target,zip,progress,ct).ConfigureAwait(false);
                await Task.Run(()=>Extract(zip,next,ct),ct).ConfigureAwait(false);
            }
            foreach (var f in extras)
            {
                ct.ThrowIfCancellationRequested();
                if (oldCuda != null && f.StartsWith(oldCuda, StringComparison.OrdinalIgnoreCase)) continue;
                string rel=Path.GetRelativePath(slot,f);
                if (supplied.Contains(rel.Replace('\\','/'))) throw new IOException("新版本与自有文件重名，请先移出：" + rel);
                string dest=Path.Combine(next,rel); Directory.CreateDirectory(Path.GetDirectoryName(dest)); File.Copy(f,dest);
            }
            File.WriteAllText(Path.Combine(next,Receipt),target.version);
            File.WriteAllText(Path.Combine(Transaction,"slot"),Path.GetFileName(slot));
            ct.ThrowIfCancellationRequested(); CheckClosed(slot);
            Directory.Move(slot,Path.Combine(Transaction,"previous"));
            Directory.Move(next,slot);
        }
        finally { Recover(); }
    }
    private Task FetchAsset(string tag,string name,Release package,string path,IProgress<Transfer> progress,CancellationToken ct)
    {
        string url=$"https://github.com/{Repository}/releases/download/{tag}/{name}";
        return new PackageDownload(client, DownloadSource.GitHubAsset(url), package, progress).Fetch(path, ct);
    }
    internal void RemoveVersion(string version)
    {
        using var gate=AcquireLibrary();
        string slot=FindSlot(version) ?? throw new IOException("本地版本不存在。");
        CheckClosed(slot);
        foreach(var file in SafeFiles(slot)) { }
        FileSystem.DeleteDirectory(slot,UIOption.OnlyErrorDialogs,RecycleOption.SendToRecycleBin,UICancelOption.ThrowException);
    }
}
