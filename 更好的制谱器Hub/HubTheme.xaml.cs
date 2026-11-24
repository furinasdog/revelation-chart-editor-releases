using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace RevelationHub;

public partial class HubTheme : ResourceDictionary
{
    public HubTheme() => InitializeComponent();

    private const double Hover = .14;
    private const double Pressed = .24;

    private void ButtonMotion(object sender, MouseEventArgs e)
    {
        var button = (Button)sender;
        Animate(button, button.IsMouseOver ? (button.IsPressed ? Pressed : Hover) : 0);
    }

    private void ButtonPress(object sender, MouseButtonEventArgs e)
    {
        var button = (Button)sender;
        Animate(button, e.ButtonState == MouseButtonState.Pressed ? Pressed : button.IsMouseOver ? Hover : 0);
    }

    private static void Animate(Button button, double opacity)
    {
        if (button.Template?.FindName("HoverFill", button) is not Border fill) return;
        if (fill.RenderTransform is not ScaleTransform scale)
        {
            scale = new ScaleTransform(.96, .96);
            fill.RenderTransformOrigin = new Point(.5, .5);
            fill.RenderTransform = scale;
        }

        bool motion = Window.GetWindow(button) is MainWindow window && window.AnimateControls;
        var duration = TimeSpan.FromMilliseconds(opacity == 0 ? 180 : 120);
        double size = opacity == 0 ? .96 : opacity >= Pressed ? .975 : 1;
        void Move(Animatable target, DependencyProperty property, double to)
        {
            double from = (double)target.GetValue(property);
            target.SetValue(property, to);
            target.BeginAnimation(property, motion ? Ease(from, to, duration) : null);
        }

        double previous = fill.Opacity;
        fill.Opacity = opacity;
        fill.BeginAnimation(UIElement.OpacityProperty, motion ? Ease(previous, opacity, duration) : null);
        Move(scale, ScaleTransform.ScaleXProperty, size);
        Move(scale, ScaleTransform.ScaleYProperty, size);
    }

    private static DoubleAnimation Ease(double from, double to, TimeSpan duration) => new(from, to, duration)
    {
        EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
        FillBehavior = FillBehavior.Stop
    };
}
