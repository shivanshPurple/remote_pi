import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/room_activity_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RoomActivityStore (in-memory)', () {
    test('defaults, markOpened stamps recency + clears unread', () async {
      final s = RoomActivityStore();
      expect(s.lastOpenedAt('e', 'r'), isNull);
      expect(s.unread('e', 'r'), 0);

      await s.bumpUnread('e', 'r');
      await s.bumpUnread('e', 'r');
      expect(s.unread('e', 'r'), 2);
      expect(s.lastOpenedAt('e', 'r'), isNull, reason: 'bump alone keeps null');

      final at = DateTime.fromMillisecondsSinceEpoch(12345);
      await s.markOpened('e', 'r', at: at);
      expect(s.lastOpenedAt('e', 'r'), at);
      expect(s.unread('e', 'r'), 0);
    });

    test('notifies listeners on writes only', () async {
      final s = RoomActivityStore();
      var calls = 0;
      s.addListener(() => calls++);
      await s.markOpened('e', 'r');
      expect(calls, 1);
      await s.markOpened('e', 'r');
      expect(calls, 2);
    });
  });

  group('RoomActivityStore (durable Hive)', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('rp_room_activity');
      await LocalBoxes.initForTest('${tmp.path}/boxes');
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('survives a store rebuild on the same box', () async {
      final box = LocalBoxes().roomActivityBox();
      final s = RoomActivityStore(box: box);
      await s.bumpUnread('epk', 'room');
      await s.bumpUnread('epk', 'room');
      await s.markOpened(
        'epk',
        'other',
        at: DateTime.fromMillisecondsSinceEpoch(42),
      );

      // Same underlying box → a fresh store sees the same data.
      final s2 = RoomActivityStore(box: LocalBoxes().roomActivityBox());
      expect(s2.unread('epk', 'room'), 2);
      expect(
        s2.lastOpenedAt('epk', 'other'),
        DateTime.fromMillisecondsSinceEpoch(42),
      );
    });
  });
}
