using CroApp.Api.Models;
using CroApp.Api.Services;

namespace CroApp.Api.Tests;

// Pure unit tests (no emulator): the backdrop formatting and prompt assembly are what turn a
// bot from "answers one line cold" into "replies with the thread, the clock, and the board in view".
public class BotBackdropTests
{
    private static readonly BotBackdrop Empty = new("Sunday evening", 0, null, [], []);

    [Fact]
    public void LocalTime_ShiftsByLongitude()
    {
        // 23:00 UTC in Ames (lng -93.6, ~6.2h behind UTC) is ~16:45 local Sunday -> afternoon.
        var result = BotBackdropFacts.LocalTime(new DateTimeOffset(2026, 9, 20, 23, 0, 0, TimeSpan.Zero), -93.6);

        Assert.Equal("Sunday afternoon", result);
    }

    [Theory]
    [InlineData(2, "night")]
    [InlineData(8, "morning")]
    [InlineData(13, "afternoon")]
    [InlineData(19, "evening")]
    public void LocalTime_NamesPartOfDay(int hour, string part)
    {
        var result = BotBackdropFacts.LocalTime(new DateTimeOffset(2026, 9, 20, hour, 0, 0, TimeSpan.Zero), 0);

        Assert.Equal($"Sunday {part}", result);
    }

    [Theory]
    [InlineData(30, "under an hour")]
    [InlineData(60, "about 1 hour")]
    [InlineData(300, "about 5 hours")]
    [InlineData(60 * 24 * 2, "about 2 days")]
    public void Duration_ReadsNaturally(int minutes, string expected) =>
        Assert.Equal(expected, BotBackdropFacts.Duration(TimeSpan.FromMinutes(minutes)));

    [Fact]
    public void Notes_AreNullWhenNothingIsKnown()
    {
        Assert.Null(BotBackdropFacts.ReplyNote("Annie", null, null));
        Assert.Null(BotBackdropFacts.OutboundNote("Annie", null));
    }

    [Fact]
    public void ReplyNote_CombinesDurationAndDistance() =>
        Assert.Equal("Annie's message took about 2 days to arrive and travelled about 40 km.",
            BotBackdropFacts.ReplyNote("Annie", 40.2, TimeSpan.FromDays(2)));

    [Fact]
    public void AppendThread_KeepsOnlyTheNewestLines()
    {
        var existing = Enumerable.Range(1, 5).Select(i => new BotThreadLine(i % 2 == 0, $"m{i}")).ToList();

        var result = BotBackdropFacts.AppendThread(existing, [new BotThreadLine(true, "m6"), new BotThreadLine(false, "m7")]);

        Assert.Equal(BotBackdropFacts.MaxThreadLines, result.Count);
        Assert.Equal("m2", result[0].Text);
        Assert.Equal("m7", result[^1].Text);
    }

    [Fact]
    public void AppendThread_HandlesNoExistingThread() =>
        Assert.Single(BotBackdropFacts.AppendThread(null, [new BotThreadLine(true, "hi")]));

    [Fact]
    public void Prompt_WithNoContext_IsJustTimeAndTheAsk()
    {
        var plan = new BotPlan(BotActionKind.NewToUser, "u2", "Annie", false);

        var prompt = BotMessageWriter.BuildUserPrompt(plan, Empty);

        Assert.Equal("It's Sunday evening where you live.\nWrite a new message to your friend Annie.", prompt.ReplaceLineEndings("\n"));
    }

    [Fact]
    public void Prompt_Reply_IncludesHistoryCountTravelAndTheInboundMessageLast()
    {
        var plan = new BotPlan(BotActionKind.ReplyToInbox, "b1", "Annie", false, "did it snow?");
        var backdrop = Empty with
        {
            ExchangeCount = 7,
            TravelNote = "Annie's message took about 2 days to arrive.",
            History = [new BotThreadLine(false, "hey!"), new BotThreadLine(true, "hi Annie")],
        };

        var prompt = BotMessageWriter.BuildUserPrompt(plan, backdrop).ReplaceLineEndings("\n");

        Assert.Contains("traded 7 cros", prompt);
        Assert.Contains("took about 2 days", prompt);
        Assert.Contains("Annie: hey!\nYou: hi Annie", prompt);
        Assert.EndsWith("Annie sent you: \"did it snow?\"\nWrite your reply.", prompt);
    }

    [Fact]
    public void Prompt_Hub_IncludesBoardTail()
    {
        var plan = new BotPlan(BotActionKind.NewToHub, "h1", "Ames Library", true);
        var backdrop = Empty with { BoardTail = ["Annie: quiet today", "Test1: same"] };

        var prompt = BotMessageWriter.BuildUserPrompt(plan, backdrop).ReplaceLineEndings("\n");

        Assert.Contains("Latest posts on this board, oldest first:\nAnnie: quiet today\nTest1: same", prompt);
        Assert.EndsWith("public board of the landmark \"Ames Library\".", prompt);
    }

    [Fact]
    public void Prompt_ClipsLongHistoryLines()
    {
        var plan = new BotPlan(BotActionKind.NewToUser, "u2", "Annie", false);
        var backdrop = Empty with { History = [new BotThreadLine(false, new string('x', 500))] };

        var prompt = BotMessageWriter.BuildUserPrompt(plan, backdrop);

        Assert.DoesNotContain(new string('x', 201), prompt);
    }
}
