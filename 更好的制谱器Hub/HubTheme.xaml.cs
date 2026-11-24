using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

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

    private void ButtonKey(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Space || e.IsRepeat) return;
        var button = (Button)sender;
        Animate(button, e.IsDown ? Pressed : button.IsMouseOver ? Hover : 0);
    }

    private void ButtonBlur(object sender, KeyboardFocusChangedEventArgs e)
    {
        var button = (Button)sender;
        Animate(button,button.IsMouseOver ? Hover : 0);
    }

    private static void Animate(Button button, double opacity)
    {
        if (button.Template?.FindName("HoverFill", button) is not Border fill) return;
        if (fill.RenderTransform is not ScaleTransform scale)
        {
            scale = new ScaleTransform(.84, .84);
            fill.RenderTransformOrigin = new Point(.5, .5);
            fill.RenderTransform = scale;
        }

        bool motion = Window.GetWindow(button) is MainWindow window && window.AnimateControls;
        bool pressed = opacity >= Pressed;
        int duration = pressed ? 60 : opacity > 0 ? 90 : 150;
        double previous = fill.Opacity;
        fill.Opacity = opacity;
        fill.BeginAnimation(UIElement.OpacityProperty, motion ? HubMotion.Tween(previous,opacity,duration) : null);
        HubMotion.Scale(scale, opacity == 0 ? .84 : 1, duration + 60,motion);
        if (button.Template.FindName("PressFace",button) is FrameworkElement face)
        {
            if (face.RenderTransform is not ScaleTransform pressScale)
                face.RenderTransform = pressScale = new ScaleTransform();
            HubMotion.Scale(pressScale, motion && pressed ? .955 : 1, pressed ? 80 : 300,motion);
        }
    }
}
