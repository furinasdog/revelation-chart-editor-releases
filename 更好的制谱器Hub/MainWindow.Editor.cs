using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Controls;
using System.Windows.Threading;

namespace RevelationHub;

public partial class MainWindow
{
    private readonly DispatcherTimer editorTimer = new() { Interval = TimeSpan.FromMilliseconds(900) };
    private Distribution.RunningEditor editor;
    private string openingVersion;
    private bool windowReady;
    private DateTime stopRequested;
    private DateTime firstStopAllowed;

    private void RefreshEditorActions()
    {
        foreach (var entry in displayed.Values) ((Action)entry.Card.Tag)();
    }

    private void ApplyEditorState(string version, Button button, StackPanel secondary)
    {
        bool own = editor?.Version == version;
        bool starting = openingVersion == version || (own && !windowReady);
        bool stopping = own && stopRequested != default;
        button.Content = stopping ? "停止中…" : starting ? "启动中…" : own ? "停止" : "启动";
        button.IsEnabled = own ? windowReady && !stopping : editor == null && openingVersion == null && download == null;
        string reason = openingVersion != null ? $"正在启动 v{openingVersion}" : editor != null ? $"v{editor.Version} 正在运行" :
            download != null ? "请等待当前任务完成" : null;
        button.ToolTip = own && windowReady ? "请求关闭制谱器" : button.IsEnabled ? null : reason;
        ToolTipService.SetShowOnDisabled(button,true);
        foreach (var actions in secondary.Children.OfType<WrapPanel>())
            actions.IsEnabled = !own && openingVersion != version && download == null;
    }

    private void WatchEditor()
    {
        if (openingVersion != null || lifetime.IsCancellationRequested) return;
        if (editor == null)
        {
            editor = library.FindRunningEditor();
            if (editor == null) return;
            Message($"正在启动制谱器 v{editor.Version}…");
            RefreshEditorActions();
        }
        try
        {
            editor.Process.Refresh();
            if (editor.Process.HasExited)
            {
                int code = editor.Process.ExitCode;
                Message(code == 0 ? "制谱器已退出。" : $"制谱器已退出（退出码 {code}）。");
                editor.Process.Dispose();
                editor = null;
                windowReady = false;
                stopRequested = default;
            }
            else if (!windowReady && editor.Process.MainWindowHandle != IntPtr.Zero && DateTime.UtcNow >= firstStopAllowed)
            {
                windowReady = true;
                Message($"制谱器 v{editor.Version} 窗口已打开。");
            }
            else if (stopRequested != default && DateTime.UtcNow - stopRequested > TimeSpan.FromSeconds(3))
            {
                stopRequested = default;
                Message("请在制谱器中处理当前弹窗或保存提示，再按需要点击「停止」。");
            }
            else return;
            RefreshEditorActions();
        }
        catch (Exception ex) when (ex is InvalidOperationException or Win32Exception)
        {
            // Re-discover by executable path if the process vanished while being queried.
            editor.Process.Dispose();editor=library.FindRunningEditor();windowReady=false;stopRequested=default;
            if (editor==null) Message("制谱器已退出。");
            RefreshEditorActions();
        }
    }

    private async Task ToggleEditor(string version)
    {
        if (openingVersion != null) return;
        if (editor != null)
        {
            if (editor.Version != version || !windowReady || stopRequested != default || DateTime.UtcNow < firstStopAllowed) return;
            try
            {
                if (editor.Process.CloseMainWindow())
                {
                    stopRequested = DateTime.UtcNow;
                    Message("正在请求制谱器关闭…");
                }
                else Message("请在制谱器中关闭当前弹窗后再停止。");
            }
            catch (Exception ex) when (ex is InvalidOperationException or Win32Exception) {Message(ex.Message,true);}
            RefreshEditorActions();WatchEditor();return;
        }
        if (download != null) return;
        openingVersion=version;
        firstStopAllowed=DateTime.UtcNow.AddMilliseconds(650);
        Message($"正在启动制谱器 v{version}…");
        RefreshEditorActions();
        try
        {
            var process=await Task.Run(()=>library.StartEditor(version),lifetime.Token);
            if (lifetime.IsCancellationRequested) {process.Dispose();return;}
            editor=new Distribution.RunningEditor(version,process);
        }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested) { }
        catch (Exception ex) {Message("启动失败 · " + (ex is Win32Exception { NativeErrorCode: 193 } ? "程序格式无效，请校验或修复此版本。" : ex.Message), true);}
        finally
        {
            openingVersion=null;
            if (!lifetime.IsCancellationRequested) RefreshEditorActions();
        }
    }
}
