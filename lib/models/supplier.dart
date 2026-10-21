import 'json.dart';

/// Proveedor guardado para reutilizar en las compras.
class Supplier {
  final String id;
  final String name;
  final String? phone;
  final String? ruc;

  const Supplier({required this.id, required this.name, this.phone, this.ruc});

  factory Supplier.fromMap(Map<String, dynamic> m) => Supplier(
        id: m['id'] as String,
        name: m['name'] as String,
        phone: textOrNull(m['phone']),
        ruc: textOrNull(m['ruc']),
      );

  String get detalle => [if (ruc != null) 'RUC $ruc', ?phone].join(' · ');
}
