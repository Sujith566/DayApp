typedef ProgressRow = Map<String, Object?>;
String progressDay(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime calendarDay(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime shiftDay(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);
List<DateTime> reviewDays(DateTime now, int count) => List.generate(count, (i) => shiftDay(now, i - count + 1));
bool habitEligible(ProgressRow habit, String day) => (habit['created_on'] as String).compareTo(day) <= 0 &&
    (habit['archived_on'] == null || day.compareTo(habit['archived_on'] as String) < 0);
String logKey(int habitId, String day) => '$habitId:$day';
int habitStreak(int id, Set<String> logs, DateTime now) {
  var d = calendarDay(now);
  // An unfinished today does not break yesterday's streak until the day ends.
  if (!logs.contains(logKey(id, progressDay(d)))) { d = shiftDay(d, -1); }
  var count = 0;
  while (logs.contains(logKey(id, progressDay(d)))) { count++; d = shiftDay(d, -1); }
  return count;
}
class HabitScore {
  final int completed, eligible;
  const HabitScore(this.completed, this.eligible);
  int? get percent => eligible == 0 ? null : (100 * completed / eligible).round();
  factory HabitScore.calculate(List<ProgressRow> habits, Set<String> logs, List<DateTime> days) {
    var completed = 0, eligible = 0;
    for (final h in habits) {
      for (final date in days) {
        final day = progressDay(date);
        if (habitEligible(h, day)) {
          eligible++;
          if (logs.contains(logKey(h['id'] as int, day))) { completed++; }
        }
      }
    }
    return HabitScore(completed, eligible);
  }
}
class ReviewSummary {
  final int days, finished, journalDays, spending, unknownCompletions;
  final HabitScore habits;
  const ReviewSummary({required this.days, required this.finished, required this.journalDays,
    required this.spending, required this.unknownCompletions, required this.habits});
  int get journalPercent => (100 * journalDays / days).round();
  String get insight {
    if (habits.eligible == 0 && journalDays == 0 && finished == 0 && spending == 0) {
      return 'Your review starts with your first saved activity. Add a habit, write a journal entry, or complete a task to build your picture.';
    }
    final habitText = habits.percent == null ? 'Add a daily habit to begin tracking consistency.'
      : 'You completed ${habits.completed} of ${habits.eligible} available habit check-ins (${habits.percent}%).';
    return 'Over the last $days days, you wrote on $journalDays days and finished $finished tasks. $habitText Choose one small action to repeat tomorrow.';
  }
}
