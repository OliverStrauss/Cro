using System.Text.Json.Serialization;

namespace CroApp.Api.Models;

public record User(
    [property: JsonPropertyName("id")] string Id,
    string Username,
    string Email,
    DateTimeOffset CreatedAt);
