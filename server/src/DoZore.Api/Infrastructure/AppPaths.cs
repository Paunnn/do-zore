namespace DoZore.Api.Infrastructure;

/// <summary>
/// Locations of the repo's /contracts and /data folders. Set explicitly with Paths:Contracts and
/// Paths:Data, or found by walking up from the app directory (works for dev, tests and the Docker
/// image, which copies both folders next to the app).
/// </summary>
public sealed class AppPaths
{
    public required string Contracts { get; init; }
    public required string Data { get; init; }

    public static AppPaths Resolve(IConfiguration config) => new()
    {
        Contracts = Path.GetFullPath(config["Paths:Contracts"] ?? FindUp("contracts", "openapi.yaml")),
        Data = Path.GetFullPath(config["Paths:Data"] ?? FindUp("data", "economy.json")),
    };

    static string FindUp(string folder, string marker)
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            var candidate = Path.Combine(dir.FullName, folder);
            if (File.Exists(Path.Combine(candidate, marker)))
                return candidate;
        }

        throw new InvalidOperationException(
            $"Could not find the /{folder} folder above {AppContext.BaseDirectory}. Set Paths:{char.ToUpperInvariant(folder[0])}{folder[1..]}.");
    }
}
