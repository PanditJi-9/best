/// Reading choices are independent of Flutter and of a chapter's page count.
/// A work profile stores only presentation; networking, OCR and device wake
/// policy remain device-wide settings.
enum ReaderMode {
  paged,
  vertical;

  static ReaderMode fromName(String? name) =>
      _named(values, name, ReaderMode.paged);
}

enum ReaderDirection {
  ltr,
  rtl;

  static ReaderDirection fromName(String? name) =>
      _named(values, name, ReaderDirection.ltr);

  bool get isRtl => this == ReaderDirection.rtl;
}

enum ReaderFit {
  screen,
  width,
  height,
  original;

  static ReaderFit fromName(String? name) =>
      _named(values, name, ReaderFit.screen);
}

/// How much of the left and right edge turns a page.
///
/// A small zone leaves a wide middle for the controls, which suits a phone held
/// one-handed; a large zone makes the edges easier to hit on a tablet.
enum ReaderTapZoneSize {
  small(0.20),
  medium(0.30),
  large(0.40);

  const ReaderTapZoneSize(this.edge);

  /// Fraction of the reader width on each side.
  final double edge;

  double get middleStart => edge;
  double get middleEnd => 1 - edge;

  static ReaderTapZoneSize fromName(String? name) =>
      _named(values, name, ReaderTapZoneSize.medium);
}

enum ReaderBackground {
  black,
  charcoal,
  sepia,
  white;

  static ReaderBackground fromName(String? name) =>
      _named(values, name, ReaderBackground.black);
}

enum ReaderSpreadMode {
  single,
  adaptive,
  doublePage;

  static ReaderSpreadMode fromName(String? name) =>
      _named(values, name, ReaderSpreadMode.single);
}

T _named<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

class ReaderPreferences {
  const ReaderPreferences({
    this.mode = ReaderMode.paged,
    this.direction = ReaderDirection.ltr,
    this.fit = ReaderFit.screen,
    this.background = ReaderBackground.black,
    this.tapZones = true,
    this.tapZoneSize = ReaderTapZoneSize.medium,
    this.webtoonGap = 0,
    this.filterMode = 'none',
    this.brightness = 0,
    this.spreadMode = ReaderSpreadMode.single,
    this.coverAlone = true,
  });

  final ReaderMode mode;
  final ReaderDirection direction;
  final ReaderFit fit;
  final ReaderBackground background;
  final bool tapZones;
  final ReaderTapZoneSize tapZoneSize;
  final int webtoonGap;
  final String filterMode;
  final int brightness;
  final ReaderSpreadMode spreadMode;
  final bool coverAlone;

  /// Never show two tiny pages on a portrait phone. Adaptive spreads are for
  /// wide landscape viewports; an explicit double-page choice also works on
  /// wide portrait tablets. Pan/fit-width surfaces keep a single scan.
  bool usesSpreads({required double width, required double height}) {
    if (!width.isFinite || !height.isFinite || width < 600 || height <= 0) {
      return false;
    }
    if (mode != ReaderMode.paged || fit != ReaderFit.screen) return false;
    return switch (spreadMode) {
      ReaderSpreadMode.single => false,
      ReaderSpreadMode.adaptive => width >= 720 && width > height,
      ReaderSpreadMode.doublePage => true,
    };
  }

  ReaderPreferences copyWith({
    ReaderMode? mode,
    ReaderDirection? direction,
    ReaderFit? fit,
    ReaderBackground? background,
    bool? tapZones,
    ReaderTapZoneSize? tapZoneSize,
    int? webtoonGap,
    String? filterMode,
    int? brightness,
    ReaderSpreadMode? spreadMode,
    bool? coverAlone,
  }) =>
      ReaderPreferences(
        mode: mode ?? this.mode,
        direction: direction ?? this.direction,
        fit: fit ?? this.fit,
        background: background ?? this.background,
        tapZones: tapZones ?? this.tapZones,
        tapZoneSize: tapZoneSize ?? this.tapZoneSize,
        webtoonGap: (webtoonGap ?? this.webtoonGap).clamp(0, 32),
        filterMode: filterMode ?? this.filterMode,
        brightness: (brightness ?? this.brightness).clamp(-75, 0),
        spreadMode: spreadMode ?? this.spreadMode,
        coverAlone: coverAlone ?? this.coverAlone,
      );

  Map<String, Object> toJson() => {
        'mode': mode.name,
        'direction': direction.name,
        'fit': fit.name,
        'background': background.name,
        'tapZones': tapZones,
        'tapZoneSize': tapZoneSize.name,
        'webtoonGap': webtoonGap,
        'filterMode': filterMode,
        'brightness': brightness,
        'spreadMode': spreadMode.name,
        'coverAlone': coverAlone,
      };

  factory ReaderPreferences.fromJson(Map<String, Object?> json) {
    String? text(String key) => switch (json[key]) {
          final String value => value,
          _ => null,
        };
    bool flag(String key, bool fallback) => switch (json[key]) {
          final bool value => value,
          _ => fallback,
        };
    int number(String key) => switch (json[key]) {
          final int value => value,
          _ => 0,
        };
    final filter = text('filterMode');
    return ReaderPreferences(
      mode: ReaderMode.fromName(text('mode')),
      direction: ReaderDirection.fromName(text('direction')),
      fit: ReaderFit.fromName(text('fit')),
      background: ReaderBackground.fromName(text('background')),
      tapZones: flag('tapZones', true),
      tapZoneSize: ReaderTapZoneSize.fromName(text('tapZoneSize')),
      webtoonGap: number('webtoonGap').clamp(0, 32),
      filterMode:
          const {'none', 'greyscale', 'invert', 'custom'}.contains(filter)
              ? filter!
              : 'none',
      brightness: number('brightness').clamp(-75, 0),
      spreadMode: ReaderSpreadMode.fromName(text('spreadMode')),
      coverAlone: flag('coverAlone', true),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderPreferences &&
      mode == other.mode &&
      direction == other.direction &&
      fit == other.fit &&
      background == other.background &&
      tapZones == other.tapZones &&
      tapZoneSize == other.tapZoneSize &&
      webtoonGap == other.webtoonGap &&
      filterMode == other.filterMode &&
      brightness == other.brightness &&
      spreadMode == other.spreadMode &&
      coverAlone == other.coverAlone;

  @override
  int get hashCode => Object.hash(mode, direction, fit, background, tapZones,
      tapZoneSize, webtoonGap, filterMode, brightness, spreadMode, coverAlone);
}
