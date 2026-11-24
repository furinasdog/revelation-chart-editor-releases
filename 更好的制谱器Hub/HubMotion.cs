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

// Only the painted surface travels. Fields and their hit areas keep their final coordinates.
internal sealed class PageCard : Border
{
    private readonly Border surface;
    private readonly TranslateTransform offset = new();

    internal PageCard(Style style, FrameworkElement content)
    {
        surface = new Border { Style = style, IsHitTestVisible = false, RenderTransform = offset };
        Margin = surface.Margin;
        surface.Margin = new Thickness(0);
        var layers = new Grid { ClipToBounds = true };
        layers.Children.Add(surface);
        layers.Children.Add(new Border { BorderThickness = surface.BorderThickness, Padding = surface.Padding, Child = content });
        Child = layers;
    }

    internal void Enter(int delay, bool motion)
    {
        BeginAnimation(OpacityProperty, motion ? HubMotion.Tween(0, 1, 105, delay) : null);
        offset.BeginAnimation(TranslateTransform.YProperty, motion ? HubMotion.Tween(-14, 0, 335, delay, true) : null);
    }
}
