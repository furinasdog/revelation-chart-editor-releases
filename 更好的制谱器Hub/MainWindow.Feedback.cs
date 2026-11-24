using System;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace RevelationHub;

public partial class MainWindow
{
    private int hintGeneration;
    private void NotifySync(bool success, string source) =>
        Message(success ? source : "版本库同步失败 · " + source, !success);

    private static DoubleAnimation Ease(double from, double to, int milliseconds) =>
        new(from,to,TimeSpan.FromMilliseconds(milliseconds)) {
            EasingFunction=new CubicEase { EasingMode=EasingMode.EaseOut }, FillBehavior=FillBehavior.Stop };

    private void EnterView(FrameworkElement view, double x, double y, int milliseconds)
    {
        var move=new TranslateTransform();
        view.RenderTransform=move;
        view.BeginAnimation(OpacityProperty,null);
        if (!AnimateControls) return;
        if (x!=0) move.BeginAnimation(TranslateTransform.XProperty,Ease(x,0,milliseconds));
        if (y!=0) move.BeginAnimation(TranslateTransform.YProperty,Ease(y,0,milliseconds));
        view.BeginAnimation(OpacityProperty,Ease(.55,1,milliseconds));
    }

    private async void Message(string text, bool error = false)
    {
        if (lifetime.IsCancellationRequested) return;
        if (SyncHint.IsVisible && SyncHintText.Text != text)
        {
            var prior = new Border { Background=SyncHint.Background, BorderBrush=SyncHint.BorderBrush,
                BorderThickness=SyncHint.BorderThickness, CornerRadius=SyncHint.CornerRadius,
                Padding=SyncHint.Padding, MaxWidth=SyncHint.MaxWidth, Margin=new Thickness(0,0,0,4),
                HorizontalAlignment=HorizontalAlignment.Right,
                Child=new TextBlock { Text=SyncHintText.Text, Foreground=SyncHintText.Foreground, FontSize=13, TextWrapping=TextWrapping.Wrap } };
            if (RecentHints.Children.Count >= 2) RecentHints.Children.RemoveAt(0);
            RecentHints.Children.Add(prior);
            _ = ExpireHint(prior);
        }
        int generation=++hintGeneration;
        SyncHint.Background=(Brush)FindResource(error ? "SyncFailure" : "SyncSuccess");
        SyncHint.BorderBrush=SyncHintText.Foreground=(Brush)FindResource(error ? "Warning" : "Success");
        SyncHintText.Text=text;
        SyncHint.Visibility=Visibility.Visible;
        SyncHint.Opacity=1;
        EnterView(SyncHint,SyncHint.MaxWidth,0,260);
        try
        {
            await Task.Delay(Math.Clamp(2200 + text.Length * 105, error ? 4800 : 3300, 18000),lifetime.Token);
            if (generation!=hintGeneration) return;
            if (AnimateControls)
            {
                SyncHint.Opacity=0;
                SyncHint.BeginAnimation(OpacityProperty,Ease(1,0,150));
                ((TranslateTransform)SyncHint.RenderTransform).BeginAnimation(TranslateTransform.XProperty,Ease(0,SyncHint.ActualWidth,150));
                await Task.Delay(150,lifetime.Token);
            }
            if (generation==hintGeneration)
            {
                SyncHint.Visibility=Visibility.Collapsed;
            }
        }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested) { }
    }

    private async Task ExpireHint(Border hint)
    {
        try { await Task.Delay(4200, lifetime.Token); RecentHints.Children.Remove(hint); }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested) { }
    }

    private void FadePage(FrameworkElement page)
    {
        page.BeginAnimation(OpacityProperty, AnimateControls ? Ease(.50, 1, 220) : null);
    }

    private void SetProgress(ProgressBar bar,double percent)
    {
        percent=Math.Clamp(percent,0,100);
        double prior=bar.Value;
        bar.Value=percent;
        bar.BeginAnimation(ProgressBar.ValueProperty,AnimateControls && percent>prior && bar.IsVisible ? Ease(prior,percent,150) : null);
    }
}
