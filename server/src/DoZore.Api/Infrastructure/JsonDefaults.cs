using System.Text.Json;
using System.Text.Json.Serialization;

namespace DoZore.Api.Infrastructure;

/// <summary>Wire format from the contract: snake_case properties and enum values.</summary>
public static class JsonDefaults
{
    public static readonly JsonSerializerOptions Options = Configure(new JsonSerializerOptions(JsonSerializerDefaults.Web));

    public static JsonSerializerOptions Configure(JsonSerializerOptions options)
    {
        options.PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower;
        // Dictionary keys are data ids (upgrade ids etc.), not property names.
        options.DictionaryKeyPolicy = null;
        options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower, allowIntegerValues: false));
        return options;
    }
}
