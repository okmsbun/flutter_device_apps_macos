## 1.1.0

- Added `detectAppTechnologies()` with categorized results. Deprecated `detectAppFrameworks()` and `MacosAppFramework` and kept their original flat results.
- Added direct Mach-O dependency detection across Apple Silicon and Intel slices, including AppKit, SwiftUI, WebKit, Metal, and libVLC.
- Added Swift detection from compiler metadata and Dart detection from bundled Kernel and AOT snapshots.
- Expanded technology detection for Qt Widgets, Qt Quick, Chromium Embedded Framework, Godot, and additional linked libraries and runtimes.

## 1.0.0

- Added single and batch app lookups by bundle ID or absolute path, standalone PNG icon lookup, and installation, system, and launchability checks.
- Added opt-in Spotlight discovery and user-selected search folders saved with security-scoped bookmarks.
- Added agent and background flags, plus optional CPU architectures, bundle size, and Team ID.
- Added framework detection for Flutter, Electron, Qt, Unity, and Java Runtime, plus install source indicators and declared capabilities.
- Added actions to open an app, reveal it in Finder, and move its bundle to Trash.
- Added running app snapshots and APIs to find the default or available file handlers and open a file in a selected app.
- Expanded the example and installed apps guide to cover discovery, app lookup, and file handlers.

## 0.1.0

- Added `listApps`, `MacosAppInfo`, bundle ID filters, and optional PNG icons.
- Added an interactive macOS example and implementation TODO list.
- Added GitHub Actions for quality checks and Dart, widget, and native macOS tests.
