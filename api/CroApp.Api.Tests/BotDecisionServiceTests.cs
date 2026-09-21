using CroApp.Api.Services;

namespace CroApp.Api.Tests;

// Pure unit tests, deliberately not IClassFixture<WebApplicationFactory<Program>>-based like
// every other test in this project - BotDecisionService.ParseAndValidate is a pure function
// (raw LLM text + context in, a validated BotDecision out) with no Cosmos/HTTP dependency, so
// it's the one piece of bot logic worth testing without spinning up the emulator. It's also
// the single gate between an LLM's freeform output and a real BirdService.SendAsync call, so
// its fail-safe-to-None behavior on anything malformed or out-of-context is the main thing
// worth pinning down here.
public class BotDecisionServiceTests
{
    private static BotTickContext BuildContext(
        List<BotTickInboxItem>? inbox = null,
        List<BotTickContact>? humanFriends = null,
        List<BotTickContact>? botFriends = null,
        List<BotTickHub>? watchedHubs = null,
        Dictionary<string, int>? consecutiveBotReplies = null,
        int maxConsecutiveBotReplies = 3,
        int maxContentLength = 500) =>
        new(
            BotUserId: "bot-1",
            BotUsername: "Pixel",
            Persona: "Cheerful and curious.",
            Model: "meta-llama/Meta-Llama-3.1-8B-Instruct",
            Inbox: inbox ?? [],
            HumanFriends: humanFriends ?? [],
            BotFriends: botFriends ?? [],
            WatchedHubs: watchedHubs ?? [],
            ConsecutiveBotReplies: consecutiveBotReplies ?? [],
            MaxConsecutiveBotReplies: maxConsecutiveBotReplies,
            MaxContentLength: maxContentLength);

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("not json at all")]
    [InlineData("{\"action\": \"DeleteEveryUser\", \"targetId\": \"x\", \"content\": \"hi\"}")]
    [InlineData("{\"action\": \"None\", \"targetId\": \"x\", \"content\": \"hi\"}")]
    public void ParseAndValidate_FallsBackToNone_ForMalformedOrNoneInput(string? raw)
    {
        var decision = BotDecisionService.ParseAndValidate(raw, BuildContext());

        Assert.Equal(BotDecision.None, decision);
    }

    [Fact]
    public void ParseAndValidate_FallsBackToNone_WhenTargetIdMissingFromContext()
    {
        var context = BuildContext(humanFriends: [new BotTickContact("user-2", "Annie")]);
        var raw = """{"action": "NewToUser", "targetId": "user-does-not-exist", "content": "hi"}""";

        var decision = BotDecisionService.ParseAndValidate(raw, context);

        Assert.Equal(BotDecision.None, decision);
    }

    [Fact]
    public void ParseAndValidate_FallsBackToNone_WhenContentOrTargetIdIsMissing()
    {
        var context = BuildContext(humanFriends: [new BotTickContact("user-2", "Annie")]);
        var raw = """{"action": "NewToUser", "targetId": "user-2", "content": null}""";

        var decision = BotDecisionService.ParseAndValidate(raw, context);

        Assert.Equal(BotDecision.None, decision);
    }

    [Fact]
    public void ParseAndValidate_AcceptsNewToUser_WhenTargetIsAKnownHumanFriend()
    {
        var context = BuildContext(humanFriends: [new BotTickContact("user-2", "Annie")]);
        var raw = """{"action": "NewToUser", "targetId": "user-2", "content": "Hey Annie!"}""";

        var decision = BotDecisionService.ParseAndValidate(raw, context);

        Assert.Equal(BotActionKind.NewToUser, decision.Action);
        Assert.Equal("user-2", decision.TargetId);
        Assert.Equal("Hey Annie!", decision.Content);
    }

    [Fact]
    public void ParseAndValidate_AcceptsReplyToInbox_WhenTargetIsAnUnreadInboxItem()
    {
        var context = BuildContext(inbox: [new BotTickInboxItem("bird-1", "user-2", "Annie", "hello", "nest-2")]);
        var raw = """{"action": "ReplyToInbox", "targetId": "bird-1", "content": "hi back!"}""";

        var decision = BotDecisionService.ParseAndValidate(raw, context);

        Assert.Equal(BotActionKind.ReplyToInbox, decision.Action);
        Assert.Equal("bird-1", decision.TargetId);
    }

    [Fact]
    public void ParseAndValidate_FallsBackToNone_WhenHubIsNotWatched()
    {
        var context = BuildContext(watchedHubs: [new BotTickHub("hub-1", "Town Square")]);
        var raw = """{"action": "NewToHub", "targetId": "hub-99", "content": "hi hub"}""";

        var decision = BotDecisionService.ParseAndValidate(raw, context);

        Assert.Equal(BotDecision.None, decision);
    }

    [Fact]
    public void ParseAndValidate_AcceptsNewToHub_WhenHubIsWatched()
    {
        var context = BuildContext(watchedHubs: [new BotTickHub("hub-1", "Town Square")]);
        var raw = """{"action": "NewToHub", "targetId": "hub-1", "content": "hi hub"}""";

        var decision = BotDecisionService.ParseAndValidate(raw, context);

        Assert.Equal(BotActionKind.NewToHub, decision.Action);
        Assert.Equal("hub-1", decision.TargetId);
    }

    [Fact]
    public void ParseAndValidate_TruncatesContent_ToMaxContentLength()
    {
        var context = BuildContext(humanFriends: [new BotTickContact("user-2", "Annie")], maxContentLength: 5);
        var raw = """{"action": "NewToUser", "targetId": "user-2", "content": "this is way too long"}""";

        var decision = BotDecisionService.ParseAndValidate(raw, context);

        Assert.Equal("this ", decision.Content);
    }

    [Fact]
    public void ParseAndValidate_AllowsNewToBot_BelowTheConsecutiveReplyCap()
    {
        var context = BuildContext(
            botFriends: [new BotTickContact("bot-2", "Doomcro")],
            consecutiveBotReplies: new Dictionary<string, int> { ["bot-2"] = 2 },
            maxConsecutiveBotReplies: 3);
        var raw = """{"action": "NewToBot", "targetId": "bot-2", "content": "doom incoming"}""";

        var decision = BotDecisionService.ParseAndValidate(raw, context);

        Assert.Equal(BotActionKind.NewToBot, decision.Action);
    }

    [Fact]
    public void ParseAndValidate_BlocksNewToBot_AtOrAboveTheConsecutiveReplyCap()
    {
        var context = BuildContext(
            botFriends: [new BotTickContact("bot-2", "Doomcro")],
            consecutiveBotReplies: new Dictionary<string, int> { ["bot-2"] = 3 },
            maxConsecutiveBotReplies: 3);
        var raw = """{"action": "NewToBot", "targetId": "bot-2", "content": "doom incoming"}""";

        var decision = BotDecisionService.ParseAndValidate(raw, context);

        Assert.Equal(BotDecision.None, decision);
    }
}
