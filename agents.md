# Agent Documentation - Wispie Music Player

## Critical Rules

- **No git commands** - Never run write git operations. Git commands are for reading only.
- **No building** - Do not run `flutter build` or `flutter run` unless explicitly requested
- **No emojis** - Never use emojis in code, comments, or messages
- **Offline only** - Do not add features requiring internet connection unless explicitly requested
- **File-based identity** - User data (favorites, stats) is linked to filenames. Do not change this
- **Comments** - Minimal. Explain _why_, not _what_. No LLM-specific comments like "// added this"

## Code & Architecture Standards

Do not generate "vibe-coded" logic. Follow these rules:

- **Explicit error handling** - Catch specific exceptions. No broad `try/catch` that silences errors. No happy-path assumptions.
- **Modular structure** - Break monolithic widgets and functions into small, testable units. If a `build` method exceeds 50 lines, extract stateless widgets.
- **Strong typing** - No force unwrap (`!`). No `dynamic`. Leverage Dart's null safety properly.
- **No magic values** - No blind timeouts or arbitrary sleeps. Use proper state synchronization.
- **Riverpod everywhere** - Do not use `StatefulWidget` + `setState` for global state. Use the existing Riverpod providers.

Before writing code, reason through: side effects, failure modes, security, and reversibility.

## Architecture Summary

Local-First Flutter music player using Riverpod for state management with MVVM/Repository pattern.

## UI / Design Standard (Flat Design 2.0)

Do not generate "vibe-coded" UI. Adhere to Flat Design 2.0:

- **Vibrant color blocking** - Use intentional, high-contrast solid colors in large blocks. Define a strict palette.
- **No gradients** - Forbidden in UI elements, backgrounds, and text.
- **No borders or outlines** - Do not use `border`, `ring`, or outlines to separate elements. Use color blocking, whitespace, and layout geometry instead.
- **Smooth animations** - Use subtle, deliberate transitions (`cubic-bezier(0.4, 0, 0.2, 1)`) for state changes.
- **Design tokens first** - Never hardcode hex values or pixel sizes. Reference a theme provider or token system.
- **Consistent component hierarchy** - Use a predictable grid/flexbox layout. No absolute positioning unless mathematically necessary.
- **Semantic accessibility** - Use semantic Flutter widgets (`ListTile`, `IconButton`, etc.), manage focus states, and ensure proper labeling.

Before returning UI code, verify: no gradients, no borders used for separation, all styling references design tokens, animations are deliberate.

## Quick Reference

### Key Files

- **Playback**: `lib/services/audio_player_manager.dart`
- **Library State**: `lib/providers/providers.dart` -> `songsProvider`
- **User Data**: `lib/providers/user_data_provider.dart`
- **Database**: `lib/services/database_service.dart`
- **Search**: `lib/domain/services/search_service.dart`
- **Library Logic**: `lib/services/library_logic.dart`
- **Queue History**: `lib/providers/queue_history_provider.dart`
- **Queue History Screen**: `lib/presentation/screens/queue_history_screen.dart`

### Running Tests

```bash
flutter test
flutter test test/shuffle_logic_test.dart  # Specific test
```

### Project Structure

```
lib/
├── services/      # Primary logic layer
├── providers/     # Riverpod state management
├── models/        # Core entities
├── domain/        # Domain logic (search, etc.)
├── data/          # Data source abstractions
└── presentation/ # UI screens, widgets, routes
    ├── screens/
    ├── widgets/
    └── routes/
```
