String _two(int n) => n.toString().padLeft(2, '0');

/// 14:02:13
String clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

String clockMs(int epochMs) => clock(DateTime.fromMillisecondsSinceEpoch(epochMs));

/// 0:42, 4:59, 1:02:03. Rounds up, so the last second reads 0:01; zero or less reads "now".
String countdown(Duration d) {
  if (d <= Duration.zero) return 'now';
  final s = (d.inMilliseconds / 1000).ceil();
  final h = s ~/ 3600, m = s % 3600 ~/ 60, sec = s % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(sec)}' : '$m:${_two(sec)}';
}

/// 0.4 s, 9.8 s, 42 s, 3 min 12 s, 2 h 5 min. Negative spans keep their sign.
String span(int ms) {
  if (ms < 0) return '-${span(-ms)}';
  if (ms < 10000) return '${(ms / 1000).toStringAsFixed(1)} s';
  final s = ms ~/ 1000;
  if (s < 60) return '$s s';
  if (s < 3600) return s % 60 == 0 ? '${s ~/ 60} min' : '${s ~/ 60} min ${s % 60} s';
  final m = s ~/ 60;
  return m % 60 == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h ${m % 60} min';
}

/// every minute, every 5 minutes
String every(Duration d) => d.inMinutes == 1 ? 'every minute' : 'every ${d.inMinutes} minutes';

/// 1,532
String count(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// 1 run, 2 runs
String plural(int n, String one, [String? many]) => '${count(n)} ${n == 1 ? one : many ?? '${one}s'}';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Today, Yesterday, Mon 3 Nov
String dayLabel(DateTime day, DateTime now) {
  final d = DateTime(day.year, day.month, day.day);
  final today = DateTime(now.year, now.month, now.day);
  if (d == today) return 'Today';
  if (d == DateTime(today.year, today.month, today.day - 1)) return 'Yesterday';
  return '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
}
