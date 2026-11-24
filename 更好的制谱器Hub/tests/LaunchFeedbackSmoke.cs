using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using RevelationHub;

internal partial class Program
{
    private static void CheckLaunchFeedback(Window w, string root, string editorDirectory)
    {
        string dir = Directory.CreateDirectory(Path.Combine(root, "versions", "1.1.1", Distribution.Editor)).FullName;
        var exe = Path.Combine(dir, Distribution.Editor + ".exe");
        File.WriteAllText(exe, "invalid executable fixture");
        File.WriteAllText(Path.ChangeExtension(exe,".pck"), "");
        var cards=(Panel)w.FindName("Cards");
        void Click(Button button) => button.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));
        Click((Button)w.FindName("RefreshButton"));Pump(150);
        Button StartButton() => Children<Button>(cards).Single(b=>Equals(b.Content,"启动"));
        Check(!Children<ProgressBar>(cards).Any(), "Transfer progress is confined to the footer");
        bool HasText(string text) => Children<TextBlock>((Panel)w.FindName("HintStack")).Any(t=>t.IsVisible && t.Text.Contains(text));
        bool WaitFor(string text)
        {
            var timer=Stopwatch.StartNew();
            while (!HasText(text) && timer.Elapsed.TotalSeconds<25) Pump(50);
            return HasText(text);
        }
        void StartTwice()
        {
            var button=StartButton();
            Click(button);w.UpdateLayout();
            Check(!button.IsEnabled && Equals(button.Content,"启动中…") && HasText("正在启动制谱器 v1.1.1"), "Click immediately acknowledges launch on the selected version");
            Click(button);
        }
        StartTwice();
        Check(WaitFor("启动失败") && StartButton().IsEnabled, "Launch failure explains the error and enables retry");
        var finished=new TaskCompletionSource<string>();
        IProgress<Transfer> reporter=null;
        Func<IProgress<Transfer>,CancellationToken,Task<string>> maintenance=(progress,_)=>{reporter=progress;return finished.Task;};
        var job=(Task)typeof(MainWindow).GetMethod("RunJob",BindingFlags.NonPublic|BindingFlags.Instance).Invoke(w,new object[]{maintenance,null});
        Check(!StartButton().IsEnabled,"Maintenance disables launch immediately");
        Click(StartButton());
        Pump(300);
        reporter.Report(new Transfer("校验文件",53,100));Pump(35);
        var bar=(ProgressBar)w.FindName("JobProgress");
        if (((MainWindow)w).AnimateControls)
            Check(bar.IsVisible && bar.Value>0 && bar.Value<53,"The visible job bar animates between progress reports");
        double originalWidth=w.Width;
        w.Width=w.MinWidth;
        Click((Button)w.FindName("RefreshButton"));Pump(300);
        var hint=(Border)w.FindName("SyncHint");var cancel=(Button)w.FindName("JobCancel");var text=(TextBlock)w.FindName("JobStatus");
        double Left(FrameworkElement element)=>element.TranslatePoint(new Point(),w).X;
        var whileVisible=(text.ActualWidth,Left(bar),Left(cancel));
        var middle=hint.TranslatePoint(new Point(hint.ActualWidth/2,hint.ActualHeight/2),w);
        Check(hint.IsVisible && w.InputHitTest(middle) is DependencyObject hit && hit!=hint && !hint.IsAncestorOf(hit),
            "Input reaches the underlying page through the visible notification");
        hint.Visibility=Visibility.Collapsed;w.UpdateLayout();
        Check(whileVisible==(text.ActualWidth,Left(bar),Left(cancel)), "Showing and hiding the overlay does not move controls or shorten the task status at minimum width");
        w.Width=originalWidth;
        Click(Children<Button>((Panel)w.FindName("Groups")).First(b=>Equals(b.Content,"设置")));Pump(250);
        Check(bar.IsVisible && Math.Abs(bar.Value-53)<.1 && ((TextBlock)w.FindName("JobStatus")).Text.Contains("53%"),"Switching tabs preserves active job progress");
        Click(Children<Button>((Panel)w.FindName("Groups")).First(b=>Equals(b.Content,"启动")));Pump(100);
        finished.SetResult("测试校验完成");Pump(80);
        Check(job.IsCompletedSuccessfully && StartButton().IsEnabled,"Launch is restored when maintenance completes");
        if (editorDirectory==null) return;

        foreach (var file in Directory.EnumerateFiles(editorDirectory, "*", SearchOption.AllDirectories))
        {
            var copy=Path.Combine(dir,Path.GetRelativePath(editorDirectory,file));
            Directory.CreateDirectory(Path.GetDirectoryName(copy));
            File.Copy(file,copy,true);
        }
        var previous=Environment.GetEnvironmentVariable("APPDATA");
        var appData=Directory.CreateDirectory(Path.Combine(root,"test-profile")).FullName;
        var editorData=Directory.CreateDirectory(Path.Combine(appData,"Godot","app_userdata",Distribution.Editor)).FullName;
        File.WriteAllText(Path.Combine(editorData,EditorProfile.Prefs),"[tutorial]\nexperience=\"branch\"\n[updates]\nlast_run_tag=\"v1.1.1\"\n");
        Environment.SetEnvironmentVariable("APPDATA",appData);
        try
        {
            StartTwice();
            Check(WaitFor("v1.1.1 窗口已打开") && Children<Button>(cards).Any(b=>b.IsEnabled && Equals(b.Content,"停止")), "Hub confirms the real editor window and offers Stop");
            Check(TestEditors().Length==1, "Repeated clicks create one editor process");
            using var otherClient=new HttpClient(new Offline());
            var other=new Distribution(root,otherClient);
            bool rejected=false;
            try {other.Launch("1.1.1");} catch(InvalidOperationException) {rejected=true;}
            Check(rejected && TestEditors().Length==1,"A separate Hub client cannot launch a duplicate");
            var reopened=new MainWindow(new HttpClient(new Offline()),root,new EditorProfile(Path.Combine(root,"test-profile"))) {Owner=w,ShowInTaskbar=false};
            try
            {
                reopened.Show();Pump(200);
                var stop=Children<Button>((Panel)reopened.FindName("Cards")).Single(b=>Equals(b.Content,"停止"));
                Check(stop.IsEnabled,"A newly opened Hub reconnects to the running editor");
                Click(stop);
                bool exited=WaitFor("制谱器已退出");
                if(!exited) Console.WriteLine("Stop result: "+string.Join(" | ",Children<TextBlock>((Panel)reopened.FindName("Cards")).Select(t=>t.Text).Where(t=>t.Contains("制谱器") || t.Contains("关闭"))));
                Check(exited && StartButton().IsEnabled && TestEditors().Length==0,"Stop closes the editor and both Hubs observe exit");
            }
            finally {reopened.Close();w.Activate();Pump(70);}
        }
        finally
        {
            Environment.SetEnvironmentVariable("APPDATA",previous);
            foreach (var process in TestEditors())
                using (process)
                {
                    process.CloseMainWindow();
                    if (!process.WaitForExit(3000)) {process.Kill();process.WaitForExit(5000);}
                }
        }
        Process[] TestEditors() => Process.GetProcessesByName(Distribution.Editor).Where(process=>{
            try {return string.Equals(process.MainModule?.FileName,exe,StringComparison.OrdinalIgnoreCase);}
            catch (Exception e) when (e is Win32Exception or InvalidOperationException) {return false;}
        }).ToArray();
    }
}
