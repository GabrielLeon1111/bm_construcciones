import '../config/supabase_config.dart';
import '../models/purchase.dart';
import 'rangos.dart';

class PurchaseRepository {
  // RPC create_purchase: suma stock y recalcula el costo promedio ponderado.
  Future<Purchase> create({
    required List<PurchaseItem> items,
    String? supplier,
    String? invoiceNumber,
    String? notes,
    DateTime? purchasedOn,
    required String idempotencyKey,
  }) async {
    final dia = purchasedOn ?? DateTime.now();
    final row = await supa.rpc('create_purchase', params: {
      'p_items': items.map((i) => i.toRpc()).toList(),
      'p_supplier': supplier,
      'p_invoice_number': invoiceNumber,
      'p_notes': notes,
      'p_idempotency_key': idempotencyKey,
      'p_purchased_on': '${dia.year.toString().padLeft(4, '0')}-${dia.month.toString().padLeft(2, '0')}-${dia.day.toString().padLeft(2, '0')}',
    });
    return get((row as Map<String, dynamic>)['id'] as String);
  }

  /// Id de la compra que ya se registró con esa clave (si el servidor respondió BM409).
  Future<String?> findIdByKey(String idempotencyKey) async {
    final row = await supa.from('purchases').select('id').eq('idempotency_key', idempotencyKey).maybeSingle();
    return row?['id'] as String?;
  }

  Future<Purchase> get(String id) async {
    final row = await supa.from('purchases').select('*, purchase_items(*)').eq('id', id).single();
    return Purchase.fromMap(row);
  }

  Future<List<Purchase>> list({DateTime? from, DateTime? to, int limit = 200}) async {
    var q = supa.from('purchases').select('*, purchase_items(*)');
    if (from != null) q = q.gte('created_at', inicioDia(from));
    if (to != null) q = q.lt('created_at', finDia(to));
    final rows = await q.order('created_at', ascending: false).limit(limit);
    return rows.map(Purchase.fromMap).toList();
  }

  /// Últimas compras de un producto (cada una trae solo la línea de ese producto).
  Future<List<Purchase>> byProduct(String productId, {int limit = 15}) async {
    final rows = await supa
        .from('purchases')
        .select('*, purchase_items!inner(*)')
        .eq('purchase_items.product_id', productId)
        .order('purchased_on', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(Purchase.fromMap).toList();
  }

  /// Proveedores usados antes, para sugerirlos al cargar una compra.
  Future<List<String>> suppliers() async {
    final rows = await supa.from('purchases').select('supplier').not('supplier', 'is', null).limit(500);
    final set = <String>{for (final r in rows) (r['supplier'] as String).trim()};
    return set.toList()..sort();
  }

  Future<Purchase> voidPurchase(String id, String reason) async {
    await supa.rpc('void_purchase', params: {'p_purchase_id': id, 'p_reason': reason});
    return get(id);
  }
}
