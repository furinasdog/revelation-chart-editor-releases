using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

namespace RevelationHub
{
    public partial class MainWindow : Window
    {
        private readonly HttpClient http;
        private readonly Distribution library;
        private readonly HubServices services;
        private readonly DispatcherTimer serviceTimer = new() { Interval = TimeSpan.FromHours(6) };
        private bool reopenAfterUpdate, showUpdateResult;
        private Task updateRequest;
        private string readyVersion;
        private readonly CancellationTokenSource lifetime = new CancellationTokenSource();
        private Transfer hubTransfer;
        private Release offeredHub;
        private Release[] available = Array.Empty<Release>();
        private CancellationTokenSource download;
        private string activeVersion;
        private bool onlyInstalled, closing;
        private Brush ThemeBrush(string key) => (Brush)FindResource(key);

        public MainWindow() : this(new HttpClient {Timeout=Timeout.InfiniteTimeSpan},HubServices.UserRoot,new EditorProfile(EditorProfile.DefaultRoot)) { }

        internal MainWindow(HttpClient connection,string root,EditorProfile editorProfile)
        {
            http=connection;
            profile=editorProfile;
            InitializeComponent();
            http.DefaultRequestHeaders.UserAgent.ParseAdd("RevelationHub/" + HubServices.Current.ToString(3));
            library = new Distribution(root, http);
            services = new HubServices(root, http);
            options = HubOptions.Load(root);
            models = new EditorModels(profile,http);
            HubVersionLabel.Text = "Hub v" + HubServices.Current.ToString(3);
            serviceTimer.Tick += async (_, __) => await CheckServices(false);
            Loaded += async (_, __) => {
                serviceTimer.Start();
                WatchEditor(); editorTimer.Start();
                _ = CheckServices(false);
                try { available = library.Offline(); Navigate(library.LocalVersions().Any()?"已安装":"版本库"); await Refresh(); }
                catch (Exception ex) { Message(ex.Message, true); }
            };
            editorTimer.Tick += (_, __) => WatchEditor();
            Closing += OnClosing;
            Closed += (_, __) => { serviceTimer.Stop(); editorTimer.Stop(); editor?.Process.Dispose(); lifetime.Cancel(); http.Dispose(); };
        }
        private void OnClosing(object sender, CancelEventArgs e)
        {
            if (download != null)
            {
                e.Cancel = true;
                closing = true;
                download.Cancel();
                return;
            }
            if (readyVersion == null) return;
            try { services.StartUpdater(readyVersion, reopenAfterUpdate); readyVersion = null; }
            catch (Exception ex)
            {
                if (!reopenAfterUpdate) return;
                e.Cancel = true;
                reopenAfterUpdate = false;
                ShowDialogMessage(new("hub-check", "Hub 更新未能启动", ex.Message, []), true);
            }
        }
        private async Task Refresh()
        {
            RefreshButton.IsEnabled = false;
            try
            {
                available = await library.Refresh(lifetime.Token);
                NotifySync(library.CatalogSynced, library.CatalogSource);
                Render();
                if (library.CatalogSynced) AnnounceEditorUpdate();
            }
            catch (OperationCanceledException) { }
            catch (Exception ex) { NotifySync(false, ex.Message); }
            finally { RefreshButton.IsEnabled = true; }
        }
        private async void RefreshClick(object sender, RoutedEventArgs e) { if (OnLibrary) await Task.WhenAll(Refresh(), CheckServices(true)); else Navigate(page,true); }
        private async Task CheckServices(bool manual, bool explicitCheck = false)
        {
            await Task.WhenAll(options.Announcements ? ReadNotices() : Task.CompletedTask,
                options.AutoUpdates || manual ? CheckUpdate(explicitCheck) : Task.CompletedTask);
        }
        private async Task CheckUpdate(bool manual)
        {
            if (readyVersion != null)
            {
                if (manual) AnnounceHubUpdate(offeredHub, true, true);
                return;
            }
            showUpdateResult |= manual;
            if (manual && offeredHub != null) AnnounceHubUpdate(offeredHub, false, true);
            var request = updateRequest ??= PrepareUpdate();
            try { await request; }
            finally
            {
                if (updateRequest == request) { updateRequest = null; showUpdateResult = false; }
            }
        }
        private async Task PrepareUpdate()
        {
            bool checkingTransfer = true;
            try
            {
                services.CleanApplied();
                var progress = new Progress<Transfer>(t =>
                {
                    if (!checkingTransfer || lifetime.IsCancellationRequested) return;
                    hubTransfer = new Transfer("Hub 更新 · " + t.Stage, t.Bytes, t.Total);
                    if (download == null) ShowTransfer(hubTransfer);
                });
                Task OnAvailable(Release release) => Dispatcher.InvokeAsync(() =>
                {
                    if (lifetime.IsCancellationRequested) return;
                    offeredHub = release;
                    AnnounceHubUpdate(release, false, showUpdateResult);
                }).Task;
                readyVersion = await services.Prepare(HubServices.Current, progress, lifetime.Token, OnAvailable);
                if (lifetime.IsCancellationRequested) return;
                if (readyVersion != null)
                {
                    AnnounceHubUpdate(offeredHub, true, showUpdateResult);
                }
                else if (showUpdateResult) ShowDialogMessage(new("hub-check","Hub 版本更新","当前已是最新版本。",[]),true);
            }
            catch (OperationCanceledException) { }
            catch (Exception ex)
            {
                if (showUpdateResult || offeredHub != null || hubTransfer != null)
                    ShowDialogMessage(new(offeredHub == null ? "hub-check" : "hub/" + offeredHub.version,
                        "Hub 更新暂时不可用", ex is FileNotFoundException or DirectoryNotFoundException
                            ? "请稍后在「设置 → Hub 设置」重新检查更新。" : ex.Message, []), true);
                offeredHub = null;
            }
            finally
            {
                checkingTransfer = false;
                hubTransfer = null;
                if (download == null) ShowTransfer(null);
            }
        }
        private void ShowTransfer(Transfer transfer)
        {
            JobStatus.Text = transfer?.Stage ?? "";
            JobProgress.Visibility = transfer == null ? Visibility.Collapsed : Visibility.Visible;
            JobCancel.Visibility = transfer != null && download != null ? Visibility.Visible : Visibility.Collapsed;
            JobProgress.IsIndeterminate = transfer != null && transfer.Total <= 0;
            if (transfer?.Total > 0)
            {
                double percent = 100.0 * transfer.Bytes / transfer.Total;
                JobStatus.Text += $"  {percent:F0}%";
                SetProgress(JobProgress, percent);
            }
            else SetProgress(JobProgress, 0);
        }

