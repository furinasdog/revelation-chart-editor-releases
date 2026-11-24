using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media.Animation;

namespace RevelationHub;

public partial class HubTheme : ResourceDictionary
{
    public HubTheme() => InitializeComponent();
        private void ButtonMotion(object sender, MouseEventArgs e) => Animate((Button)sender,((Button)sender).IsMouseOver ? .15 : 0);
        private void ButtonPress(object sender, MouseButtonEventArgs e) => Animate((Button)sender,e.ButtonState==MouseButtonState.Pressed ? .29 : ((Button)sender).IsMouseOver ? .15 : 0);
        private static void Animate(Button b,double target)
        {
            if (b.Template?.FindName("HoverFill", b) is not Border fill) return;
            double prior = fill.Opacity;
            fill.BeginAnimation(UIElement.OpacityProperty,null);
            fill.Opacity=target;
            if (Window.GetWindow(b) is MainWindow w && w.AnimateControls)
                fill.BeginAnimation(UIElement.OpacityProperty,new DoubleAnimation(prior,target,TimeSpan.FromMilliseconds(125))
                    {EasingFunction=new CubicEase{EasingMode=EasingMode.EaseOut},FillBehavior=FillBehavior.Stop});
        }
}
