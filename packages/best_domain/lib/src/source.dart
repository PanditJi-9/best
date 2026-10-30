import 'media.dart';
import 'units.dart';

/// One addressable page or stream.
sealed class MediaResource {
  const MediaResource();
}

final class ImageResource extends MediaResource {
  const ImageResource(this.url, {this.headers = const {}});

  final String url;

  /// Referer/cookies required by some sources. Never logged.
  final Map<String, String> headers;
}

final class VideoResource extends MediaResource {
  const VideoResource(
    this.url, {
    this.headers = const {},
    this.subtitleUrl,
    this.mimeType,
  });

  final String url;
  final Map<String, String> headers;
  final String? subtitleUrl;
  final String? mimeType;
}

/// A generated page used by the offline guide and by tests. It is explicit so
/// the reader never pretends a missing image is a real page.
final class SyntheticPage extends MediaResource {
  const SyntheticPage(this.index, this.label);

  final int index;
  final String label;
}

/// The contract every catalogue implements: a website, an extension host, a
/// self-hosted server, or the bundled guide.
///
/// It is deliberately small and suspend-only. Adding a method is a breaking
/// change for every adapter, so the surface stays this thin.
abstract interface class SourceAdapter {
  /// Stable machine id, namespaced by adapter family (`mangadex`, `mihon:123`).
  String get id;

  /// What a person sees in the source picker.
  String get name;

  /// BCP-47-ish tag, or `all`.
  String get language;

  Future<List<Media>> popular({int page = 1});

  Future<List<Media>> search(String query, {int page = 1});

  /// Fills fields the listing does not carry. Default: the listing is enough.
  Future<Media> details(Media media) async => media;

  Future<List<MediaUnit>> units(Media media);

  Future<List<MediaResource>> resources(MediaUnit unit);
}

/// Resolves a source by id and lists what is installed.
///
/// The list is supplied through a callback, not captured once: installing or
/// disabling an adapter must be visible to the next screen without rebuilding
/// the object graph.
class SourceRegistry {
  SourceRegistry(this._provider);

  SourceRegistry.fixed(List<SourceAdapter> sources) : _provider = (() => sources);

  final List<SourceAdapter> Function() _provider;

  List<SourceAdapter> get all => List.unmodifiable(_provider());

  SourceAdapter? byId(String id) {
    for (final source in all) {
      if (source.id == id) return source;
    }
    return null;
  }
}
