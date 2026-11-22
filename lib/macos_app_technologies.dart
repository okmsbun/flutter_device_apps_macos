/// A technology identified by a packaged component in a macOS app bundle.
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

  /// Dart code identified by a bundled Dart Kernel header.
  dart({_Category.programmingLanguages});

  const MacosAppTechnology(this._categories);

  final Set<_Category> _categories;
}

/// Categorized technologies identified in an accessible macOS app.
///
/// Each list is unmodifiable and contains each match at most once. A match can
/// come from a packaged dependency and appear in more than one category.
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
