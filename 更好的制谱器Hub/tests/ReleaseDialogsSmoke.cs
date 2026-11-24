using System;
using System.Linq;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using RevelationHub;

internal partial class Program
{
    private static void CheckReleaseDialogs(MainWindow w, Offline routes)
    {
        void Click(string name) => Children<Button>(w).First(b=>b.IsVisible && Equals(b.Content,name)).RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));
        var overlay=(Grid)w.FindName("FeedbackOverlay");
        bool Shows(string value) => overlay.IsVisible && Children<TextBlock>(overlay).Any(t=>t.Text.Contains(value));
        routes.NoticeJson="""{"schema":1,"items":[{"title":"试验公告","body":"一条应在弹窗中展示的消息"}]}""";
        Click("刷新版本");Pump(250);
        Check(Shows("试验公告"),"Cloud announcement opens a persistent modal after sync");
        Check(!Children<TextBlock>((Panel)w.FindName("HintStack")).Any(t=>t.Text.Contains("试验公告")),"Announcement never enters the bottom toast stack");
        Click("知道了");Pump(200);
        Click("刷新版本");Pump(220);
        Check(!overlay.IsVisible,"An acknowledged announcement does not interrupt another refresh");
        Click("公告");Pump(150);
        Check(Shows("试验公告"),"Announcement can be reopened from the sidebar");
        var hubUpdate = typeof(MainWindow).GetMethod("AnnounceHubUpdate", BindingFlags.NonPublic | BindingFlags.Instance);
        var release = new Release { version = "2.0.0", notes = "新版本说明" };
        hubUpdate.Invoke(w,[release,false,false]);
        Check(Shows("试验公告"),"An arriving update waits for the current announcement");
        Click("知道了");Pump(200);
        Check(Shows("Hub v2.0.0") && Shows("正在下载新版"),"A discovered Hub update opens the next modal");
        hubUpdate.Invoke(w,[release,true,false]);
        Check(Shows("通过校验") && ((Button)w.FindName("DialogAction")).IsVisible, "A verified download updates the open dialog in place");
        Check(!Children<TextBlock>((Panel)w.FindName("HintStack")).Any(t=>t.Text.Contains("2.0.0")),"Hub update is absent from the toast stack");
        Click("稍后");Pump(170);
        hubUpdate.Invoke(w,[release,true,false]);
        Check(!overlay.IsVisible,"Later dismisses the automatic prompt for this version");
        routes.NoticeJson=routes.NoticeJson.Replace("一条应在弹窗中展示的消息","公告内容有变更");
        Click("刷新版本");Pump(200);
        Check(Shows("公告内容有变更"), "A revised notice with the same title is shown again");
        Click("知道了");Pump(170);
        Click("设置");Pump(25);
        var body=(FrameworkElement)w.FindName("ManagerBody");
        Check(!w.AnimateControls || (body.Opacity<1 && body.RenderTransform.Value.IsIdentity),"Page content fades in without changing its position");
        Pump(260);
        Check(body.Opacity==1,"Page content settles at full opacity");
    }
}
