/// Límites de un día local convertidos a UTC para filtrar created_at.
String inicioDia(DateTime d) => DateTime(d.year, d.month, d.day).toUtc().toIso8601String();
String finDia(DateTime d) => DateTime(d.year, d.month, d.day + 1).toUtc().toIso8601String();

/// Fecha (sin hora) en formato de Postgres: 2026-10-18
String fechaSql(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
