using System.Diagnostics;
using System.Globalization;
using System.Runtime.Versioning;
using System.ServiceProcess;
using System.Text;
using System.Text.RegularExpressions;
using ExoForge.Schema;
using Microsoft.Win32;

namespace ExoForge.Engine;

/// <summary>
/// Read-only: compare playbook desired state against the live Windows system.
/// Proves what dry-run cannot — whether registry/services/tasks/appx/files actually match.
/// Scripts (run/cmd) are NotAuditable (side effects, no declared post-condition).
/// </summary>
public sealed class PlaybookAuditor
{
    private readonly LoadedPlaybook _playbook;
    private readonly ApplyOptions _options;
    private readonly Dictionary<string, string> _optionsMap;

    public PlaybookAuditor(LoadedPlaybook playbook, ApplyOptions options)
    {
        _playbook = playbook;
        _options = options;
        _optionsMap = PlaybookOptions.Merge(playbook.Manifest.DefaultOptions, options.OptionOverrides);
    }

    public ApplyReport Run()
    {
        var report = new ApplyReport
        {
            PlaybookId = _playbook.Manifest.Id,
            PlaybookVersion = _playbook.Manifest.Version,
            DryRun = true,
            Audit = true,
            StartedUtc = DateTimeOffset.UtcNow
        };

        var enabledTiers = PlaybookOptions.ResolveTiers(_playbook, _options);

        foreach (var (file, doc) in _playbook.Documents)
        {
            var tier = string.IsNullOrWhiteSpace(doc.Tier) ? "base" : doc.Tier;
            if (!enabledTiers.Contains(tier))
            {
                report.Results.Add(new ActionResult
                {
                    ActionType = "document",
                    ActionId = Path.GetFileName(file),
                    Kind = ActionResultKind.SkippedTierDisabled,
                    Message = $"Tier '{tier}' disabled"
                });
                continue;
            }

            foreach (var action in doc.Actions)
                report.Results.Add(AuditOne(action));
        }

        report.FinishedUtc = DateTimeOffset.UtcNow;
        return report;
    }

    private ActionResult AuditOne(PlaybookAction action)
    {
        if (!PlaybookOptions.Enabled(_optionsMap, action))
        {
            return R(action, ActionResultKind.SkippedOptionDisabled,
                $"Option '{action.WhenOption}' != '{action.OptionEquals ?? "true"}'");
        }

        var risk = (action.Risk ?? "safe").ToLowerInvariant();
        if (risk is "nuclear" && !PlaybookOptions.AllowsNuclear(_options, _optionsMap))
            return R(action, ActionResultKind.SkippedTierDisabled, "Nuclear blocked (pass --nuclear)");
        if (risk is "ac-sensitive" && !PlaybookOptions.AllowsAcSensitive(_options, _optionsMap))
            return R(action, ActionResultKind.SkippedTierDisabled, "AC-sensitive blocked (pass --ac-sensitive)");

        try
        {
            if (!OperatingSystem.IsWindows())
                return R(action, ActionResultKind.Failed, "Windows only");

            return action.Type.ToLowerInvariant() switch
            {
                "registry.set" or "reg.set" => AuditRegistrySet(action),
                "registry.delete" or "reg.delete" => AuditRegistryDelete(action),
                "service.set" => AuditService(action),
                "task.disable" => AuditTask(action, wantDisabled: true),
                "task.enable" => AuditTask(action, wantDisabled: false),
                "appx.remove" => AuditAppxRemoved(action),
                "file.delete" => AuditFileDelete(action),
                "file.write" => AuditFileWrite(action),
                "feature.disable" or "dism.feature.disable" => AuditFeature(action, enabled: false),
                "feature.enable" or "dism.feature.enable" => AuditFeature(action, enabled: true),
                "noop" or "note" or "status" => R(action, ActionResultKind.SkippedAlreadyDesired, action.Description ?? "note"),
                "run" or "cmd" or "powershell" or "taskkill" or "process.kill"
                    or "power.activate" or "power.import"
                    or "capability.remove" or "dism.capability.remove"
                    or "package.add" or "systempackage.add"
                    or "package.remove" or "systempackage.remove"
                    => R(action, ActionResultKind.NotAuditable,
                        $"No post-condition check for {action.Type} (scripts/side-effects)"),
                _ => R(action, ActionResultKind.NotAuditable, $"Unknown/unaudited type: {action.Type}")
            };
        }
        catch (Exception ex)
        {
            return R(action, ActionResultKind.Failed, ex.Message);
        }
    }

