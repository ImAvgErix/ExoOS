using ExoForge.Schema;

namespace ExoForge.Engine;

/// <summary>Shared option / tier resolution for apply and audit.</summary>
internal static class PlaybookOptions
{
    public static Dictionary<string, string> Merge(
        IReadOnlyDictionary<string, string> defaults,
        IReadOnlyDictionary<string, string>? overrides)
    {
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var kv in defaults)
            map[kv.Key] = kv.Value;
        if (overrides is null) return map;
        foreach (var kv in overrides)
            map[kv.Key] = kv.Value;
        return map;
    }

    public static bool IsTrue(Dictionary<string, string> map, string key) =>
        map.TryGetValue(key, out var v) &&
        string.Equals(v.Trim(), "true", StringComparison.OrdinalIgnoreCase);

    public static bool Enabled(Dictionary<string, string> map, PlaybookAction a)
    {
        if (string.IsNullOrWhiteSpace(a.WhenOption)) return true;
        var want = string.IsNullOrWhiteSpace(a.OptionEquals) ? "true" : a.OptionEquals!;
        map.TryGetValue(a.WhenOption!, out var have);
        have ??= "false";
        return string.Equals(have.Trim(), want.Trim(), StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Extreme (playbook default) unlocks nuclear-risk actions. --nuclear still forces on.
    /// </summary>
    public static bool AllowsNuclear(ApplyOptions options, Dictionary<string, string> map) =>
        options.AllowNuclear || IsTrue(map, "extremeMode") || IsTrue(map, "nuclearMode");

    public static bool AllowsAcSensitive(ApplyOptions options, Dictionary<string, string> map) =>
        options.AllowAcSensitive || IsTrue(map, "extremeMode") || IsTrue(map, "disableVbs");

    public static HashSet<string> ResolveTiers(LoadedPlaybook playbook, ApplyOptions options)
    {
        if (options.EnabledTiers is { Count: > 0 })
            return new HashSet<string>(options.EnabledTiers, StringComparer.OrdinalIgnoreCase);

        if (playbook.Manifest.Tiers.Count == 0)
        {
            var all = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "base" };
            foreach (var (_, doc) in playbook.Documents)
                all.Add(string.IsNullOrWhiteSpace(doc.Tier) ? "base" : doc.Tier);
            return all;
        }

        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "base" };
        foreach (var t in playbook.Manifest.Tiers.Where(t => t.DefaultEnabled))
            set.Add(t.Id);
        return set;
    }
}
