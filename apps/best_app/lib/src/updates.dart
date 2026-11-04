import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'providers.dart';

/// Where Best publishes its signed APKs.
///
/// The repository is public, so the check needs no token and no account: the
/// app asks GitHub for the latest release, compares it with the installed
/// build, and stops there. Nothing about the reader leaves the device.
const String bestRepositoryUrl = 'https://github.com/PanditJi-9/best';
const String bestReleasesUrl = '$bestRepositoryUrl/releases';
const String bestReleasesApi =
    'https://api.github.com/repos/PanditJi-9/best/releases/latest';

/// A version as Flutter writes it: `1.0.0+19`.
///
/// Build metadata is compared too. A release tagged `v1.0.0` is not newer than
/// an installed `1.0.0+19`, while `v1.0.0+20` is. That keeps a rebuild of the
/// same release from nagging every reader.
@immutable
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(
    this.major,
    this.minor,
    this.patch, {
    this.build = 0,
    this.preRelease = '',
  });

  final int major;
  final int minor;
  final int patch;
  final int build;
  final String preRelease;

  static final RegExp _pattern = RegExp(
    r'^[vV]?(\d+)(?:\.(\d+))?(?:\.(\d+))?'
    r'(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.-]+))?$',
  );

  static AppVersion? tryParse(String raw) {
    final match = _pattern.firstMatch(raw.trim());
    if (match == null) return null;
    final buildText = match.group(5) ?? '';
    final build = int.tryParse(buildText) ?? 0;
    return AppVersion(
      int.parse(match.group(1)!),
      int.tryParse(match.group(2) ?? '') ?? 0,
      int.tryParse(match.group(3) ?? '') ?? 0,
      build: build,
      preRelease: match.group(4) ?? '',
    );
  }

  bool get isPreRelease => preRelease.isNotEmpty;

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    // A finished release outranks any pre-release of the same number.
    if (isPreRelease != other.isPreRelease) return isPreRelease ? -1 : 1;
    if (isPreRelease) {
      final byName = preRelease.compareTo(other.preRelease);
      if (byName != 0) return byName;
    }
    return build.compareTo(other.build);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;

  @override
  String toString() =>
      '$major.$minor.$patch${isPreRelease ? '-$preRelease' : ''}'
      '${build > 0 ? '+$build' : ''}';
}

/// True only when [candidate] parses and is strictly newer than [current].
///
/// An unparseable tag never produces an update prompt: inventing one would
/// send the reader to a page that may not be a release at all.
bool isNewerVersion(String candidate, String current) {
  final latest = AppVersion.tryParse(candidate);
  final installed = AppVersion.tryParse(current);
  if (latest == null || installed == null) return false;
  return latest > installed;
}

/// One published release, reduced to what the app needs.
@immutable
class AppRelease {
  const AppRelease({
    required this.tag,
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.apkUrl,
    this.publishedAt,
    this.prerelease = false,
  });

  final String tag;

  /// The tag without its `v`, e.g. `1.0.0`.
  final String version;
  final String notes;
  final String pageUrl;

  /// A direct `.apk` asset, or `null` when the release only has a page.
  final String? apkUrl;
  final DateTime? publishedAt;
  final bool prerelease;

  /// Parses one release object from the GitHub API.
  ///
  /// Returns `null` instead of throwing for a malformed object: one bad
  /// response must not take down the About screen.
  static AppRelease? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final tag = (raw['tag_name'] as Object?)?.toString().trim() ?? '';
    if (tag.isEmpty) return null;

    final page = _httpsUrl(raw['html_url']) ?? bestReleasesUrl;
    String? apk;
    final assets = raw['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is! Map<String, dynamic>) continue;
        final name = (asset['name'] as Object?)?.toString().toLowerCase() ?? '';
        if (!name.endsWith('.apk')) continue;
        final url = _httpsUrl(asset['browser_download_url']);
        if (url == null) continue;
        // Prefer the release build when a release publishes more than one APK.
        if (apk == null || name.contains('release')) apk = url;
      }
    }

    final published = DateTime.tryParse(
      (raw['published_at'] as Object?)?.toString() ?? '',
    );
    return AppRelease(
      tag: tag,
      version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      notes: plainReleaseNotes((raw['body'] as Object?)?.toString() ?? ''),
      pageUrl: page,
      apkUrl: apk,
      publishedAt: published,
      prerelease: raw['prerelease'] == true,
    );
  }

  static String? _httpsUrl(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return text;
  }
}

