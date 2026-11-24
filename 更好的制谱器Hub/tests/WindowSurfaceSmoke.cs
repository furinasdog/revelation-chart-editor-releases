using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

internal partial class Program
{
    [StructLayout(LayoutKind.Sequential)]
    private struct ScreenPoint { public int X, Y; }
    [DllImport("user32.dll")] private static extern IntPtr WindowFromPhysicalPoint(ScreenPoint point);
    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr window, IntPtr dc);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleBitmap(IntPtr dc, int width, int height);
    [DllImport("gdi32.dll")] private static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);
    [DllImport("gdi32.dll")] private static extern bool BitBlt(IntPtr dest, int x, int y, int width, int height, IntPtr source, int sx, int sy, uint op);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr handle);

    private static void CheckWindowSurface(Window window, Color backdrop, string path)
    {
        var origin = window.PointToScreen(new Point(0, 0));
        var end = window.PointToScreen(new Point(window.ActualWidth, window.ActualHeight));
        int width = (int)(end.X - origin.X), height = (int)(end.Y - origin.Y);
        var hwnd = new WindowInteropHelper(window).Handle;
        foreach (var offset in new[]{new Point(.03,.03),new Point(.97,.03),new Point(.5,.5),new Point(.03,.97),new Point(.97,.97)})
            if (WindowFromPhysicalPoint(new ScreenPoint { X=(int)(origin.X+offset.X*width), Y=(int)(origin.Y+offset.Y*height) }) != hwnd)
                throw new InvalidOperationException("Test window must be unobscured before capture.");
        var desktop = GetDC(IntPtr.Zero);
        var local = CreateCompatibleDC(desktop);
        var bitmap = CreateCompatibleBitmap(desktop, width, height);
        var previous = SelectObject(local, bitmap);
        try
        {
            if (!BitBlt(local, 0, 0, width, height, desktop, (int)origin.X, (int)origin.Y, 0x40CC0020))
                throw new InvalidOperationException("Could not capture the test window.");
            var screen = Imaging.CreateBitmapSourceFromHBitmap(bitmap, IntPtr.Zero, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            var rgb = new FormatConvertedBitmap(screen, PixelFormats.Bgr32, null, 0);
            var pixels = new byte[width * height * 4];
            rgb.CopyPixels(pixels, width * 4, 0);
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(rgb));
            using (var output = File.Create(path)) encoder.Save(output);

            Color Pixel(int x, int y)
            {
                int i = (y * width + x) * 4;
                return Color.FromRgb(pixels[i+2], pixels[i+1], pixels[i]);
            }
            static int Difference(Color a, Color b) => Math.Max(Math.Abs(a.R-b.R), Math.Max(Math.Abs(a.G-b.G), Math.Abs(a.B-b.B)));
            int radius = (int)Math.Ceiling(14 * VisualTreeHelper.GetDpi(window).DpiScaleX);
            foreach (bool left in new[]{true, false})
            foreach (bool top in new[]{true, false})
            {
                Color Sample(int x, int y) => Pixel(left ? x : width-1-x, top ? y : height-1-y);
                var inside = Sample(radius, radius);
                Check(Difference(Sample(0,0), backdrop) < 4, "Desktop shows through the outside of the rounded corner");
                bool blended = false;
                for (int y=0; y<radius; y++)
                for (int x=0; x<radius; x++)
                {
                    var p = Sample(x,y);
                    if (top && (p.R > Math.Max(inside.R,backdrop.R)+9 || p.G > Math.Max(inside.G,backdrop.G)+9 || p.B > Math.Max(inside.B,backdrop.B)+9))
                        throw new InvalidOperationException($"Light fringe at title corner ({x},{y}): {p} between {backdrop} and {inside}");
                    if (Difference(p,backdrop)>4 && Difference(p,inside)>4) blended = true;
                }
                Check(blended, "Curved edge contains intermediate desktop-composited pixels");
            }
            // These two unoccupied title-bar columns cross the line drawn by a legacy caption.
            foreach (double fraction in new[]{.24, .76})
            {
                int x = (int)(width*fraction);
                var header = Pixel(x, radius);
                for (int y = 1; y < 3*radius; y++)
                    if (Difference(Pixel(x,y),header)>12)
                        throw new InvalidOperationException("Unexpected native caption line on the restored title bar.");
            }
            double dpi = VisualTreeHelper.GetDpi(window).DpiScaleX;
            for (int y=(int)(4*dpi); y<(int)(37*dpi); y++)
            {
                int bright = 0;
                for (int x=width-(int)(72*dpi); x<width-(int)(3*dpi); x++)
                    if (Pixel(x,y).R > 180) bright++;
                if (bright > 32*dpi) throw new InvalidOperationException("Unexpected legacy button strip on the restored title bar.");
            }
            Console.WriteLine("Only the custom title bar and window buttons are visible at " + dpi*100 + "% scaling");
        }
        finally
        {
            SelectObject(local, previous);
            DeleteObject(bitmap);
            DeleteDC(local);
            ReleaseDC(IntPtr.Zero, desktop);
        }
    }

}
