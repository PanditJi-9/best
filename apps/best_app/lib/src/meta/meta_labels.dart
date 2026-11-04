import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import 'meta_models.dart';

String metaKindLabel(AppLocalizations l10n, MetaKind kind) => switch (kind) {
      MetaKind.anime => l10n.kindAnime,
      MetaKind.manga => l10n.kindManga,
      MetaKind.manhwa => l10n.kindManhwa,
      MetaKind.manhua => l10n.kindManhua,
      MetaKind.unknown => l10n.statusUnknown,
    };

/// Provider status strings are not one vocabulary: AniList says RELEASING,
/// MAL says "Finished Airing", hwa says completed. This is the one place that
/// turns them into a sentence.
String metaStatusLabel(AppLocalizations l10n, String? raw) {
  final value = raw?.trim().toLowerCase() ?? '';
  if (value.isEmpty) return '';
  if (value.contains('releasing') ||
      value.contains('airing') && !value.contains('finished')) {
    return l10n.statusAiring;
  }
  if (value.contains('finished')) return l10n.statusFinished;
  if (value.contains('not_yet') ||
      value.contains('not yet') ||
      value.contains('upcoming')) {
    return l10n.statusUpcoming;
  }
  if (value.contains('hiatus')) return l10n.statusHiatus;
  if (value.contains('cancel')) return l10n.statusCancelled;
  if (value.contains('complete')) return l10n.statusCompleted;
  if (value.contains('ongoing')) return l10n.statusOngoing;
  if (value.contains('announce')) return l10n.statusAnnounced;
  return raw!;
}

String metaFormatLabel(String? raw) {
  final value = raw?.trim().toUpperCase() ?? '';
  return switch (value) {
    'TV' => 'TV',
    'TV_SHORT' => 'TV Short',
    'MOVIE' => 'Movie',
    'OVA' => 'OVA',
    'ONA' => 'ONA',
    'SPECIAL' => 'Special',
    'MUSIC' => 'Music',
    'MANGA' => 'Manga',
    'NOVEL' => 'Novel',
    'ONE_SHOT' => 'One-shot',
    _ => raw?.trim() ?? '',
  };
}

String metaSeasonLabel(String? season, int? year, bool arabic) {
  if (season == null && year == null) return '';
  final name = switch (season?.toUpperCase()) {
    'WINTER' => arabic ? 'الشتاء' : 'Winter',
    'SPRING' => arabic ? 'الربيع' : 'Spring',
    'SUMMER' => arabic ? 'الصيف' : 'Summer',
    'FALL' => arabic ? 'الخريف' : 'Fall',
    _ => '',
  };
  if (name.isEmpty) return year?.toString() ?? '';
  if (year == null) return name;
  return arabic ? '$name $year' : '$name $year';
}

String metaCount(int? value) {
  if (value == null || value <= 0) return '—';
  if (value >= 1000000) {
    final short = value / 1000000;
    return '${short.toStringAsFixed(short >= 10 ? 0 : 1)}M';
  }
  if (value >= 1000) {
    final short = value / 1000;
    return '${short.toStringAsFixed(short >= 10 ? 0 : 1)}K';
  }
  return '$value';
}

String metaScoreText(double? score) =>
    score == null ? '—' : score.toStringAsFixed(1);

String metaCountdown(int? epochSeconds, bool arabic) {
  if (epochSeconds == null) return '';
  final at = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  final diff = at.difference(DateTime.now());
  if (diff.isNegative) return metaDateLabel(at, arabic);
  if (diff.inDays > 0) {
    return arabic ? 'بعد ${diff.inDays} يوم' : 'in ${diff.inDays}d';
  }
  if (diff.inHours > 0) {
    return arabic ? 'بعد ${diff.inHours} ساعة' : 'in ${diff.inHours}h';
  }
  final minutes = diff.inMinutes < 1 ? 1 : diff.inMinutes;
  return arabic ? 'بعد $minutes دقيقة' : 'in ${minutes}m';
}

String metaDateLabel(DateTime? date, bool arabic) {
  if (date == null) return '';
  final local = date.toLocal();
  final diff = DateTime.now().difference(local);
  if (!diff.isNegative) {
    if (diff.inMinutes < 60) {
      final minutes = diff.inMinutes < 1 ? 1 : diff.inMinutes;
      if (arabic) {
        return minutes == 1 ? 'منذ دقيقة' : 'منذ $minutes دقائق';
      }
      return '${minutes}m ago';
    }
    if (diff.inHours < 24) {
      if (arabic) {
        return diff.inHours == 1 ? 'منذ ساعة' : 'منذ ${diff.inHours} ساعات';
      }
      return '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      if (arabic) {
        return diff.inDays == 1 ? 'منذ يوم' : 'منذ ${diff.inDays} أيام';
      }
      return '${diff.inDays}d ago';
    }
  }
  const arMonths = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];
  const enMonths = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = arabic ? arMonths[local.month - 1] : enMonths[local.month - 1];
  return '${local.day} $month ${local.year}';
}

String metaGenreLabel(String genre, bool arabic) {
  if (!arabic) return genre;
  const translations = <String, String>{
    'Action': 'أكشن',
    'Adventure': 'مغامرة',
    'Comedy': 'كوميديا',
    'Drama': 'دراما',
    'Fantasy': 'فانتازيا',
    'Horror': 'رعب',
    'Mystery': 'غموض',
    'Romance': 'رومانسية',
    'Sci-Fi': 'خيال علمي',
    'Slice of Life': 'شريحة من الحياة',
    'Sports': 'رياضة',
    'Supernatural': 'خارق للطبيعة',
    'Thriller': 'إثارة',
    'Psychological': 'نفسي',
    'Historical': 'تاريخي',
    'School': 'مدرسي',
    'Shounen': 'شونين',
    'Shonen': 'شونين',
    'Seinen': 'سينين',
    'Josei': 'جوسي',
    'Shoujo': 'شوجو',
    'Isekai': 'إيسيكاي',
    'Martial Arts': 'فنون قتالية',
    'Mecha': 'ميكا',
    'Music': 'موسيقى',
    'Ecchi': 'إيتشي',
    'Harem': 'حريم',
    'Military': 'عسكري',
    'Space': 'فضاء',
    'Vampire': 'مصاصو دماء',
    'Demons': 'شياطين',
    'Magic': 'سحر',
    'Award Winning': 'حاصل على جوائز',
    'Award-Winning': 'حاصل على جوائز',
    'Game': 'ألعاب',
    'Parody': 'محاكاة ساخرة',
    'Samurai': 'ساموراي',
    'Gore': 'عنف دموي',
    'Survival': 'بقاء',
    'Reincarnation': 'تناسخ',
    'Time Travel': 'السفر عبر الزمن',
    'Adult Cast': 'طاقم بالغ',
    'Detective': 'تحقيق',
    'Delinquents': 'مشاغبون',
    'Organized Crime': 'جريمة منظمة',
    'Workplace': 'بيئة العمل',
    'Otaku Culture': 'ثقافة أوتاكو',
    'Video Game': 'ألعاب فيديو',
    'Visual Arts': 'فنون بصرية',
  };
  return translations[genre] ?? genre;
}

Color metaSourceColor(MetaSource source) => switch (source) {
      MetaSource.anilist => BestColors.blue,
      MetaSource.myAnimeList => const Color(0xFF4F7CC9),
      MetaSource.hwa => const Color(0xFFEC4899),
      MetaSource.animeCorner => const Color(0xFFF97316),
    };
