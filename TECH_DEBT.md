# Tech Debt

Accepted shortcuts, things flagged but out of scope at the time, and other known gaps
worth revisiting. See `CLAUDE.md` for the working conventions this file supports.

## `api/CroApp.Api.Tests/*.cs` fixture `ConfigureAppConfiguration` dictionaries are missing keys

17 of the 18 backend test files' `WebApplicationFactory<Program>` setup (the `AddInMemoryCollection`
dictionary in each file's constructor) never picks up `appsettings.json`'s real Cosmos container
names or the `BlobStorage:*` section at all - only whatever's explicitly listed in that file's own
dictionary resolves; everything else silently binds to its C# default (`string.Empty`), and
`Program.cs`'s dev-only startup container/blob-container provisioning then throws
(`ArgumentNullException`/`Azure.RequestFailedException`) before the test host ever finishes
starting. Only `HubPictureSuggestionEndpointTests.cs` and `ProfilePictureEndpointTests.cs` happen
to list a fuller key set (because they specifically exercise those features), so most of the
suite currently fails to boot at all when run locally against a fresh emulator
(`dotnet test CroApp.Api.Tests/CroApp.Api.Tests.csproj`) - reproduced 2026-09-02 on 17/18 files.
Suspected root cause: this repo's local checkout path contains a space (`.../Summer26/untitled
folder/...`), which plausibly breaks `WebApplicationFactory`'s content-root-based
`appsettings.json` discovery for the test host specifically (not `dotnet run`, which works fine
per CLAUDE.md's local-dev instructions) - unconfirmed, but would explain why CI (checkout paths
never contain spaces) doesn't see this. `EventEndpointTests.cs` was patched with the full key set
as part of the notification-tint work so it could actually run locally; the other 16 files still
have the gap. Fix: either give every fixture the same full key set (mechanical, but 16x
copy-paste), or add one shared test fixture/base class that supplies the whole `CosmosDb`/
`BlobStorage` config once. If the space-in-path theory holds, worth flagging to Oliver too, since
it'd affect any other tool that shells out based on content-root path assumptions.

## `HubPanelContent`'s header can't reuse the shared `PanelHeader` widget

`app/lib/web/widgets/hub_panel_content.dart` hand-rolls its own header instead of using
`PanelHeader` (`app/lib/web/widgets/panel_header.dart`), which every other panel body
(nest, bird, friend bird) uses. `PanelHeader` is a left-aligned `Row` (static avatar |
title/subtitle | close button); the Hub header is a centered `Column` with the avatar
itself acting as a tappable "suggest a photo" control (camera-badge overlay, upload
spinner state) - a shape `PanelHeader`'s API has no room for (`avatar` is a static
`Widget`, no `onTap`/loading slot). Flagged during the #128 frontend-refinement pass
rather than generalizing `PanelHeader` to fit both layouts, since that's a real design
question (does a second layout mode belong on the shared widget, or does Hub's tappable-
avatar pattern belong on every panel eventually?) rather than a mechanical fix. Revisit if
a third panel needs a non-Row header shape, which would make the case for a shared
variant clearer.
