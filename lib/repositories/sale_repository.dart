import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../config/supabase_config.dart';
import '../models/doc_line.dart';
import '../models/sale.dart';
import 'rangos.dart';

class SaleRepository {
  // Costos (cost_total, returned_cost y unit_cost de cada línea): solo el administrador,
  // con la función ventas_admin. El vendedor lee estas columnas.
  static const _columnasVendedor = 'id, number, client_id, client_name, client_phone, client_document, client_address, '
      'payment_method, subtotal, discount, total, notes, quote_id, status, void_reason, voided_at, created_by, created_at, '
      'returned_amount, paid_cash, paid_transfer, cash_received, change_amount, seller_name, '
      'sale_items(id, sale_id, position, product_id, description, unit, quantity, unit_price, is_gift, line_total, load_id, returned_qty, price_is_total, line_discount, discount_pct)';

  Future<List<Sale>> _admin({DateTime? from, DateTime? to, String? clientId, String? id, int limit = 300}) async {
    final r = await supa.rpc('ventas_admin', params: {
      'p_from': from == null ? null : inicioDia(from),
      'p_to': to == null ? null : finDia(to),
      'p_client': clientId,
      'p_id': id,
      'p_limit': limit,
    });
    return ((r as List?) ?? const []).map((e) => Sale.fromMap(Map<String, dynamic>.from(e as Map))).toList();
  }

  // RPC create_sale: descuenta stock, guarda la venta y sus líneas en una sola operación.
  // La idempotencyKey evita duplicar la venta si se toca dos veces o se corta internet.
  Future<Sale> create({
    required List<DocLine> lines,
    required String paymentMethod,
    String? clientId,
    int discount = 0,
    String? notes,
    String? quoteId,
    required String idempotencyKey,
    int? paidCash,
    int? paidTransfer,
    int? cashReceived,
  }) async {
    final row = await supa.rpc('create_sale', params: {
      'p_items': lines.map((l) => l.toRpc()).toList(),
      'p_payment_method': paymentMethod,
      'p_client_id': clientId,
      'p_discount': discount,
      'p_notes': notes,
      'p_quote_id': quoteId,
      'p_idempotency_key': idempotencyKey,
      // Mixto: las dos partes. Efectivo: con cuánto pagó (para el vuelto).
      'p_paid_cash': paidCash,
      'p_paid_transfer': paidTransfer,
      'p_cash_received': cashReceived,
    });
    return get((row as Map<String, dynamic>)['id'] as String);
  }

  /// La venta que ya se registró con esa clave (si el servidor respondió BM409).
  Future<Sale?> findByKey(String idempotencyKey) async {
    final row = await supa.from('sales').select('id').eq('idempotency_key', idempotencyKey).maybeSingle();
    return row == null ? null : get(row['id'] as String);
  }

  Future<Sale> get(String id) async {
    if (sesionEsAdmin) {
      final r = await _admin(id: id, limit: 1);
      if (r.isEmpty) throw const PostgrestException(message: 'La venta no existe.', code: 'P0001');
      return r.first;
    }
    final row = await supa.from('sales').select(_columnasVendedor).eq('id', id).single();
    return Sale.fromMap(row);
  }

  Future<List<Sale>> list({DateTime? from, DateTime? to, int limit = 200}) async {
    if (sesionEsAdmin) return _admin(from: from, to: to, limit: limit);
    var q = supa.from('sales').select(_columnasVendedor);
    if (from != null) q = q.gte('created_at', inicioDia(from));
    if (to != null) q = q.lt('created_at', finDia(to));
    final rows = await q.order('created_at', ascending: false).limit(limit);
    return rows.map(Sale.fromMap).toList();
  }

  /// Todo lo que compró un cliente (con costos: solo el administrador).
  Future<List<Sale>> byClient(String clientId) => _admin(clientId: clientId, limit: 1000);

  // RPC return_sale: devolución parcial. El material vuelve al stock y ese monto
  // deja de contar en ventas y ganancias. [cantidades]: id de línea → cantidad devuelta.
  Future<Sale> returnItems(String saleId, Map<String, double> cantidades, String reason, {required String idempotencyKey}) async {
    await supa.rpc('return_sale', params: {
      'p_sale_id': saleId,
      'p_items': [
        for (final e in cantidades.entries)
          if (e.value > 0) {'sale_item_id': e.key, 'quantity': e.value},
      ],
      'p_reason': reason,
      'p_idempotency_key': idempotencyKey,
    });
    return get(saleId);
  }

  // RPC set_sale_client: "Asociar cliente" a una venta ya hecha.
  Future<void> setClient(String saleId, String? clientId) =>
      supa.rpc('set_sale_client', params: {'p_sale_id': saleId, 'p_client_id': clientId});

  // RPC void_sale: devuelve el stock y marca la venta como anulada (queda en el historial).
  Future<Sale> voidSale(String id, String reason) async {
    await supa.rpc('void_sale', params: {'p_sale_id': id, 'p_reason': reason});
    return get(id);
  }
}
