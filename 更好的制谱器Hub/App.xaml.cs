using System;
using System.IO;
using System.Windows;

namespace RevelationHub
{
    public partial class App : Application
    {
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
