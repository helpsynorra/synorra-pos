import 'package:flutter_test/flutter_test.dart';
import 'package:synorra_pos/manila_time.dart';

void main() {
  test('converts UTC timestamps to Manila time', () {
    expect(
      ManilaTime.parse('2026-09-30T11:58:00Z'),
      DateTime.utc(2026, 9, 30, 19, 58),
    );
  });

  test('converts timestamps with an explicit offset to Manila time', () {
    expect(
      ManilaTime.parse('2026-09-30T11:58:00+02:00'),
      DateTime.utc(2026, 9, 30, 17, 58),
    );
  });

  test('treats legacy timestamps without an offset as Manila wall time', () {
    expect(
      ManilaTime.parse('2026-09-30T11:58:00'),
      DateTime.utc(2026, 9, 30, 11, 58),
    );
  });

  test('serializes Manila wall time as the corresponding UTC instant', () {
    expect(
      ManilaTime.utcIsoFromManilaWallTime(DateTime.utc(2026, 9, 30, 14, 37)),
      '2026-09-30T06:37:00.000Z',
    );
  });

  test('matches ranges using the selected Manila date as the anchor', () {
    final anchor = DateTime.utc(2026, 10, 1);

    expect(ManilaTime.matchesRange('2026-09-30T16:00:00Z', 'Today', anchor), isTrue);
    expect(ManilaTime.matchesRange('2026-09-30T16:00:00Z', 'Date', anchor), isTrue);
    expect(ManilaTime.matchesRange('2026-10-01T16:00:00Z', 'Date', anchor), isFalse);
    expect(ManilaTime.matchesRange('2026-09-29T16:00:00Z', 'This Week', anchor), isTrue);
    expect(ManilaTime.matchesRange('2026-09-26T16:00:00Z', 'Last Week', anchor), isTrue);
    expect(ManilaTime.matchesRange('2026-09-30T15:00:00Z', 'Last Month', anchor), isTrue);
    expect(ManilaTime.matchesRange('2025-09-30T16:00:00Z', 'Last Year', anchor), isTrue);
    expect(ManilaTime.matchesRange('2026-10-01T16:00:00Z', 'Last Week', anchor), isFalse);
  });
}