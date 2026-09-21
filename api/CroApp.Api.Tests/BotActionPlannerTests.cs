using CroApp.Api.Data;
using CroApp.Api.Services;

namespace CroApp.Api.Tests;

// Pure unit tests (no emulator, unlike most of this project): the planner is the only thing
// deciding what a bot does, and BotMessageWriter.Clean is the only gate on LLM text.
public class BotActionPlannerTests
{
    private static readonly BotTickContact Human = new("user-2", "Annie");
    private static readonly BotTickContact OtherBot = new("bot-2", "Doomcro");
    private static readonly BotTickHub Hub = new("hub-1", "Ames Library");

    private static BotTickContext Ctx(
        List<BotTickInboxItem>? inbox = null,
        List<BotTickContact>? humans = null,
        List<BotTickContact>? bots = null,
        List<BotTickHub>? hubs = null,
        Dictionary<string, int>? volleys = null) =>
        new("bot-1", "Pixel", "Cheerful.", "model", inbox ?? [], humans ?? [], bots ?? [], hubs ?? [], volleys ?? [], 3, 500);

    // Random whose NextDouble()/Next(n) are pinned - NextDouble drives the act roll, Next(n) the picks.
    private sealed class FixedRandom(double next, int pick) : Random
    {
        public override double NextDouble() => next;
        public override int Next(int maxValue) => Math.Min(pick, maxValue - 1);
    }

    [Fact]
    public void FailedRoll_ReturnsNull_SoNoLlmCallHappens()
    {
        var plan = BotActionPlanner.Plan(Ctx(humans: [Human], hubs: [Hub]), new BotOrchestratorOptions(), new FixedRandom(0.5, 0));

        Assert.Null(plan); // ActChance 0.5: roll of 0.5 is not < 0.5
    }

    [Fact]
    public void Inbox_AlwaysReplies_EvenOnFailedRoll()
    {
        var inbox = new List<BotTickInboxItem> { new("bird-1", "user-2", "Annie", "hi", "nest-9") };

        var plan = BotActionPlanner.Plan(Ctx(inbox: inbox), new BotOrchestratorOptions(), new FixedRandom(0.99, 0));

        Assert.Equal(BotActionKind.ReplyToInbox, plan!.Action);
        Assert.Equal("bird-1", plan.TargetId);
        Assert.Equal("hi", plan.InboundContent);
    }

    [Fact]
    public void CappedBotInbox_IsNotReplied_FallsThroughToDice()
    {
        var inbox = new List<BotTickInboxItem> { new("bird-1", "bot-2", "Doomcro", "hi", "nest-9") };
        var ctx = Ctx(inbox: inbox, bots: [OtherBot], volleys: new() { ["bot-2"] = 3 });

        var plan = BotActionPlanner.Plan(ctx, new BotOrchestratorOptions(), new FixedRandom(0.99, 0));

        Assert.Null(plan);
    }

    [Fact]
    public void NoTargets_ReturnsNull_EvenOnPassingRoll()
    {
        Assert.Null(BotActionPlanner.Plan(Ctx(), new BotOrchestratorOptions(), new FixedRandom(0, 0)));
    }

    [Fact]
    public void OnlyHubs_PostsPubliclyToHub()
    {
        var plan = BotActionPlanner.Plan(Ctx(hubs: [Hub]), new BotOrchestratorOptions(), new FixedRandom(0, 0));

        Assert.Equal(BotActionKind.NewToHub, plan!.Action);
        Assert.Equal("hub-1", plan.TargetId);
        Assert.True(plan.IsPublic);
    }

    [Fact]
    public void OnlyCappedBotFriend_IsNeverTargeted()
    {
        var ctx = Ctx(bots: [OtherBot], volleys: new() { ["bot-2"] = 3 });

        Assert.Null(BotActionPlanner.Plan(ctx, new BotOrchestratorOptions(), new FixedRandom(0, 0)));
    }

    [Fact]
    public void WeightedPick_HitsEachBucketInOrder()
    {
        // Choices in order: friend(35), public(20), bot(15), hub(30) = 100. Next(total) pinned via `pick`.
        var ctx = Ctx(humans: [Human], bots: [OtherBot], hubs: [Hub]);
        var opts = new BotOrchestratorOptions();

        var friend = BotActionPlanner.Plan(ctx, opts, new FixedRandom(0, 0))!;
        var pub = BotActionPlanner.Plan(ctx, opts, new FixedRandom(0, 35))!;
        var bot = BotActionPlanner.Plan(ctx, opts, new FixedRandom(0, 55))!;
        var hub = BotActionPlanner.Plan(ctx, opts, new FixedRandom(0, 70))!;

        Assert.Equal((BotActionKind.NewToUser, false), (friend.Action, friend.IsPublic));
        Assert.Equal((BotActionKind.NewToUser, true), (pub.Action, pub.IsPublic));
        Assert.Equal(BotActionKind.NewToBot, bot.Action);
        Assert.Equal(BotActionKind.NewToHub, hub.Action);
    }

    [Theory]
    [InlineData(null, 500, null)]
    [InlineData("   ", 500, null)]
    [InlineData("\"hello there\"", 500, "hello there")]
    [InlineData("\u201chello\u201d", 500, "hello")]
    [InlineData("abcdefghij", 5, "abcde")]
    public void Clean_TrimsQuotesAndClips(string? raw, int max, string? expected)
    {
        Assert.Equal(expected, BotMessageWriter.Clean(raw, max));
    }
}
