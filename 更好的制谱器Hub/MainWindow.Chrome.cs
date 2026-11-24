using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;

namespace RevelationHub;

public partial class MainWindow
{
    private const int WindowStyleIndex = -16;
    private const int MaximizeBoxStyle = 0x00010000;
    private const int SystemCommand = 0x0112;
    private const int MaximizeCommand = 0xF030;
    private const int NonClientDoubleClick = 0x00A3;
    private const int CaptionHit = 2;
    private const int NonClientHitTest = 0x0084;
    private enum Hit { Client=1, Title=CaptionHit, Left=10, Right, Top, TopLeft, TopRight, Bottom, BottomLeft, BottomRight }

    static MainWindow()
    {
        WindowStateProperty.OverrideMetadata(typeof(MainWindow), new FrameworkPropertyMetadata(
            WindowState.Normal, null, (_, value) => (WindowState)value == WindowState.Maximized ? WindowState.Normal : value));
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        var hwnd = new WindowInteropHelper(this).Handle;
        HwndSource.FromHwnd(hwnd).AddHook(WindowMessage);
        int style = GetWindowLongW(hwnd, WindowStyleIndex);
        SetWindowLongW(hwnd, WindowStyleIndex, style & ~MaximizeBoxStyle);
        // Recalculate the native frame without moving, resizing, activating or reordering the window.
        const uint refreshFrame = 0x0020 | 0x0001 | 0x0002 | 0x0010 | 0x0004;
        SetWindowPos(hwnd, IntPtr.Zero, 0, 0, 0, 0, refreshFrame);
    }

    private IntPtr WindowMessage(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message == NonClientHitTest && IsLoaded)
        {
            long coordinates = lParam.ToInt64();
            var screen = new Point(unchecked((short)coordinates), unchecked((short)(coordinates >> 16)));
            handled = true;
            return new IntPtr((int)HitTestFrame(PointFromScreen(screen)));
        }
        long command = wParam.ToInt64();
        if ((message == SystemCommand && (command & 0xFFF0) == MaximizeCommand) ||
            (message == NonClientDoubleClick && command == CaptionHit))
            handled = true;
        return IntPtr.Zero;
    }

    private Hit HitTestFrame(Point point)
    {
        const double grip = 6;
        bool left = point.X < grip, right = point.X >= ActualWidth - grip;
        bool top = point.Y < grip, bottom = point.Y >= ActualHeight - grip;
        if (top) return left ? Hit.TopLeft : right ? Hit.TopRight : Hit.Top;
        if (bottom) return left ? Hit.BottomLeft : right ? Hit.BottomRight : Hit.Bottom;
        if (left) return Hit.Left;
        if (right) return Hit.Right;
        bool Inside(FrameworkElement element) => new Rect(element.RenderSize).Contains(TranslatePoint(point, element));
        if (!FeedbackOverlay.IsVisible && Inside(TitleBar) && !Inside(Groups) && !Inside(CaptionButtons)) return Hit.Title;
        return Hit.Client;
    }

    private void ClipWindowFrame(object sender, SizeChangedEventArgs e)
    {
        var frame = (Border)sender;
        double radius = frame.CornerRadius.TopLeft;
        frame.Clip = new RectangleGeometry(new Rect(e.NewSize), radius, radius);
    }

    [DllImport("user32.dll")]
    private static extern int GetWindowLongW(IntPtr hwnd, int index);

    [DllImport("user32.dll")]
    private static extern int SetWindowLongW(IntPtr hwnd, int index, int style);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(IntPtr hwnd, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
}
