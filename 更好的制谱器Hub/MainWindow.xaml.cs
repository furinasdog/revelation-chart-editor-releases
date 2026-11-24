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
        private bool checkingServices, reopenAfterUpdate;
        private string readyVersion;
        private readonly CancellationTokenSource lifetime = new CancellationTokenSource();
        private readonly Dictionary<string, Transfer> transfers = new Dictionary<string, Transfer>();
        private Release[] available = Array.Empty<Release>();
        private CancellationTokenSource download;
        private string activeVersion;
        private bool onlyInstalled, closing;
        private static SolidColorBrush ColorOf(string hex) => new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));

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
            StateChanged += (_,__) => {
                MaximizeButton.Content = WindowState==WindowState.Maximized ? "\uE923" : "\uE922";
                WindowFrame.Padding=WindowState==WindowState.Maximized ? SystemParameters.WindowResizeBorderThickness : new Thickness(0);
            };
            serviceTimer.Tick += async (_, __) => await CheckServices(false);
            Loaded += async (_, __) => {
                serviceTimer.Start();
                _ = CheckServices(false);
                try { available = library.Offline(); CatalogStatus.Text = library.CatalogSource; Navigate(library.LocalVersions().Any()?"已安装":"版本库"); await Refresh(); }
                catch (Exception ex) { CatalogStatus.Text = ex.Message; }
            };
            Closing += OnClosing;
            Closed += (_, __) => { serviceTimer.Stop(); lifetime.Cancel(); http.Dispose(); };
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
            catch (Exception ex) { if (reopenAfterUpdate) e.Cancel = true; UpdateStatus.Text = "更新未能启动 · " + ex.Message; }
        }
        private async Task Refresh()
        {
            RefreshButton.IsEnabled = false;
            CatalogStatus.Text = "正在检查可用版本…";
            try
            {
                available = await library.Refresh(lifetime.Token);
                CatalogStatus.Text = library.CatalogSource;
                Render();
            }
            catch (OperationCanceledException) { }
            catch (Exception ex) { CatalogStatus.Text = ex.Message; }
            finally { RefreshButton.IsEnabled = true; }
        }
        private async void RefreshClick(object sender, RoutedEventArgs e) { if (OnLibrary) await Task.WhenAll(Refresh(), CheckServices(true)); else Navigate(page,true); }
        private void ShowNotices() => NoticePanel.Visibility = options.Announcements && !onlyInstalled && Notices.Children.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        private void FeedbackClick(object sender, RoutedEventArgs e)
        {
            try { Process.Start(new ProcessStartInfo(HubServices.IssuesUrl) { UseShellExecute = true }); }
            catch (Exception ex) { Message("无法打开问题反馈 · " + ex.Message); }
        }
        private void ApplyClick(object sender, RoutedEventArgs e) { if (download == null && readyVersion != null) { reopenAfterUpdate = true; Close(); } }
        private async Task CheckServices(bool manual)
        {
            if (checkingServices) return;
            checkingServices = true;
            try { await Task.WhenAll(options.Announcements ? ReadNotices() : Task.CompletedTask, options.AutoUpdates || manual ? CheckUpdate(manual) : Task.CompletedTask); }
            finally { checkingServices = false; }
        }
        private async Task ReadNotices()
        {
            try
            {
                var items = await services.Notices(lifetime.Token);
                Notices.Children.Clear();
                foreach (var item in items)
                {
                    var title = Label(item.title, 14, "#245675");
                    title.FontWeight = FontWeights.SemiBold;
                    Notices.Children.Add(title);
                    var content = Label(item.body, 13, "#485C6E");
                    content.Margin = new Thickness(0, 3, 0, 6);
                    Notices.Children.Add(content);
                }
                ShowNotices();
            }
            catch (OperationCanceledException) { }
            catch (Exception) { /* Keep the last displayed notice while offline. */ }
        }
        private async Task CheckUpdate(bool manual)
        {
            if (readyVersion != null) return;
            try
            {
                services.CleanApplied();
                var progress = new Progress<Transfer>(t =>
                {
                    if (readyVersion != null || lifetime.IsCancellationRequested) return;
                    UpdatePanel.Visibility = Visibility.Visible;
                    UpdateStatus.Text = "Hub 更新 · " + t.Stage + (t.Total > 0 ? $"  {100.0 * t.Bytes / t.Total:F0}%" : "");
                });
                readyVersion = await services.Prepare(HubServices.Current, progress, lifetime.Token);
                if (readyVersion != null)
                {
                    UpdateStatus.Text = $"Hub v{readyVersion} 已就绪，退出时自动安装";
                    UpdatePanel.Visibility = ApplyButton.Visibility = Visibility.Visible;
                    ApplyButton.IsEnabled = download == null;
                }
                else { UpdateStatus.Text = "Hub 已是最新版本"; UpdatePanel.Visibility = manual ? Visibility.Visible : Visibility.Collapsed; }
            }
            catch (OperationCanceledException) { }
            catch (Exception ex)
            {
                if (manual || UpdatePanel.IsVisible) { UpdatePanel.Visibility = Visibility.Visible; UpdateStatus.Text = "暂时无法更新 Hub · " + ex.Message; }
            }
        }
        private void OpenFolder(object sender, RoutedEventArgs e)
        {
            try { Process.Start(new ProcessStartInfo(library.Versions) { UseShellExecute = true }); }
            catch (Exception ex) { Message(ex.Message); }
        }
        private sealed record CardView(string Notes,string Date,long Size,string Hash,bool Present,bool Installed,string Update,bool Busy,bool Active);
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
                var view=new CardView(r.notes,r.date,r.size,r.sha256,present,present && library.Installed(r.version),upgrade?.version,activeVersion!=null && !present,activeVersion==r.version);
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
        private static TextBlock Label(string text, double size, string color) =>
            new TextBlock { Text = text, FontSize = size, TextWrapping = TextWrapping.Wrap, Foreground = ColorOf(color), VerticalAlignment = VerticalAlignment.Center };
        private Border BuildCard(Release r,CardView view,Release upgrade)
        {
            bool installed = view.Installed;
            bool damaged = !installed && view.Present;
            var panel = new StackPanel();
            var card = new Border { Style=(Style)FindResource("Card"), Child=panel };
            var header = new DockPanel();
            var version = Label("v" + r.version, 20, "#273344");
            version.FontWeight = FontWeights.SemiBold;
            var state = Label(damaged ? "需要修复" : installed ? "已安装" : "可安装", 13, damaged?"#873E27":installed ? "#27634F" : "#415F7A");
            DockPanel.SetDock(state, Dock.Right); header.Children.Add(state); header.Children.Add(version);
            panel.Children.Add(header);
            var detail = Label($"Windows  x64   ·   {r.date}" + (r.size > 0 ? $"   ·   {r.size / 1048576.0:F1} MiB" : ""), 12, "#526477");
            detail.Margin = new Thickness(0,4,0,10); panel.Children.Add(detail);
            if (!String.IsNullOrWhiteSpace(r.notes)) panel.Children.Add(Label(r.notes,14,"#394B5A"));
            var progress = new ProgressBar { Height=5, Maximum=100, Foreground=ColorOf("#295F88"), Background=ColorOf("#DEE5EA"), BorderThickness=new Thickness(0) };
            var status = Label("",12,"#526477");
            var action = new Button { Content=installed ? "启动" : "安装", MinWidth=86, Background=ColorOf("#285C80"), Foreground=ColorOf("#FFFFFF") };
            if (damaged) action.Visibility=Visibility.Collapsed;
            var bottom = new DockPanel { Margin=new Thickness(0,14,0,0) };
            DockPanel.SetDock(action,Dock.Right); bottom.Children.Add(action); bottom.Children.Add(status);
            action.Click += async (_, __) => {
                if (activeVersion == r.version && download != null) { download.Cancel(); return; }
                if (installed) { try { library.Launch(r.version); } catch (Exception ex) { status.Text = ex.Message; } }
                else await Install(r);
            };
            if (activeVersion == r.version)
            {
                action.Content="取消"; action.Background=ColorOf("#444A51"); action.Foreground=ColorOf("#FFFFFF");
            }
            else if (view.Busy) action.IsEnabled=false;
            panel.Children.Add(bottom);
            if (view.Present) AddMaintenanceButtons(panel,r,upgrade);
            progress.Margin = new Thickness(0,10,0,0);
            panel.Children.Add(progress);
            card.Tag = new Action<Transfer>(t => {
                bool running = r.version == activeVersion;
                progress.Visibility = running ? Visibility.Visible : Visibility.Collapsed;
                progress.IsIndeterminate = running && (t == null || t.Total == 0);
                status.Text = t?.Stage ?? "";
                if (t != null && t.Total > 0) {
                    progress.Value=100.0*t.Bytes/t.Total;
                    status.Text=$"{t.Stage}   {progress.Value:F0}%   ·   {t.Bytes/1048576.0:F1} / {t.Total/1048576.0:F1} MiB";
                }
            });
            card.Name = "V" + r.version.Replace('.','_');
            transfers.TryGetValue(r.version,out Transfer prior);
            ((Action<Transfer>)card.Tag)(prior);
            return card;
        }
        private async Task Install(Release r)
        {
            if (download != null) return;
            download = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
            ApplyButton.IsEnabled = false;
            activeVersion = r.version;
            transfers[r.version] = new Transfer("准备下载");
            Render();
            var progress = new Progress<Transfer>(t => {
                if (activeVersion != r.version) return;
                transfers[r.version]=t;
                var card = Cards.Children.OfType<Border>().FirstOrDefault(c => c.Name=="V"+r.version.Replace('.','_'));
                if (card != null) ((Action<Transfer>)card.Tag)(t);
            });
            try { await library.Install(r,progress,download.Token); transfers[r.version]=new Transfer("安装完成"); }
            catch (OperationCanceledException) { transfers[r.version]=new Transfer("已取消下载"); }
            catch (Exception ex) { transfers[r.version]=new Transfer("安装失败 · "+ex.Message); }
            finally {
                download.Dispose(); download=null; activeVersion=null; ApplyButton.IsEnabled=true;
                if (closing) Close(); else Render();
            }
        }
    }
}
