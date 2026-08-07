using System.IO;

namespace ExoOS;

public static class PlaybookPaths
{
    /// <summary>
    /// Resolve playbook folder: next to the exe, then repo layout, then Documents fallback.
    /// </summary>
    public static string Resolve()
    {
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "playbooks", "exoos"),
            Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "playbooks", "exoos"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "ExoOS-repo", "playbooks", "exoos"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "ExoForge", "playbooks", "exoos"),
        };

        foreach (var c in candidates)
        {
            try
            {
                var full = Path.GetFullPath(c);
                if (Directory.Exists(full) && File.Exists(Path.Combine(full, "playbook.yml")))
                    return full;
            }
            catch { /* skip */ }
        }

        throw new DirectoryNotFoundException(
            "ExoOS playbook not found. Expected playbooks/exoos next to the app or under the repo.");
    }
}
