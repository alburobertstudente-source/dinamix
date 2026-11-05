String _two(int v) => v.toString().padLeft(2, '0');

String formatDateTime(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_two(t.day)}/${_two(t.month)}/${t.year} ${_two(t.hour)}:${_two(t.minute)}';
}

String formatTime(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
}

String formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  return hours > 0
      ? '$hours:${_two(minutes)}:${_two(seconds)}'
      : '${_two(minutes)}:${_two(seconds)}';
}

String formatRelative(int ms) {
  final diff = DateTime.now().millisecondsSinceEpoch - ms;
  if (diff < 60000) return 'pochi secondi fa';
  if (diff < 3600000) return '${diff ~/ 60000} min fa';
  if (diff < 86400000) return '${diff ~/ 3600000} h fa';
  return formatDateTime(ms);
}

String formatCount(int value) {
  final digits = value.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return out.toString();
}
