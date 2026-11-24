using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using RevelationHub;

internal partial class Program
{
    private sealed class Offline : HttpMessageHandler
    {
        internal bool CatalogOnline;
        internal string NoticeJson = """{"schema":1,"items":[]}""";
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage r,CancellationToken ct)
        {
            if (r.RequestUri.AbsolutePath.EndsWith("/announcements.json"))
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content=new StringContent(NoticeJson) });
            if (CatalogOnline && r.RequestUri.AbsolutePath.EndsWith("/catalog.signed.json"))
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content=new StreamContent(typeof(Distribution).Assembly.GetManifestResourceStream("RevelationHub.catalog.signed.json")) });
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
        }
    }
    private static IEnumerable<T> Children<T>(DependencyObject parent) where T:DependencyObject
    {
        for(int i=0;i<VisualTreeHelper.GetChildrenCount(parent);i++)
        {
            var child=VisualTreeHelper.GetChild(parent,i);
            if(child is T item)yield return item;
            foreach(var nested in Children<T>(child))yield return nested;
        }
    }
    private static void Pump(int ms)
    {
        var f=new DispatcherFrame();
        var timer=new DispatcherTimer{Interval=TimeSpan.FromMilliseconds(ms)};
        timer.Tick+=(_,_)=>{timer.Stop();f.Continue=false;};
        timer.Start();Dispatcher.PushFrame(f);
    }
    [DllImport("user32.dll")] private static extern int GetWindowLongW(IntPtr hwnd, int index);
    [DllImport("user32.dll")] private static extern IntPtr SendMessageW(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam);
    private static async Task CheckLayout(string output, string editorDirectory = null, bool noticesOnly = false)
    {
        var done=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread=new Thread(()=>{
            var work=Directory.CreateTempSubdirectory("hub-layout-");
            try
            {
                Directory.CreateDirectory(output);
                var app=new Application{ShutdownMode=ShutdownMode.OnExplicitShutdown,Resources=new HubTheme()};
                SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(Dispatcher.CurrentDispatcher));
                var profile=new EditorProfile(Path.Combine(work.FullName,"editor"));
                var theme=EditorProfile.Fields.Single(f=>f.Key=="theme");
                var modelDir=EditorProfile.Fields.Single(f=>f.Key=="music2emo_models");
                profile.Config(EditorProfile.Prefs).Save(new(){[theme]="gray",[modelDir]=Path.Combine(profile.Root,"models")});
                var backdrop = Color.FromRgb(83, 36, 62);
                var wall = new Window { ShowInTaskbar=false, Topmost=true, WindowStyle=WindowStyle.None, ResizeMode=ResizeMode.NoResize,
                    Background=new SolidColorBrush(backdrop), WindowStartupLocation=WindowStartupLocation.CenterScreen, Width=910, Height=626 };
                wall.Show();
                var routes=new Offline();
                var w=new MainWindow(new HttpClient(routes),work.FullName,profile){Owner=wall,Topmost=true,ShowInTaskbar=false,Width=865,Height=580};
                try
                {
                    w.Show();Pump(260);
                    if (noticesOnly)
                    {
                        CheckReleaseDialogs(w,routes);
                        done.SetResult();
                        return;
                    }
                    var handle = new WindowInteropHelper(w).Handle;
                    var style = GetWindowLongW(handle, -16);
                    Check((style & 0x10000) == 0 && (style & 0x60000) == 0x60000, "Window allows resizing and minimizing, with maximization disabled");
                    SendMessageW(handle, 0x0112, new IntPtr(0xF030), IntPtr.Zero);
                    Pump(60);
                    Check(w.WindowState == WindowState.Normal, "System maximize command leaves the window restored");
                    SendMessageW(handle, 0x00A3, new IntPtr(2), IntPtr.Zero);
                    Pump(60);
                    Check(w.WindowState == WindowState.Normal, "Caption double-click leaves the window restored");
                    w.WindowState = WindowState.Maximized;
                    Check(w.WindowState == WindowState.Normal, "Application cannot switch to maximized state");
                    SystemCommands.MinimizeWindow(w);Pump(100);
                    Check(w.WindowState == WindowState.Minimized, "Window still minimizes");
                    SystemCommands.RestoreWindow(w);Pump(100);
                    Check(w.WindowState == WindowState.Normal && (GetWindowLongW(handle, -16) & 0x10000) == 0, "Restoring preserves the maximize restriction");
                    w.Activate();Pump(160);
                    CheckWindowSurface(w, backdrop, Path.Combine(output,"restored.png"));
                    Check((GetWindowLongW(handle, -16) & 0x00C00000) == 0, "Native caption is absent after restore");
                    int Hit(double x, double y)
                    {
                        var p = w.PointToScreen(new Point(x, y));
                        int packed = unchecked(((int)p.Y << 16) | ((int)p.X & 0xFFFF));
                        return (int)SendMessageW(handle, 0x0084, IntPtr.Zero, new IntPtr(packed));
                    }
                    double right=w.ActualWidth-3, bottom=w.ActualHeight-3;
                    Check(Hit(3,3)==13 && Hit(right,3)==14 && Hit(3,bottom)==16 && Hit(right,bottom)==17 &&
                        Hit(3,90)==10 && Hit(right,90)==11 && Hit(90,3)==12 && Hit(90,bottom)==15,
                        "All four edges and four corners support native resizing");
                    Check(Hit(100,24)==2 && Hit(w.ActualWidth-20,24)==1 && Hit(w.ActualWidth/2,24)==1,
                        "Title bar drags, navigation and window controls receive clicks");
                    SystemCommands.MinimizeWindow(w);Pump(100);
                    backdrop=Color.FromRgb(185,193,207);wall.Background=new SolidColorBrush(backdrop);
                    SystemCommands.RestoreWindow(w);w.Activate();Pump(200);
                    CheckWindowSurface(w, backdrop, Path.Combine(output,"restored-light.png"));
                    Button Button(string name) => Children<Button>(w).First(b=>b.IsVisible && Equals(b.Content,name));
                    void Click(string name){Button(name).RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));w.UpdateLayout();}
                    void Capture(string file)
                    {
                        var visual=(FrameworkElement)w.Content;
                        var bmp=new RenderTargetBitmap((int)Math.Ceiling(visual.ActualWidth),(int)Math.Ceiling(visual.ActualHeight),96,96,PixelFormats.Pbgra32);
                        bmp.Render(visual);var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bmp));
                        using var dest=File.Create(Path.Combine(output,file));encoder.Save(dest);
                    }
                    var hint=(Border)w.FindName("SyncHint");
                    var hintText=(TextBlock)w.FindName("SyncHintText");
                    Check(hint.IsVisible && hintText.Text.Contains("版本库同步失败"),"Offline catalog fallback shows the failure notification");
                    routes.CatalogOnline=true;Click("刷新版本");Pump(35);
                    Check(hint.IsVisible && Children<TextBlock>((Panel)w.FindName("HintStack")).Any(t=>t.Text.Contains("已从 GitHub 同步")),"Signed online catalog shows a success notification");
                    var hintLayer=(Canvas)((FrameworkElement)hint.Parent).Parent;
                    if(w.AnimateControls) Check(((TranslateTransform)hint.RenderTransform).X>0,"Sync notification slides inward from the right");
                    Pump(270);
                    var hintEnd=hint.TranslatePoint(new Point(hint.ActualWidth,0),w);
                    Check(hintLayer.ClipToBounds && !hint.IsHitTestVisible && hintLayer.DesiredSize.Width==0 && hintLayer.DesiredSize.Height==0 && Math.Abs(hintEnd.X-w.ActualWidth)<1,
                        "Right-aligned toast floats over content without reserving width or height");
                    Click("问题反馈");Pump(220);
                    var overlay=(Grid)w.FindName("FeedbackOverlay");
                    Check(overlay.IsVisible && !((Grid)w.FindName("Workspace")).IsEnabled && Children<TextBlock>(overlay).Any(t=>t.Text=="请在制谱师/企划群中 @短夜月 反馈"),"Feedback opens an in-app modal with the requested message");
                    Capture("feedback.png");
                    Click("知道了");Pump(170);Check(!overlay.IsVisible && ((Button)w.FindName("FeedbackButton")).IsKeyboardFocused,"Feedback dismisses and restores focus");
                    Click("下载");Click("模型管理");Pump(25);
                    var area=(Grid)w.FindName("ContentArea");
                    if(w.AnimateControls)
                        Check(area.Opacity==1 && area.RenderTransform.Value.IsIdentity && ((TextBlock)w.FindName("PageTitle")).IsDescendantOf(area) && ((Grid)w.FindName("JobPanel")).IsDescendantOf(area),"Changing tabs keeps the title, content and footer stationary");
                    Pump(220);
                    Capture("sync-right.png");
                    var button=Button("校验");button.Focus();
                    var viewport=(ScrollViewer)w.FindName("ManagerBody");
                    var counts=Children<TextBlock>(viewport).First(t=>t.Text.Contains("个模型及配套文件"));
                    var chrome=(FrameworkElement)button.Template.FindName("HoverFill",button);
                    var animate=typeof(HubTheme).GetMethod("Animate",BindingFlags.Static|BindingFlags.NonPublic);
                    foreach(var opacity in new[]{.15,.29,0})
                    {
                        animate.Invoke(null,new object[]{button,opacity});Pump(145);
                        var rect=chrome.TransformToAncestor(button).TransformBounds(new Rect(chrome.RenderSize));
                        Check(button.RenderTransform.Value.IsIdentity && rect.Left>=1 && rect.Top>=1 && rect.Right<=button.ActualWidth-1 && rect.Bottom<=button.ActualHeight-1 && button.Template.FindName("FocusRing",button)==null,"Interaction stays inset without adding a focus rectangle");
                    }
                    Capture("models.png");
                    var progress=(ProgressBar)w.FindName("JobProgress");
                    bool flashed=false;progress.IsVisibleChanged+=(_,_)=>flashed|=progress.IsVisible;
                    double scroll=viewport.VerticalOffset;var status=(TextBlock)w.FindName("JobStatus");
                    Click("校验");
                    var clock=Stopwatch.StartNew();while(!hintText.Text.Contains("补齐")&&clock.ElapsedMilliseconds<4000)Pump(10);
                    Pump(280);
                    Check(hintText.Text.Contains("补齐") && status.Text.Length==0,"Verification uses the notification overlay and clears the footer");
                    Check(!flashed,"Quick verification skips the transient progress indicator");
                    Check(ReferenceEquals(button,Button("校验")) && counts.IsVisible && button.IsKeyboardFocused && Math.Abs(viewport.VerticalOffset-scroll)<.1,"Verification preserves the existing controls, scroll and focus");
                    Click("设置");Pump(170);
                    var rail = Button("编辑器配置");
                    rail.Focus();
                    Click("编辑器配置");
                    Check(rail.IsKeyboardFocused && !Children<Border>(rail).Any(b => b.IsVisible && b.BorderThickness != new Thickness(0)), "Selected navigation item has no rectangular outline after click focus");
                    Capture("navigation-focused.png");
                    var combo=Children<ComboBox>(w).First(c=>c.IsVisible);
                    combo.Focus();
                    Check(!rail.IsKeyboardFocused && !Children<Border>(rail).Any(b => b.IsVisible && b.BorderThickness != new Thickness(0)), "Selected navigation item stays outline-free when focus moves");
                    Check((string)combo.SelectedValue=="gray" && ((SolidColorBrush)combo.Foreground).Color.R<90 && ((SolidColorBrush)combo.Background).Color.R>225,"Configuration selection has a readable light palette");
                    Capture("configuration.png");combo.IsDropDownOpen=true;Pump(80);
                    var popup=(System.Windows.Controls.Primitives.Popup)combo.Template.FindName("PART_Popup",combo);
                    Check(combo.ItemContainerGenerator.ContainerFromIndex(0) is ComboBoxItem && popup.Child.RenderSize.Width>=combo.ActualWidth-1,"Theme dropdown opens at field width with selectable values");
                    combo.SelectedValue="dark";combo.IsDropDownOpen=false;
                    var tabs = Children<TabControl>(w).Single(t=>t.IsVisible);
                    var mark = (Border)tabs.Template.FindName("SelectionMark",tabs);
                    tabs.SelectedIndex=1;w.UpdateLayout();Pump(20);
                    var agentForm=(StackPanel)((TabItem)tabs.SelectedItem).Content;
                    Check(Grid.GetColumn(mark)==1 && Children<PasswordBox>(agentForm).Any(), "Agent tab selects the matching form");
                    if (w.AnimateControls)
                        Check(((TranslateTransform)mark.RenderTransform).X < 0 && agentForm.RenderTransform.Value.IsIdentity && agentForm.Opacity < 1,
                            "The selected indicator slides and the form fades in place");
                    tabs.SelectedIndex=2;tabs.SelectedIndex=0;Pump(270);
                    Check(Grid.GetColumn(mark)==0 && ((TranslateTransform)mark.RenderTransform).X==0 && (string)combo.SelectedValue=="dark" && combo.IsVisible,
                        "Rapid tab switches settle on the last tab and keep the unsaved preference");
                    var modelLabel=Children<TextBlock>(viewport).First(t=>t.Text=="Music2Emo 模型目录");
                    viewport.ScrollToVerticalOffset(viewport.VerticalOffset+modelLabel.TranslatePoint(new Point(0,modelLabel.ActualHeight/2),viewport).Y-viewport.ActualHeight);
                    Pump(70);
                    var footer=(Border)w.FindName("StatusBackdrop");
                    double viewportBottom=viewport.TranslatePoint(new Point(0,viewport.ActualHeight),w).Y;
                    var footerStart=footer.TranslatePoint(new Point(),w);
                    Check(Math.Abs(footerStart.Y-viewportBottom)<1 && Math.Abs(footerStart.X+footer.ActualWidth-w.ActualWidth)<1 &&
                        footer.BorderThickness.Top==1 && ((SolidColorBrush)footer.Background).Color!=((SolidColorBrush)w.FindResource("Canvas")).Color,
                        "The scrolled configuration meets a distinct full-width status surface at the exact viewport boundary");
                    Capture("status-strip.png");
                    viewport.ScrollToEnd();Pump(70);Check(viewport.VerticalOffset>0,"Configuration scroll reaches the lower fields");
                    Click("保存配置");Check(profile.Config(EditorProfile.Prefs).Get(theme)=="dark","Selected Chinese theme label saves its editor value");
                    Click("Hub 设置");Click("更多");Click("使用文档");
                    var search=Children<TextBox>(w).Single(t=>t.IsVisible);search.Text="增量";w.UpdateLayout();
                    Check(Children<Expander>(w).Any(x=>x.IsVisible && x.Header.ToString().Contains("增量")),"Searchable documentation remains reachable");
                    Click("启动");
                    CheckLaunchFeedback(w,work.FullName,editorDirectory);
                    Click("下载");Click("版本库");w.Width=w.MinWidth;w.Height=w.MinHeight;Pump(180);
                    var groups=(FrameworkElement)w.FindName("Groups");var minimize=(Button)w.FindName("MinimizeButton");
                    Check(groups.TranslatePoint(new Point(groups.ActualWidth,0),w).X < minimize.TranslatePoint(new Point(0,0),w).X,"Top navigation and window controls fit at minimum width");
                    CheckWindowSurface(w, backdrop, Path.Combine(output,"small-desktop.png"));
                    Capture("library-small.png");
                }
                finally{w.Close();wall.Close();app.Shutdown();}
                done.SetResult();
            }
            catch(Exception ex){done.SetException(ex);}
            finally{work.Delete(true);}
        });
        thread.SetApartmentState(ApartmentState.STA);thread.Start();await done.Task;
    }
}
