import 'package:flutter_test/flutter_test.dart';
import 'package:daynest/features/progress/progress_model.dart';
void main() {
  test('rolling review includes today across year boundaries', () {
    final days = reviewDays(DateTime(2027,1,2), 7).map(progressDay).toList();
    expect(days.first, '2026-12-27'); expect(days.last, '2027-01-02'); expect(days.length, 7);
  });
  test('a new habit does not penalize days before creation', () {
    final h = <String,Object?>{'id':1,'created_on':'2026-11-01','archived_on':null};
    final score = HabitScore.calculate([h], {'1:2026-11-01'}, reviewDays(DateTime(2026,11,1),7));
    expect(score.eligible,1); expect(score.completed,1); expect(score.percent,100);
  });
  test('archive retains historical eligibility but stops future days', () {
    final h = <String,Object?>{'id':1,'created_on':'2026-10-30','archived_on':'2026-11-02'};
    final score = HabitScore.calculate([h], {'1:2026-10-31','1:2026-11-01','1:2026-11-02'}, reviewDays(DateTime(2026,11,3),7));
    expect(score.eligible,3); expect(score.completed,2); expect(score.percent,67);
  });
  test('no habits is unavailable rather than a fabricated score', () {
    expect(HabitScore.calculate([], {}, reviewDays(DateTime(2026,11,1),7)).percent, isNull);
  });
  test('unfinished today preserves yesterday streak; missed yesterday breaks it', () {
    final now = DateTime(2026,11,1);
    expect(habitStreak(1, {'1:2026-10-30','1:2026-10-31'},now),2);
    expect(habitStreak(1, {'1:2026-10-30'},now),0);
    expect(habitStreak(1, {'1:2026-10-30','1:2026-10-31','1:2026-11-01'},now),3);
  });
  test('streak handles leap days', () {
    expect(habitStreak(1, {'1:2028-02-28','1:2028-02-29','1:2028-03-01'},DateTime(2028,3,1)),3);
  });
}
