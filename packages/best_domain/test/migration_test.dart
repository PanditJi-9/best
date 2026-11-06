import 'package:best_domain/best_domain.dart';
import 'package:test/test.dart';

MediaUnit unit(
  String mediaId,
  double number,
  String title, {
  int pages = 0,
  String url = '',
}) {
  return MediaUnit(
    mediaId: mediaId,
    url: url.isEmpty ? 'u$number' : url,
    number: number,
    title: title,
    kind: UnitKind.chapter,
    pageCount: pages,
  );
}

void main() {
  group('MigrationPlan', () {
    test('pairs chapters by number even when the labels disagree', () {
      final from = [
        unit('old::a', 1, 'Chapter 1'),
        unit('old::a', 2, 'Chapter 2'),
        unit('old::a', 2.5, 'Chapter 2.5'),
      ];
      final to = [
        unit('new::b', 2.5, '٢.٥'),
        unit('new::b', 1, '١'),
        unit('new::b', 2, '2'),
      ];

      final plan = MigrationPlan.between(from, to);

      expect(plan.pairs, hasLength(3));
      expect(plan.unmatchedOld, isEmpty);
      expect(plan.coverage, 1.0);
      expect(plan.pairs.first.from.number, 1);
      expect(plan.pairs.first.to.mediaId, 'new::b');
    });

    test('does not pair one target chapter twice', () {
      final from = [
        unit('old::a', 1, 'Chapter 1'),
        unit('old::a', 1, 'Chapter 1 (duplicate)'),
      ];
      final to = [unit('new::b', 1, 'Chapter 1')];

      final plan = MigrationPlan.between(from, to);

      expect(plan.pairs, hasLength(1));
      expect(plan.unmatchedOld, hasLength(1));
    });

    test('falls back to a normalised label when the number is missing', () {
      final from = [unit('old::a', 0, 'الفصل ٤٢')];
      final to = [unit('new::b', 0, 'chapter 42')];

      final plan = MigrationPlan.between(from, to);

      expect(plan.pairs, hasLength(1));
    });

    test('leaves a chapter that is not on the target unmatched', () {
      final from = [
        unit('old::a', 1, 'Chapter 1'),
        unit('old::a', 2, 'Chapter 2'),
      ];
      final to = [unit('new::b', 1, 'Chapter 1')];

      final plan = MigrationPlan.between(from, to);

      expect(plan.pairs, hasLength(1));
      expect(plan.unmatchedOld.single.number, 2);
      expect(plan.coverage, closeTo(0.5, 0.0001));
    });

    test('carries positions onto the new unit and clamps to its page count', () {
      final from = [
        unit('old::a', 4, 'Chapter 4', pages: 20),
      ];
      final to = [
        unit('new::b', 4, 'Chapter 4', pages: 10),
      ];
      final plan = MigrationPlan.between(from, to);
      final oldId = from.single.id;

      final carried = plan.carryProgress({
        oldId: UnitProgress(
          unitId: oldId,
          position: 18,
          total: 20,
          completed: true,
          updatedAt: 99,
        ),
      });

      expect(carried, hasLength(1));
      expect(carried.single.unitId, to.single.id);
      expect(carried.single.position, 9);
      expect(carried.single.total, 10);
      expect(carried.single.completed, isTrue);
      expect(carried.single.updatedAt, 99);
    });

    test('does not carry progress for an unmatched chapter', () {
      final from = [unit('old::a', 1, 'Chapter 1')];
      final to = [unit('new::b', 2, 'Chapter 2')];
      final plan = MigrationPlan.between(from, to);

      final carried = plan.carryProgress({
        from.single.id: UnitProgress(
          unitId: from.single.id,
          position: 2,
          total: 10,
          updatedAt: 1,
        ),
      });

      expect(plan.pairs, isEmpty);
      expect(carried, isEmpty);
    });
  });

  group('Library categories', () {
    Media work(List<String> tags, {bool favorite = false}) => Media(
          ref: const SourceRef('test', 'a'),
          title: 'A',
          kind: MediaKind.manga,
          inLibrary: true,
          favorite: favorite,
          tags: tags,
        );

    LibraryEntry entry(Media media) => LibraryEntry(
          media: media,
          totalUnits: 4,
          completedUnits: 1,
        );

    test('narrows the shelf to one category', () {
      final entries = [
        entry(work(const ['Action'])),
        entry(work(const ['Romance'])),
      ];

      final result = LibraryPolicy.apply(
        entries,
        const LibraryQuery(tag: 'Action'),
      );

      expect(result, hasLength(1));
      expect(result.single.media.tags, contains('Action'));
    });

    test('keeps hidden categories out until they are revealed', () {
      final entries = [
        entry(work(const ['Action'])),
        entry(work(const ['Guilty pleasure'])),
      ];

      final hidden = LibraryPolicy.apply(
        entries,
        const LibraryQuery(hiddenTags: {'Guilty pleasure'}),
      );
      final revealed = LibraryPolicy.apply(
        entries,
        const LibraryQuery(
          hiddenTags: {'Guilty pleasure'},
          includeHidden: true,
        ),
      );

      expect(hidden, hasLength(1));
      expect(revealed, hasLength(2));
    });
  });
}
