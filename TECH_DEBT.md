# Tech Debt

Accepted shortcuts, things flagged but out of scope at the time, and other known gaps
worth revisiting. See `CLAUDE.md` for the working conventions this file supports.

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
