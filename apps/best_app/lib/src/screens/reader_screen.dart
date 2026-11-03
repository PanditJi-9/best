import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:best_domain/best_domain.dart';
import 'package:best_ui/best_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../extension_host.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers.dart';

class ReaderScreen extends ConsumerWidget {
  const ReaderScreen({
    super.key,
    required this.sourceId,
    required this.url,
    required this.unitUrl,
  });

  final String sourceId;
  final String url;
  final String unitUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final key = (sourceId: sourceId, url: url, unitUrl: unitUrl);
    final data = ref.watch(readerProvider(key));

    return data.when(
      loading: () => const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
      error: (error, stack) => Theme(
        data: bestTheme(Brightness.dark),
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          backgroundColor: Colors.black,
          body: EmptyState(
            icon: Icons.broken_image_outlined,
            title: l10n.sourceError,
            body: '$error',
            action: FilledButton.icon(
              onPressed: () => ref.invalidate(readerProvider(key)),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.retry),
            ),
          ),
        ),
      ),
      data: (reader) =>
          _ReaderView(key: ValueKey(reader.unit.id), data: reader),
    );
  }
}

class _ReaderView extends ConsumerStatefulWidget {
  const _ReaderView({super.key, required this.data});

  final ReaderData data;

  @override
  ConsumerState<_ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends ConsumerState<_ReaderView> {
  late final PageController _controller;
  late final LibraryRepository _repository;
  late int _index;
  Timer? _saveTimer;

  /// The furthest page reached in this session. Activity counts new ground
  /// only: flipping back and forth is one page read, not twenty.
  late int _furthest;

  List<MediaResource> get _resources => widget.data.resources;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(repositoryProvider);
    final total = _resources.length;
    final saved = widget.data.progress?.position ?? 0;
    _index = total == 0 ? 0 : saved.clamp(0, total - 1);
    _furthest = _index;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveNow();
    _controller.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    if (index > _furthest) {
      final fresh = index - _furthest;
      _furthest = index;
      unawaited(_repository.recordActivity(pages: fresh));
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 320), _saveNow);
  }

  void _saveNow() {
    final total = _resources.length;
    if (total == 0) return;
    unawaited(
      _repository.saveProgress(
        UnitProgress(
          unitId: widget.data.unit.id,
          position: _index,
          total: total,
          completed: _index >= total - 1,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unit = widget.data.unit;
    final total = _resources.length;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
              ),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              unit.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            Text(
              widget.data.media.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          if (widget.data.offline)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 14),
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: BestColors.jade.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(BestRadius.pill),
                    border: Border.all(
                      color: BestColors.jade.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    child: Text(
                      l10n.offlineBadge,
                      style: const TextStyle(
                        color: BestColors.jade,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: total == 0
          ? Theme(
              data: bestTheme(Brightness.dark),
              child: Center(
                child: EmptyState(
                  icon: Icons.play_circle_outline,
                  title: unit.kind == UnitKind.episode
                      ? l10n.videoInPlayer
                      : l10n.nothingHere,
                  body: l10n.nothingHereBody,
                ),
              ),
            )
          : Stack(
              children: [
                PageView.builder(
                  controller: _controller,
                  onPageChanged: _onPageChanged,
                  itemCount: total,
                  itemBuilder: (context, index) => _ResourcePage(
                    resource: _resources[index],
                    sourceId: widget.data.media.ref.sourceId,
                    index: index,
                    total: total,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        34,
                        20,
                        12 + MediaQuery.paddingOf(context).bottom,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.82),
                          ],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              if (_index + 1 >= total) ...[
                                const Icon(
                                  Icons.check_circle_rounded,
                                  size: 13,
                                  color: BestColors.jade,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  _index + 1 >= total
                                      ? l10n.readerEnd
                                      : l10n.pageOf(_index + 1, total),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                              const SizedBox(width: BestSpace.md),
                              Flexible(
                                child: Text(
                                  widget.data.media.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius:
                                BorderRadius.circular(BestRadius.pill),
                            child: LinearProgressIndicator(
                              value: (_index + 1) / total,
                              minHeight: 3,
                              backgroundColor: Colors.white24,
                              color: BestColors.jade,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

Widget _pageFrame(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) {
  if (frame == null && !wasSynchronouslyLoaded) {
    return const Center(
      child: CircularProgressIndicator(color: Colors.white54),
    );
  }
  // Announced by screen readers, and the smoke gate waits for it so a page
  // count alone can never be mistaken for a decoded image again.
  return Semantics(
    label: AppLocalizations.of(context).pageImage,
    image: true,
    child: child,
  );
}

Widget _networkImage(String url, Map<String, String> headers) {
  return Image.network(
    url,
    headers: headers.isEmpty ? null : headers,
    fit: BoxFit.contain,
    frameBuilder: _pageFrame,
    loadingBuilder: (context, child, progress) {
      if (progress == null) return child;
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    },
    errorBuilder: (context, error, stack) => _PageError(message: '$error'),
  );
}

class _PageError extends StatelessWidget {
  const _PageError({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    return Semantics(
      label: AppLocalizations.of(context).pageImageError,
      container: true,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.broken_image_outlined,
              color: Colors.white38,
              size: 40,
            ),
            if (text != null && text.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResourcePage extends ConsumerStatefulWidget {
  const _ResourcePage({
    required this.resource,
    required this.sourceId,
    required this.index,
    required this.total,
  });

  final MediaResource resource;
  final String sourceId;
  final int index;
  final int total;

  @override
  ConsumerState<_ResourcePage> createState() => _ResourcePageState();
}

class _ResourcePageState extends ConsumerState<_ResourcePage> {
  /// Non-null only for an extension page: the host fetches it with the
  /// extension's own client, cookies and signing interceptors included.
  Future<Uint8List?>? _bytes;

  @override
  void initState() {
    super.initState();
    final resource = widget.resource;
    final source = extensionSourceIdOf(widget.sourceId);
    if (resource is ImageResource && source != null) {
      _bytes = ref
          .read(extensionHostProvider)
          .imageBytes(source, resource.url, headers: resource.headers);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resource = widget.resource;
    return switch (resource) {
      ImageResource(:final url, :final headers) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: _bytes == null
                ? _networkImage(url, headers)
                : FutureBuilder<Uint8List?>(
                    future: _bytes,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _PageError(message: '${snapshot.error}');
                      }
                      final bytes = snapshot.data;
                      if (bytes == null || bytes.isEmpty) {
                        // The host is absent (tests, desktop) or declined.
                        return _networkImage(url, headers);
                      }
                      return Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        frameBuilder: _pageFrame,
                        errorBuilder: (context, error, stack) =>
                            const _PageError(),
                      );
                    },
                  ),
          ),
        ),
      FileResource(:final path) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white38,
                  size: 40,
                ),
              ),
            ),
          ),
        ),
      SyntheticPage(index: final pageIndex, label: final label) =>
        _SyntheticPageView(
          page: pageIndex,
          label: label,
          position: widget.index,
          total: widget.total,
        ),
      VideoResource() => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.play_circle_outline,
                  color: Colors.white54,
                  size: 56,
                ),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context).videoInPlayer,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, height: 1.5),
                ),
              ],
            ),
          ),
        ),
    };
  }
}

/// A generated guide page. It is drawn, not downloaded, so the reader is fully
/// usable offline and the app never pretends a placeholder is licensed art.
class _SyntheticPageView extends StatelessWidget {
  const _SyntheticPageView({
    required this.page,
    required this.label,
    required this.position,
    required this.total,
  });

  final int page;
  final String label;
  final int position;
  final int total;

  static const List<List<Color>> _palettes = [
    [Color(0xFF15121B), Color(0xFF3A2233)],
    [Color(0xFF101A18), Color(0xFF1F4038)],
    [Color(0xFF1B1610), Color(0xFF4A3320)],
    [Color(0xFF111823), Color(0xFF233A52)],
  ];

  @override
  Widget build(BuildContext context) {
    final palette = _palettes[page % _palettes.length];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BEST · ${(page + 1).toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${position + 1} / $total',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
