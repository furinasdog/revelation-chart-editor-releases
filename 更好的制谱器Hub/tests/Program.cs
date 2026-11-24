using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Threading;
using System.Threading.Tasks;
using RevelationHub;

internal partial class Program
{
    sealed class Routes : HttpMessageHandler
    {
        public string Archive, Catalog;
        public bool RejectPrimary, SupportRanges;
        private int cut;
        public bool Resumed;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage req, CancellationToken cancellation)
        {
            var response = new HttpResponseMessage(HttpStatusCode.OK);
            if (RejectPrimary && req.RequestUri.Host is "raw.githubusercontent.com" or "github.com")
                response.StatusCode = HttpStatusCode.ServiceUnavailable;
            else if (req.RequestUri.AbsolutePath.EndsWith(".json"))
                response.Content = new StringContent(File.ReadAllText(Catalog));
            else if (SupportRanges && req.Headers.Range?.Ranges.SingleOrDefault() is {From: long from, To: long to})
            {
                using var file = File.OpenRead(Archive);
                int count = checked((int)(to - from + 1));
                if (from == 0 && Interlocked.Exchange(ref cut, 1) == 0) count /= 2;
                if (from == 524288) Resumed = true;
                file.Position = from;
                byte[] bytes = new byte[count];
                file.ReadExactly(bytes);
                response.StatusCode = HttpStatusCode.PartialContent;
                response.Content = new ByteArrayContent(bytes);
                response.Content.Headers.ContentRange = new ContentRangeHeaderValue(from, to, file.Length);
            }
            else
                response.Content = new StreamContent(File.OpenRead(Archive));
            return Task.FromResult(response);
        }
    }
    sealed class Observer : IProgress<Transfer>
    {
        public bool Bytes, Verifying, Installing, Mirror;
        public bool Log;
        private readonly Stopwatch clock = Stopwatch.StartNew();
        public void Report(Transfer t) {
            Bytes |= t.Bytes > 0 && t.Total >= t.Bytes;
            Verifying |= t.Stage.Contains("校验");
            Installing |= t.Stage.Contains("安装");
            Mirror |= t.Stage.Contains("镜像");
            if (Log && (t.Total == 0 || clock.Elapsed.TotalSeconds >= 15 || t.Bytes == t.Total))
            {
                Console.WriteLine($"{t.Stage} {t.Bytes/1048576.0:F1} / {t.Total/1048576.0:F1} MiB");
                clock.Restart();
            }
        }
    }
    static void Check(bool ok,string label) { if (!ok) throw new Exception(label); Console.WriteLine(label); }
    static async Task CheckLaunch(Distribution service, string work)
    {
        string executable = service.Executable("1.1.0");
        var start = new ProcessStartInfo(executable)
        {
            WorkingDirectory = Path.GetDirectoryName(executable),
            UseShellExecute = false,
            CreateNoWindow = true
        };
        foreach (string arg in new[] { "--headless", "--quit-after", "8" })
            start.ArgumentList.Add(arg);
        start.Environment["APPDATA"] = Directory.CreateDirectory(Path.Combine(work, "profile")).FullName;
        using var child = Process.Start(start);
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(60));
        try { await child.WaitForExitAsync(timeout.Token); }
        catch (OperationCanceledException) { child.Kill(true); throw; }
        Check(child.ExitCode == 0, "Installed editor started with its packaged resources");
    }
    static async Task Main(string[] args)
    {
        if (args is ["--layout", var output]) { await CheckLayout(output);return; }
        if (args is ["--notices", var captures]) { await CheckLayout(captures,noticesOnly:true);return; }
        if (args is ["--layout", var screenshots, var editorDirectory]) { await CheckLayout(screenshots,editorDirectory);return; }
        if (args is ["--management",var oldZip,var nextZip,var delta,var signedCatalog]) { await CheckManagement(oldZip,nextZip,delta,signedCatalog);return; }
        if (args is ["--hub", var msi, var manifest, var editorCatalog])
        {
            await CheckHubServices(msi, manifest, editorCatalog);
            return;
        }
        var work = Directory.CreateDirectory(Path.Combine(Path.GetTempPath(), "revelation-hub-" + Guid.NewGuid().ToString("N"))).FullName;
        var routes = new Routes {Archive=args[0],Catalog=args[1],RejectPrimary=true,SupportRanges=true};
        using var http = new HttpClient(routes);
        try {
            var service = new Distribution(work,http);
            var releases = await service.Refresh(CancellationToken.None);
            var r = releases.Single(x=>x.version=="1.1.0");
            Check(service.CatalogSource.Contains("镜像"),"Mirror catalog fallback");
            var observer = new Observer();
            await service.Install(r,observer,CancellationToken.None);
            Check(routes.Resumed, "Interrupted byte range resumed at the first missing byte");
            Check(service.Installed(r.version) && service.LocalVersions().Contains(r.version),"Verified ZIP installed atomically");
            Check(observer.Bytes && observer.Mirror && observer.Verifying && observer.Installing,"Download progress, mirror, verification and installation");
            Check(File.Exists(Path.ChangeExtension(service.Executable(r.version),".pck")),"Launch target and resources");
            await CheckLaunch(service,work);
            // A damaged response of the right length must still fail the signed digest.
            var data=File.ReadAllBytes(args[0]);
            data[100]^=1;
            var bad=Path.Combine(work,"damaged.zip");
            File.WriteAllBytes(bad,data);
            var invalidRoot=Path.Combine(work,"invalid");
            var corrupt=new Distribution(invalidRoot,new HttpClient(new Routes{Archive=bad,Catalog=args[1]}));
            try { await corrupt.Install(r,new Observer(),CancellationToken.None); throw new Exception("Accepted a modified file"); }
            catch(IOException) { Check(!corrupt.Installed(r.version) && !Directory.EnumerateFileSystemEntries(Path.Combine(invalidRoot,"staging")).Any(),"Corruption rejected and temporary data cleared"); }
            using var cancel = new CancellationTokenSource(); cancel.Cancel();
            try { await corrupt.Install(r,new Observer(),cancel.Token); throw new Exception("Cancellation ignored"); }
            catch(OperationCanceledException) { Check(!corrupt.Installed(r.version),"Cancellation preserved library"); }
            if(args.Contains("--live")){
                using var online=new HttpClient { Timeout=Timeout.InfiniteTimeSpan };
                online.DefaultRequestHeaders.UserAgent.ParseAdd("RevelationHub/1.1");
                var releaseLibrary=new Distribution(Path.Combine(work,"live"),online);
                var result=await releaseLibrary.Refresh(CancellationToken.None);
                Check(releaseLibrary.CatalogSource.Contains("同步"),"Live signed catalog: "+releaseLibrary.CatalogSource);
                var progress=new Observer { Log=true };
                await releaseLibrary.Install(result.Single(x=>x.version=="1.1.0"),progress,CancellationToken.None);
                Check(releaseLibrary.Installed("1.1.0"),"Live release download and install; mirror="+progress.Mirror);
            }
        } finally { Directory.Delete(work,true); }
    }

    static async Task CheckHubServices(string msi, string manifest, string editorCatalog)
    {
        var work = Directory.CreateTempSubdirectory("revelation-hub-services-");
        try
        {
            var routes = new Routes { Archive=msi, Catalog=manifest, RejectPrimary=true };
            using var http = new HttpClient(routes);
            var services = new HubServices(work.FullName, http);
            string signed = File.ReadAllText(manifest);
            var newest = Distribution.ReadCatalog(signed, "hub")[0];
            var progress = new Observer();
            var ct = CancellationToken.None;
            bool offered = false;
            string version = await services.Prepare(new Version(1,1,1), progress, ct, release =>
            {
                offered = release.version == newest.version && !progress.Bytes;
                return Task.CompletedTask;
            });
            Check(offered, "A verified release is offered before downloading the MSI");
            string staged = Path.Combine(work.FullName, "updates", Path.GetFileName(msi));
            Check(version == newest.version && File.Exists(staged) && progress.Bytes && progress.Mirror, "Signed MSI staged through the mirror with progress");
            Check(await services.Prepare(Version.Parse(version), progress, ct) == null, "Current Hub skips installation");
            try { Distribution.ReadCatalog(File.ReadAllText(editorCatalog), "hub"); throw new Exception("Accepted editor catalog for self update"); }
            catch (InvalidDataException) { Check(true, "Editor catalog rejected for self update"); }
            using (var file = File.OpenWrite(staged)) { file.Position = 64; file.WriteByte(0x2a); file.SetLength(file.Length - 1); }
            Check(await HubServices.InstallVerified(staged, version) == 3, "Damaged MSI rejected before Windows Installer");
            Check(await services.Prepare(new Version(1,1,1), progress, ct) == version && new FileInfo(staged).Length == newest.size, "Damaged staging recovered");
            string notices = Path.Combine(work.FullName, "orig-notices.json");
            routes.Catalog = notices;
            File.WriteAllText(notices, "{}");
            Check((await services.Notices(ct)).Any(), "First offline launch can display bundled announcements");
            File.WriteAllText(notices, """{"schema":1,"items":[{"title":"更新","body":"编辑器已发布"}]}""");
            Check((await services.Notices(ct)).Single().body == "编辑器已发布", "Raw announcement decoded");
            File.WriteAllText(notices, "{}");
            Check((await services.Notices(ct)).Single().title == "更新", "Invalid response keeps cached notice");
            File.WriteAllText(notices, """{"schema":1,"items":[]}""");
            Check((await services.Notices(ct)).Length == 0, "An empty feed clears notices");
            string exe = Path.Combine(work.FullName, "RevelationHub.exe");
            string link = Path.Combine(work.FullName, "更好的制谱器 Hub.lnk");
            Shortcuts.WriteLink(work.FullName, exe, true);
            Check(File.Exists(link), "Windows shortcut created");
            Shortcuts.WriteLink(work.FullName, exe, false);
            Check(!File.Exists(link), "Matching Windows shortcut removed");
        }
        finally { work.Delete(true); }
    }
}
