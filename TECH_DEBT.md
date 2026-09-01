# Tech Debt

Accepted shortcuts, things flagged but out of scope at the time, and other known gaps
worth revisiting. See `CLAUDE.md` for the working conventions this file supports.

## Leftover mobile-UI references after the `HomeScreen`/`birds_screen` removal

The mobile-UI retirement itself is done — `main.dart` no longer branches on `kIsWeb` and
`lib/screens/home_screen.dart`/`birds_screen.dart` are deleted — but a few things still
point at the removed screens:

- `theme.dart`'s `navigationBarTheme` block (`NavigationBarThemeData`, ~20 lines) is now
  dead: nothing in the app builds a `NavigationBar` widget anymore since `HomeScreen` (the
  only thing that used it) is gone. Safe to delete along with its "HomeScreen wraps the bar
  in a Container" comment.
- Stale comments in `web/screens/web_shell_screen.dart` ("the kIsWeb-gated sibling to the
  phone HomeScreen") and `services/bird_service.dart` ("rather than called directly from
  BirdsScreen") still describe the old two-UI structure.

Found while adding a 5-bird spawn cap to the web dock (`your_birds_dock.dart`).
