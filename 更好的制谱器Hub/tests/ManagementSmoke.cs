using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;
using RevelationHub;

internal partial class Program
{
    private sealed class BetaAssets(string catalog, string manifest, string archive) : HttpMessageHandler
    {
        internal int FullRequests;
        internal bool Offline;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            string name = Path.GetFileName(request.RequestUri.AbsolutePath);
            if (Offline) return Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
            HttpContent content = name switch
            {
                "catalog.signed.json" => new StreamContent(HubResources.Open("RevelationHub.catalog.signed.json")),
                "beta-catalog.signed.json" => new StreamContent(File.OpenRead(catalog)),
                _ when name == Path.GetFileName(manifest) => new StreamContent(File.OpenRead(manifest)),
                _ when name == Path.GetFileName(archive) => FullPackage(),
                _ => throw new InvalidOperationException("Unexpected asset request " + name)
            };
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = content });
        }
        private HttpContent FullPackage()
        {
            FullRequests++;
            return new StreamContent(File.OpenRead(archive));
        }
    }

    private static async Task CheckBeta(string catalog, string manifest, string archive)
    {
        var routes = new BetaAssets(catalog, manifest, archive);
        using var client = new HttpClient(routes);
        var temp = Directory.CreateTempSubdirectory("hub-beta-");
        try
        {
            var library = new Distribution(temp.FullName, client);
            var releases = await library.Refresh(default);
            var beta = releases.Single(r => EditorVersion.IsBeta(r.version));
            var stable = releases.Where(r => !EditorVersion.IsBeta(r.version)).ToArray();
            Check(stable.Length > 0 && library.CatalogSynced, "Stable and Beta signed catalogs load independently");
            Check(EditorVersion.Parse("1.5.0-beta.2").CompareTo(EditorVersion.Parse("1.5.0-beta.10")) < 0 &&
                EditorVersion.Parse("1.5.0-beta.10").CompareTo(EditorVersion.Parse("1.5.0")) < 0,
                "Numeric Beta sequence sorts ahead of older Beta and below its stable version");
            Check(Distribution.StableUpdate([beta], stable[0].version, new HashSet<string>()) == null &&
                Distribution.StableUpdate(releases, beta.version, new HashSet<string>()) == null &&
                Distribution.StableUpdate(releases, "1.0.0", new HashSet<string>())?.version == stable[0].version,
                "Beta has no update offer and stable-to-stable offers still work");
            var progress = new Observer();
            await library.Install(beta, progress, default);
            Check(library.Installed(beta.version) && library.LocalVersions().Contains(beta.version) && routes.FullRequests > 0,
                "A signed Beta installs into a recognizable local slot from the full ZIP");
            var index = Distribution.ReadSigned<FileIndex>(File.ReadAllText(manifest));
            Check(index.version == beta.version && index.patches.Length == 0 &&
                (await library.Verify(beta, progress, default)).Count == 0, "Beta assets verify and the manifest contains no delta");
            int before = routes.FullRequests;
            await library.Update(beta, beta, progress, default);
            Check(routes.FullRequests > before && library.Installed(beta.version), "Beta repair requests the full asset");
            routes.Offline = true;
            Check((await library.Refresh(default)).Any(r => r.version == beta.version) && !library.CatalogSynced,
                "A verified Beta remains recognized offline with the signed cache");
        }
        finally { temp.Delete(true); }
    }

    private sealed class LocalAssets(string full,string delta):HttpMessageHandler
    {
        internal int Patches,Full;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken ct)
        {
            bool patch=request.RequestUri.AbsolutePath.EndsWith(Path.GetFileName(delta));
            if(patch)Patches++;else if(request.RequestUri.AbsolutePath.EndsWith(Path.GetFileName(full)))Full++;
            else throw new InvalidOperationException("Unexpected request "+request.RequestUri.AbsolutePath);
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK){Content=new StreamContent(File.OpenRead(patch?delta:full))});
        }
    }
    private static async Task CheckManagement(string oldZip,string nextZip,string delta,string signedCatalog)
    {
        var temp=Directory.CreateTempSubdirectory("revelation-management-");
        try
        {
            var routes=new LocalAssets(nextZip,delta);using var http=new HttpClient(routes);
            var library=new Distribution(temp.FullName,http);var progress=new Observer();var ct=CancellationToken.None;
            var releases=Distribution.ReadCatalog(File.ReadAllText(signedCatalog));
            var old=releases.Single(r=>r.version=="1.1.0");var next=releases.Single(r=>r.version=="1.1.1");
            string slot=Path.Combine(library.Versions,old.version);ZipFile.ExtractToDirectory(oldZip,slot);
            string exe=library.Executable(old.version);
            string mine=Path.Combine(slot,Distribution.Editor,"my-chart.json");File.WriteAllText(mine,"my chart");
            await library.Update(old,next,progress,ct);
            Check(routes.Patches>0 && routes.Full==0 && library.LocalVersions().SequenceEqual(new[]{next.version}),"Only delta requested; legacy version replaced");
            Check(library.Executable(next.version)==exe && File.ReadAllText(mine)=="my chart","Path and custom chart preserved");
            Check((await library.Verify(next,progress,ct)).Count==0,"All installed files match the signed distribution");
            File.AppendAllText(Path.Combine(slot,Distribution.Editor,"README.md"),"damage");
            Check((await library.Verify(next,progress,ct)).Single().EndsWith("README.md"),"Integrity verification identifies exact damage offline");
            await library.Update(next,next,progress,ct);
            Check(routes.Full>0 && (await library.Verify(next,progress,ct)).Count==0 && File.ReadAllText(mine)=="my chart","Full repair preserves custom files");
            var alternate=new Distribution(Path.Combine(temp.FullName,"other"),http);
            string baseSlot=Path.Combine(alternate.Versions,old.version);
            ZipFile.ExtractToDirectory(oldZip,baseSlot);
            string unchanged=Directory.EnumerateFiles(Path.Combine(baseSlot,Distribution.Editor,"licenses")).First();
            File.AppendAllText(unchanged,"damage");
            int requests=routes.Full;
            await alternate.Update(old,next,progress,ct);
            Check(routes.Full>requests && (await alternate.Verify(next,progress,ct)).Count==0,"Damaged base falls back to the full package");
            using(var cancelled=new CancellationTokenSource()){
                cancelled.Cancel();try{await library.Update(next,next,progress,cancelled.Token);throw new Exception("Cancellation ignored");}
                catch(OperationCanceledException){Check(library.Installed(next.version),"Cancel leaves the installed version usable");}
            }
            string txn=Path.Combine(temp.FullName,"maintenance");Directory.CreateDirectory(txn);
            File.WriteAllText(Path.Combine(txn,"slot"),old.version);Directory.Move(slot,Path.Combine(txn,"previous"));
            var recovered=new Distribution(temp.FullName,http);Check(recovered.Installed(next.version),"Interrupted directory swap recovered");
            // Exercise deletion with a small isolated fixture, not the 1 GiB package.
            string disposable=Path.Combine(library.Versions,"0.0.5");Directory.CreateDirectory(disposable);File.WriteAllText(Path.Combine(disposable,"fixture.txt"),"fixture");
            library.RemoveVersion("0.0.5");Check(!Directory.Exists(disposable) && library.Installed(next.version),"Only selected version moved to Recycle Bin");
            var profile=new EditorProfile(Path.Combine(temp.FullName,"profile"));Directory.CreateDirectory(profile.Root);
            var cfgPath=Path.Combine(profile.Root,EditorProfile.Prefs);
            File.WriteAllText(cfgPath,"[display]\ntheme=\"dark\"\n\n[custom]\nnested={\n\"k\": 9\n}\n");
            var config=profile.Config(EditorProfile.Prefs);var theme=EditorProfile.Fields.Single(f=>f.Key=="theme");
            config.Save(new(){[theme]="gray"});Check(profile.Config(EditorProfile.Prefs).Get(theme)=="gray" && File.ReadAllText(cfgPath).Contains("\"k\": 9"),"Editor cfg edits round trip without losing unknown multiline settings");
            File.AppendAllText(cfgPath,"\n; external");try{config.Save(new(){[theme]="light"});throw new Exception("Concurrent edit lost");}catch(IOException){Check(true,"Changed editor configuration protected");}
            string refPath=Path.Combine(temp.FullName,"chart.json");File.WriteAllText(refPath,"""{"basic":{"chartName":"sample","difficulty":"HD"},"items":[{"type":"note"}]}""");
            string id=profile.ImportReference(refPath);Check(profile.ListReferences().Single() is {Title:"sample",Items:1} && id.Length==24,"Imported reference is visible in editor format");
            profile.RemoveReference(id);Check(!profile.ListReferences().Any(),"Reference removed");
            var models=new EditorModels(profile,http);Check(models.Verify("madmom",ct).Count==models.Files("madmom").Length && models.Count("music2emo")==0,"Actual model paths and offline validation");
            var options=new HubOptions(false,false,true,false);options.Save(temp.FullName);Check(HubOptions.Load(temp.FullName)==options,"Hub settings persist");
            Check(Guide.Chapters.Count>=20 && Guide.Chapters.Any(c=>c.Body.Contains("黄键")) && Guide.Chapters.Any(c=>c.Body.Contains("增量")),"Offline guides include both manuals and searchable chapters");
        }
        finally{temp.Delete(true);}
    }

    private static async Task CheckUpgrade(string oldVersion, string oldZip, string nextVersion, string full, string patch)
    {
        var temp = Directory.CreateTempSubdirectory("hub-release-upgrade-");
        try
        {
            var routes = new LocalAssets(full, patch);
            using var http = new HttpClient(routes);
            var library = new Distribution(temp.FullName, http);
            string slot = Path.Combine(library.Versions, oldVersion);
            ZipFile.ExtractToDirectory(oldZip, slot);
            string chart = Path.Combine(slot, Distribution.Editor, "personal-chart.json");
            File.WriteAllText(chart, "{}");
            await using var archive = File.OpenRead(full);
            var next = new Release { version = nextVersion, size = archive.Length,
                sha256 = Convert.ToHexString(await SHA256.HashDataAsync(archive)) };
            var progress = new Observer();
            await library.Update(new Release { version = oldVersion }, next, progress, default);
            Check(routes.Patches == 1 && routes.Full == 0 && library.Installed(nextVersion), "Signed delta updates the existing slot");
            Check(File.ReadAllText(chart) == "{}" && (await library.Verify(next, progress, default)).Count == 0,
                "Personal chart preserved and all distribution files verified offline");
        }
        finally { temp.Delete(true); }
    }
}
