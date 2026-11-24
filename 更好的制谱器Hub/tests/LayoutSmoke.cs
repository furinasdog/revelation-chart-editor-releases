using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using RevelationHub;

internal partial class Program
{
    private sealed class Offline : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage r,CancellationToken ct) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
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
    private static async Task CheckLayout(string output)
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
                var w=new MainWindow(new HttpClient(new Offline()),work.FullName,profile){ShowInTaskbar=false,Width=865,Height=580};
                try
                {
                    w.Show();Pump(260);
                    Button Button(string name) => Children<Button>(w).First(b=>b.IsVisible && Equals(b.Content,name));
                    void Click(string name){Button(name).RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));w.UpdateLayout();}
                    void Capture(string file)
                    {
                        var visual=(FrameworkElement)w.Content;
                        var bmp=new RenderTargetBitmap((int)Math.Ceiling(visual.ActualWidth),(int)Math.Ceiling(visual.ActualHeight),96,96,PixelFormats.Pbgra32);
                        bmp.Render(visual);var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bmp));
                        using var dest=File.Create(Path.Combine(output,file));encoder.Save(dest);
                    }
                    Click("下载");Click("模型管理");Pump(200);
                    var button=Button("校验");button.Focus();
                    var viewport=(ScrollViewer)w.FindName("ManagerBody");
                    var counts=Children<TextBlock>(viewport).First(t=>t.Text.Contains("个模型及配套文件"));
                    var chrome=(FrameworkElement)button.Template.FindName("HoverFill",button);
                    var focus=(FrameworkElement)button.Template.FindName("FocusRing",button);
                    var animate=typeof(HubTheme).GetMethod("Animate",BindingFlags.Static|BindingFlags.NonPublic);
                    foreach(var opacity in new[]{.15,.29,0})
                    {
                        animate.Invoke(null,new object[]{button,opacity});Pump(145);
                        var rect=chrome.TransformToAncestor(button).TransformBounds(new Rect(chrome.RenderSize));
                        Check(button.RenderTransform.Value.IsIdentity && rect.Left>=1 && rect.Top>=1 && rect.Right<=button.ActualWidth-1 && rect.Bottom<=button.ActualHeight-1 && focus.Visibility==Visibility.Visible,"Interaction stays inside the button and preserves its focus ring");
                    }
                    Capture("models.png");
                    var progress=(ProgressBar)w.FindName("JobProgress");
                    bool flashed=false;progress.IsVisibleChanged+=(_,_)=>flashed|=progress.IsVisible;
                    double scroll=viewport.VerticalOffset;var status=(TextBlock)w.FindName("JobStatus");
                    Click("校验");
                    var clock=Stopwatch.StartNew();while(string.IsNullOrEmpty(status.Text)&&clock.ElapsedMilliseconds<4000)Pump(10);
                    Pump(280);
                    Check(status.Text.Contains("补齐"),"Local fixture verification reported missing models: "+status.Text);
                    Check(!flashed,"Quick verification skips the transient progress indicator");
                    Check(ReferenceEquals(button,Button("校验")) && counts.IsVisible && button.IsKeyboardFocused && Math.Abs(viewport.VerticalOffset-scroll)<.1,"Verification preserves the existing controls, scroll and focus");
                    Click("设置");Pump(170);
                    var combo=Children<ComboBox>(w).First(c=>c.IsVisible);
                    Check((string)combo.SelectedValue=="gray" && ((SolidColorBrush)combo.Foreground).Color.R<90 && ((SolidColorBrush)combo.Background).Color.R>225,"Configuration selection has a readable light palette");
                    Capture("configuration.png");combo.IsDropDownOpen=true;Pump(80);
                    var popup=(System.Windows.Controls.Primitives.Popup)combo.Template.FindName("PART_Popup",combo);
                    Check(combo.ItemContainerGenerator.ContainerFromIndex(0) is ComboBoxItem && popup.Child.RenderSize.Width>=combo.ActualWidth-1,"Theme dropdown opens at field width with selectable values");
                    combo.SelectedValue="dark";combo.IsDropDownOpen=false;
                    viewport.ScrollToEnd();Pump(70);Check(viewport.VerticalOffset>0,"Configuration scroll reaches the lower fields");
                    Click("保存配置");Check(profile.Config(EditorProfile.Prefs).Get(theme)=="dark","Selected Chinese theme label saves its editor value");
                    Click("Hub 设置");Click("更多");Click("使用文档");
                    var search=Children<TextBox>(w).Single(t=>t.IsVisible);search.Text="增量";w.UpdateLayout();
                    Check(Children<Expander>(w).Any(x=>x.IsVisible && x.Header.ToString().Contains("增量")),"Searchable documentation remains reachable");
                    Click("启动");Click("下载");Click("版本库");w.Width=w.MinWidth;w.Height=w.MinHeight;Pump(180);
                    var groups=(FrameworkElement)w.FindName("Groups");var max=(Button)w.FindName("MaximizeButton");
                    Check(groups.TranslatePoint(new Point(groups.ActualWidth,0),w).X < max.TranslatePoint(new Point(0,0),w).X,"Top navigation and window controls fit at minimum width");
                    Capture("library-small.png");
                }
                finally{w.Close();app.Shutdown();}
                done.SetResult();
            }
            catch(Exception ex){done.SetException(ex);}
            finally{work.Delete(true);}
        });
        thread.SetApartmentState(ApartmentState.STA);thread.Start();await done.Task;
    }
}
