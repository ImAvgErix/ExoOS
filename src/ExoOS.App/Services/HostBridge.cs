using System.Collections.Concurrent;
using System.Text.Json;
using System.Windows;
using ExoForge.Engine;
using ExoForge.Schema;
using Microsoft.Web.WebView2.Core;
using Microsoft.Win32;

namespace ExoOS.Services;

/// <summary>JSON-RPC between React UI and ExoForge engine.</summary>
public sealed class HostBridge
{
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true
    };

    private readonly ConcurrentDictionary<string, bool> _options = new(StringComparer.OrdinalIgnoreCase);
    private CoreWebView2? _web;

    public HostBridge()
    {
        foreach (var (k, v) in DefaultOptions())
            _options[k] = v;
        LoadPersistedOptions();
    }

    public void Attach(CoreWebView2 web)
    {
        _web = web;
        web.WebMessageReceived += OnMessage;
    }

    private void OnMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        try
        {
            var raw = e.WebMessageAsJson;
            // Some hosts wrap a second time as a JSON string.
            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;
            string payload = raw;
            if (root.ValueKind == JsonValueKind.String)
                payload = root.GetString() ?? raw;

            using var msg = JsonDocument.Parse(payload);
            var el = msg.RootElement;
            var id = el.TryGetProperty("id", out var idEl) ? idEl.GetInt32() : 0;
            var method = el.TryGetProperty("method", out var mEl) ? mEl.GetString() ?? "" : "";
            var paramsJson = el.TryGetProperty("params", out var p) ? p.GetRawText() : "{}";

            // drag/close must hit the UI thread immediately (not Task.Run)
            if (method is "drag" or "close")
            {
                try
                {
                    using var paramsDoc = JsonDocument.Parse(paramsJson);
                    var result = DispatchAsync(method, paramsDoc.RootElement.Clone())
                        .GetAwaiter().GetResult();
                    Reply(id, result, null);
                }
                catch (Exception ex)
                {
                    Reply(id, null, ex.Message);
                }
                return;
            }

            _ = Task.Run(async () =>
            {
                try
                {
                    using var paramsDoc = JsonDocument.Parse(paramsJson);
                    var result = await DispatchAsync(method, paramsDoc.RootElement.Clone());
                    Reply(id, result, null);
                }
                catch (Exception ex)
                {
                    Reply(id, null, ex.Message);
                }
            });
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine(ex);
        }
    }

    private async Task<object?> DispatchAsync(string method, JsonElement paramsEl)
    {
        switch (method)
        {
            case "getDashboard":
                return GetDashboard();
            case "getLive":
                return await Task.Run(SystemSnapshot.GetLive);
            case "getOptions":
                return GetOptionsList();
            case "setOptions":
                if (paramsEl.ValueKind != JsonValueKind.Undefined &&
                    paramsEl.TryGetProperty("options", out var opts))
                {
                    foreach (var prop in opts.EnumerateObject())
                        _options[prop.Name] = prop.Value.GetBoolean();
                    SavePersistedOptions();
                }
                return null;
            case "preview":
                return await Task.Run(() => RunPlaybook(dryRun: true));
            case "apply":
                // Setup questions capture intent — no type-to-confirm gate in the product UI.
                return await Task.Run(() => RunPlaybook(dryRun: false));
            case "close":
                Application.Current.Dispatcher.Invoke(() => Application.Current.MainWindow?.Close());
                return null;
            case "drag":
                Application.Current.Dispatcher.Invoke(() =>
                {
                    if (Application.Current.MainWindow is MainWindow mw)
                        mw.BeginDrag();
                });
                return null;
            case "openDocs":
                try
                {
                    ProcessStart("https://github.com/ImAvgErix/ExoOS");
                }
                catch { /* */ }
                return null;
            case "openUrl":
                try
                {
                    var url = paramsEl.TryGetProperty("url", out var urlEl)
                        ? urlEl.GetString()
                        : null;
                    if (!string.IsNullOrWhiteSpace(url) &&
                        (url.StartsWith("https://", StringComparison.OrdinalIgnoreCase) ||
                         url.StartsWith("http://", StringComparison.OrdinalIgnoreCase)))
                        ProcessStart(url);
                }
                catch { /* */ }
                return null;
            case "getOnboarding":
                return new { complete = IsOnboardingComplete(), answers = LoadPersistedAnswersRaw() };
            case "completeOnboarding":
                if (paramsEl.ValueKind != JsonValueKind.Undefined &&
                    paramsEl.TryGetProperty("answers", out var answersEl) &&
                    answersEl.ValueKind is not JsonValueKind.Undefined and not JsonValueKind.Null)
                {
                    SavePersistedAnswers(answersEl.GetRawText());
                }
                SavePersistedOptions();
                SetOnboardingComplete(true);
                return null;
            case "resetOnboarding":
                ClearPersistedOptions();
                SetOnboardingComplete(false);
                return null;
            default:
                throw new InvalidOperationException("Unknown method: " + method);
        }
    }

    private object GetDashboard()
    {
        string state = "ready";
        string detail;
        string name = "Exo OS";
        string playbookVersion = "—";
        string appVersion = typeof(HostBridge).Assembly.GetName().Version is { } av
            ? $"{av.Major}.{av.Minor}.{av.Build}"
            : "1.8.0";
        var actions = 0;
        var admin = IsAdmin();

        try
        {
            var loaded = PlaybookLoader.Load(PlaybookPaths.Resolve());
            name = loaded.Manifest.Name;
            playbookVersion = loaded.Manifest.Version;
            actions = loaded.Documents.Sum(d => d.Doc.Actions.Count);
            if (!admin)
            {
                state = "blocked";
                detail = "Run as Administrator to apply.";
            }
            else if (IsApplied())
            {
                state = "applied";
                detail = $"{actions:N0} actions · already applied on this PC";
            }
            else
            {
                state = "ready";
                detail = $"{actions:N0} actions ready · reboot after apply";
            }
        }
        catch (Exception ex)
        {
            state = "missing";
            detail = ex.Message;
        }

        return new
        {
            version = playbookVersion,
            appVersion,
            playbookName = name,
            actionCount = actions,
            state,
            detail,
            isAdmin = admin,
            osLabel = SystemSnapshot.GetOsLabel(),
            specs = SystemSnapshot.GetSpecs()
        };
    }

    private object GetOptionsList()
    {
        // Runtimes (DirectX / .NET / VC++) always install — not listed as toggles.
        var labels = new (string key, string label)[]
        {
            ("defenderStrip", "Strip Defender"),
            ("serviceStrip", "Service strip"),
            ("removeAi", "Remove AI / Copilot"),
            ("removeOneDrive", "Remove OneDrive"),
            ("stripEdge", "Edge cleanup"),
            ("privacyHosts", "Privacy hosts"),
            ("dismStrip", "DISM strip"),
            ("disableVbs", "Disable VBS"),
            // Extras
            ("install7zip", "Install 7-Zip"),
            ("installSnipping", "Install Snipping Tool"),
            ("installPhotos", "Install Photos"),
            ("installNotepad", "Install Notepad"),
            ("installTerminalPreview", "Install Terminal Preview"),
            ("installPowerShellPreview", "Install PowerShell Preview"),
            // Browsers
            ("installBrave", "Install Brave"),
            ("installHelium", "Install Helium"),
            ("installZen", "Install Zen"),
            ("installLibreWolf", "Install LibreWolf"),
            ("extremeMode", "Extreme (Maximum FPS)"),
            ("stripEdge", "Strip Edge"),
            // Apps
            ("installSteam", "Install Steam"),
            ("installDiscord", "Install Discord"),
            ("installEpic", "Install Epic"),
            ("installRiot", "Install Riot Client"),
            ("installRevo", "Install Revo Uninstaller"),
            ("installObs", "Install OBS Studio"),
            ("installSpotify", "Install Spotify"),
        };
        return labels.Select(l => new
        {
            key = l.key,
            label = l.label,
            value = _options.GetValueOrDefault(l.key)
        }).ToList();
    }

    private object RunPlaybook(bool dryRun)
    {
        void Progress(int p) => Emit("progress", new { percent = p });

        Progress(4);
        var optionMap = _options.ToDictionary(
            kv => kv.Key,
            kv => kv.Value ? "true" : "false",
            StringComparer.OrdinalIgnoreCase);

        // Ensure optional software keys exist (setup / defaults fill real values)
        foreach (var k in new[]
                 {
                     "installChrome", "installFirefox", "installBrave", "installHelium", "installZen",
                     "installLibreWolf", "install7zip", "installSnipping", "installPhotos", "installNotepad",
                     "installTerminalPreview", "installPowerShellPreview", "installSteam", "installDiscord",
                     "installEpic", "installRiot", "installRevo", "installObs", "installSpotify",
                     "amoled", "disableTransparency", "dnsCloudflare", "dnsGoogle", "dnsQuad9",
                     "extremeMode", "dismStrip", "disableVbs", "serviceStrip", "defenderStrip",
                     "removeAi", "removeOneDrive", "stripEdge", "privacyHosts"
                 })
            optionMap.TryAdd(k, "false");

        // Always install common gaming runtimes (not setup toggles)
        foreach (var k in new[] {
                     "installDirectX", "installVcRedist", "installDotNet8", "installDotNet10" })
            optionMap[k] = "true";

        var log = new System.Text.StringBuilder();
        log.AppendLine(dryRun ? "ExoOS dry-run" : "ExoOS apply");
        log.AppendLine("Playbook: " + PlaybookPaths.Resolve());
        log.AppendLine();

        Progress(12);
        var loaded = PlaybookLoader.Load(PlaybookPaths.Resolve());
        var extreme = optionMap.GetValueOrDefault("extremeMode") == "true";
        var exec = new ActionExecutor(loaded, new ApplyOptions
        {
            DryRun = dryRun,
            // Maximum FPS / extremeMode unlocks nuclear-risk actions (WU block, mitigations, etc.)
            AllowNuclear = extreme || optionMap.GetValueOrDefault("nuclearMode") == "true",
            AllowAcSensitive = extreme || optionMap.GetValueOrDefault("disableVbs") == "true",
            OptionOverrides = optionMap
        });
        var report = exec.Run();

        foreach (var r in report.Results)
        {
            if (r.Kind == ActionResultKind.Failed)
                log.AppendLine($"FAIL  {r.ActionType}  {r.ActionId}: {r.Message}");
            else if (!dryRun && r.Kind == ActionResultKind.Applied)
                log.AppendLine($"OK    {r.ActionType}  {r.ActionId}");
        }
        log.AppendLine();
        log.AppendLine($"applied={report.Applied}  skipped={report.Skipped}  failed={report.Failed}");
        Progress(100);

        return new
        {
            dryRun,
            applied = report.Applied,
            skipped = report.Skipped,
            failed = report.Failed,
            log = log.ToString()
        };
    }

    private void Reply(int id, object? result, string? error)
    {
        var web = _web;
        if (web is null) return;
        var payload = JsonSerializer.Serialize(new { id, result, error }, JsonOpts);
        // Post as JSON object so the UI receives a structured message
        Application.Current.Dispatcher.Invoke(() =>
        {
            try { web.PostWebMessageAsJson(payload); }
            catch { /* window closing */ }
        });
    }

    private void Emit(string eventName, object data)
    {
        var web = _web;
        if (web is null) return;
        var payload = JsonSerializer.Serialize(new { @event = eventName, data }, JsonOpts);
        Application.Current.Dispatcher.Invoke(() =>
        {
            try { web.PostWebMessageAsJson(payload); }
            catch { /* */ }
        });
    }

    // Defaults align with Balanced (safe ceiling). Extreme/Privacy set via onboarding answersToOptions.
    private static Dictionary<string, bool> DefaultOptions() => new(StringComparer.OrdinalIgnoreCase)
    {
        ["defenderStrip"] = false,
        ["serviceStrip"] = false,
        ["removeAi"] = true,
        ["removeOneDrive"] = true,
        // Browsers are essentials — do not force Edge uninstall by default
        ["stripEdge"] = false,
        ["privacyHosts"] = true,
        ["dismStrip"] = false,
        ["disableVbs"] = false,
        ["extremeMode"] = false,
        ["installDirectX"] = true,
        ["installVcRedist"] = true,
        ["installDotNet8"] = true,
        ["installDotNet10"] = true,
        // extras defaults (match setup)
        ["install7zip"] = true,
        ["installSnipping"] = true,
        ["installPhotos"] = true,
        ["installNotepad"] = true,
        ["installTerminalPreview"] = true,
        ["installPowerShellPreview"] = false,
        // browsers / apps off until setup
        ["installBrave"] = false,
        ["installHelium"] = false,
        ["installZen"] = false,
        ["installFirefox"] = false,
        ["installLibreWolf"] = false,
        ["installChrome"] = false,
        ["installSteam"] = false,
        ["installDiscord"] = false,
        ["installEpic"] = false,
        ["installRiot"] = false,
        ["installRevo"] = false,
        ["installObs"] = false,
        ["installSpotify"] = false,
    };

    private static bool IsApplied()
    {
        try
        {
            using var k = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\ExoOS");
            return k?.GetValue("Applied") is int i && i == 1;
        }
        catch { return false; }
    }

    private static bool IsAdmin()
    {
        try
        {
            using var id = System.Security.Principal.WindowsIdentity.GetCurrent();
            return new System.Security.Principal.WindowsPrincipal(id)
                .IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
        }
        catch { return false; }
    }

    private static void ProcessStart(string url)
    {
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
        {
            FileName = url,
            UseShellExecute = true
        });
    }

    private static string? LoadPersistedAnswersRaw()
    {
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(@"Software\ExoOS");
            return k?.GetValue("AnswersJson") as string;
        }
        catch
        {
            return null;
        }
    }

    private static bool IsOnboardingComplete()
    {
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(@"Software\ExoOS");
            return k?.GetValue("OnboardingComplete") is int i && i == 1;
        }
        catch { return false; }
    }

    private static void SetOnboardingComplete(bool complete)
    {
        using var k = Registry.CurrentUser.CreateSubKey(@"Software\ExoOS");
        k?.SetValue("OnboardingComplete", complete ? 1 : 0, RegistryValueKind.DWord);
    }

    private void LoadPersistedOptions()
    {
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(@"Software\ExoOS");
            var json = k?.GetValue("OptionsJson") as string;
            if (string.IsNullOrWhiteSpace(json)) return;
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return;
            foreach (var prop in doc.RootElement.EnumerateObject())
            {
                if (prop.Value.ValueKind == JsonValueKind.True ||
                    prop.Value.ValueKind == JsonValueKind.False)
                    _options[prop.Name] = prop.Value.GetBoolean();
            }
        }
        catch
        {
            /* keep defaults */
        }
    }

    private void SavePersistedOptions()
    {
        try
        {
            var map = _options.ToDictionary(
                kv => kv.Key,
                kv => kv.Value,
                StringComparer.OrdinalIgnoreCase);
            var json = JsonSerializer.Serialize(map, JsonOpts);
            using var k = Registry.CurrentUser.CreateSubKey(@"Software\ExoOS");
            k?.SetValue("OptionsJson", json, RegistryValueKind.String);
        }
        catch
        {
            /* non-fatal */
        }
    }

    private static void SavePersistedAnswers(string answersJson)
    {
        try
        {
            using var k = Registry.CurrentUser.CreateSubKey(@"Software\ExoOS");
            k?.SetValue("AnswersJson", answersJson, RegistryValueKind.String);
        }
        catch
        {
            /* non-fatal */
        }
    }

    private void ClearPersistedOptions()
    {
        try
        {
            using var k = Registry.CurrentUser.CreateSubKey(@"Software\ExoOS");
            k?.DeleteValue("OptionsJson", throwOnMissingValue: false);
            k?.DeleteValue("AnswersJson", throwOnMissingValue: false);
            foreach (var (key, value) in DefaultOptions())
                _options[key] = value;
        }
        catch
        {
            /* non-fatal */
        }
    }
}
