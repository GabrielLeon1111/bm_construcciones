import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException, PostgrestFilterBuilder;
import '../config/supabase_config.dart';
import '../models/json.dart';
import '../models/load_status.dart';
import '../models/product.dart';
import '../models/stock_movement.dart';

class ProductRepository {
  // El costo promedio (avg_cost) solo lo puede leer el administrador: el vendedor
  // lee estas columnas y el administrador usa la función productos_admin.
  static const _columnas = 'id, name, category, brand, unit, stock, sale_price, min_stock, active, notes, created_at, updated_at, sold_by_load';

  PostgrestFilterBuilder<List<Map<String, dynamic>>> _consulta() => sesionEsAdmin
      ? supa.rpc<List<Map<String, dynamic>>>('productos_admin')
      : supa.from('products').select(_columnas);

  // Todos los productos, ordenados por nombre.
  Future<List<Product>> list({bool includeInactive = true}) async {
    var q = _consulta();
    if (!includeInactive) q = q.eq('active', true);
    final rows = await q.order('name');
    return rows.map(Product.fromMap).toList();
  }

  Future<Product> get(String id) async {
    final row = await _consulta().eq('id', id).single();
    return Product.fromMap(row);
  }

  // INSERT products: alta con stock 0 (lo que ya compró entra después como compra).
  // El id lo genera la pantalla al abrirse: si se toca dos veces o se reintenta,
  // el segundo insert choca con la clave primaria y se devuelve el ya creado.
  Future<Product> create(String id, Product data) async {
    try {
      await supa.from('products').insert({'id': id, ...data.toEditable()});
      return await get(id);
    } on PostgrestException catch (e) {
      // Mismo nombre que otro producto: no es un reintento, es un duplicado.
      if (e.code != '23505' || e.message.contains('products_name_unique')) rethrow;
      return get(id);
    }
  }

  Future<Product> update(String id, Product data) async {
    await supa.from('products').update(data.toEditable()).eq('id', id);
    return get(id);
  }

  Future<void> setActive(String id, bool active) => supa.from('products').update({'active': active}).eq('id', id);

  // DELETE: falla con 23503 si ya tiene movimientos (se sugiere desactivar).
  Future<void> delete(String id) => supa.from('products').delete().eq('id', id);

  // RPC load_status: la carga abierta (pagado, vendido) y las últimas cerradas.
  Future<LoadStatus> loadStatus(String productId) async {
    final r = await supa.rpc('load_status', params: {'p_product_id': productId});
    return LoadStatus.fromMap(r as Map<String, dynamic>);
  }

  // RPC close_load: "Se terminó la carga". Reparte el costo real entre sus ventas.
  // Repetible: si ya estaba cerrada no hace nada.
  Future<void> closeLoad(String productId) => supa.rpc('close_load', params: {'p_product_id': productId});

  // RPC register_damage: descuenta mercadería averiada (rota, mojada, vencida).
  // Queda en el historial como "Averiado" con lo que costó, para saber cuánto se perdió.
  Future<void> registerDamage(String id, double quantity, String reason, {required String idempotencyKey}) =>
      supa.rpc('register_damage', params: {
        'p_product_id': id,
        'p_quantity': quantity,
        'p_reason': reason,
        'p_idempotency_key': idempotencyKey,
      });

  // RPC adjust_stock: fija el stock a un valor (recuento, rotura, stock inicial).
  // Con la misma clave, un reintento devuelve el ajuste ya hecho.
  Future<void> adjustStock(String id, double newStock, String reason, {int? unitCost, required String idempotencyKey}) =>
      supa.rpc('adjust_stock', params: {
        'p_product_id': id,
        'p_new_stock': newStock,
        'p_reason': reason,
        'p_unit_cost': unitCost,
        'p_idempotency_key': idempotencyKey,
      });

  /// Cuántas cargas quedan de cada producto por carga (arena, piedra bruta):
  /// lo comprado en la carga abierta menos lo vendido de ella (sin anuladas y
  /// descontando devoluciones). Solo el administrador (lee las compras).
  Future<Map<String, double>> cargasRestantes() async {
    if (!sesionEsAdmin) return {};
    final cargas = await supa.from('product_loads').select('id, product_id').eq('status', 'abierta');
    if (cargas.isEmpty) return {};
    final productoDe = {for (final c in cargas) c['id'] as String: c['product_id'] as String};
    final ids = productoDe.keys.toList();
    final compras = await supa
        .from('purchase_items')
        .select('load_id, quantity, purchases!inner(status)')
        .inFilter('load_id', ids)
        .eq('purchases.status', 'activa');
    final ventas = await supa
        .from('sale_items')
        .select('load_id, quantity, returned_qty, sales!inner(status)')
        .inFilter('load_id', ids)
        .eq('sales.status', 'activa');
    final quedan = <String, double>{for (final p in productoDe.values) p: 0};
    for (final c in compras) {
      final p = productoDe[c['load_id']]!;
      quedan[p] = quedan[p]! + toDouble(c['quantity']);
    }
    for (final v in ventas) {
      final p = productoDe[v['load_id']]!;
      quedan[p] = quedan[p]! - (toDouble(v['quantity']) - toDouble(v['returned_qty']));
    }
    // 1/3 se guarda como 0,333: tres tercios dan 0,999 → se redondea para que quede 0.
    return quedan.map((k, v) => MapEntry(k, v.abs() < 0.01 ? 0.0 : double.parse(v.toStringAsFixed(3))));
  }

  Future<List<StockMovement>> movements(String productId, {int limit = 100}) async {
    final rows = await supa
        .from('stock_movements')
        .select()
        .eq('product_id', productId)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(StockMovement.fromMap).toList();
  }
}
