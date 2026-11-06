/// Maps viewport positions to the original, zero-based source page numbers.
/// Pairing never changes bookmark/progress identities and never crosses a
/// chapter boundary. Pages are returned in reading order, not screen order.
class ReaderPageLayout {
  const ReaderPageLayout({
    required this.pageCount,
    this.doublePage = false,
    this.coverAlone = true,
  }) : assert(pageCount >= 0);

  final int pageCount;
  final bool doublePage;
  final bool coverAlone;

  int get viewCount {
    if (!doublePage || pageCount < 2) return pageCount;
    return coverAlone ? 1 + (pageCount ~/ 2) : (pageCount + 1) ~/ 2;
  }

  int viewForPage(int page) {
    if (pageCount == 0) return 0;
    final index = page.clamp(0, pageCount - 1);
    if (!doublePage) return index;
    return coverAlone ? (index + 1) ~/ 2 : index ~/ 2;
  }

  List<int> pagesForView(int view) {
    if (pageCount == 0) return const [];
    final index = view.clamp(0, viewCount - 1);
    if (!doublePage) return [index];
    if (coverAlone && index == 0) return const [0];
    final first = coverAlone ? (index * 2) - 1 : index * 2;
    return [first, if (first + 1 < pageCount) first + 1];
  }

  int lastVisiblePage(int page) =>
      pageCount == 0 ? 0 : pagesForView(viewForPage(page)).last;

  @override
  bool operator ==(Object other) =>
      other is ReaderPageLayout &&
      pageCount == other.pageCount &&
      doublePage == other.doublePage &&
      coverAlone == other.coverAlone;

  @override
  int get hashCode => Object.hash(pageCount, doublePage, coverAlone);
}
