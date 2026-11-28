using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using RevelationHub;

internal partial class Program
{
    private static Task CheckStartupAgreements()
    {
        var done = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            var work = Directory.CreateTempSubdirectory("hub-agreements-");
            var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            var reviewed = new List<string>();
            Window terms = null;
            var clock = new Stopwatch();
            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
            int phase = 0;
            Exception failure = null;
            timer.Tick += (_, _) =>
            {
                var dialog = app.Windows.OfType<Window>().SingleOrDefault(w => w.IsVisible);
                if (dialog == null) return;
                try
                {
                    var accept = Children<Button>(dialog).Single(b => b.IsDefault);
                    if (dialog.Title.StartsWith("开源许可"))
                    {
                        Check(accept.IsEnabled, "Hub open-source license has no wait or scroll gate");
                        reviewed.Add(dialog.Title);
                        accept.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                        return;
                    }
                    var reader = Children<ScrollViewer>(dialog).Single();
                    if (!ReferenceEquals(terms, dialog))
                    {
                        Check(!accept.IsEnabled && reader.ScrollableHeight > 0, "Hub user agreement starts locked with text below the fold");
                        terms = dialog;
                        clock.Restart();
                        reader.ScrollToEnd();
                    }
                    else if (phase == 0 && reader.VerticalOffset > 0)
                    {
                        Check(!accept.IsEnabled, "Reading to the end does not bypass the Hub wait");
                        reader.ScrollToHome();
                        phase++;
                    }
                    else if (phase == 1 && clock.Elapsed.TotalSeconds >= 15.3)
                    {
                        Check(reader.VerticalOffset == 0 && !accept.IsEnabled, "Elapsed time does not bypass reading to the end in Hub");
                        reader.ScrollToEnd();
                        phase++;
                    }
                    else if (phase == 2 && accept.IsEnabled)
                    {
                        reviewed.Add(dialog.Title);
                        accept.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                    }
                    else if (clock.Elapsed.TotalSeconds >= 20)
                        throw new TimeoutException("Hub user agreement did not enable confirmation");
                }
                catch (Exception ex)
                {
                    failure = ex;
                    dialog.DialogResult = false;
                }
            };
            try
            {
                timer.Start();
                bool accepted = StartupAgreements.Confirm(work.FullName);
                if (failure != null) throw failure;
                Check(accepted && reviewed.Count == 2 && reviewed[0] == "用户使用协议" && File.Exists(Path.Combine(work.FullName, "user-agreement")),
                    "Hub shows user terms then GPL and saves acceptance");
                reviewed.Clear();
                accepted = StartupAgreements.Confirm(work.FullName);
                if (failure != null) throw failure;
                Check(accepted && reviewed.Count == 1 && reviewed[0].StartsWith("开源许可"), "Hub shows only the GPL on the next startup");
                done.SetResult();
            }
            catch (Exception ex) { done.SetException(ex); }
            finally
            {
                timer.Stop();
                app.Shutdown();
                work.Delete(true);
            }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        return done.Task;
    }
}
