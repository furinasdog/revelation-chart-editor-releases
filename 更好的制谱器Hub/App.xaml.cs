using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace RevelationHub
{
    public partial class App : Application
    {
        private void ButtonMotion(object sender, MouseEventArgs e) => Animate((Button)sender,((Button)sender).IsMouseOver?1.025:1);
        private void ButtonPress(object sender, MouseButtonEventArgs e) => Animate((Button)sender,e.ButtonState==MouseButtonState.Pressed?.97:1.025);
        private static void Animate(Button b,double target)
        {
            if (Window.GetWindow(b) is not MainWindow w || !w.AnimateControls) return;
            if(b.RenderTransform is not ScaleTransform scale){scale=new ScaleTransform();b.RenderTransform=scale;}
            var animation=new DoubleAnimation(target,TimeSpan.FromMilliseconds(140)){EasingFunction=new CubicEase{EasingMode=EasingMode.EaseOut}};
            scale.BeginAnimation(ScaleTransform.ScaleXProperty,animation);
            scale.BeginAnimation(ScaleTransform.ScaleYProperty,animation);
        }
        protected override async void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);
            if (e.Args.Length == 0) { new MainWindow().Show(); return; }
            ShutdownMode = ShutdownMode.OnExplicitShutdown;
            try
            {
                if (e.Args is ["--set-shortcuts", var start, var desktop] &&
                    start is "start=1" or "start=" && desktop is "desktop=1" or "desktop=")
                {
                    Shortcuts.Set(start == "start=1", desktop == "desktop=1");
                    Shutdown(0);
                }
                else if (e.Args is ["--restore-shortcuts"]) { Shortcuts.Set(null, null); Shutdown(0); }
                else if (e.Args is ["--apply-update", var parent, var version, var mode] && int.TryParse(parent, out int pid))
                    Shutdown(await HubServices.Apply(HubServices.UserRoot, pid, version, mode == "reopen"));
                else Shutdown(2);
            }
            catch (Exception ex)
            {
                Directory.CreateDirectory(HubServices.UserRoot);
                File.WriteAllText(Path.Combine(HubServices.UserRoot, "maintenance-error.txt"), ex.Message);
                Shutdown(1);
            }
        }
    }
}
