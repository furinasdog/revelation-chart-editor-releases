using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;

namespace RevelationHub;

internal sealed class PackageDownload(HttpClient http, string[] urls, Release release, IProgress<Transfer> progress)
{
    public async Task Fetch(string archive, CancellationToken ct)
    {
        string partial = archive + "." + Guid.NewGuid().ToString("N") + ".part";
        Exception lastError = null;
        bool isolateSources = false;
        int attempts = urls.Length + 1;
        try
        {
            for (int attempt = 0; attempt < attempts; attempt++)
            {
                ct.ThrowIfCancellationRequested();
                int first = attempt % urls.Length;
                var sources = new DownloadSource(http, urls, first, isolateSources);
                progress.Report(new Transfer("正在连接 " + sources.Label(first)));
                try
                {
                    await Download(partial, sources, first, ct).ConfigureAwait(false);
                    progress.Report(new Transfer("正在校验 SHA-256"));
                    await using (var file = File.OpenRead(partial))
                    {
                        var digest = await SHA256.HashDataAsync(file, ct).ConfigureAwait(false);
                        if (!Convert.ToHexString(digest).Equals(release.sha256, StringComparison.OrdinalIgnoreCase))
                        {
                            // Bytes from more than one host may have contributed. Retry each host independently.
                            if (!isolateSources && sources.Count > 1)
                            {
                                isolateSources = true;
                                attempt = -1;
                                attempts = urls.Length;
                            }
                            throw new InvalidDataException("文件校验不匹配。");
                        }
                    }
                }
                catch (Exception error) when (DownloadSource.Retryable(error))
                {
                    ct.ThrowIfCancellationRequested();
                    lastError = error;
                    continue;
                }
                ct.ThrowIfCancellationRequested();
                File.Move(partial, archive, true);
                return;
            }
            throw new IOException("发行包下载失败：" + lastError?.Message, lastError);
        }
        finally { File.Delete(partial); }
    }

    private async Task Download(string path, DownloadSource sources, int first, CancellationToken ct)
    {
        long firstEnd = Math.Min(DownloadRanges.MinimumPiece, release.size);
        using var probe = await sources.Open(first, 0, firstEnd, ct).ConfigureAwait(false);
        bool retryWhole = probe.StatusCode is HttpStatusCode.RequestedRangeNotSatisfiable or HttpStatusCode.NotImplemented or HttpStatusCode.BadRequest;
        using var fallback = retryWhole ? await sources.Open(first, 0, release.size, ct, whole: true).ConfigureAwait(false) : null;
        var head = fallback ?? probe;
        head.EnsureSuccessStatusCode();

        var clock = Stopwatch.StartNew();
        long lastReported = 0;
        void Report(int source, long bytes)
        {
            lock (clock)
            {
                if (bytes <= lastReported || (bytes < release.size && clock.ElapsedMilliseconds < 150)) return;
                lastReported = bytes;
                clock.Restart();
                progress.Report(new Transfer(sources.Label(source) + " 下载中", bytes, release.size));
            }
        }

        await using var output = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.None, 1, true);
        if (head.StatusCode == HttpStatusCode.OK)
        {
            long bytes = await Distribution.CopyLimited(head, output, release.size, ct, n => Report(first, n)).ConfigureAwait(false);
            if (bytes != release.size) throw new EndOfStreamException("下载不完整。");
            return;
        }
        DownloadSource.CheckRange(head, 0, firstEnd, release.size);
        output.SetLength(release.size);
        try
        {
            await new ParallelTransfer(sources, release.size, Report).Run(output.SafeFileHandle, first, head, firstEnd, ct).ConfigureAwait(false);
        }
        catch (RangeUnavailableException)
        {
            ct.ThrowIfCancellationRequested();
            output.SetLength(0);
            lastReported = 0;
            using var entire = await sources.Open(first, 0, release.size, ct, whole: true).ConfigureAwait(false);
            entire.EnsureSuccessStatusCode();
            long bytes = await Distribution.CopyLimited(entire, output, release.size, ct, n => Report(first, n)).ConfigureAwait(false);
            if (bytes != release.size) throw new EndOfStreamException("下载不完整。");
        }
    }
}
