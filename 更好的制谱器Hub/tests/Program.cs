using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using RevelationHub;

internal class Program
{
    sealed class Routes : HttpMessageHandler
    {
        public string Archive, Catalog;
        public bool RejectPrimary;
        public readonly List<Uri> Requests = new();
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage req, CancellationToken cancellation)
        {
            Requests.Add(req.RequestUri);
            var response = new HttpResponseMessage(HttpStatusCode.OK);
            if (RejectPrimary && req.RequestUri.Host is "raw.githubusercontent.com" or "github.com")
                response.StatusCode = HttpStatusCode.ServiceUnavailable;
            else if (req.RequestUri.AbsolutePath.EndsWith(".json"))
                response.Content = new StringContent(File.ReadAllText(Catalog));
            else
                response.Content = new StreamContent(File.OpenRead(Archive));
            return Task.FromResult(response);
        }
    }
    sealed class Observer : IProgress<Transfer>
    {
        public bool Bytes, Verifying, Installing, Mirror;
        public void Report(Transfer t) {
            Bytes |= t.Bytes > 0 && t.Total >= t.Bytes;
            Verifying |= t.Stage.Contains("校验");
            Installing |= t.Stage.Contains("安装");
            Mirror |= t.Stage.Contains("镜像");
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
        var work = Directory.CreateDirectory(Path.Combine(Path.GetTempPath(), "revelation-hub-" + Guid.NewGuid().ToString("N"))).FullName;
        using var http = new HttpClient(new Routes {Archive=args[0],Catalog=args[1],RejectPrimary=true});
        try {
            var service = new Distribution(work,http);
            var releases = await service.Refresh(CancellationToken.None);
            var r = releases.Single(x=>x.version=="1.1.0");
            Check(service.CatalogSource.Contains("镜像"),"Mirror catalog fallback");
            var observer = new Observer();
            await service.Install(r,observer,CancellationToken.None);
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
                var progress=new Observer();
                await releaseLibrary.Install(result.Single(x=>x.version=="1.1.0"),progress,CancellationToken.None);
                Check(releaseLibrary.Installed("1.1.0"),"Live release download and install; mirror="+progress.Mirror);
            }
        } finally { Directory.Delete(work,true); }
    }
}
