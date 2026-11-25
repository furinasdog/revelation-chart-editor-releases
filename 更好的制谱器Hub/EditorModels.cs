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

internal sealed class EditorModels(EditorProfile profile,HttpClient http)
{
    private const string EmotionHash="3048c7ff326523812cab440f1d086f754d074f663e6cb193a0823dbe65cf6ce0";
    private const string EmotionUrl="https://github.com/furinasdog/music2emo-native/releases/download/models-v1/Music2Emo-ONNX-v1.zip";
    private const string MadmomUrl="https://raw.githubusercontent.com/alumkal/madmom_models/1491c42703e177b812a8eb49a78e49438861ae36/";
    private static readonly Dictionary<string,PackageFile[]> Assets=Read();
    private static Dictionary<string,PackageFile[]> Read()
    {
        using var stream=typeof(EditorModels).Assembly.GetManifestResourceStream("RevelationHub.assets.model-files.json");
        return JsonSerializer.Deserialize<Dictionary<string,PackageFile[]>>(stream);
    }
    internal PackageFile[] Files(string model)=>Assets[model];
    internal string Location(string model)
    {
        var cfg=profile.Config(EditorProfile.Prefs);
        string path=model=="music2emo"?cfg.Get(EditorProfile.Fields.Single(f=>f.Key=="music2emo_models")):cfg.MadmomPath();
        if (model=="music2emo" && string.IsNullOrWhiteSpace(path))
        {
            path=Environment.GetEnvironmentVariable("AUTOREVELATION_MUSIC2EMO_MODELS");
            string legacy=Path.Combine(profile.Root,"music2emo-models");
            if(string.IsNullOrWhiteSpace(path) && !File.Exists(Path.Combine(legacy,"v1","mert.onnx")) && File.Exists(Path.Combine(legacy,"mert.onnx"))) path=legacy;
        }
        if (model=="madmom" && string.IsNullOrWhiteSpace(path)) path=Environment.GetEnvironmentVariable("AUTOREVELATION_MADMOM_MODELS");
        if (string.IsNullOrWhiteSpace(path)) path=model=="music2emo"?"user://music2emo-models/v1":"user://madmom-models";
        if (path.StartsWith("user://",StringComparison.Ordinal)) path=Path.Combine(profile.Root,path[7..]);
        if (!Path.IsPathFullyQualified(path)) throw new IOException("请在编辑器配置中指定绝对模型路径。");
        return Path.GetFullPath(path);
    }
    internal int Count(string model)=>Files(model).Count(f=>File.Exists(Path.Combine(Location(model),f.path)));
    private static void CheckPath(string path)
    {
        for(var p=new FileInfo(path).FullName;p!=null;p=Path.GetDirectoryName(p))
            if ((File.Exists(p)||Directory.Exists(p)) && File.GetAttributes(p).HasFlag(FileAttributes.ReparsePoint)) throw new IOException("模型路径包含文件链接。");
    }
    internal List<string> Verify(string model,CancellationToken ct)
    {
        string root=Location(model);var missing=new List<string>();
        foreach(var f in Files(model))
        {
            ct.ThrowIfCancellationRequested();
            string path=Path.Combine(root,f.path);
            if (!File.Exists(path) || new FileInfo(path).Length!=f.size) {missing.Add(f.path);continue;}
            using var stream=File.OpenRead(path);
            if (!Convert.ToHexString(SHA256.HashData(stream)).Equals(f.sha256,StringComparison.OrdinalIgnoreCase)) missing.Add(f.path);
        }
        return missing;
    }
    internal async Task Install(string model,IProgress<Transfer> progress,CancellationToken ct)
    {
        string root=Location(model);
        CheckPath(root); Directory.CreateDirectory(root);
        using var gate=new FileStream(Path.Combine(root,".hub-model.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None,1,FileOptions.DeleteOnClose);
        var missing=await Task.Run(()=>Verify(model,ct),ct).ConfigureAwait(false);
        string staging=Path.Combine(root,".hub-"+Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(staging);
        try
        {
            if(missing.Count>0 && model=="music2emo")
            {
                var zip=Path.Combine(staging,"models.zip");
                await Download(EmotionUrl,zip,new Release{size=159258931,sha256=EmotionHash},progress,ct).ConfigureAwait(false);
                using var archive=ZipFile.OpenRead(zip);
                foreach(var f in Files(model).Where(f=>missing.Contains(f.path)))
                {
                    ct.ThrowIfCancellationRequested();
                    var entry=archive.GetEntry("Music2Emo-ONNX/"+f.path);
                    if(entry?.Length!=f.size) throw new InvalidDataException("模型包缺少 "+f.path);
                    entry.ExtractToFile(Path.Combine(staging,f.path));
                }
            }
            else if(model=="madmom")
            {
                foreach(var f in Files(model).Where(f=>missing.Contains(f.path)))
                {
                    string dest=Path.Combine(staging,f.path);Directory.CreateDirectory(Path.GetDirectoryName(dest));
                    await Download(MadmomUrl+f.path,dest,new Release{size=f.size,sha256=f.sha256},progress,ct).ConfigureAwait(false);
                }
            }
            foreach(string file in missing)
            {
                ct.ThrowIfCancellationRequested();
                string dest=Path.Combine(root,file);CheckPath(dest);Directory.CreateDirectory(Path.GetDirectoryName(dest));
                File.Move(Path.Combine(staging,file),dest,true);
            }
            if(model=="music2emo") EditorProfile.Atomic(Path.Combine(root,".archive-sha256"),EmotionHash+"\n");
        } finally {Directory.Delete(staging,true);}
    }
    private Task Download(string url,string dest,Release r,IProgress<Transfer> p,CancellationToken ct)=>
        new PackageDownload(http, DownloadSource.GitHubAsset(url), r, p).Fetch(dest, ct);
    internal void Remove(string model)
    {
        string root=Location(model);CheckPath(root);if(!Directory.Exists(root)) return;
        using var gate=new FileStream(Path.Combine(root,".hub-model.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None,1,FileOptions.DeleteOnClose);
        foreach(var f in Files(model)) {var path=Path.Combine(root,f.path);CheckPath(path);if(File.Exists(path)) File.Delete(path);}
        if(model=="music2emo") File.Delete(Path.Combine(root,".archive-sha256"));
    }
}
