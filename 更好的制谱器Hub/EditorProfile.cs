using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace RevelationHub;

internal sealed record HubOptions(bool Animations=true, bool Incremental=true, bool Announcements=true, bool AutoUpdates=true)
{
    internal static HubOptions Load(string root)
    {
        string path=Path.Combine(root,"settings.json");
        try { return JsonSerializer.Deserialize<HubOptions>(File.ReadAllText(path)) ?? new(); }
        catch (IOException) { return new(); } catch (JsonException) { return new(); }
    }
    internal void Save(string root) => EditorProfile.Atomic(Path.Combine(root,"settings.json"),JsonSerializer.Serialize(this));
}

internal sealed record Setting(string File,string Section,string Key,string Label,string Default,string Kind="text",double Min=0,double Max=0);
internal sealed class ConfigDocument(string path)
{
    private string original=File.Exists(path)?File.ReadAllText(path):"";
    private static (int head,int end,int match) Locate(List<string> lines,string section,string key)
    {
        int head=lines.FindIndex(s=>s.Trim()=="["+section+"]");
        if (head<0) return (-1,lines.Count,-1);
        int end=lines.FindIndex(head+1,s=>Regex.IsMatch(s.Trim(),@"^\[[\w.-]+\]$"));
        if (end<0) end=lines.Count;
        int match=lines.FindIndex(head+1,end-head-1,s=>s.StartsWith(key+"=",StringComparison.Ordinal));
        return (head,end,match);
    }
    internal string Get(Setting field)
    {
        var lines=original.Replace("\r\n","\n").Split('\n').ToList();
        var (_,_,i)=Locate(lines,field.Section,field.Key);
        if (i<0) return field.Default;
        var raw=lines[i][(field.Key.Length+1)..].Trim();
        if (raw.StartsWith('"')) { try{return JsonSerializer.Deserialize<string>(raw);} catch(JsonException){return raw.Trim('"');} }
        return raw;
    }
    internal bool Contains(Setting field) =>
        Locate(original.Replace("\r\n","\n").Split('\n').ToList(),field.Section,field.Key).match >= 0;
    internal void Save(Dictionary<Setting,string> values)
    {
        if ((File.Exists(path)?File.ReadAllText(path):"")!=original) throw new IOException("编辑器已修改此配置，请刷新后重新保存。");
        string newline=original.Contains("\r\n")?"\r\n":"\n";
        var lines=original.Replace("\r\n","\n").TrimEnd('\n').Split('\n').ToList();
        foreach(var (f,value) in values)
        {
            string raw=value;
            if (f.Kind=="bool") { if (value is not ("true" or "false")) throw new InvalidDataException(f.Label); }
            else if (f.Kind is "number" or "integer") {
                if (!double.TryParse(value,NumberStyles.Float,CultureInfo.InvariantCulture,out double n) || !double.IsFinite(n) || n<f.Min || n>f.Max || (f.Kind=="integer" && n!=Math.Truncate(n))) throw new InvalidDataException($"{f.Label} 的范围为 {f.Min} 至 {f.Max}。");
                raw=n.ToString("G",CultureInfo.InvariantCulture);
            } else {
                if (f.Kind.Contains('|') && !f.Kind.Split('|').Contains(value)) throw new InvalidDataException(f.Label);
                if (value.Any(char.IsControl)) throw new InvalidDataException(f.Label+"含有控制字符。");
                raw=JsonSerializer.Serialize(value,EditorProfile.Json);
            }
            var (head,end,i)=Locate(lines,f.Section,f.Key);
            if (head<0) { lines.Add("");lines.Add("["+f.Section+"]");lines.Add(f.Key+"="+raw); }
            else if (i<0) lines.Insert(end,f.Key+"="+raw);
            else lines[i]=f.Key+"="+raw;
        }
        var text=string.Join(newline,lines)+newline;
        EditorProfile.Atomic(path,text);
        original=text;
    }
    internal string MadmomPath()
    {
        var m=Regex.Match(original,"\"madmom_model_cache\"\\s*:\\s*(\"(?:[^\"\\\\]|\\\\.)*\")");
        return m.Success?JsonSerializer.Deserialize<string>(m.Groups[1].Value):null;
    }
}

