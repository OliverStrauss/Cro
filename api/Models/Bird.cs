using System.Text.Json.Serialization;

namespace CroApp.Api.Models;

// Id is a generated GUID (a user always has exactly 3 of these), and UserId is the owning
// user's id and the partition key - same single-partition-per-owner reasoning as Waypoint.
// CurrentNestId is null until the owner creates their first nest (see the auto-assignment
// hook on POST /waypoints in Program.cs). IsTraveling/NestFromId/NestToId/Speed/Content are
// placeholders for the future send-a-bird flow - not populated or read this PR, always
// false/null for every bird created here.
public record Bird(
    [property: JsonPropertyName("id")] string Id,
    string UserId,
    string Name,
    string? CurrentNestId,
    bool IsTraveling,
    string? NestFromId,
    string? NestToId,
    double? Speed,
    string? Content,
    DateTimeOffset UpdatedAt);
