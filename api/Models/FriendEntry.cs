namespace CroApp.Api.Models;

// ExchangeCount counts cro's actually delivered between these two users (see
// BirdService.ResolveArrivalIfDueAsync) - each side of a friendship keeps its own copy of
// this entry (see FriendService.SendRequestAsync), so both copies are bumped in lockstep on
// every delivery. Defaults to 0 so the existing FriendService/DevDataSeeder call sites that
// don't pass it keep compiling unchanged.
public record FriendEntry(string Id, string Username, string Status, string? Color, int ExchangeCount = 0);
