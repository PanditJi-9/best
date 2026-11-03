import 'package:flutter/widgets.dart';

/// One sentence in the two languages the app ships with.
///
/// Release notes are constants, not ARB entries: they describe a past build
/// and should read the same even if a later translation changes the wording of
/// the UI around them.
class LocalizedText {
  const LocalizedText({required this.en, required this.ar});

  final String en;
  final String ar;

  String of(Locale locale) =>
      locale.languageCode.toLowerCase() == 'ar' ? ar : en;
}