    [SupportedOSPlatform("windows")]
    private ActionResult AuditRegistrySet(PlaybookAction a)
    {
        if (string.IsNullOrWhiteSpace(a.Path))
            return R(a, ActionResultKind.Failed, "registry.set needs path");

        var valueName = a.ValueName ?? "";
        var type = (a.ValueType ?? "dword").ToLowerInvariant();
        if (type is "none" or "key")
        {
            using var keyOnly = OpenRead(a.Path!);
            return keyOnly is null
                ? R(a, ActionResultKind.Mismatch, $"Key missing: {a.Path}")
                : R(a, ActionResultKind.Match, $"Key exists: {a.Path}");
        }

        using var key = OpenRead(a.Path!);
        if (key is null)
            return R(a, ActionResultKind.Mismatch, $"Key missing: {a.Path}");

        var raw = key.GetValue(valueName, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
        if (raw is null)
            return R(a, ActionResultKind.Mismatch,
                $"Value missing: {a.Path}\\{(valueName.Length == 0 ? "(Default)" : valueName)} (want {a.Value})");

        var expected = NormalizeExpected(type, a.Value ?? "0");
        var actual = NormalizeActual(type, raw);
        if (ValuesEqual(type, expected, actual, raw))
            return R(a, ActionResultKind.Match,
                $"{a.Path}\\{(valueName.Length == 0 ? "(Default)" : valueName)} = {actual}");

        return R(a, ActionResultKind.Mismatch,
            $"{a.Path}\\{(valueName.Length == 0 ? "(Default)" : valueName)} want={expected} have={actual}");
    }

    [SupportedOSPlatform("windows")]
    private ActionResult AuditRegistryDelete(PlaybookAction a)
    {
        if (string.IsNullOrWhiteSpace(a.Path))
            return R(a, ActionResultKind.Failed, "registry.delete needs path");

        var valueName = a.ValueName ?? "";
        if (string.Equals(valueName, "__KEY__", StringComparison.OrdinalIgnoreCase)
            || string.Equals(valueName, "*", StringComparison.OrdinalIgnoreCase))
        {
            using var key = OpenRead(a.Path!);
            return key is null
                ? R(a, ActionResultKind.Match, $"Key absent: {a.Path}")
                : R(a, ActionResultKind.Mismatch, $"Key still present: {a.Path}");
        }

        using var k = OpenRead(a.Path!);
        if (k is null)
            return R(a, ActionResultKind.Match, $"Key absent (value gone): {a.Path}");

        var raw = k.GetValue(valueName, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
        return raw is null
            ? R(a, ActionResultKind.Match, $"Value absent: {a.Path}\\{valueName}")
            : R(a, ActionResultKind.Mismatch, $"Value still present: {a.Path}\\{valueName}={raw}");
    }

    [SupportedOSPlatform("windows")]
    private ActionResult AuditService(PlaybookAction a)
    {
        if (string.IsNullOrWhiteSpace(a.Service))
            return R(a, ActionResultKind.Failed, "service.set needs service");

        try
        {
            using var sc = new ServiceController(a.Service!);
            _ = sc.Status; // force query
        }
        catch (InvalidOperationException)
        {
            // Not installed — for disable goals this is acceptable
            if (string.Equals(a.Start, "disabled", StringComparison.OrdinalIgnoreCase))
                return R(a, ActionResultKind.Match, $"Service {a.Service} not installed (equivalent to disabled)");
            return R(a, ActionResultKind.Mismatch, $"Service {a.Service} not installed");
        }

        var startReg = ReadServiceStart(a.Service!);
        if (startReg is null)
            return R(a, ActionResultKind.Mismatch, $"Cannot read Start for {a.Service}");

        var (start, delayed) = startReg.Value;
        var want = (a.Start ?? "").ToLowerInvariant();
        var ok = want switch
        {
            "disabled" => start == 4,
            "manual" or "demand" => start == 3,
            "automatic" or "auto" => start == 2 && !delayed,
            "automaticdelayed" or "delayed" => start == 2 && delayed,
            "" => true,
            _ => false
        };

        if (!ok && want.Length > 0)
            return R(a, ActionResultKind.Mismatch,
                $"Service {a.Service} start want={want} have=start={start} delayed={delayed}");

        if (a.Stop == true)
        {
            using var sc = new ServiceController(a.Service!);
            if (sc.Status is not ServiceControllerStatus.Stopped and not ServiceControllerStatus.StopPending)
                return R(a, ActionResultKind.Mismatch, $"Service {a.Service} running (want stopped), status={sc.Status}");
        }

        return R(a, ActionResultKind.Match, $"Service {a.Service} start={start} delayed={delayed}");
    }

    [SupportedOSPlatform("windows")]
    private static (int start, bool delayed)? ReadServiceStart(string name)
    {
        using var key = Registry.LocalMachine.OpenSubKey($@"SYSTEM\CurrentControlSet\Services\{name}");
        if (key is null) return null;
        var startObj = key.GetValue("Start");
        if (startObj is not int start) return null;
        var delayed = Convert.ToInt32(key.GetValue("DelayedAutostart", 0)) != 0;
        return (start, delayed);
    }

    private ActionResult AuditTask(PlaybookAction a, bool wantDisabled)
    {
        if (string.IsNullOrWhiteSpace(a.TaskPath))
            return R(a, ActionResultKind.Failed, "task needs taskPath");

        var path = a.TaskPath!.Trim();
        if (!path.StartsWith('\\')) path = "\\" + path;

        var psi = new ProcessStartInfo
        {
            FileName = "schtasks.exe",
            Arguments = $"/Query /TN \"{path}\" /FO LIST /V",
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        using var p = Process.Start(psi);
        if (p is null) return R(a, ActionResultKind.Failed, "schtasks failed to start");
        var stdout = p.StandardOutput.ReadToEnd();
        var stderr = p.StandardError.ReadToEnd();
        p.WaitForExit(15_000);

        var errBlob = stdout + stderr;
        if (p.ExitCode != 0 || Regex.IsMatch(errBlob, @"ERROR:|cannot find|does not exist", RegexOptions.IgnoreCase))
        {
            // Missing task: disable goal satisfied
            return wantDisabled
                ? R(a, ActionResultKind.Match, $"Task absent: {path}")
                : R(a, ActionResultKind.Mismatch, $"Task missing: {path}");
        }

        var disabled = Regex.IsMatch(stdout, @"Scheduled Task State:\s*Disabled", RegexOptions.IgnoreCase)
            || Regex.IsMatch(stdout, @"Status:\s*Disabled", RegexOptions.IgnoreCase);

        if (wantDisabled)
            return disabled
                ? R(a, ActionResultKind.Match, $"Task disabled: {path}")
                : R(a, ActionResultKind.Mismatch, $"Task still enabled: {path}");

        return !disabled
            ? R(a, ActionResultKind.Match, $"Task enabled: {path}")
            : R(a, ActionResultKind.Mismatch, $"Task disabled (want enabled): {path}");
    }

    private ActionResult AuditAppxRemoved(PlaybookAction a)
    {
        if (string.IsNullOrWhiteSpace(a.Package))
            return R(a, ActionResultKind.Failed, "appx.remove needs package");

        // Package may be a wildcard like *Microsoft.BingNews*
        var pattern = a.Package!.Trim('*');
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments =
                $"-NoProfile -NonInteractive -Command \"Get-AppxPackage -Name '{EscapePs(a.Package)}' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name\"",
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };

        // Wildcard: query all and filter
        if (a.Package.Contains('*'))
        {
            psi.Arguments =
                "-NoProfile -NonInteractive -Command \"Get-AppxPackage -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name\"";
        }

        using var p = Process.Start(psi);
        if (p is null) return R(a, ActionResultKind.Failed, "powershell failed");
        var stdout = p.StandardOutput.ReadToEnd();
        p.WaitForExit(60_000);

        var names = stdout.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
        var hit = a.Package.Contains('*')
            ? names.Any(n => n.Contains(pattern, StringComparison.OrdinalIgnoreCase))
            : names.Any(n => n.Equals(a.Package, StringComparison.OrdinalIgnoreCase)
                             || n.Contains(a.Package, StringComparison.OrdinalIgnoreCase));

        return hit
            ? R(a, ActionResultKind.Mismatch, $"AppX still installed matching {a.Package}")
            : R(a, ActionResultKind.Match, $"AppX not present: {a.Package}");
    }

    private ActionResult AuditFileDelete(PlaybookAction a)
    {
        if (string.IsNullOrWhiteSpace(a.Path))
            return R(a, ActionResultKind.Failed, "file.delete needs path");
        var path = Expand(a.Path!);
        return File.Exists(path) || Directory.Exists(path)
            ? R(a, ActionResultKind.Mismatch, $"Still exists: {path}")
            : R(a, ActionResultKind.Match, $"Absent: {path}");
    }

    private ActionResult AuditFileWrite(PlaybookAction a)
    {
        if (string.IsNullOrWhiteSpace(a.Path))
            return R(a, ActionResultKind.Failed, "file.write needs path");
        var path = Expand(a.Path!);
        if (!File.Exists(path))
            return R(a, ActionResultKind.Mismatch, $"File missing: {path}");
        if (a.Content is null && a.Value is null)
            return R(a, ActionResultKind.Match, $"File exists: {path}");
        var want = a.Content ?? a.Value ?? "";
        var have = File.ReadAllText(path);
        return string.Equals(have, want, StringComparison.Ordinal)
            ? R(a, ActionResultKind.Match, $"File content matches: {path}")
            : R(a, ActionResultKind.Mismatch, $"File content differs: {path}");
    }

    private ActionResult AuditFeature(PlaybookAction a, bool enabled)
    {
        if (string.IsNullOrWhiteSpace(a.Feature))
            return R(a, ActionResultKind.Failed, "feature needs name");

        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments =
                $"-NoProfile -NonInteractive -Command \"(Get-WindowsOptionalFeature -Online -FeatureName '{EscapePs(a.Feature)}' -ErrorAction SilentlyContinue).State\"",
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        using var p = Process.Start(psi);
        if (p is null) return R(a, ActionResultKind.Failed, "powershell failed");
        var stdout = p.StandardOutput.ReadToEnd().Trim();
        p.WaitForExit(120_000);

        if (string.IsNullOrEmpty(stdout))
            return R(a, ActionResultKind.NotAuditable, $"Feature query empty: {a.Feature}");

        var isEnabled = stdout.Contains("Enabled", StringComparison.OrdinalIgnoreCase);
        var isDisabled = stdout.Contains("Disabled", StringComparison.OrdinalIgnoreCase);

        if (enabled)
            return isEnabled
                ? R(a, ActionResultKind.Match, $"Feature enabled: {a.Feature}")
                : R(a, ActionResultKind.Mismatch, $"Feature not enabled ({stdout}): {a.Feature}");

        return isDisabled || !isEnabled
            ? R(a, ActionResultKind.Match, $"Feature disabled/absent: {a.Feature} ({stdout})")
            : R(a, ActionResultKind.Mismatch, $"Feature still enabled: {a.Feature}");
    }

    private static string Expand(string path) =>
        Environment.ExpandEnvironmentVariables(path);

    private static string EscapePs(string s) => s.Replace("'", "''");

    [SupportedOSPlatform("windows")]
    private static RegistryKey? OpenRead(string path)
    {
        var parts = path.Replace('/', '\\').Split('\\', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2) return null;
        var root = parts[0].ToUpperInvariant() switch
        {
            "HKCU" or "HKEY_CURRENT_USER" => Registry.CurrentUser,
            "HKLM" or "HKEY_LOCAL_MACHINE" => Registry.LocalMachine,
            "HKU" or "HKEY_USERS" => Registry.Users,
            "HKCR" or "HKEY_CLASSES_ROOT" => Registry.ClassesRoot,
            _ => throw new InvalidOperationException($"Unknown hive {parts[0]}")
        };
        var sub = string.Join('\\', parts.Skip(1));
        return root.OpenSubKey(sub, writable: false);
    }

    private static string NormalizeExpected(string type, string value) => type switch
    {
        "dword" => ParseDwordString(value),
        "qword" => ParseQwordString(value),
        "binary" or "bin" => NormalizeBinaryExpected(value),
        _ => value
    };

    private static string NormalizeActual(string type, object raw) => type switch
    {
        "dword" when raw is int i => unchecked((uint)i).ToString(CultureInfo.InvariantCulture),
        "dword" => Convert.ToUInt32(raw).ToString(CultureInfo.InvariantCulture),
        "qword" when raw is long l => unchecked((ulong)l).ToString(CultureInfo.InvariantCulture),
        "qword" => Convert.ToUInt64(raw).ToString(CultureInfo.InvariantCulture),
        "binary" or "bin" when raw is byte[] b => Convert.ToHexString(b).ToLowerInvariant(),
        _ => raw.ToString() ?? ""
    };

    private static bool ValuesEqual(string type, string expected, string actual, object raw)
    {
        if (string.Equals(expected, actual, StringComparison.OrdinalIgnoreCase))
            return true;
        // string types: case-sensitive prefer, but allow ignore for sz
        if (type is "string" or "sz" or "expandstring" or "expand_sz")
            return string.Equals(expected, actual, StringComparison.Ordinal);
        // dword sometimes stored differently
        if (type is "dword" && raw is int i)
            return ParseDwordString(expected) == unchecked((uint)i).ToString(CultureInfo.InvariantCulture);
        return false;
    }

    private static string ParseDwordString(string value)
    {
        if (value.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
            return Convert.ToUInt32(value[2..], 16).ToString(CultureInfo.InvariantCulture);
        return Convert.ToUInt32(value, CultureInfo.InvariantCulture).ToString(CultureInfo.InvariantCulture);
    }

    private static string ParseQwordString(string value)
    {
        if (value.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
            return Convert.ToUInt64(value[2..], 16).ToString(CultureInfo.InvariantCulture);
        return Convert.ToUInt64(value, CultureInfo.InvariantCulture).ToString(CultureInfo.InvariantCulture);
    }

    private static string NormalizeBinaryExpected(string value)
    {
        var v = value.Replace("-", "").Replace(" ", "");
        if (v.Contains('+') || v.Contains('/') || v.EndsWith('='))
            return Convert.ToHexString(Convert.FromBase64String(v)).ToLowerInvariant();
        return v.ToLowerInvariant();
    }

    private static ActionResult R(PlaybookAction a, ActionResultKind kind, string message) => new()
    {
        ActionType = a.Type,
        ActionId = a.Id ?? a.Name ?? a.Service ?? a.ValueName ?? a.ProcessName,
        Kind = kind,
        Message = message
    };
}
