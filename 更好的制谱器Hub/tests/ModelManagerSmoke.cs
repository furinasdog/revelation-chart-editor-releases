using System;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using RevelationHub;

internal partial class Program
{
    private static async Task CheckOnlineModel(string model, string profileRoot)
    {
        if (model is not ("madmom" or "music2emo" or "htdemucs") || Directory.Exists(profileRoot))
            throw new ArgumentException("Specify a model and a new isolated profile directory.");
        Environment.SetEnvironmentVariable($"AUTOREVELATION_{model.ToUpperInvariant()}_MODELS", null);
        using var http = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
        http.DefaultRequestHeaders.UserAgent.ParseAdd("RevelationHub/" + HubServices.Current.ToString(3));
        var models = new EditorModels(new EditorProfile(profileRoot), http);
        using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(12));
        await models.Install(model, new Observer { Log = true }, timeout.Token);
        Check(models.Verify(model, timeout.Token).Count == 0, $"Online installation of {model} verified at {models.Location(model)}");
    }

    private sealed class LocalModelSource(string madmom, string stems) : HttpMessageHandler
    {
        internal int Requests;

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            var uri = request.RequestUri;
            const string madmomPrefix = "/alumkal/madmom_models/1491c42703e177b812a8eb49a78e49438861ae36/";
            const string stemsPath = "/StemSplitio/htdemucs-onnx/resolve/d54ed9eb60e258ea82131c6ee14578628816456a/htdemucs_fp16weights.onnx";
            string source = uri.Host switch
            {
                "raw.githubusercontent.com" when uri.AbsolutePath.StartsWith(madmomPrefix) =>
                    Path.Combine(madmom, uri.AbsolutePath[madmomPrefix.Length..]),
                "huggingface.co" when uri.AbsolutePath == stemsPath => Path.Combine(stems, Path.GetFileName(stemsPath)),
                _ => throw new InvalidOperationException("Unexpected model source " + uri)
            };
            Requests++;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StreamContent(File.OpenRead(source)) });
        }
    }

    private static async Task CheckModels(string madmom, string emotion, string stems)
    {
        var temp = Directory.CreateTempSubdirectory("revelation-models-");
        try
        {
            // Keep all install/repair/remove operations in this test profile even if the caller has overrides.
            foreach (string key in new[] {"MADMOM", "MUSIC2EMO", "HTDEMUCS"})
                Environment.SetEnvironmentVariable($"AUTOREVELATION_{key}_MODELS", null);
            var profile = new EditorProfile(temp.FullName);
            var source = new LocalModelSource(madmom, stems);
            using var http = new HttpClient(source);
            var models = new EditorModels(profile, http);
            var ct = CancellationToken.None;
            var progress = new Observer();
            string legacy = Path.Combine(temp.FullName, "music2emo-models");
            Directory.CreateDirectory(legacy);
            foreach (var file in models.Files("music2emo"))
                File.Copy(Path.Combine(emotion, file.path), Path.Combine(legacy, file.path));
            Check(models.Location("music2emo") == legacy, "Existing Music2Emo installation is reused");
            foreach (string id in new[] { "music2emo", "madmom", "htdemucs" })
            {
                await models.Install(id, progress, ct);
                Check(models.Verify(id, ct).Count == 0, $"Verified real {id} weights");
                int previousRequests = source.Requests;
                await models.Install(id, progress, ct);
                Check(previousRequests == source.Requests, $"Complete {id} install works offline");
            }
            var first = models.Files("madmom").First();
            using (var damaged = File.Open(Path.Combine(models.Location("madmom"), first.path), FileMode.Open, FileAccess.ReadWrite))
            {
                int original = damaged.ReadByte();
                damaged.Position = 0;
                damaged.WriteByte((byte)(original ^ 0xff));
            }
            Check(models.Verify("madmom", ct).SequenceEqual(new[]{first.path}), "Identifies a damaged model with unchanged size");
            int beforeRepair = source.Requests;
            await models.Install("madmom", progress, ct);
            Check(source.Requests == beforeRepair + 1 && models.Verify("madmom", ct).Count == 0, "Repairs just the damaged weight");
            string custom = Path.Combine(models.Location("htdemucs"), "custom.txt");
            File.WriteAllText(custom, "keep");
            models.Remove("htdemucs");
            Check(models.Count("htdemucs") == 0 && File.ReadAllText(custom) == "keep", "Removes only managed weights");
        }
        finally { temp.Delete(true); }
    }
}
