using System;
using System.Diagnostics;
using System.Linq;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
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
        var card=(Border)w.FindName("FeedbackCard");
        var shift=(TranslateTransform)((TransformGroup)card.RenderTransform).Children[1];
        Check(!w.AnimateControls || shift.HasAnimatedProperties,"Announcement card has its own settling motion");
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
        bool SawFrame(Func<bool> condition)
        {
            var clock=Stopwatch.StartNew();
            while (!condition() && clock.ElapsedMilliseconds<400) Pump(8);
            return condition();
        }
        Click("设置");w.UpdateLayout();
        var body=(FrameworkElement)w.FindName("ManagerBody");
        var sections=Children<PageCard>(body).Where(card=>card.IsVisible).Take(2).ToArray();
        Check(sections.Length==2 && body.Opacity==1 && body.RenderTransform.Value.IsIdentity,"The viewport stays anchored while its cards enter");
        Check(!w.AnimateControls || SawFrame(()=>sections[0].Opacity>sections[1].Opacity),"New sections appear in reading order");
        Pump(420);
        Check(sections.All(card=>card.Opacity==1),"All sections settle at full opacity");
        Click("Hub 设置");w.UpdateLayout();
        var settings=Children<Button>(w).First(b=>b.IsVisible && Equals(b.Content,"Hub 设置"));
        var bar=(Border)settings.Template.FindName("Bar",settings);
        var scale=(ScaleTransform)bar.RenderTransform;
        Check(!w.AnimateControls || SawFrame(()=>scale.ScaleY>0 && scale.ScaleY<1),"The rail indicator grows from its center");
        var moving=Children<PageCard>(body).First(c=>c.IsVisible);
        var title=Children<TextBlock>(moving).First();
        var action=Children<Button>(moving).First();
        double ScreenY(FrameworkElement element) => element.TranslatePoint(new Point(),w).Y;
        if (w.AnimateControls)
        {
            Check(SawFrame(()=>moving.RenderTransform.Value.OffsetY < -1 && moving.Opacity > .1),"The whole card travels during entry");
            var cardStart=ScreenY(moving);
            var textStart=ScreenY(title);
            var buttonStart=ScreenY(action);
            var point=action.TranslatePoint(new Point(action.ActualWidth/2,action.ActualHeight/2),w);
            Check(w.InputHitTest(point) is DependencyObject hit && (hit==action || action.IsAncestorOf(hit)),"The button receives hits at its animated position");
            Pump(400);
            var distance=ScreenY(moving)-cardStart;
            Check(distance>1 && Math.Abs(ScreenY(title)-textStart-distance)<.01 && Math.Abs(ScreenY(action)-buttonStart-distance)<.01,
                "Card, text and action button travel the same distance on screen");
        }
        else Pump(100);
        Check(scale.ScaleY==1,"The selected rail indicator settles at full height");
        var motion=Children<CheckBox>(w).Single(b=>Equals(b.Content,"启用界面缓动动画"));
        motion.IsChecked=false;Click("保存设置");
        Click("编辑器配置");
        Check(!w.AnimateControls && Children<PageCard>(body).All(c=>c.Opacity==1 && !c.HasAnimatedProperties && c.RenderTransform.Value.IsIdentity),"Turning motion off makes a new page immediately usable");
    }
}
