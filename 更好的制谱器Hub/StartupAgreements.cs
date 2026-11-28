using System;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;

namespace RevelationHub;

internal static class StartupAgreements
{
    internal static string Read(string resource)
    {
        using var stream = HubResources.Open(resource) ?? throw new InvalidDataException("随附许可缺失。");
        using var reader = new StreamReader(stream, Encoding.UTF8);
        string text = reader.ReadToEnd();
        return string.IsNullOrWhiteSpace(text) ? throw new InvalidDataException("随附许可为空。") : text;
    }

    internal static bool Confirm(string root)
    {
        string terms = Read("RevelationHub.license.user");
        string revision = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(terms)));
        string receipt = Path.Combine(root, "user-agreement");
        if (File.Exists(receipt) && new FileInfo(receipt).Length == 64 && File.ReadAllText(receipt) == revision)
            return Show("开源许可 · GNU GPL v3", Read("RevelationHub.license.gpl"), false);
        if (!Show("用户使用协议", terms, true) ||
            !Show("开源许可 · GNU GPL v3", Read("RevelationHub.license.gpl"), false))
            return false;
        Directory.CreateDirectory(root);
        string temporary = receipt + "." + Guid.NewGuid().ToString("N");
        try
        {
            File.WriteAllText(temporary, revision);
            File.Move(temporary, receipt, true);
        }
        finally
        {
            File.Delete(temporary);
        }
        return true;
    }

    private static bool Show(string title, string text, bool requireReview)
    {
        var window = new Window
        {
            Title = title, Width = Math.Min(740, SystemParameters.WorkArea.Width),
            Height = Math.Min(490, SystemParameters.WorkArea.Height), MinWidth = 340, MinHeight = 245,
            WindowStartupLocation = WindowStartupLocation.CenterScreen
        };
        var panel = new DockPanel { Margin = new Thickness(16) };
        window.Content = panel;
        var footer = new StackPanel { Margin = new Thickness(0, 10, 0, 0) };
        DockPanel.SetDock(footer, Dock.Bottom);
        panel.Children.Add(footer);
        var status = new TextBlock { Margin = new Thickness(0, 0, 0, 8) };
        if (requireReview) footer.Children.Add(status);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        footer.Children.Add(actions);
        var cancel = new Button { Content = "退出", MinWidth = 80, IsCancel = true };
        actions.Children.Add(cancel);
        var accept = new Button
        {
            Content = requireReview ? "同意并继续" : "已阅读",
            MinWidth = 100, IsDefault = true, IsEnabled = !requireReview, Margin = new Thickness(8, 0, 0, 0)
        };
        actions.Children.Add(accept);
        accept.Click += (_, _) => window.DialogResult = true;
        var reader = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Focusable = true };
        reader.Content = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, Padding = new Thickness(0, 0, 10, 0) };
        panel.Children.Add(reader);
        if (!requireReview) return window.ShowDialog() == true;

        var clock = new Stopwatch();
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(150) };
        void Update()
        {
            int remaining = Math.Max(0, (int)Math.Ceiling(15 - clock.Elapsed.TotalSeconds));
            bool atEnd = reader.VerticalOffset >= reader.ScrollableHeight - 0.5;
            accept.IsEnabled = remaining == 0 && atEnd;
            status.Text = remaining > 0 ? $"请阅读至文末，可确认还需 {remaining} 秒。"
                : atEnd ? "已到文末，可以确认。" : "请滚动到协议末尾。";
        }
        reader.ScrollChanged += (_, _) => Update();
        timer.Tick += (_, _) => Update();
        window.ContentRendered += (_, _) => { clock.Start(); timer.Start(); Update(); reader.Focus(); };
        window.Closed += (_, _) => timer.Stop();
        return window.ShowDialog() == true;
    }
}
