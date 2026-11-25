using System;
using System.Collections.Concurrent;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;
using RevelationHub;

internal partial class Program
{
    private sealed class RangeServer(byte[] data) : HttpMessageHandler
    {
        internal bool DropPrimary, RecoverPrimary, IgnoreRange, RejectRange, PrefixOnly, WrongRange, Damaged;
        internal int Peak, Calls, Mirrors, Primary;
        internal readonly ConcurrentBag<(long Start, long End)> Requests = new();
        private int active;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage req, CancellationToken ct)
        {
            Interlocked.Increment(ref Calls);
            bool primary = req.RequestUri.Host == "github.com";
            if (primary) Interlocked.Increment(ref Primary); else Interlocked.Increment(ref Mirrors);
            int live = Interlocked.Increment(ref active);
            int peak;
            do { peak = Peak; } while (peak < live && Interlocked.CompareExchange(ref Peak, live, peak) != peak);
            try
            {
                await Task.Delay(8, ct);
                var range = req.Headers.Range?.Ranges.Single();
                if (RecoverPrimary && ((primary && Primary == 1) || (!primary && range?.From > 0)))
                    return new HttpResponseMessage(HttpStatusCode.ServiceUnavailable);
                if (RejectRange && range != null) return new HttpResponseMessage(HttpStatusCode.RequestedRangeNotSatisfiable);
                if (IgnoreRange || range == null || (PrefixOnly && range.From > 0))
                    return new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(data) };
                long from = range.From.Value, end = range.To.Value;
                Requests.Add((from,end));
                if (DropPrimary && primary && from != 0) return new HttpResponseMessage(HttpStatusCode.ServiceUnavailable);
                int count = checked((int)(end - from + 1));
                if (DropPrimary && primary) count /= 2;
                var content = new ByteArrayContent(data, (int)from, count);
                if (Damaged && primary) content = new ByteArrayContent(new byte[count]);
                content.Headers.ContentRange = new ContentRangeHeaderValue(from + (WrongRange && primary && end > from ? 1 : 0), end, data.Length);
                return new HttpResponseMessage(HttpStatusCode.PartialContent) { Content = content };
            }
            finally { Interlocked.Decrement(ref active); }
        }
    }

    private static async Task CheckDownloads()
    {
        byte[] payload = new byte[32 * 1024 * 1024 + 137];
        new Random(3).NextBytes(payload);
        var release = new Release { size = payload.Length, sha256 = Convert.ToHexString(SHA256.HashData(payload)) };
        var work = Directory.CreateTempSubdirectory("hub-ranges-");
        var path = Path.Combine(work.FullName, "asset");
        var urls = new[] { "https://github.com/test", "https://mirror.example/test" };
        async Task Fetch(RangeServer server, CancellationToken token = default)
        {
            using var client = new HttpClient(server);
            await new PackageDownload(client, urls, release, new Observer()).Fetch(path, token);
            Check(File.ReadAllBytes(path).SequenceEqual(payload), "All output bytes match the fixture");
        }
        try
        {
            var fast = new RangeServer(payload);
            await Fetch(fast);
            Check(fast.Peak > 1 && fast.Peak <= ParallelTransfer.MaxConnections && fast.Mirrors == 0, $"GitHub parallel requests peak={fast.Peak}, requests={fast.Calls}");
            var ranges = new DownloadRanges(0, 16L << 20);
            var first = ranges.Take();
            ranges.Reserve(first, 65536);
            var second = ranges.Take();
            long boundary = ranges.EndOf(first);
            ranges.Advance(first, 65536);
            ranges.Finish(second);
            var stolen = ranges.Take();
            Check(stolen.Next < boundary && stolen.End == boundary && stolen.Next >= first.Next + 65536, "Idle worker takes the remaining tail of an active range");
            var broken = new RangeServer(payload) { DropPrimary = true };
            await Fetch(broken);
            Check(broken.Mirrors > 0 && broken.Requests.Any(r => r.Start == 524288), "Mirror resumes prefix at the exact interrupted offset");
            var recovered = new RangeServer(payload) { RecoverPrimary = true };
            await Fetch(recovered);
            Check(recovered.Mirrors > 0 && recovered.Primary > 1, "Mirror workers retry recovered GitHub source");
            var noRange = new RangeServer(payload) { IgnoreRange = true };
            await Fetch(noRange);
            Check(noRange.Calls == 1, "HTTP 200 streamed once");
            var rejectsRange = new RangeServer(payload) { RejectRange = true };
            await Fetch(rejectsRange);
            Check(rejectsRange.Calls == 2, "HTTP 416 retries without Range");
            await Fetch(new RangeServer(payload) { PrefixOnly = true });
            var corrupt = new RangeServer(payload) { Damaged = true };
            await Fetch(corrupt);
            Check(corrupt.Mirrors > 0, "Bad digest recovered from independent mirror");
            var wrong = new RangeServer(payload) { WrongRange = true };
            await Fetch(wrong);
            Check(wrong.Mirrors > 0, "Incorrect Content-Range rejected before writing");
            File.WriteAllText(path,"previous");
            using var abort = new CancellationTokenSource(12);
            try { await Fetch(new RangeServer(payload), abort.Token); throw new Exception("Cancellation ignored"); }
            catch (OperationCanceledException) { }
            Check(File.ReadAllText(path) == "previous" && Directory.GetFiles(work.FullName).Length == 1, "Cancellation preserves previous target and releases partial file");
        }
        finally { work.Delete(true); }
    }

    private static async Task CheckCuda(string descriptor, string archive)
    {
        var work = Directory.CreateTempSubdirectory("hub-cuda-");
        try
        {
            var routes = new Routes { Archive=archive, RejectPrimary=true };
            using var http = new HttpClient(routes);
            var library = new Distribution(work.FullName, http);
            var package = Distribution.ReadCatalog(File.ReadAllText(descriptor), "cuda").Single();
            string app = Path.Combine(library.Versions,package.version,Distribution.Editor);
            Directory.CreateDirectory(app);
            File.Copy(descriptor,Path.Combine(app,"cuda-addon.signed.json"));
            Directory.CreateDirectory(Path.Combine(library.Versions,"1.1.1",Distribution.Editor));
            Check(library.CudaFor("1.1.1")==null && library.CudaFor(package.version) is { Installed:false }, "Legacy version hides CUDA, compatible version starts in CPU mode");
            await library.ChangeCuda(package.version,true,new Observer(),default);
            Check(library.CudaFor(package.version).Installed && File.Exists(Path.Combine(app,"cuda","onnxruntime_providers_cuda.dll")), "Signed CUDA archive installed from simulated mirror");
            await library.ChangeCuda(package.version,false,new Observer(),default);
            Check(!library.CudaFor(package.version).Installed && !Directory.Exists(Path.Combine(app,"cuda")), "CUDA removed without replacing the base installation");
        }
        finally { work.Delete(true); }
    }
}
