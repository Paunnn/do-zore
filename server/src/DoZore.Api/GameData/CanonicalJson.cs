using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace DoZore.Api.GameData;

/// <summary>
/// Canonical form used for the config version hash: object keys sorted by ordinal comparison,
/// no insignificant whitespace, UTF-8, numbers written as they appear in /data.
/// </summary>
public static class CanonicalJson
{
    public static string Serialize(JsonNode node)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream, new JsonWriterOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping }))
            Write(writer, node);
        return Encoding.UTF8.GetString(stream.ToArray());
    }

    public static string Sha256Hex(string canonical) =>
        Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(canonical)));

    static void Write(Utf8JsonWriter writer, JsonNode? node)
    {
        switch (node)
        {
            case null:
                writer.WriteNullValue();
                break;
            case JsonObject obj:
                writer.WriteStartObject();
                foreach (var (key, value) in obj.OrderBy(kv => kv.Key, StringComparer.Ordinal))
                {
                    writer.WritePropertyName(key);
                    Write(writer, value);
                }
                writer.WriteEndObject();
                break;
            case JsonArray arr:
                writer.WriteStartArray();
                foreach (var item in arr)
                    Write(writer, item);
                writer.WriteEndArray();
                break;
            default:
                node.WriteTo(writer);
                break;
        }
    }
}
