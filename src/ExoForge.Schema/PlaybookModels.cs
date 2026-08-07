namespace ExoForge.Schema;

/// <summary>Root manifest: playbook.yml</summary>
public sealed class PlaybookManifest
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Version { get; set; } = "0.1.0";
    public string Description { get; set; } = "";
    public string MinWindowsBuild { get; set; } = "22000";
    public List<string> Authors { get; set; } = new();
    public List<PlaybookTier> Tiers { get; set; } = new();
    public List<string> ActionFiles { get; set; } = new();
    /// <summary>
    /// Feature flags (browser, defenderStrip, install7zip, …).
    /// Values are "true"/"false" strings so YAML never coerces poorly.
    /// </summary>
    public Dictionary<string, string> DefaultOptions { get; set; } = new();
}

public sealed class PlaybookTier
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Risk { get; set; } = "safe";
    public string Description { get; set; } = "";
    public bool DefaultEnabled { get; set; } = true;
}

public sealed class ActionDocument
{
    public string Title { get; set; } = "";
    public string Tier { get; set; } = "base";
    public List<PlaybookAction> Actions { get; set; } = new();
}

public sealed class PlaybookAction
{
    /// <summary>
    /// registry.set | registry.delete | service.set | task.disable | task.enable |
    /// taskkill | appx.remove | run | power.import | power.activate |
    /// capability.remove | feature.disable | feature.enable |
    /// package.add | package.remove | file.delete | file.write | note
    /// </summary>
    public string Type { get; set; } = "";

    public string? Id { get; set; }
    public string? Name { get; set; }
    public string? Description { get; set; }
    public string Risk { get; set; } = "safe";
    public bool RequiresAdmin { get; set; } = true;
    public string? Reboot { get; set; }

    // Conditional: only run when option key is true (or false if OptionEquals is "false")
    public string? WhenOption { get; set; }
    public string? OptionEquals { get; set; } // default "true"

    // registry
    public string? Path { get; set; }
    public string? ValueName { get; set; }
    public string? ValueType { get; set; }
    public string? Value { get; set; }

    // service
    public string? Service { get; set; }
    public string? Start { get; set; }
    public bool? Stop { get; set; }

    // task
    public string? TaskPath { get; set; }

    // taskkill
    public string? ProcessName { get; set; }

    // appx / package
    public string? Package { get; set; }
    /// <summary>Path to .cab/.msu for package.add (relative to playbook root or absolute / URL handled by script)</summary>
    public string? PackagePath { get; set; }

    // run
    public string? File { get; set; }
    public string? Args { get; set; }
    public string? WorkDir { get; set; }
    /// <summary>admin | system | current — system uses a one-shot scheduled task as SYSTEM</summary>
    public string? RunAs { get; set; }
    public bool? Wait { get; set; }
    public bool? IgnoreErrors { get; set; }
    public int? TimeoutMs { get; set; }

    // power
    public string? SchemeGuid { get; set; }
    public string? PowFile { get; set; }

    // dism
    public string? Capability { get; set; }
    public string? Feature { get; set; }

    // file
    public string? Content { get; set; }

    public Dictionary<string, string>? Extra { get; set; }
}

public enum ActionResultKind
{
    Applied,
    SkippedAlreadyDesired,
    SkippedTierDisabled,
    SkippedOptionDisabled,
    SkippedDryRun,
    Failed,
    DetectOnly,
    /// <summary>Audit: live system matches desired state.</summary>
    Match,
    /// <summary>Audit: live system differs from desired state.</summary>
    Mismatch,
    /// <summary>Audit: action type has no reliable post-hoc check (scripts, kills, etc.).</summary>
    NotAuditable,
}

public sealed class ActionResult
{
    public string ActionType { get; set; } = "";
    public string? ActionId { get; set; }
    public ActionResultKind Kind { get; set; }
    public string Message { get; set; } = "";
}

public sealed class ApplyReport
{
    public string PlaybookId { get; set; } = "";
    public string PlaybookVersion { get; set; } = "";
    public bool DryRun { get; set; }
    public bool Audit { get; set; }
    public DateTimeOffset StartedUtc { get; set; }
    public DateTimeOffset FinishedUtc { get; set; }
    public List<ActionResult> Results { get; set; } = new();
    public int Applied => Results.Count(r => r.Kind == ActionResultKind.Applied);
    public int Failed => Results.Count(r => r.Kind == ActionResultKind.Failed);
    public int Matched => Results.Count(r => r.Kind == ActionResultKind.Match);
    public int Mismatched => Results.Count(r => r.Kind == ActionResultKind.Mismatch);
    public int NotAuditable => Results.Count(r => r.Kind == ActionResultKind.NotAuditable);
    public int Skipped => Results.Count(r =>
        r.Kind is ActionResultKind.SkippedAlreadyDesired
            or ActionResultKind.SkippedTierDisabled
            or ActionResultKind.SkippedOptionDisabled
            or ActionResultKind.SkippedDryRun);
}
