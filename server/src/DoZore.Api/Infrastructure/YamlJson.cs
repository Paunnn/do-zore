using System.Globalization;
using System.Text.Json.Nodes;
using YamlDotNet.Core;
using YamlDotNet.RepresentationModel;

namespace DoZore.Api.Infrastructure;

/// <summary>
/// Converts YAML to JSON with YAML 1.2 core-schema typing: plain scalars become numbers, booleans
/// or null where they parse as such; quoted scalars stay strings.
/// </summary>
public static class YamlJson
{
    public static JsonNode? Parse(string yaml)
    {
        var stream = new YamlStream();
        stream.Load(new StringReader(yaml));
        return Convert(stream.Documents[0].RootNode);
    }

    static JsonNode? Convert(YamlNode node) => node switch
    {
        YamlMappingNode map => new JsonObject(map.Children.Select(kv =>
            KeyValuePair.Create(((YamlScalarNode)kv.Key).Value!, Convert(kv.Value)))),
        YamlSequenceNode seq => new JsonArray(seq.Children.Select(Convert).ToArray()),
        YamlScalarNode { Style: ScalarStyle.Plain } scalar => Plain(scalar.Value ?? ""),
        YamlScalarNode scalar => JsonValue.Create(scalar.Value),
        _ => throw new NotSupportedException($"Unsupported YAML node {node.NodeType}"),
    };

    static JsonNode? Plain(string value)
    {
        switch (value)
        {
            case "" or "~" or "null": return null;
            case "true": return JsonValue.Create(true);
            case "false": return JsonValue.Create(false);
        }

        if (long.TryParse(value, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var l))
            return JsonValue.Create(l);
        if (double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var d))
            return JsonValue.Create(d);
        return JsonValue.Create(value);
    }
}
