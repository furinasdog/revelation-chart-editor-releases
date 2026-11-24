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

namespace RevelationHub
{
    public partial class MainWindow : Window
    {
        private readonly HttpClient http = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
        private readonly Distribution library;
        private readonly CancellationTokenSource lifetime = new CancellationTokenSource();
        private readonly Dictionary<string, Transfer> transfers = new Dictionary<string, Transfer>();
        private Release[] available = Array.Empty<Release>();
        private CancellationTokenSource download;
        private string activeVersion;
        private bool onlyInstalled, closing;
        private static SolidColorBrush ColorOf(string hex) => new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));

        public MainWindow()
        {
            InitializeComponent();
            http.DefaultRequestHeaders.UserAgent.ParseAdd("RevelationHub/1.1");
            var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RevelationHub");
            library = new Distribution(root, http);
            Loaded += async (_, __) => {
                try { available = library.Offline(); CatalogStatus.Text = library.CatalogSource; Render(); await Refresh(); }
                catch (Exception ex) { CatalogStatus.Text = ex.Message; }
            };
            Closing += OnClosing;
            Closed += (_, __) => { lifetime.Cancel(); http.Dispose(); };
        }
        private void OnClosing(object sender, CancelEventArgs e)
        {
            if (download == null) return;
            e.Cancel = true;
            closing = true;
            download.Cancel();
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
        private async void RefreshClick(object sender, RoutedEventArgs e) => await Refresh();
        private void ShowLibrary(object sender, RoutedEventArgs e) { onlyInstalled = false; Render(); }
        private void ShowInstalled(object sender, RoutedEventArgs e) { onlyInstalled = true; Render(); }
        private void OpenFolder(object sender, RoutedEventArgs e)
        {
            try { Process.Start(new ProcessStartInfo(library.Versions) { UseShellExecute = true }); }
            catch (Exception ex) { CatalogStatus.Text = ex.Message; }
        }
        private void Render()
        {
            LibraryTab.Background = ColorOf(onlyInstalled ? "#191D22" : "#353A42");
            InstalledTab.Background = ColorOf(onlyInstalled ? "#353A42" : "#191D22");
            PageTitle.Text = onlyInstalled ? "已安装" : "版本库";
            var releases = available.ToList();
            foreach (string v in library.LocalVersions())
                if (releases.All(r => r.version != v)) releases.Add(new Release {version=v});
            Cards.Children.Clear();
            foreach (var r in releases.OrderByDescending(item => Version.Parse(item.version)))
                if (!onlyInstalled || library.Installed(r.version)) AddCard(r);
            EmptyState.Text = Cards.Children.Count > 0 ? "" : onlyInstalled ? "还没有安装制谱器。可在版本库选择版本安装。" : "当前没有可用版本。";
        }
        private static TextBlock Label(string text, double size, string color) =>
            new TextBlock { Text = text, FontSize = size, TextWrapping = TextWrapping.Wrap, Foreground = ColorOf(color), VerticalAlignment = VerticalAlignment.Center };
        private void AddCard(Release r)
        {
            bool installed = library.Installed(r.version);
            var panel = new StackPanel();
            var card = new Border { Background = ColorOf("#24282E"), BorderBrush = ColorOf("#41464C"),
                BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(6), Margin = new Thickness(0,0,6,14),
                Padding = new Thickness(20,17,20,15), Child = panel };
            var header = new DockPanel();
            var version = Label("v" + r.version, 23, "#F3F4F5");
            version.FontWeight = FontWeights.SemiBold;
            var state = Label(installed ? "已安装" : "可安装", 13, installed ? "#96D1A5" : "#F3C654");
            DockPanel.SetDock(state, Dock.Right); header.Children.Add(state); header.Children.Add(version);
            panel.Children.Add(header);
            var detail = Label($"Windows  x64   ·   {r.date}" + (r.size > 0 ? $"   ·   {r.size / 1048576.0:F1} MiB" : ""), 12, "#B0BAC5");
            detail.Margin = new Thickness(0,4,0,10); panel.Children.Add(detail);
            if (!String.IsNullOrWhiteSpace(r.notes)) panel.Children.Add(Label(r.notes,14,"#DADEE3"));
            var progress = new ProgressBar { Height=6, Maximum=100, Foreground=ColorOf("#F3C654"), Background=ColorOf("#434950"), BorderThickness=new Thickness(0) };
            var status = Label("",12,"#CBD4DD");
            var action = new Button { Content=installed ? "启动" : "安装", MinWidth=86, Background=ColorOf("#F3C654"), Foreground=ColorOf("#191915") };
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
            else if (!installed && download != null) action.IsEnabled=false;
            panel.Children.Add(bottom);
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
            Cards.Children.Add(card);
        }
        private async Task Install(Release r)
        {
            if (download != null) return;
            download = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
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
                download.Dispose(); download=null; activeVersion=null;
                if (closing) Close(); else Render();
            }
        }
    }
}
