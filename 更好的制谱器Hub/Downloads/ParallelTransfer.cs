using System;
using System.IO;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

namespace RevelationHub;

internal sealed class ParallelTransfer(DownloadSource sources, long size, Action<int, long> progress)
{
    internal const int MaxConnections = 8;
    private long received;

    internal async Task Run(SafeFileHandle file, int first, HttpResponseMessage initial, long firstEnd, CancellationToken ct)
    {
        var tail = new DownloadRanges(firstEnd, size);
        var prefix = new DownloadRanges(0, firstEnd);
        using var workers = CancellationTokenSource.CreateLinkedTokenSource(ct);
        async Task Worker(bool ownsPrefix)
        {
            try
            {
                if (ownsPrefix)
                    await ReadPiece(file, prefix, prefix.Take(), first, initial, workers.Token).ConfigureAwait(false);
                while (tail.Take() is { } piece)
                {
                    await ReadPiece(file, tail, piece, sources.Preferred, null, workers.Token).ConfigureAwait(false);
                    tail.Finish(piece);
                }
            }
            catch (OperationCanceledException) when (workers.IsCancellationRequested && !ct.IsCancellationRequested) { }
            catch { workers.Cancel(); throw; }
        }

        var tasks = new Task[(int)Math.Min(MaxConnections, 1 + (size - 1) / DownloadRanges.MinimumPiece)];
        for (int i = 0; i < tasks.Length; i++)
        {
            bool ownsPrefix = i == 0;
            tasks[i] = Task.Run(() => Worker(ownsPrefix), workers.Token);
        }
        await Task.WhenAll(tasks).ConfigureAwait(false);
    }

    private async Task ReadPiece(SafeFileHandle file, DownloadRanges ranges, DownloadRanges.Piece piece,
        int source, HttpResponseMessage initial, CancellationToken ct)
    {
        var buffer = new byte[64 * 1024];
        int consecutiveFailures = 0;
        while (piece.Next < ranges.EndOf(piece))
        {
            ct.ThrowIfCancellationRequested();
            long before = piece.Next;
            long requestEnd = ranges.EndOf(piece);
            try
            {
                using var response = initial ?? await sources.Open(source, before, requestEnd, ct).ConfigureAwait(false);
                initial = null;
                DownloadSource.CheckRange(response, before, requestEnd, size);
                using var stream = await response.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
                using var idle = CancellationTokenSource.CreateLinkedTokenSource(ct);
                for (int count; (count = ranges.Reserve(piece, buffer.Length)) > 0;)
                {
                    idle.CancelAfter(TimeSpan.FromSeconds(25));
                    int read = await stream.ReadAsync(buffer.AsMemory(0, count), idle.Token).ConfigureAwait(false);
                    if (read == 0) throw new EndOfStreamException("下载分段中断。");
                    await RandomAccess.WriteAsync(file, buffer.AsMemory(0, read), piece.Next, ct).ConfigureAwait(false);
                    ranges.Advance(piece, read);
                    progress(source, Interlocked.Add(ref received, read));
                }
            }
            catch (Exception error) when (DownloadSource.Retryable(error))
            {
                ct.ThrowIfCancellationRequested();
                consecutiveFailures = piece.Next > before ? 0 : consecutiveFailures + 1;
                if (consecutiveFailures >= sources.Count * 2) throw;
                source = sources.AfterFailure(source);
                if (consecutiveFailures > 1) await Task.Delay(250, ct).ConfigureAwait(false);
            }
        }
    }
}