/// Turns GitHub's Markdown body into readable plain text.
///
/// The About screen is not a Markdown renderer: showing `##` and `**` would
/// look broken, and pulling a renderer in for one card is not worth the
/// weight. Links keep their text, lists keep their bullets.
String plainReleaseNotes(String markdown) {
  var text = markdown.replaceAll('\r\n', '\n').trim();
  if (text.isEmpty) return '';
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
    (match) => '${match.group(1)} (${match.group(2)})',
  );
  text = text.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
  text = text.replaceAll(RegExp(r'\*\*|__'), '');
  text = text.replaceAll(RegExp(r'(?<!\w)[*_](?=\S)|(?<=\S)[*_](?!\w)'), '');
  text = text.replaceAll('`', '');
  text = text.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '• ');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

enum UpdateFailure { network, rateLimited, notFound, malformed, server }

class UpdateException implements Exception {
  const UpdateException(this.failure);

  final UpdateFailure failure;

  @override
  String toString() => 'UpdateException($failure)';
}

/// Reads the latest release from GitHub's public API.
class UpdateChecker {
  UpdateChecker({required http.Client client, Uri? endpoint})
      : _client = client,
        _endpoint = endpoint ?? Uri.parse(bestReleasesApi);

  static const int _maxBytes = 512 * 1024;

  final http.Client _client;
  final Uri _endpoint;

  Future<AppRelease> latest() async {
    http.Response response;
    try {
      response = await _client.get(
        _endpoint,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Best-App',
        },
      ).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const UpdateException(UpdateFailure.network);
    } on UpdateException {
      rethrow;
    } catch (_) {
      throw const UpdateException(UpdateFailure.network);
    }

    if (response.statusCode == 403 || response.statusCode == 429) {
      throw const UpdateException(UpdateFailure.rateLimited);
    }
    if (response.statusCode == 404) {
      throw const UpdateException(UpdateFailure.notFound);
    }
    if (response.statusCode != 200) {
      throw const UpdateException(UpdateFailure.server);
    }
    if (response.bodyBytes.length > _maxBytes) {
      throw const UpdateException(UpdateFailure.malformed);
    }

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const UpdateException(UpdateFailure.malformed);
    }
    final release = AppRelease.fromJson(decoded);
    if (release == null) {
      throw const UpdateException(UpdateFailure.malformed);
    }
    if (release.prerelease) {
      throw const UpdateException(UpdateFailure.notFound);
    }
    return release;
  }
}

@immutable
class UpdateStatus {
  const UpdateStatus({
    required this.currentVersion,
    required this.release,
    required this.available,
  });

  final String currentVersion;
  final AppRelease release;
  final bool available;

  String get latestVersion => release.version;
}

/// The installed version, read once per launch.
typedef AppBuild = ({String version, String build});

final FutureProvider<AppBuild> appBuildProvider = FutureProvider<AppBuild>(
  (ref) async {
    final info = await PackageInfo.fromPlatform();
    return (version: info.version, build: info.buildNumber);
  },
);

final Provider<UpdateChecker> updateCheckerProvider = Provider<UpdateChecker>(
  (ref) => UpdateChecker(client: ref.watch(httpClientProvider)),
);

class UpdateController extends AsyncNotifier<UpdateStatus?> {
  /// GitHub allows 60 anonymous checks an hour per address. Six hours between
  /// automatic checks is plenty for a release feed and leaves the budget for
  /// every other app on the same network.
  static const Duration _minimumGap = Duration(hours: 6);
  static const String _checkedAtKey = 'app_update_checked_at';

  /// The About screen and the launch check can ask at the same moment; one
  /// request is enough, and the second caller can read the same result.
  bool _running = false;

  @override
  Future<UpdateStatus?> build() async => null;

  Future<void> check({bool force = false}) async {
    if (_running) return;
    final preferences = ref.read(preferencesProvider);
    if (!force && preferences != null) {
      final last = preferences.getInt(_checkedAtKey) ?? 0;
      if (last > 0) {
        final elapsed = DateTime.now().millisecondsSinceEpoch - last;
        if (elapsed >= 0 && elapsed < _minimumGap.inMilliseconds) return;
      }
    }

    _running = true;
    state = const AsyncLoading();
    try {
      final build = await ref.read(appBuildProvider.future);
      final current = build.build.isEmpty
          ? build.version
          : '${build.version}+${build.build}';
      final release = await ref.read(updateCheckerProvider).latest();
      final status = UpdateStatus(
        currentVersion: current,
        release: release,
        available: isNewerVersion(release.tag, current),
      );
      unawaited(preferences?.setInt(
        _checkedAtKey,
        DateTime.now().millisecondsSinceEpoch,
      ));
      state = AsyncData(status);
    } catch (error, stack) {
      state = AsyncError(error, stack);
    } finally {
      _running = false;
    }
  }
}

final AsyncNotifierProvider<UpdateController, UpdateStatus?> updateProvider =
    AsyncNotifierProvider<UpdateController, UpdateStatus?>(
  UpdateController.new,
);
