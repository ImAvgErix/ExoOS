using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

class Program
{
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, int nFlags);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] static extern void mouse_event(int dwFlags, int dx, int dy, int cButtons, int dwExtraInfo);
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }

    static Bitmap Cap(IntPtr h)
    {
        ShowWindow(h, 9);
        SetForegroundWindow(h);
        Thread.Sleep(400);
        GetWindowRect(h, out var r);
        int w = r.Right - r.Left, hh = r.Bottom - r.Top;
        var bmp = new Bitmap(w, hh);
        using var g = Graphics.FromImage(bmp);
        var hdc = g.GetHdc();
        PrintWindow(h, hdc, 2);
        g.ReleaseHdc(hdc);
        return bmp;
    }

    static void Click(int x, int y)
    {
        SetCursorPos(x, y);
        Thread.Sleep(80);
        mouse_event(0x02, 0, 0, 0, 0);
        mouse_event(0x04, 0, 0, 0, 0);
    }

    static void Main()
    {
        var outDir = @"C:\Users\Erix\Documents\ExoOS-repo\docs\media";
        Directory.CreateDirectory(outDir);
        var p = Process.GetProcessesByName("ExoOS").First(x => x.MainWindowHandle != IntPtr.Zero);
        var h = p.MainWindowHandle;
        GetWindowRect(h, out var r);

        Click(r.Left + 36, r.Top + 28);
        Thread.Sleep(1200);
        using (var home = Cap(h))
        {
            home.Save(Path.Combine(outDir, "home.png"), ImageFormat.Png);
            Console.WriteLine($"home {home.Width}x{home.Height}");
        }

        Click((r.Left + r.Right) / 2, r.Top + 28);
        Thread.Sleep(1200);
        using (var mod = Cap(h))
        {
            mod.Save(Path.Combine(outDir, "module.png"), ImageFormat.Png);
            Console.WriteLine($"module {mod.Width}x{mod.Height}");
        }
    }
}
