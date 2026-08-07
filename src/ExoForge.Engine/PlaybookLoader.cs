using System.Text;
using ExoForge.Schema;
using YamlDotNet.Serialization;
using YamlDotNet.Serialization.NamingConventions;

namespace ExoForge.Engine;

public sealed class LoadedPlaybook
{
    public required string RootPath { get; init; }
    public required PlaybookManifest Manifest { get; init; }
    public required List<(string File, ActionDocument Doc)> Documents { get; init; }
}

public static class PlaybookLoader
{
    private static readonly IDeserializer Yaml = new DeserializerBuilder()
        .WithNamingConvention(CamelCaseNamingConvention.Instance)
        .IgnoreUnmatchedProperties()
        .Build();

    public static LoadedPlaybook Load(string path)
    {
        path = Path.GetFullPath(path);
        if (!Directory.Exists(path))
            throw new DirectoryNotFoundException($"Playbook folder not found: {path}");

        var manifestPath = Path.Combine(path, "playbook.yml");
        if (!File.Exists(manifestPath))
            throw new FileNotFoundException("playbook.yml missing", manifestPath);

        var manifest = Yaml.Deserialize<PlaybookManifest>(File.ReadAllText(manifestPath, Encoding.UTF8));
        if (string.IsNullOrWhiteSpace(manifest.Id))
            throw new InvalidDataException("playbook.yml must set id");

        var docs = new List<(string, ActionDocument)>();
        var actionDir = Path.Combine(path, "actions");
        IEnumerable<string> files;
        if (manifest.ActionFiles is { Count: > 0 })
        {
            files = manifest.ActionFiles.Select(f =>
                Path.IsPathRooted(f) ? f : Path.Combine(path, f.Replace('/', Path.DirectorySeparatorChar)));
        }
        else if (Directory.Exists(actionDir))
        {
            files = Directory.GetFiles(actionDir, "*.yml").OrderBy(f => f, StringComparer.OrdinalIgnoreCase);
        }
        else
        {
            files = Array.Empty<string>();
        }

        foreach (var file in files)
        {
            if (!File.Exists(file))
                throw new FileNotFoundException("Action file missing", file);
            var doc = Yaml.Deserialize<ActionDocument>(File.ReadAllText(file, Encoding.UTF8));
            docs.Add((file, doc));
        }

        return new LoadedPlaybook
        {
            RootPath = path,
            Manifest = manifest,
            Documents = docs
        };
    }
}
