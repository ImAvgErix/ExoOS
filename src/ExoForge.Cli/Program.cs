using ExoForge.Engine;
using ExoForge.Schema;

static int Usage()
{
    Console.WriteLine("""
        ExoForge — ExoOS playbook engine

        Usage:
          ExoForge.Cli validate <playbookFolder>
          ExoForge.Cli apply    <playbookFolder> [--dry-run] [--live] [--nuclear] [--ac-sensitive]
                                                 [--tier <id>]... [--option key=value]...

        Default apply mode is DRY-RUN. Live changes require --live.
        --option overrides playbook defaultOptions (feature flags).

        Examples:
          ExoForge.Cli validate playbooks/exoos
          ExoForge.Cli apply    playbooks/exoos --dry-run
          ExoForge.Cli apply    playbooks/exoos --live --option defenderStrip=true
        """);
    return 1;
}

if (args.Length < 2) return Usage();

var cmd = args[0].ToLowerInvariant();
var playbookPath = args[1];
var dryRun = !args.Any(a => a is "--live");
if (args.Any(a => a is "--dry-run")) dryRun = true;
var nuclear = args.Any(a => a is "--nuclear");
var ac = args.Any(a => a is "--ac-sensitive");
var tiers = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
var optionOverrides = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
for (var i = 0; i < args.Length; i++)
{
    if (args[i] is "--tier" && i + 1 < args.Length)
        tiers.Add(args[++i]);
    if (args[i] is "--option" && i + 1 < args.Length)
    {
        var pair = args[++i];
        var eq = pair.IndexOf('=');
        if (eq > 0)
            optionOverrides[pair[..eq]] = pair[(eq + 1)..];
    }
}

try
{
    var loaded = PlaybookLoader.Load(playbookPath);
    Console.WriteLine($"Playbook: {loaded.Manifest.Name} ({loaded.Manifest.Id}) v{loaded.Manifest.Version}");
    Console.WriteLine($"Root:     {loaded.RootPath}");
    Console.WriteLine($"Actions:  {loaded.Documents.Sum(d => d.Doc.Actions.Count)} in {loaded.Documents.Count} file(s)");
    Console.WriteLine($"Desc:     {loaded.Manifest.Description.Trim().ReplaceLineEndings(" ").Truncate(120)}");

    if (cmd is "validate")
    {
        Console.WriteLine("OK — playbook loads.");
        foreach (var (file, doc) in loaded.Documents)
            Console.WriteLine($"  {Path.GetFileName(file),-28} {doc.Actions.Count,4} actions  — {doc.Title}");
        return 0;
    }

    if (cmd is not "apply")
        return Usage();

    if (!OperatingSystem.IsWindows())
    {
        Console.Error.WriteLine("Apply is Windows-only.");
        return 2;
    }

    if (!dryRun)
    {
        Console.WriteLine("LIVE apply — changes will be written. Ctrl+C within 3s to abort...");
        Thread.Sleep(3000);
    }
    else
    {
        Console.WriteLine("DRY-RUN (pass --live to apply for real)");
    }

    // extremeMode (Maximum FPS) is the product opt-in for nuclear-risk actions
    var extremeOpt = optionOverrides.TryGetValue("extremeMode", out var em)
        && string.Equals(em, "true", StringComparison.OrdinalIgnoreCase);
    var exec = new ActionExecutor(loaded, new ApplyOptions
    {
        DryRun = dryRun,
        AllowNuclear = nuclear || extremeOpt,
        AllowAcSensitive = ac || extremeOpt
            || (optionOverrides.TryGetValue("disableVbs", out var vbs)
                && string.Equals(vbs, "true", StringComparison.OrdinalIgnoreCase)),
        EnabledTiers = tiers.Count > 0 ? tiers : null,
        OptionOverrides = optionOverrides.Count > 0 ? optionOverrides : null
    });

    var report = exec.Run();
    foreach (var r in report.Results)
        Console.WriteLine($"[{r.Kind,-22}] {r.ActionType,-16} {r.ActionId} — {r.Message}");

    Console.WriteLine();
    Console.WriteLine($"Done. applied={report.Applied} skipped={report.Skipped} failed={report.Failed} dryRun={report.DryRun}");
    return report.Failed > 0 ? 3 : 0;
}
catch (Exception ex)
{
    Console.Error.WriteLine("ERROR: " + ex.Message);
    return 10;
}

file static class StringExt
{
    public static string Truncate(this string s, int max)
        => s.Length <= max ? s : s[..(max - 1)] + "…";
}
