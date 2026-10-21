import '../config/supabase_config.dart';
import '../models/stock_movement.dart';
import 'rangos.dart';

class MovementRepository {
  Future<List<StockMovement>> list({String? type, DateTime? from, DateTime? to, int limit = 300}) async {
    var q = supa.from('stock_movements').select('*, products(name, unit, sale_price)');
    if (type == 'averia') {
      q = q.eq('movement_subtype', 'averia');
    } else if (type == 'ajuste') {
      q = q.eq('movement_type', 'ajuste').isFilter('movement_subtype', null);
    } else if (type != null) {
      q = q.eq('movement_type', type);
    }
    if (from != null) q = q.gte('created_at', inicioDia(from));
    if (to != null) q = q.lt('created_at', finDia(to));
    final rows = await q.order('created_at', ascending: false).limit(limit);
    // "Promedio actual" de cada producto (solo el administrador lo puede leer).
    final costos = {
      for (final p in await supa.rpc<List<Map<String, dynamic>>>('productos_admin').select('id, avg_cost')) p['id']: p['avg_cost'],
    };
    return rows.map((m) {
      final prod = m['products'];
      if (prod is Map<String, dynamic>) prod['avg_cost'] = costos[m['product_id']];
      return StockMovement.fromMap(m);
    }).toList();
  }
}
