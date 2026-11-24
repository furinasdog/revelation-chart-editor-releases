using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace RevelationHub;

public partial class MainWindow
{
    private sealed record DialogMessage(string Key, string Title, string Body, string[] Receipts,
        string ActionLabel = null, Action Action = null, string CloseLabel = "知道了");

    private readonly List<DialogMessage> pendingDialogs = new();
    private HashSet<string> acknowledged;
    private DialogMessage activeDialog;
    private bool dismissing;
    private IInputElement restoreFocus;
    private Task<Notice[]> noticeRequest;
    private string ReceiptPath => Path.Combine(library.Root, "acknowledgements.json");

    private HashSet<string> Acknowledged
    {
        get
        {
            if (acknowledged != null) return acknowledged;
            try { acknowledged = JsonSerializer.Deserialize<HashSet<string>>(File.ReadAllText(ReceiptPath)); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException) { }
            return acknowledged ??= new();
        }
    }

    private static string Receipt(Notice notice) => "notice/" + Convert.ToHexString(
        SHA256.HashData(Encoding.UTF8.GetBytes(notice.title + "\0" + notice.body)));

    private async void NoticesClick(object sender, RoutedEventArgs e) => await ReadNotices(true);

    private async Task ReadNotices(bool manual = false)
    {
        var request = noticeRequest ??= services.Notices(lifetime.Token);
        try
        {
            var items = await request;
            if (lifetime.IsCancellationRequested || (!manual && !options.Announcements)) return;
            var visible = items.Distinct().Where(n => manual || !Acknowledged.Contains(Receipt(n))).ToArray();
            if (!manual && visible.Length == 0) return;
            string body = visible.Length == 0 ? "暂无发行公告。" :
                string.Join("\n\n", visible.Select(n => n.title + "\n" + n.body));
            ShowDialogMessage(new("notices", "发行公告", body, visible.Select(Receipt).ToArray()), manual);
        }
        catch (OperationCanceledException) { }
        catch (Exception) when (!lifetime.IsCancellationRequested)
        {
            if (manual) ShowDialogMessage(new("notices", "发行公告", "暂时无法读取公告，请稍后再试。", []),true);
        }
        finally { if (noticeRequest == request) noticeRequest = null; }
    }

    private void AnnounceEditorUpdate()
    {
        var latest = available.OrderByDescending(r => Version.Parse(r.version)).FirstOrDefault();
        var installed = library.LocalVersions().Select(Version.Parse).OrderDescending().FirstOrDefault();
        if (latest == null || installed == null || Version.Parse(latest.version) <= installed) return;
        string key = "editor/" + latest.version;
        ShowDialogMessage(new(key, $"制谱器 v{latest.version} 可更新",
            $"当前已安装 v{installed}。\n\n{latest.notes}", [key], "查看更新", () => Navigate("已安装"), "稍后"));
    }

    private void AnnounceHubUpdate(Release release, bool ready, bool manual)
    {
        string key = "hub/" + release.version;
        string status = ready ? "新版已下载并通过校验。可以现在重启并更新，也可以在退出 Hub 时安装。"
                              : "正在下载新版。你可以继续使用 Hub，下载进度可在底栏查看。";
        ShowDialogMessage(new(key, $"Hub v{release.version} 可更新", status + "\n\n" + release.notes, [key],
            ready ? "重启并更新" : null, ready ? RestartForUpdate : null, ready ? "稍后" : "知道了"), manual);
    }

    private void RestartForUpdate()
    {
        if (download != null || readyVersion == null) return;
        reopenAfterUpdate = true;
        Close();
    }

    private void ShowDialogMessage(DialogMessage message, bool force = false)
    {
        if (lifetime.IsCancellationRequested || closing) return;
        if (!force && message.Receipts.Length > 0 && message.Receipts.All(Acknowledged.Contains)) return;
        if (activeDialog?.Key == message.Key && !dismissing)
        {
            DisplayDialog(message, false);
            return;
        }
        int index = pendingDialogs.FindIndex(p => p.Key == message.Key);
        if (index >= 0) pendingDialogs[index] = message;
        else pendingDialogs.Add(message);
        if (activeDialog == null) NextDialog();
    }

    private void NextDialog()
    {
        if (pendingDialogs.Count == 0 || lifetime.IsCancellationRequested) return;
        var message = pendingDialogs[0];
        pendingDialogs.RemoveAt(0);
        if (!FeedbackOverlay.IsVisible)
        {
            restoreFocus = Keyboard.FocusedElement;
            FeedbackOverlay.Visibility = Visibility.Visible;
            Workspace.IsEnabled = TitleBar.IsEnabled = false;
        }
        DisplayDialog(message, true);
    }

    private void DisplayDialog(DialogMessage message, bool entering)
    {
        activeDialog = message;
        DialogTitle.Text = message.Title;
        DialogText.Text = message.Body;
        FeedbackOk.Content = message.CloseLabel;
        DialogAction.Content = message.ActionLabel;
        DialogAction.Visibility = message.Action == null ? Visibility.Collapsed : Visibility.Visible;
        UpdateDialogAction();
        if (!entering) return;
        DialogScroll.ScrollToHome();
        FeedbackOverlay.BeginAnimation(OpacityProperty,null);
        FeedbackOverlay.Opacity = 1;
        EnterView(FeedbackCard,0,12,220);
        if (AnimateControls) FeedbackOverlay.BeginAnimation(OpacityProperty,Ease(0,1,150));
        FeedbackOk.Focus();
    }

    private void UpdateDialogAction() =>
        DialogAction.IsEnabled = activeDialog?.Key.StartsWith("hub/",StringComparison.Ordinal) != true || download == null;

    private void FeedbackClick(object sender, RoutedEventArgs e)
    {
        FeedbackButton.Focus();
        ShowDialogMessage(new("feedback", "问题反馈", "请在制谱师/企划群中 @短夜月 反馈", []), true);
    }

    private void FeedbackKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Escape) return;
        e.Handled = true;
        CloseDialog(false);
    }

    private void DismissFeedback(object sender, RoutedEventArgs e) => CloseDialog(false);
    private void InvokeDialogAction(object sender, RoutedEventArgs e) => CloseDialog(true);

    private async void CloseDialog(bool invoke)
    {
        if (dismissing || activeDialog == null) return;
        dismissing = true;
        var message = activeDialog;
        if (message.Receipts.Length > 0)
        {
            Acknowledged.UnionWith(message.Receipts);
            try { EditorProfile.Atomic(ReceiptPath, JsonSerializer.Serialize(Acknowledged)); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
        }
        if (AnimateControls)
        {
            double opacity = FeedbackOverlay.Opacity;
            FeedbackOverlay.Opacity = 0;
            FeedbackOverlay.BeginAnimation(OpacityProperty,Ease(opacity,0,130));
            await Task.Delay(130);
        }
        if (lifetime.IsCancellationRequested) return;
        activeDialog = null;
        dismissing = false;
        FeedbackOverlay.Visibility = Visibility.Collapsed;
        Workspace.IsEnabled = TitleBar.IsEnabled = true;
        if (restoreFocus is UIElement { IsVisible:true, IsEnabled:true } element) element.Focus();
        restoreFocus = null;
        if (invoke) message.Action?.Invoke();
        NextDialog();
    }
}
