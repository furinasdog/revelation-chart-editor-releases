using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace RevelationHub;

internal static class HubMotion
{
    internal static DoubleAnimationUsingKeyFrames Tween(double from, double to, int duration, int delay = 0, bool settle = false)
    {
        var frames = new DoubleAnimationUsingKeyFrames { FillBehavior = FillBehavior.Stop };
        frames.KeyFrames.Add(new DiscreteDoubleKeyFrame(from, TimeSpan.Zero));
        if (delay > 0) frames.KeyFrames.Add(new DiscreteDoubleKeyFrame(from, TimeSpan.FromMilliseconds(delay)));
        EasingFunctionBase curve = settle ? new BackEase { Amplitude = .55 } : new CubicEase();
        curve.EasingMode = EasingMode.EaseOut;
        frames.KeyFrames.Add(new EasingDoubleKeyFrame(to, TimeSpan.FromMilliseconds(delay + duration), curve));
        return frames;
    }

    internal static void Scale(ScaleTransform scale, double to, int duration, bool motion)
    {
        double x = scale.ScaleX, y = scale.ScaleY;
        scale.ScaleX = scale.ScaleY = to;
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, motion ? Tween(x, to, duration) : null);
        scale.BeginAnimation(ScaleTransform.ScaleYProperty, motion ? Tween(y, to, duration) : null);
    }
}

internal sealed class PageCard : Border
{
    private readonly TranslateTransform travel = new();
    private readonly TranslateTransform settle = new();

    internal PageCard(Style style, FrameworkElement content)
    {
        Style = style;
        Child = content;
        // Move the card's entire visual tree so text, controls and hit testing follow its face.
        var movement = new TransformGroup();
        movement.Children.Add(travel);
        movement.Children.Add(settle);
        RenderTransform = movement;
    }

    internal void Enter(int delay, bool motion)
    {
        BeginAnimation(OpacityProperty, motion ? HubMotion.Tween(0, 1, 105, delay) : null);
        travel.BeginAnimation(TranslateTransform.YProperty, motion ? HubMotion.Tween(-5,0,250,delay) : null);
        settle.BeginAnimation(TranslateTransform.YProperty, motion ? HubMotion.Tween(-11,0,350,delay,true) : null);
    }
}
