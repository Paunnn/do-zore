using System.Text.Json;
using Json.Schema;

namespace DoZore.Api.Infrastructure;

public sealed record SchemaError(string Pointer, string Message);

/// <summary>
/// JSON Schema validators built straight from /contracts: every file in contracts/schemas and every
/// component schema in openapi.yaml. Validating against the contract itself keeps the server from
/// drifting from it.
/// </summary>
public sealed class ContractSchemas
{
    static readonly Uri OpenApiUri = new("https://do-zore.example/openapi.json");

    static readonly EvaluationOptions Evaluation = new()
    {
        OutputFormat = OutputFormat.List,
        RequireFormatValidation = true,
    };

    // Applicator keywords only summarise nested failures; the nested errors are more useful.
    static readonly HashSet<string> SummaryKeywords = ["properties", "items", "prefixItems", "$ref", "allOf", "patternProperties"];

    readonly Dictionary<string, JsonSchema> _files = [];
    readonly Dictionary<string, JsonSchema> _components = [];

    public JsonElement OpenApi { get; }

    public ContractSchemas(AppPaths paths)
    {
        var build = new BuildOptions { SchemaRegistry = new SchemaRegistry() };

        // Schema files reference each other; build until no more progress (dependency order).
        var pending = Directory.GetFiles(Path.Combine(paths.Contracts, "schemas"), "*.schema.json").ToList();
        while (pending.Count > 0)
        {
            var before = pending.Count;
            Exception? lastError = null;
            foreach (var file in pending.ToList())
            {
                try
                {
                    _files[Path.GetFileName(file)[..^".schema.json".Length]] = JsonSchema.FromFile(file, build);
                    pending.Remove(file);
                }
                catch (Exception ex)
                {
                    lastError = ex; // may reference a schema not built yet; retry next round
                }
            }

            if (pending.Count == before)
                throw new InvalidOperationException(
                    $"Could not build contract schemas: {string.Join(", ", pending.Select(Path.GetFileName))}", lastError);
        }

        var openApi = YamlJson.Parse(File.ReadAllText(Path.Combine(paths.Contracts, "openapi.yaml")))
            ?? throw new InvalidOperationException("openapi.yaml is empty");
        OpenApi = JsonDocument.Parse(openApi.ToJsonString()).RootElement.Clone();
        build.SchemaRegistry.Register(OpenApiUri, new JsonElementBaseDocument(OpenApi, OpenApiUri));

        foreach (var component in OpenApi.GetProperty("components").GetProperty("schemas").EnumerateObject())
        {
            var wrapper = $$"""{"$schema":"https://json-schema.org/draft/2020-12/schema","$ref":"{{OpenApiUri}}#/components/schemas/{{component.Name}}"}""";
            _components[component.Name] = JsonSchema.FromText(wrapper, build, new Uri($"https://do-zore.example/components/{component.Name}"));
        }
    }

    public IReadOnlyCollection<string> ComponentNames => _components.Keys;

    /// <summary>Validate against an OpenAPI component schema, e.g. "DeviceLoginRequest".</summary>
    public IReadOnlyList<SchemaError> ValidateComponent(string component, JsonElement instance) =>
        Collect(_components[component].Evaluate(instance, Evaluation));

    /// <summary>Validate against a file in contracts/schemas, e.g. "venues".</summary>
    public IReadOnlyList<SchemaError> ValidateFile(string schema, JsonElement instance) =>
        Collect(_files[schema].Evaluate(instance, Evaluation));

    static List<SchemaError> Collect(EvaluationResults results)
    {
        if (results.IsValid)
            return [];

        var all = new List<(string Keyword, SchemaError Error)>();
        foreach (var detail in results.Details ?? [])
        {
            if (detail.Errors is null) continue;
            foreach (var (keyword, message) in detail.Errors)
                all.Add((keyword, new SchemaError(detail.InstanceLocation.ToString(), message)));
        }

        var specific = all.Where(e => !SummaryKeywords.Contains(e.Keyword)).Select(e => e.Error).Distinct().ToList();
        if (specific.Count > 0)
            return specific;
        var any = all.Select(e => e.Error).Distinct().ToList();
        return any.Count > 0 ? any : [new SchemaError("", "Does not match the schema.")];
    }
}
