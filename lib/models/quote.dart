import 'client.dart';
import 'doc_line.dart';
import 'json.dart';

class Quote {
  final String id;
  final int number;
  final String? clientId;
  final String? clientName;
  final Client? client;
  final String status;
  final int subtotal;
  final int discount;
  final int total;
  final String? notes;
  final DateTime? validUntil;
  final String? saleId;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<DocLine> items;

  /// Nombre y apellido de quien hizo el presupuesto (lo pone el servidor).
  final String? sellerName;

  const Quote({
    required this.id,
    required this.number,
    this.clientId,
    this.clientName,
    this.client,
    required this.status,
    required this.subtotal,
    required this.discount,
    required this.total,
    this.notes,
    this.validUntil,
    this.saleId,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
    this.sellerName,
  });

  factory Quote.fromMap(Map<String, dynamic> m) {
    final version = toInt(m['version']);
    // Solo las líneas de la versión vigente (las anteriores son historial de ediciones).
    final rawItems = ((m['quote_items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .where((i) => i['version'] == null || toInt(i['version']) == version)
        .toList()
      ..sort((a, b) => toInt(a['position']).compareTo(toInt(b['position'])));
    final c = m['clients'];
    return Quote(
      id: m['id'] as String,
      number: toInt(m['number']),
      clientId: m['client_id'] as String?,
      clientName: textOrNull(m['client_name']),
      client: c is Map<String, dynamic> ? Client.fromMap(c) : null,
      status: m['status'] as String,
      subtotal: toInt(m['subtotal']),
      discount: toInt(m['discount']),
      total: toInt(m['total']),
      notes: textOrNull(m['notes']),
      validUntil: m['valid_until'] == null ? null : DateTime.parse(m['valid_until'] as String),
      saleId: m['sale_id'] as String?,
      version: version,
      createdAt: toDate(m['created_at']),
      updatedAt: toDate(m['updated_at']),
      items: rawItems.map(DocLine.fromMap).toList(),
      sellerName: textOrNull(m['seller_name']),
    );
  }

  bool get isPending => status == 'pendiente';
  bool get isExpired {
    if (validUntil == null || !isPending) return false;
    final hoy = DateTime.now();
    return DateTime(hoy.year, hoy.month, hoy.day).isAfter(validUntil!);
  }

  String get displayClient => client?.fullName ?? clientName ?? 'Sin nombre';
}
