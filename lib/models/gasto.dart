import 'package:flutter/material.dart';

import 'json.dart';

/// Categorías de gasto (las mismas que acepta el servidor en categorias_gasto()).
const categoriasGasto = <(String, IconData)>[
  ('Alquiler', Icons.home_work_outlined),
  ('Sueldos', Icons.badge_outlined),
  ('Pago a empleados', Icons.groups_outlined),
  ('Flete', Icons.local_shipping_outlined),
  ('Luz (ANDE)', Icons.bolt_outlined),
  ('Agua', Icons.water_drop_outlined),
  ('Internet y teléfono', Icons.wifi_outlined),
  ('Combustible', Icons.local_gas_station_outlined),
  ('Repuestos y reparaciones', Icons.build_outlined),
  ('Mantenimiento del local', Icons.handyman_outlined),
  ('Impuestos', Icons.account_balance_outlined),
  ('Limpieza', Icons.cleaning_services_outlined),
  ('Útiles de oficina', Icons.edit_note_outlined),
  ('Publicidad', Icons.campaign_outlined),
  ('Comida y bebida', Icons.restaurant_outlined),
  ('Otros', Icons.more_horiz_rounded),
];

IconData iconoGasto(String categoria) =>
    categoriasGasto.firstWhere((c) => c.$1 == categoria, orElse: () => categoriasGasto.last).$2;

class Gasto {
  final String id;
  final int number;
  final String category;
  final int amount;
  final String? description;
  final String? invoiceNumber;
  /// Día y hora en que se hizo el gasto.
  final DateTime spentAt;
  final String status;
  final String? voidReason;
  final DateTime? voidedAt;
  final String? createdByName;
  final DateTime createdAt;

  const Gasto({
    required this.id,
    required this.number,
    required this.category,
    required this.amount,
    this.description,
    this.invoiceNumber,
    required this.spentAt,
    this.status = 'activo',
    this.voidReason,
    this.voidedAt,
    this.createdByName,
    required this.createdAt,
  });

  bool get anulado => status == 'anulado';

  factory Gasto.fromMap(Map<String, dynamic> m) => Gasto(
        id: m['id'] as String,
        number: toInt(m['number']),
        category: (m['category'] ?? 'Otros') as String,
        amount: toInt(m['amount']),
        description: textOrNull(m['description']),
        invoiceNumber: textOrNull(m['invoice_number']),
        spentAt: toDate(m['spent_at']),
        status: (m['status'] ?? 'activo') as String,
        voidReason: textOrNull(m['void_reason']),
        voidedAt: toDateOrNull(m['voided_at']),
        createdByName: textOrNull(m['created_by_name']),
        createdAt: toDate(m['created_at']),
      );
}

/// Total de gastos de un período y cuánto fue en cada categoría.
class GastosResumen {
  final int total;
  final int count;
  final List<({String category, int amount, int count})> porCategoria;

  const GastosResumen({this.total = 0, this.count = 0, this.porCategoria = const []});

  static const vacio = GastosResumen();

  factory GastosResumen.fromMap(Object? m) {
    final map = (m as Map?) ?? const {};
    return GastosResumen(
      total: toInt(map['total']),
      count: toInt(map['count']),
      porCategoria: [
        for (final e in ((map['by_category'] as List?) ?? const []).cast<Map>())
          (category: (e['category'] ?? 'Otros') as String, amount: toInt(e['amount']), count: toInt(e['count'])),
      ],
    );
  }

  /// Resumen calculado de una lista (los anulados no suman).
  factory GastosResumen.deLista(Iterable<Gasto> gastos) {
    final activos = gastos.where((g) => !g.anulado).toList();
    final porCat = <String, (int, int)>{};
    for (final g in activos) {
      final a = porCat[g.category] ?? (0, 0);
      porCat[g.category] = (a.$1 + g.amount, a.$2 + 1);
    }
    final lista = [for (final e in porCat.entries) (category: e.key, amount: e.value.$1, count: e.value.$2)]
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return GastosResumen(total: activos.fold(0, (s, g) => s + g.amount), count: activos.length, porCategoria: lista);
  }
}
