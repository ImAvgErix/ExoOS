using System.IO;
using System.Windows;
using System.Windows.Input;
using ExoOS.Services;
using Microsoft.Web.WebView2.Core;

namespace ExoOS;

public partial class MainWindow : Window
{
    private readonly HostBridge _bridge = new();

    public MainWindow()
    {
        InitializeComponent();
        Loaded += async (_, _) => await InitWebAsync();
    }

    private void DragStrip_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left) return;
        if (e.OriginalSource is System.Windows.Controls.Button) return;
        if (e.ClickCount == 2) return;
        try { DragMove(); }
        catch { /* */ }
    }

    private void Minimize_Click(object sender, RoutedEventArgs e) =>
        WindowState = WindowState.Minimized;

    private void Close_Click(object sender, RoutedEventArgs e) => Close();

    private async Task InitWebAsync()
    {
        try
        {
            var userData = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "ExoOS", "WebView2");
            Directory.CreateDirectory(userData);

            var opts = new CoreWebView2EnvironmentOptions();
            // Compositor-friendly flags for stable 60+ Hz UI
            var args = new List<string>
            {
                "--force-renderer-accessibility",
                "--enable-gpu-rasterization",
                "--enable-zero-copy",
                "--ignore-gpu-blocklist",
                "--disable-features=CalculateNativeWinOcclusion",
            };
            var cdp = Environment.GetEnvironmentVariable("EXOOS_CDP");
            var cdpPort = Environment.GetEnvironmentVariable("EXOOS_CDP_PORT");
            if (string.Equals(cdp, "1", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(cdp, "true", StringComparison.OrdinalIgnoreCase) ||
                !string.IsNullOrWhiteSpace(cdpPort))
            {
                var port = 9229;
                if (!string.IsNullOrWhiteSpace(cdpPort) && int.TryParse(cdpPort, out var p) && p is > 0 and < 65536)
                    port = p;
                args.Add($"--remote-debugging-port={port}");
                Title = $"Exo OS  ·  CDP {port}";
            }
            opts.AdditionalBrowserArguments = string.Join(' ', args);

            var env = await CoreWebView2Environment.CreateAsync(null, userData, opts);
            await Web.EnsureCoreWebView2Async(env);

            Web.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
            Web.CoreWebView2.Settings.IsStatusBarEnabled = false;
            Web.CoreWebView2.Settings.AreDevToolsEnabled =
                !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("EXOOS_CDP")) ||
                !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("EXOOS_CDP_PORT"));

            try
            {
                await Web.CoreWebView2.Profile.ClearBrowsingDataAsync(
                    CoreWebView2BrowsingDataKinds.DiskCache | CoreWebView2BrowsingDataKinds.CacheStorage);
            }
            catch { /* older runtime */ }

            _bridge.Attach(Web.CoreWebView2);

            var www = ResolveWwwRoot();
            if (www is null)
            {
                BootPanel.Visibility = Visibility.Visible;
                if (BootPanel.Children[0] is System.Windows.Controls.TextBlock t0)
                    t0.Text = "UI not built. Run npm run build in src/ExoOS.App/ui";
                return;
            }

            Web.CoreWebView2.SetVirtualHostNameToFolderMapping(
                "exoos.local",
                www,
                CoreWebView2HostResourceAccessKind.Allow);

            Web.CoreWebView2.NavigationCompleted += (_, args) =>
            {
                if (args.IsSuccess)
                    BootPanel.Visibility = Visibility.Collapsed;
            };

            var stamp = Directory.GetLastWriteTimeUtc(www).Ticks;
            Web.CoreWebView2.Navigate($"https://exoos.local/index.html?v={stamp}");
        }
        catch (Exception ex)
        {
            BootPanel.Visibility = Visibility.Visible;
            if (BootPanel.Children[0] is System.Windows.Controls.TextBlock tb)
                tb.Text = "WebView2 failed: " + ex.Message;
        }
    }

    private static string? ResolveWwwRoot()
    {
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "wwwroot"),
            Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "wwwroot"),
            Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "src", "ExoOS.App", "wwwroot")),
        };
        foreach (var c in candidates)
        {
            try
            {
                var full = Path.GetFullPath(c);
                if (File.Exists(Path.Combine(full, "index.html")))
                    return full;
            }
            catch { /* */ }
        }
        return null;
    }
}