internal sealed record ReferenceItem(string Id,string Title,string Difficulty,int Items,bool Media);
internal sealed class EditorProfile(string root)
{
    internal static readonly JsonSerializerOptions Json=new(){Encoder=JavaScriptEncoder.UnsafeRelaxedJsonEscaping};
    internal static string DefaultRoot => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"Godot","app_userdata",Distribution.Editor);
    internal string Root => root;
    internal string References => Path.Combine(root,"reference_charts");
    internal const string Prefs="desktop_preferences.cfg", Agent="chart_agent.cfg", Mcp="mcp_server.cfg";
    internal static readonly Setting[] Fields={
        new(Prefs,"display","theme","主题","system","system|dark|gray|light"),new(Prefs,"display","automatic_scale","自动缩放","true","bool"),
        new(Prefs,"display","scale","界面缩放","1","number",.75,2.5),new(Prefs,"audio","play_startup_sound","播放启动音","true","bool"),
        new(Prefs,"audio","startup_sound_volume","启动音量","0.5","number",0,1),new(Prefs,"audio","import_matching_lyrics","导入同名歌词","false","bool"),
        new(Prefs,"audio","output_device","音频输出设备","Default"),new(Prefs,"analysis","ffmpeg","FFmpeg 程序路径",""),
        new(Prefs,"analysis","music2emo_models","Music2Emo 模型目录",""),new(Prefs,"analysis","music2emo_low_memory","情绪分析低内存模式","false","bool"),
        new(Prefs,"analysis","music2emo_automatic","自动分析情绪（仅旧版）","true","bool"),new(Prefs,"shortcuts","scheme","快捷键方案","standard","standard|original"),
        new(Agent,"agent","url","API URL",""),new(Agent,"agent","model","模型名称",""),new(Agent,"agent","key","API Key","","secret"),
        new(Mcp,"mcp","port","服务端口","17387","integer",1,65535),new(Mcp,"mcp","path","服务路径","/mcp"),
        new(Mcp,"mcp","share_paths","共享本地文件路径","false","bool")
    };
    internal ConfigDocument Config(string name) => new(Path.Combine(root,name));
    internal static void Atomic(string path,string content)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        string tmp=path+"."+Guid.NewGuid().ToString("N")+".tmp";
        try {File.WriteAllText(tmp,content);File.Move(tmp,path,true);} finally {File.Delete(tmp);}
    }
    private static JsonObject Chart(string path)
    {
        const int limit=8<<20;
        byte[] Read(Stream source)
        {
            using var mem=new MemoryStream();
            var buf=new byte[65536];int n;
            while ((n=source.Read(buf))>0) {if(mem.Length+n>limit) throw new InvalidDataException("参考谱超过 8 MiB。");mem.Write(buf,0,n);}
            return mem.ToArray();
        }
        byte[] bytes;
        if (Path.GetExtension(path).Equals(".zip",StringComparison.OrdinalIgnoreCase)) {
            using var zip=ZipFile.OpenRead(path);
            var entry=zip.Entries.Where(e=>e.Name.EndsWith(".json",StringComparison.OrdinalIgnoreCase)&&e.Length<=limit).OrderByDescending(e=>e.Name.Equals("chart.json",StringComparison.OrdinalIgnoreCase)).FirstOrDefault() ?? throw new InvalidDataException("压缩包中找不到谱面 JSON。");
            using var file=entry.Open(); bytes=Read(file);
        } else {using var file=File.OpenRead(path);bytes=Read(file);}
        var node=JsonNode.Parse(bytes);
        if (node is JsonArray array && array.Count>0) return new JsonObject{["data"]=array};
        if (node is JsonObject obj && (obj["data"]??obj["items"]) is JsonArray) return obj;
        throw new InvalidDataException("此文件缺少谱面数据。");
    }
    internal string ImportReference(string path)
    {
        var chart=Chart(path);
        var basic=chart["basic"] as JsonObject;
        var doc=new JsonObject{["basic"]=new JsonObject{["chartName"]=basic?["chartName"]?.ToString()??Path.GetFileNameWithoutExtension(path),["difficulty"]=basic?["difficulty"]?.ToString()??""},["data"]=(chart["data"]??chart["items"]).DeepClone()};
        foreach(var k in new[]{"anim_rect_slots","bgAnimKeySlots","animationRectData","defaultBackgroundSetting"}) if(chart[k]!=null) doc[k]=chart[k].DeepClone();
        string text=doc.ToJsonString(Json);var bytes=Encoding.UTF8.GetBytes(text);
        if(bytes.Length>(8<<20)) throw new InvalidDataException("参考谱超过 8 MiB。");
        string id=Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant()[..24];
        Directory.CreateDirectory(References);
        var dest=ReferenceFile(id);
        if(File.Exists(dest)) return id;
        if(Directory.EnumerateFiles(References,"*.json").Count(f=>Regex.IsMatch(Path.GetFileNameWithoutExtension(f),"^[0-9a-f]{24}$"))>=64) throw new IOException("参考库最多可保存 64 个本地工程。");
        Atomic(dest,text);return id;
    }
    internal string ReferenceFile(string id) => Regex.IsMatch(id,"^[a-f0-9]{24}$")?Path.Combine(References,id+".json"):throw new ArgumentException("无效的参考谱编号。");
    internal IEnumerable<ReferenceItem> ListReferences()
    {
        if(!Directory.Exists(References)) yield break;
        foreach(var path in Directory.EnumerateFiles(References,"*.json"))
        {
            string id=Path.GetFileNameWithoutExtension(path);
            if(!Regex.IsMatch(id,"^[0-9a-f]{24}$")) continue;
            ReferenceItem row;
            try {var doc=Chart(path);var basic=doc["basic"] as JsonObject;row=new(id,basic?["chartName"]?.ToString()??id,basic?["difficulty"]?.ToString()??"",((JsonArray)(doc["data"]??doc["items"])).Count,File.Exists(Path.ChangeExtension(path,"zip")));}
            catch(Exception ex) when(ex is IOException or JsonException or InvalidDataException) {row=new(id,id,"文件损坏",0,false);}
            yield return row;
        }
    }
    internal void RemoveReference(string id)
    {
        string json=ReferenceFile(id);
        foreach(string ext in new[]{"json","media","zip"}) File.Delete(Path.ChangeExtension(json,ext));
    }
}
