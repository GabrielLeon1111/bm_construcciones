/// Conversores tolerantes: Postgres puede devolver numeric como número o texto.
double toDouble(Object? v) => switch (v) {
      null => 0,
      num n => n.toDouble(),
      String s => double.tryParse(s) ?? 0,
      _ => 0,
    };

int toInt(Object? v) => switch (v) {
      null => 0,
      int n => n,
      num n => n.round(),
      String s => num.tryParse(s)?.round() ?? 0,
      _ => 0,
    };

DateTime toDate(Object? v) => v == null ? DateTime.now() : DateTime.parse(v as String).toLocal();

DateTime? toDateOrNull(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

String? textOrNull(Object? v) {
  final s = (v as String?)?.trim();
  return (s == null || s.isEmpty) ? null : s;
}
