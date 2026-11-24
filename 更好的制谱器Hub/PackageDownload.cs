using Microsoft.Win32.SafeHandles;
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;

namespace RevelationHub;

internal sealed class PackageDownload(HttpClient http, string[] urls, Release release, IProgress<Transfer> progress)
{
    private const int ChunkSize = 1024 * 1024;
    private const int Parallelism = 8;
    private readonly Stopwatch reporting = Stopwatch.StartNew();
    private long downloaded;
    private int preferred;
    private string Source(int index) => new Uri(urls[index]).Host == "github.com" ? "GitHub" : "镜像";

    public async Task Fetch(string archive, CancellationToken ct)
    {
        Exception last = null;
        for (int first = 0; first < urls.Length; first++)
        {
            ct.ThrowIfCancellationRequested();
            preferred = first;
            downloaded = 0;
            lastReported = 0;
            progress.Report(new Transfer("正在连接 " + Source(first)));
            try
            {
                await Download(archive, first, ct).ConfigureAwait(false);
                progress.Report(new Transfer("正在校验 SHA-256"));
                await using var file = File.OpenRead(archive);
                var actual = await SHA256.HashDataAsync(file, ct).ConfigureAwait(false);
                if (Convert.ToHexString(actual).Equals(release.sha256, StringComparison.OrdinalIgnoreCase)) return;
                throw new InvalidDataException("文件校验不匹配。");
            }
            catch (Exception error) when (Transient(error))
            {
                ct.ThrowIfCancellationRequested();
                last = error;
            }
        }
        throw new IOException("发行包下载失败：" + last?.Message, last);
    }

    private static bool Transient(Exception e) =>
        e is HttpRequestException or IOException or InvalidDataException or OperationCanceledException or ObjectDisposedException;

    private async Task<HttpResponseMessage> Request(int source, long start, long end, CancellationToken ct)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, urls[source]);
        request.Headers.Range = new RangeHeaderValue(start, end);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(18));
        return await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token).ConfigureAwait(false);
    }

    private async Task Download(string archive, int first, CancellationToken ct)
    {
        long firstEnd = Math.Min(ChunkSize, release.size) - 1;
        using var head = await Request(first, 0, firstEnd, ct).ConfigureAwait(false);
        head.EnsureSuccessStatusCode();
        await using var output = new FileStream(archive, FileMode.Create, FileAccess.ReadWrite, FileShare.None, 1, true);
        if (head.StatusCode == HttpStatusCode.OK)
        {
            long length = await Distribution.CopyLimited(head, output, release.size, ct, bytes => Report(first, bytes)).ConfigureAwait(false);
            if (length != release.size) throw new EndOfStreamException("下载不完整。");
            return;
        }
        output.SetLength(release.size);
        int count = checked((int)((release.size + ChunkSize - 1) / ChunkSize));
        await Parallel.ForEachAsync(Enumerable.Range(0, count),
            new ParallelOptions { MaxDegreeOfParallelism = Parallelism, CancellationToken = ct },
            async (index, token) =>
            {
                long start = (long)index * ChunkSize;
                long end = Math.Min(release.size, start + ChunkSize) - 1;
                await Chunk(output.SafeFileHandle, start, end, first, index == 0 ? head : null, token).ConfigureAwait(false);
            }).ConfigureAwait(false);
    }

    private async Task Chunk(SafeFileHandle file, long next, long end, int first, HttpResponseMessage initial, CancellationToken ct)
    {
        var buffer = new byte[64 * 1024];
        int source = initial != null ? first : Volatile.Read(ref preferred);
        int failuresWithoutProgress = 0;
        while (next <= end)
        {
            ct.ThrowIfCancellationRequested();
            long before = next;
            try
            {
                using var response = initial ?? await Request(source, next, end, ct).ConfigureAwait(false);
                initial = null;
                response.EnsureSuccessStatusCode();
                var range = response.Content.Headers.ContentRange;
                if (response.StatusCode != HttpStatusCode.PartialContent || range?.Unit != "bytes" ||
                    range.From != next || range.To != end || range.Length != release.size)
                    throw new InvalidDataException("下载源返回了错误的字节区间。");
                using var stream = await response.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
                using var idle = CancellationTokenSource.CreateLinkedTokenSource(ct);
                while (next <= end)
                {
                    idle.CancelAfter(TimeSpan.FromSeconds(25));
                    var memory = buffer.AsMemory(0, (int)Math.Min(buffer.Length, end - next + 1));
                    int read = await stream.ReadAsync(memory, idle.Token).ConfigureAwait(false);
                    if (read == 0) throw new EndOfStreamException("下载分段中断。");
                    await RandomAccess.WriteAsync(file, memory[..read], next, ct).ConfigureAwait(false);
                    next += read;
                    Report(source, Interlocked.Add(ref downloaded, read));
                }
            }
            catch (Exception error) when (Transient(error))
            {
                ct.ThrowIfCancellationRequested();
                initial = null;
                failuresWithoutProgress = next > before ? 0 : failuresWithoutProgress + 1;
                if (failuresWithoutProgress >= (urls.Length - first) * 3) throw;
                int alternative = first + (source - first + 1) % (urls.Length - first);
                Interlocked.CompareExchange(ref preferred, alternative, source);
                source = alternative;
                if (failuresWithoutProgress > 1) await Task.Delay(500, ct).ConfigureAwait(false);
            }
        }
    }

    private long lastReported;
    private void Report(int source, long received)
    {
        lock (reporting)
        {
            if (received <= lastReported || (reporting.ElapsedMilliseconds < 150 && received < release.size)) return;
            lastReported = received;
            reporting.Restart();
            progress.Report(new Transfer(Source(source) + " 下载中", received, release.size));
        }
    }
}