        private void OpenFolder(object sender, RoutedEventArgs e)
        {
            try { Process.Start(new ProcessStartInfo(library.Versions) { UseShellExecute = true }); }
            catch (Exception ex) { Message(ex.Message, true); }
        }
        private sealed record CardView(string Notes,string Date,long Size,string Hash,bool Present,bool Installed,string Update,CudaSupport Cuda);
        private readonly Dictionary<string,(CardView View,Border Card)> displayed = new();
        private void Render()
        {
            if (!OnLibrary) return;
            var local=library.LocalVersions().ToHashSet();
            var releases = available.ToList();
            foreach (string v in local)
                if (releases.All(r => r.version != v)) releases.Add(new Release {version=v});
            var rows=releases.Where(r=>!onlyInstalled || local.Contains(r.version)).OrderByDescending(r=>Version.Parse(r.version)).ToArray();
            var keys=rows.Select(r=>r.version).ToHashSet();
            foreach(string key in displayed.Keys.Where(k=>!keys.Contains(k)).ToArray()) {Cards.Children.Remove(displayed[key].Card);displayed.Remove(key);}
            for(int i=0;i<rows.Length;i++)
            {
                var r=rows[i];bool present=local.Contains(r.version);
                var upgrade=present?available.FirstOrDefault(x=>Version.Parse(x.version)>Version.Parse(r.version) && !local.Contains(x.version)):null;
                bool installed = present && library.Installed(r.version);
                var view=new CardView(r.notes,r.date,r.size,r.sha256,present,installed,upgrade?.version,installed ? library.CudaFor(r.version) : null);
                bool exists=displayed.TryGetValue(r.version,out var prior);
                if(!exists || prior.View!=view)
                {
                    if(exists) Cards.Children.Remove(prior.Card);
                    var card=BuildCard(r,view,upgrade);
                    displayed[r.version]=(view,card);Cards.Children.Insert(i,card);
                }
                else if(Cards.Children.IndexOf(prior.Card)!=i) {Cards.Children.Remove(prior.Card);Cards.Children.Insert(i,prior.Card);}
            }
            EmptyState.Text = Cards.Children.Count > 0 ? "" : onlyInstalled ? "还没有安装制谱器。可在版本库选择版本安装。" : "当前没有可用版本。";
        }
        private TextBlock Label(string text, double size, string color) =>
            new TextBlock { Text = text, FontSize = size, TextWrapping = TextWrapping.Wrap, Foreground = ThemeBrush(color), VerticalAlignment = VerticalAlignment.Center };
        private Border BuildCard(Release r,CardView view,Release upgrade)
        {
            bool installed = view.Installed;
            bool damaged = !installed && view.Present;
            var panel = new StackPanel();
            var card = new PageCard((Style)FindResource("Card"),panel);
            var header = new DockPanel();
            var version = Label("v" + r.version, 20, "Ink");
            version.FontWeight = FontWeights.SemiBold;
            var state = Label(damaged ? "需要修复" : installed ? "已安装" : "可安装", 13, damaged?"Warning":installed ? "Success" : "Muted");
            DockPanel.SetDock(state, Dock.Right); header.Children.Add(state); header.Children.Add(version);
            panel.Children.Add(header);
            var detail = Label($"Windows  x64   ·   {r.date}" + (r.size > 0 ? $"   ·   {r.size / 1048576.0:F1} MiB" : ""), 12, "Muted");
            detail.Margin = new Thickness(0,4,0,10); panel.Children.Add(detail);
            if (!String.IsNullOrWhiteSpace(r.notes)) panel.Children.Add(Label(r.notes,14,"Ink"));
            var action = new Button { Content=installed ? "启动" : "安装", MinWidth=86, VerticalAlignment=VerticalAlignment.Center, Background=ThemeBrush("Accent"), BorderBrush=ThemeBrush("Accent"), Foreground=ThemeBrush("Paper") };
            if (damaged) action.Visibility=Visibility.Collapsed;
            var bottom = new DockPanel { Margin=new Thickness(0,14,0,0) };
            DockPanel.SetDock(action,Dock.Right); bottom.Children.Add(action);
            var secondary = new StackPanel { VerticalAlignment=VerticalAlignment.Center };
            if (view.Present) AddMaintenanceButtons(secondary,r,upgrade,view.Cuda);
            bottom.Children.Add(secondary);
            action.Click += async (_, __) => {
                if (installed) await ToggleEditor(r.version);
                else await Install(r);
            };
            panel.Children.Add(bottom);
            void UpdateActions()
            {
                if (installed) ApplyEditorState(r.version, action, secondary);
                else
                {
                    action.IsEnabled = download == null;
                    action.Content = activeVersion == r.version ? "安装中…" : "安装";
                    secondary.IsEnabled = download == null;
                }
            }
            card.Tag = (Action)UpdateActions;
            card.Name = "V" + r.version.Replace('.','_');
            UpdateActions();
            return card;
        }
        private async Task Install(Release r)
        {
            if (download != null) return;
            download = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
            UpdateDialogAction();
            activeVersion = r.version;
            var job = download;
            ShowTransfer(new Transfer("准备下载 v" + r.version));
            RefreshEditorActions();
            var progress = new Progress<Transfer>(t => { if (download == job) ShowTransfer(t); });
            try { await library.Install(r,progress,job.Token); Message("已安装 v" + r.version + "。"); }
            catch (OperationCanceledException) { Message("已取消下载。"); }
            catch (Exception ex) { Message("安装失败 · " + ex.Message, true); }
            finally {
                download.Dispose(); download=null; activeVersion=null; UpdateDialogAction();
                ShowTransfer(hubTransfer); RefreshEditorActions();
                if (closing) Close(); else Render();
            }
        }
    }
}
