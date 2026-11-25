using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Threading;
using System.Threading.Tasks;

namespace RevelationHub;

internal sealed class RangeUnavailableException() : IOException("下载源不支持分段读取。");

internal sealed class DownloadSource(HttpClient http, string[] urls, int first, bool isolate)
{
    private int preferred = first;
    internal int Preferred => Volatile.Read(ref preferred);
    internal int Count => isolate ? 1 : urls.Length;
    internal static string[] GitHubAsset(string url) =>
        [url, "https://gh-proxy.org/" + url, "https://ghfast.top/" + url];
    internal static string Label(string url) => new Uri(url).Host is "github.com" or "raw.githubusercontent.com" ? "GitHub" : "镜像";
    internal string Label(int index) => Label(urls[index]);

    internal int AfterFailure(int index)
    {
        int next = isolate ? index : (index + 1) % urls.Length;
        Interlocked.CompareExchange(ref preferred, next, index);
        return next;
    }

    internal async Task<HttpResponseMessage> Open(int index, long start, long end, CancellationToken ct, bool whole = false)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, urls[index]);
        if (!whole) request.Headers.Range = new RangeHeaderValue(start, end - 1);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(18));
        return await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token).ConfigureAwait(false);
    }

    internal static void CheckRange(HttpResponseMessage response, long next, long end, long size)
    {
        if (response.StatusCode is HttpStatusCode.OK or HttpStatusCode.RequestedRangeNotSatisfiable)
            throw new RangeUnavailableException();
        response.EnsureSuccessStatusCode();
        var range = response.Content.Headers.ContentRange;
        if (response.StatusCode != HttpStatusCode.PartialContent || range?.Unit != "bytes" ||
            range.From != next || range.To != end - 1 || range.Length != size)
            throw new InvalidDataException("下载源返回了错误的字节区间。");
    }

    internal static bool Retryable(Exception error) =>
        error is HttpRequestException or IOException or InvalidDataException or OperationCanceledException or ObjectDisposedException;
}
