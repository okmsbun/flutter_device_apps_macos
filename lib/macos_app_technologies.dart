/// A technology identified by a packaged component or executable in a macOS app.
enum MacosAppTechnology {
  flutter({_Category.frameworks, _Category.uiToolkits}),
  electron({_Category.frameworks, _Category.runtimes}),

  /// The Qt framework, identified through its Qt Core library.
  qt({_Category.frameworks, _Category.libraries}),
  unity({_Category.gameEngines}),
  javaRuntime({_Category.runtimes}),
  qtWidgets({_Category.uiToolkits, _Category.libraries}),
  qtQuick({_Category.uiToolkits, _Category.libraries}),
  chromiumEmbeddedFramework({_Category.frameworks, _Category.libraries}),
  godot({_Category.gameEngines}),

  /// Dart code identified by a bundled Kernel header or AOT snapshot symbols.
  dart({_Category.programmingLanguages}),

  /// Swift code identified by Swift compiler metadata in the main executable.
  swift({_Category.programmingLanguages}),
  cocoa({_Category.frameworks}),
  macCatalyst({_Category.frameworks}),
  webKit({_Category.frameworks}),
  coreData({_Category.frameworks}),
  swiftData({_Category.frameworks}),
  sceneKit({_Category.frameworks}),
  realityKit({_Category.frameworks}),
  appKit({_Category.uiToolkits}),
  swiftUI({_Category.uiToolkits}),
  uiKit({_Category.uiToolkits}),
  avKit({_Category.uiToolkits, _Category.libraries}),
  spriteKit({_Category.frameworks, _Category.gameEngines}),
  javaScriptCore({_Category.runtimes}),
  pythonRuntime({_Category.runtimes}),
  dotnetRuntime({_Category.runtimes}),
  monoRuntime({_Category.runtimes}),
  libVlc({_Category.libraries}),
  sdl2({_Category.libraries}),
  sdl3({_Category.libraries}),
  combine({_Category.libraries}),
  coreML({_Category.libraries}),
  metal({_Category.libraries}),
  metalKit({_Category.libraries}),
  openGL({_Category.libraries}),
  coreGraphics({_Category.libraries}),
  quartzCore({_Category.libraries}),
  avFoundation({_Category.libraries}),
  coreMedia({_Category.libraries}),
  coreAudio({_Category.libraries}),
  audioToolbox({_Category.libraries});

  const MacosAppTechnology(this._categories);

  final Set<_Category> _categories;
}

/// Categorized technologies identified in an accessible macOS app.
///
/// Each list is unmodifiable and contains each match at most once. A match can
/// come from a linked dependency and appear in more than one category.
class MacosAppTechnologies {
  factory MacosAppTechnologies(Iterable<MacosAppTechnology> technologies) {
    final detected = technologies.toSet();
    List<MacosAppTechnology> forCategory(_Category category) =>
        List.unmodifiable(
          detected.where(
            (technology) => technology._categories.contains(category),
          ),
        );

    return MacosAppTechnologies._(
      frameworks: forCategory(_Category.frameworks),
      programmingLanguages: forCategory(_Category.programmingLanguages),
      uiToolkits: forCategory(_Category.uiToolkits),
      gameEngines: forCategory(_Category.gameEngines),
      runtimes: forCategory(_Category.runtimes),
      libraries: forCategory(_Category.libraries),
    );
  }

  const MacosAppTechnologies._({
    required this.frameworks,
    required this.programmingLanguages,
    required this.uiToolkits,
    required this.gameEngines,
    required this.runtimes,
    required this.libraries,
  });

  final List<MacosAppTechnology> frameworks;

  /// Languages identified directly from packaged code.
  final List<MacosAppTechnology> programmingLanguages;

  final List<MacosAppTechnology> uiToolkits;
  final List<MacosAppTechnology> gameEngines;
  final List<MacosAppTechnology> runtimes;
  final List<MacosAppTechnology> libraries;
}

enum _Category {
  frameworks,
  programmingLanguages,
  uiToolkits,
  gameEngines,
  runtimes,
  libraries,
}
