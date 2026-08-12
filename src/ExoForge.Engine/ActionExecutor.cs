using System.Diagnostics;
using System.Runtime.Versioning;
using System.ServiceProcess;
using System.Text;
using ExoForge.Schema;
using Microsoft.Win32;

namespace ExoForge.Engine;

public sealed class ApplyOptions
{
    public bool DryRun { get; init; } = true;
    public HashSet<string>? EnabledTiers { get; init; }
    public bool AllowNuclear { get; init; }
    public bool AllowAcSensitive { get; init; }
    /// <summary>Overrides for playbook defaultOptions (feature flags).</summary>
    public Dictionary<string, string>? OptionOverrides { get; init; }
}

public sealed class ActionExecutor
{
    private readonly LoadedPlaybook _playbook;
    private readonly ApplyOptions _options;
    private readonly Dictionary<string, string> _optionsMap;

    public ActionExecutor(LoadedPlaybook playbook, ApplyOptions options)
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
            DryRun = _options.DryRun,
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
                report.Results.Add(ExecuteOne(action));
        }

        report.FinishedUtc = DateTimeOffset.UtcNow;
        return report;
    }

    private ActionResult ExecuteOne(PlaybookAction action)
    {
        if (!PlaybookOptions.Enabled(_optionsMap, action))
        {
            return Result(action, ActionResultKind.SkippedOptionDisabled,
                $"Option '{action.WhenOption}' != '{action.OptionEquals ?? "true"}'");
        }

        var risk = (action.Risk ?? "safe").ToLowerInvariant();
        if (risk is "nuclear" && !PlaybookOptions.AllowsNuclear(_options, _optionsMap))
            return Result(action, ActionResultKind.SkippedTierDisabled, "Nuclear blocked (pass --nuclear)");
        if (risk is "ac-sensitive" && !PlaybookOptions.AllowsAcSensitive(_options, _optionsMap))
            return Result(action, ActionResultKind.SkippedTierDisabled, "AC-sensitive blocked (pass --ac-sensitive)");

        try
        {
            return action.Type.ToLowerInvariant() switch
            {
                "registry.set" or "reg.set" => RegistrySet(action),
                "registry.delete" or "reg.delete" => RegistryDelete(action),
                "service.set" => ServiceSet(action),
                "task.disable" => TaskDisable(action),
                "task.enable" => TaskEnable(action),
                "taskkill" or "process.kill" => TaskKill(action),
                "appx.remove" => AppxRemove(action),
                "run" or "cmd" or "powershell" => RunProcess(action),
                "power.activate" => PowerActivate(action),
                "power.import" => PowerImport(action),
                "capability.remove" or "dism.capability.remove" => CapabilityRemove(action),
                "feature.disable" or "dism.feature.disable" => FeatureDisable(action),
                "feature.enable" or "dism.feature.enable" => FeatureEnable(action),
                "package.add" or "systempackage.add" => PackageAdd(action),
                "package.remove" or "systempackage.remove" => PackageRemove(action),
                "file.delete" => FileDelete(action),
                "file.write" => FileWrite(action),
                "noop" or "note" or "status" => Result(action, ActionResultKind.SkippedAlreadyDesired, action.Description ?? "note"),
                _ => Result(action, ActionResultKind.Failed, $"Unknown action type: {action.Type}")
            };
        }
        catch (Exception ex)
        {
            if (action.IgnoreErrors == true)
                return Result(action, ActionResultKind.Applied, $"ignored error: {ex.Message}");
            return Result(action, ActionResultKind.Failed, ex.Message);
        }
    }

    private ActionResult RegistrySet(PlaybookAction a)
    {
        if (string.IsNullOrWhiteSpace(a.Path))
            return Result(a, ActionResultKind.Failed, "registry.set needs path");

        var valueName = a.ValueName ?? "";
        if (_options.DryRun)
            return Result(a, ActionResultKind.SkippedDryRun,
                $"Would set {a.Path}\\{(valueName.Length == 0 ? "(Default)" : valueName)} = {a.Value} ({a.ValueType})");

        if (!OperatingSystem.IsWindows())
            return Result(a, ActionResultKind.Failed, "Windows only");

        SetRegistryValue(a.Path!, valueName, a.ValueType ?? "dword", a.Value ?? "0");
        return Result(a, ActionResultKind.Applied,
            $"Set {a.Path}\\{(valueName.Length == 0 ? "(Default)" : valueName)}");
    }

    private ActionResult RegistryDelete(PlaybookAction a)
    {
        if (string.IsNullOrWhiteSpace(a.Path))
            return Result(a, ActionResultKind.Failed, "registry.delete needs path");

        var valueName = a.ValueName ?? "";
        if (_options.DryRun)
            return Result(a, ActionResultKind.SkippedDryRun,
                $"Would delete {a.Path}\\{(valueName.Length == 0 ? "(Default)" : valueName)}");

        if (!OperatingSystem.IsWindows())
            return Result(a, ActionResultKind.Failed, "Windows only");

        if (string.Equals(valueName, "__KEY__", StringComparison.OrdinalIgnoreCase)
            || string.Equals(valueName, "*", StringComparison.OrdinalIgnoreCase))
        {
            var parts = a.Path!.Replace('/', '\\').Split('\\', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length < 2)
                return Result(a, ActionResultKind.Failed, "Cannot delete hive root");
            var root = ResolveHive(parts[0]);
            var parentPath = string.Join('\\', parts.Skip(1).Take(parts.Length - 2));
            var leaf = parts[^1];
            using var parent = string.IsNullOrEmpty(parentPath) ? root : root.OpenSubKey(parentPath, writable: true);
            parent?.DeleteSubKeyTree(leaf, throwOnMissingSubKey: false);
            return Result(a, ActionResultKind.Applied, $"Deleted key {a.Path}");
        }

        using var key = OpenWritable(a.Path!);
        key?.DeleteValue(valueName, throwOnMissingValue: false);
        return Result(a, ActionResultKind.Applied,
            $"Deleted {a.Path}\\{(valueName.Length == 0 ? "(Default)" : valueName)}");
    }

    [SupportedOSPlatform("windows")]
    private ActionResult ServiceSet(PlaybookAction a)
    {
        if (string.IsNullOrWhiteSpace(a.Service))
            return Result(a, ActionResultKind.Failed, "service.set needs service");

        if (_options.DryRun)
            return Result(a, ActionResultKind.SkippedDryRun, $"Would set service {a.Service} start={a.Start} stop={a.Stop}");

        try
        {
            using var sc = new ServiceController(a.Service!);
            if (a.Stop == true && sc.Status != ServiceControllerStatus.Stopped)
            {
                try { sc.Stop(); sc.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(30)); }
                catch { /* best effort */ }
            }
        }
        catch (InvalidOperationException)
        {
            return Result(a, ActionResultKind.SkippedAlreadyDesired, $"Service {a.Service} not installed — skip");
        }

        if (!string.IsNullOrWhiteSpace(a.Start))
        {
            // Accept names or SCM numeric start types (0 boot … 4 disabled).
            var mode = a.Start!.Trim().ToLowerInvariant() switch
            {
                "disabled" or "4" => "disabled",
                "manual" or "demand" or "3" => "demand",
                "automatic" or "auto" or "2" => "auto",
                "automaticdelayed" or "delayed" or "delayed-auto" => "delayed-auto",
                "system" or "1" => "system",
                "boot" or "0" => "boot",
                _ => a.Start!.Trim()
            };
            var code = RunHidden("sc.exe", $"config \"{a.Service}\" start= {mode}");
            if (code != 0 && a.IgnoreErrors != true)
                return Result(a, ActionResultKind.SkippedAlreadyDesired, $"sc config {a.Service} exit {code}");
        }

        return Result(a, ActionResultKind.Applied, $"Service {a.Service} configured");
    }

    private ActionResult AppxRemove(PlaybookAction a)
    {
        if (string.IsNullOrWhiteSpace(a.Package))
            return Result(a, ActionResultKind.Failed, "appx.remove needs package");

        if (_options.DryRun)
            return Result(a, ActionResultKind.SkippedDryRun, $"Would remove AppX {a.Package}");

        var pattern = a.Package!.Replace("'", "''");
        var script = Path.Combine(Path.GetTempPath(), "exo-appx-" + Guid.NewGuid().ToString("n") + ".ps1");
        var body =
            "$ErrorActionPreference='SilentlyContinue'\r\n" +
            $"Get-AppxPackage -AllUsers '{pattern}' | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue\r\n" +
            $"Get-AppxPackage '{pattern}' | Remove-AppxPackage -ErrorAction SilentlyContinue\r\n" +
            $"Get-AppxProvisionedPackage -Online | Where-Object {{ $_.PackageName -like '{pattern}' }} | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null\r\n" +
            "exit 0\r\n";
        File.WriteAllText(script, body);
        try
        {
            var code = RunHidden("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -File \"{script}\"");
            return Result(a, ActionResultKind.Applied, $"AppX remove attempted: {a.Package} (exit {code})");
        }
        finally
        {
            try { File.Delete(script); } catch { /* ignore */ }
        }
    }

    private ActionResult TaskDisable(PlaybookAction a)
    {
        if (string.IsNullOrWhiteSpace(a.TaskPath))
            return Result(a, ActionResultKind.Failed, "task.disable needs taskPath");

        if (_options.DryRun)
            return Result(a, ActionResultKind.SkippedDryRun, $"Would disable task {a.TaskPath}");

        var code = RunHidden("schtasks.exe", $"/Change /TN \"{a.TaskPath}\" /Disable");
        if (code != 0 && a.IgnoreErrors == true)
            return Result(a, ActionResultKind.Applied, $"task disable exit {code} (ignored)");
        return code == 0
            ? Result(a, ActionResultKind.Applied, $"Disabled {a.TaskPath}")
            : Result(a, ActionResultKind.Failed, $"schtasks failed ({code}) for {a.TaskPath}");
    }

    private ActionResult TaskEnable(PlaybookAction a)
    {
        if (string.IsNullOrWhiteSpace(a.TaskPath))
            return Result(a, ActionResultKind.Failed, "task.enable needs taskPath");

        if (_options.DryRun)
            return Result(a, ActionResultKind.SkippedDryRun, $"Would enable task {a.TaskPath}");

        var code = RunHidden("schtasks.exe", $"/Change /TN \"{a.TaskPath}\" /Enable");
        return code == 0
            ? Result(a, ActionResultKind.Applied, $"Enabled {a.TaskPath}")
            : Result(a, ActionResultKind.Failed, $"schtasks failed ({code}) for {a.TaskPath}");
    }

    private ActionResult TaskKill(PlaybookAction a)
    {
        var name = a.ProcessName ?? a.Name ?? a.Package;
        if (string.IsNullOrWhiteSpace(name))
            return Result(a, ActionResultKind.Failed, "taskkill needs processName");

        // Never kill the shell mid-apply
        if (name.Equals("explorer", StringComparison.OrdinalIgnoreCase)
            || name.Equals("explorer.exe", StringComparison.OrdinalIgnoreCase))
            return Result(a, ActionResultKind.SkippedAlreadyDesired, "Skipping explorer kill (desktop safety)");

        if (_options.DryRun)
            return Result(a, ActionResultKind.SkippedDryRun, $"Would taskkill {name}");

        var code = RunHidden("taskkill.exe", $"/F /IM \"{name}\" /T");
        // 128 = not found — OK
        if (code is 0 or 128 || a.IgnoreErrors == true)
            return Result(a, ActionResultKind.Applied, $"taskkill {name} exit {code}");
        return Result(a, ActionResultKind.Failed, $"taskkill {name} exit {code}");
    }

    private ActionResult RunProcess(PlaybookAction a)
    {
        if (string.IsNullOrWhiteSpace(a.File))
            return Result(a, ActionResultKind.Failed, "run needs file");

        var file = ResolvePath(a.File!);
        var runAs = (a.RunAs ?? "admin").ToLowerInvariant();

        if (_options.DryRun)
            return Result(a, ActionResultKind.SkippedDryRun, $"Would run [{runAs}] {file} {a.Args}");

        string fileName;
        string arguments;
        if (file.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase))
        {
            fileName = "powershell.exe";
            arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{file}\" {a.Args}".Trim();
        }
        else if (file.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase)
                 || file.EndsWith(".bat", StringComparison.OrdinalIgnoreCase))
        {
            fileName = "cmd.exe";
            arguments = $"/c \"\"{file}\" {a.Args}\"".Trim();
        }
        else
        {
            fileName = file;
            arguments = a.Args ?? "";
        }

        var timeout = a.TimeoutMs is > 0 ? a.TimeoutMs.Value : 300_000;
        int code;
        if (runAs is "system" or "0" or "ti" or "trustedinstaller")
            code = RunAsSystem(fileName, arguments, a.WorkDir, timeout);
        else
            code = RunHidden(fileName, arguments, a.WorkDir, timeout);

        var name = Path.GetFileName(file);
        if (code == 0)
            return Result(a, ActionResultKind.Applied, $"Ran {name}");
        if (a.IgnoreErrors == true)
            return Result(a, ActionResultKind.Applied, $"{name} exit {code} (ignored)");
        if (name.Equals("bcdedit.exe", StringComparison.OrdinalIgnoreCase)
            || name.Equals("powercfg.exe", StringComparison.OrdinalIgnoreCase)
            || name.Equals("taskkill.exe", StringComparison.OrdinalIgnoreCase))
            return Result(a, ActionResultKind.Applied, $"{name} exit {code} (treated OK)");
        return Result(a, ActionResultKind.Failed, $"{name} exited {code}");
    }

    /// <summary>One-shot scheduled task as SYSTEM — deep path used by gaming playbooks for locked resources.</summary>
    private static int RunAsSystem(string fileName, string arguments, string? workDir, int timeoutMs)
    {
        var taskName = "ExoForge_" + Guid.NewGuid().ToString("N")[..12];
        var tr = string.IsNullOrWhiteSpace(arguments)
            ? $"\"{fileName}\""
            : $"\"{fileName}\" {arguments}";
        try
        {
            // /RL HIGHEST /RU SYSTEM
            var create = RunHidden("schtasks.exe",
                $"/Create /TN \"{taskName}\" /TR {EscapeSchtasksTr(tr)} /SC ONCE /ST 00:00 /RU SYSTEM /RL HIGHEST /F");
            if (create != 0)
            {
                // fallback to normal elevated process
                return RunHidden(fileName, arguments, workDir, timeoutMs);
            }
            var run = RunHidden("schtasks.exe", $"/Run /TN \"{taskName}\"");
            // Poll until task finishes or timeout
            var sw = Stopwatch.StartNew();
            while (sw.ElapsedMilliseconds < timeoutMs)
            {
                Thread.Sleep(500);
                // query status — rough: if Last Run Result available
                break; // schtasks /Run returns after start; wait fixed window for short scripts
            }
            Thread.Sleep(Math.Min(timeoutMs, 15_000));
            return run == 0 ? 0 : run;
        }
        finally
        {
            RunHidden("schtasks.exe", $"/Delete /TN \"{taskName}\" /F");
        }
    }

    private static string EscapeSchtasksTr(string tr)
    {
        // schtasks wants the entire /TR value quoted once
        return "\"" + tr.Replace("\"", "\\\"") + "\"";
    }

    private ActionResult PowerActivate(PlaybookAction a)
    {
        if (string.IsNullOrWhiteSpace(a.SchemeGuid))
            return Result(a, ActionResultKind.Failed, "power.activate needs schemeGuid");

        if (_options.DryRun)
            return Result(a, ActionResultKind.SkippedDryRun, $"Would activate power plan {a.SchemeGuid}");

        var code = RunHidden("powercfg.exe", $"/setactive {a.SchemeGuid}");
        return code == 0
            ? Result(a, ActionResultKind.Applied, $"Power plan {a.SchemeGuid}")
            : Result(a, ActionResultKind.Failed, $"powercfg failed ({code})");
    }

    private ActionResult PowerImport(PlaybookAction a)
    {
        var rel = a.PowFile ?? a.File;
        if (string.IsNullOrWhiteSpace(rel))
            return Result(a, ActionResultKind.Failed, "power.import needs powFile");

        var path = ResolvePath(rel!);
        if (!File.Exists(path))
            return Result(a, ActionResultKind.Failed, $"pow not found: {path}");

        var guid = string.IsNullOrWhiteSpace(a.SchemeGuid)
            ? "e80e0e0e-e80e-4e0e-e80e-0e0e0e0e0e0e"
            : a.SchemeGuid!;

        if (_options.DryRun)
            return Result(a, ActionResultKind.SkippedDryRun, $"Would import {Path.GetFileName(path)} as {guid}");

        var imp = RunHidden("powercfg.exe", $"-import \"{path}\" {guid}");
        var act = RunHidden("powercfg.exe", $"/setactive {guid}");
        return act == 0 || imp == 0
            ? Result(a, ActionResultKind.Applied, $"Imported+activated {Path.GetFileName(path)}")
            : Result(a, ActionResultKind.Failed, $"powercfg import/activate failed imp={imp} act={act}");
    }

    private ActionResult CapabilityRemove(PlaybookAction a)
    {
        var name = a.Capability ?? a.Name ?? a.Package;
        if (string.IsNullOrWhiteSpace(name))
            return Result(a, ActionResultKind.Failed, "capability.remove needs capability");

        if (_options.DryRun)
            return Result(a, ActionResultKind.SkippedDryRun, $"Would Remove-WindowsCapability {name}");

        var ps = $"Remove-WindowsCapability -Online -Name '{name.Replace("'", "''")}' -ErrorAction SilentlyContinue | Out-Null; exit 0";
        var code = RunHidden("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"{ps}\"");
        return Result(a, ActionResultKind.Applied, $"Capability remove: {name} (exit {code})");
    }

    private ActionResult FeatureDisable(PlaybookAction a)
    {
        var name = a.Feature ?? a.Name;
        if (string.IsNullOrWhiteSpace(name))
            return Result(a, ActionResultKind.Failed, "feature.disable needs feature");

        if (_options.DryRun)
            return Result(a, ActionResultKind.SkippedDryRun, $"Would Disable-WindowsOptionalFeature {name}");

        var ps = $"Disable-WindowsOptionalFeature -Online -FeatureName '{name.Replace("'", "''")}' -NoRestart -ErrorAction SilentlyContinue | Out-Null; exit 0";
        var code = RunHidden("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"{ps}\"");
        return Result(a, ActionResultKind.Applied, $"Feature disable: {name} (exit {code})");
    }

    private ActionResult FeatureEnable(PlaybookAction a)
    {
        var name = a.Feature ?? a.Name;
        if (string.IsNullOrWhiteSpace(name))
            return Result(a, ActionResultKind.Failed, "feature.enable needs feature");

        if (_options.DryRun)
            return Result(a, ActionResultKind.SkippedDryRun, $"Would Enable-WindowsOptionalFeature {name}");

        var ps = $"Enable-WindowsOptionalFeature -Online -FeatureName '{name.Replace("'", "''")}' -NoRestart -ErrorAction SilentlyContinue | Out-Null; exit 0";
        var code = RunHidden("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"{ps}\"");
        return Result(a, ActionResultKind.Applied, $"Feature enable: {name} (exit {code})");
    }

    private ActionResult PackageAdd(PlaybookAction a)
    {
        var path = a.PackagePath ?? a.File ?? a.Path;
        if (string.IsNullOrWhiteSpace(path))
            return Result(a, ActionResultKind.Failed, "package.add needs packagePath");

        path = ResolvePath(path!);
        if (_options.DryRun)
            return Result(a, ActionResultKind.SkippedDryRun, $"Would Add-WindowsPackage {path}");

        if (!File.Exists(path))
            return Result(a, ActionResultKind.Failed, $"package not found: {path}");

        // Match deep CAB path used by Defender/AI removal scripts
        var ps =
            $"$ErrorActionPreference='Continue'; " +
            $"Add-WindowsPackage -Online -PackagePath '{path.Replace("'", "''")}' -NoRestart -IgnoreCheck -ErrorAction SilentlyContinue | Out-Null; " +
            "exit 0";
        var code = RunAsSystem("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"{ps}\"", null, 600_000);
        return Result(a, ActionResultKind.Applied, $"Package add {Path.GetFileName(path)} exit {code}");
    }

    private ActionResult PackageRemove(PlaybookAction a)
    {
        var name = a.Package ?? a.Name ?? a.PackagePath;
        if (string.IsNullOrWhiteSpace(name))
            return Result(a, ActionResultKind.Failed, "package.remove needs package");

        if (_options.DryRun)
            return Result(a, ActionResultKind.SkippedDryRun, $"Would Remove-WindowsPackage {name}");

        var ps =
            $"Get-WindowsPackage -Online | Where-Object {{ $_.PackageName -like '{name.Replace("'", "''")}' }} | " +
            "ForEach-Object { Remove-WindowsPackage -Online -PackageName $_.PackageName -NoRestart -ErrorAction SilentlyContinue }; exit 0";
        var code = RunHidden("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"{ps}\"");
        return Result(a, ActionResultKind.Applied, $"Package remove {name} exit {code}");
    }

    private ActionResult FileDelete(PlaybookAction a)
    {
        var path = a.Path ?? a.File;
        if (string.IsNullOrWhiteSpace(path))
            return Result(a, ActionResultKind.Failed, "file.delete needs path");

        path = ResolvePath(path!);
        if (_options.DryRun)
            return Result(a, ActionResultKind.SkippedDryRun, $"Would delete {path}");

        try
        {
            if (Directory.Exists(path))
                Directory.Delete(path, recursive: true);
            else if (File.Exists(path))
                File.Delete(path);
            return Result(a, ActionResultKind.Applied, $"Deleted {path}");
        }
        catch (Exception ex) when (a.IgnoreErrors == true)
        {
            return Result(a, ActionResultKind.Applied, $"delete ignored: {ex.Message}");
        }
    }

    private ActionResult FileWrite(PlaybookAction a)
    {
        var path = a.Path ?? a.File;
        if (string.IsNullOrWhiteSpace(path))
            return Result(a, ActionResultKind.Failed, "file.write needs path");

        path = ResolvePath(path!);
        if (_options.DryRun)
            return Result(a, ActionResultKind.SkippedDryRun, $"Would write {path}");

        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir))
            Directory.CreateDirectory(dir);
        File.WriteAllText(path, a.Content ?? a.Value ?? "", Encoding.UTF8);
        return Result(a, ActionResultKind.Applied, $"Wrote {path}");
    }

    private string ResolvePath(string file)
    {
        var isSystemTool = file.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)
            && !file.Contains('\\') && !file.Contains('/');
        if (isSystemTool) return file;
        if (Path.IsPathRooted(file)) return file;
        return Path.Combine(_playbook.RootPath, file.Replace('/', Path.DirectorySeparatorChar));
    }

    private static ActionResult Result(PlaybookAction a, ActionResultKind kind, string message) => new()
    {
        ActionType = a.Type,
        ActionId = a.Id ?? a.Name ?? a.Service ?? a.ValueName ?? a.ProcessName,
        Kind = kind,
        Message = message
    };

    private static int RunHidden(string file, string args, string? workDir = null, int timeoutMs = 300_000)
    {
        var psi = new ProcessStartInfo
        {
            FileName = file,
            Arguments = args,
            WorkingDirectory = workDir ?? Environment.CurrentDirectory,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        using var p = Process.Start(psi);
        if (p is null) return -1;
        if (!p.WaitForExit(timeoutMs))
        {
            try { p.Kill(entireProcessTree: true); } catch { /* ignore */ }
            return -9;
        }
        return p.ExitCode;
    }

    [SupportedOSPlatform("windows")]
    private static void SetRegistryValue(string path, string name, string type, string value)
    {
        using var key = OpenWritable(path) ?? throw new InvalidOperationException($"Cannot open {path}");
        switch (type.ToLowerInvariant())
        {
            case "dword":
                key.SetValue(name, ParseDword(value), RegistryValueKind.DWord);
                break;
            case "qword":
            {
                long q = value.StartsWith("0x", StringComparison.OrdinalIgnoreCase)
                    ? unchecked((long)Convert.ToUInt64(value[2..], 16))
                    : long.Parse(value, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture);
                key.SetValue(name, q, RegistryValueKind.QWord);
                break;
            }
            case "string":
            case "sz":
                key.SetValue(name, value, RegistryValueKind.String);
                break;
            case "expandstring":
            case "expand_sz":
                key.SetValue(name, value, RegistryValueKind.ExpandString);
                break;
            case "binary":
            case "bin":
            {
                var v = value.Replace("-", "").Replace(" ", "");
                byte[] bytes;
                if (v.Contains('+') || v.Contains('/') || v.EndsWith('='))
                    bytes = Convert.FromBase64String(v);
                else
                {
                    if (v.Length % 2 != 0) throw new FormatException("binary hex length odd");
                    bytes = new byte[v.Length / 2];
                    for (int i = 0; i < bytes.Length; i++)
                        bytes[i] = Convert.ToByte(v.Substring(i * 2, 2), 16);
                }
                key.SetValue(name, bytes, RegistryValueKind.Binary);
                break;
            }
            case "none":
            case "key":
                break;
            default:
                throw new NotSupportedException($"Value type '{type}' not supported yet");
        }
    }

    private static int ParseDword(string value)
    {
        if (value.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
        {
            var u = Convert.ToUInt32(value[2..], 16);
            return BitConverter.ToInt32(BitConverter.GetBytes(u), 0);
        }
        return checked((int)Convert.ToUInt32(value));
    }

    [SupportedOSPlatform("windows")]
    private static RegistryKey ResolveHive(string hive) => hive.ToUpperInvariant() switch
    {
        "HKCU" or "HKEY_CURRENT_USER" => Registry.CurrentUser,
        "HKLM" or "HKEY_LOCAL_MACHINE" => Registry.LocalMachine,
        "HKU" or "HKEY_USERS" => Registry.Users,
        "HKCR" or "HKEY_CLASSES_ROOT" => Registry.ClassesRoot,
        _ => throw new InvalidOperationException($"Unknown hive {hive}")
    };

    [SupportedOSPlatform("windows")]
    private static RegistryKey? OpenWritable(string path)
    {
        var parts = path.Replace('/', '\\').Split('\\', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2) return null;
        var root = ResolveHive(parts[0]);
        var sub = string.Join('\\', parts.Skip(1));
        return root.CreateSubKey(sub, writable: true);
    }
}
