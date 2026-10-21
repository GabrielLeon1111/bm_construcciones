import '../config/supabase_config.dart';
import '../models/gasto.dart';
import 'rangos.dart';

/// Gastos del negocio (solo el administrador). Se cargan y anulan con funciones
/// del servidor, que validan y no duplican el gasto si se toca dos veces.
class GastoRepository {
  Future<Gasto> registrar({
    required String categoria,
    required int monto,
    String? descripcion,
    String? factura,
    required DateTime fecha,
    required String idempotencyKey,
  }) async {
    final r = await supa.rpc('registrar_gasto', params: {
      'p_categoria': categoria,
      'p_monto': monto,
      'p_descripcion': descripcion,
      'p_factura': factura,
      'p_fecha': fecha.toUtc().toIso8601String(),
      'p_idempotency_key': idempotencyKey,
    });
    return Gasto.fromMap(Map<String, dynamic>.from(r as Map));
  }

  Future<Gasto> anular(String id, String motivo) async {
    final r = await supa.rpc('anular_gasto', params: {'p_id': id, 'p_motivo': motivo});
    return Gasto.fromMap(Map<String, dynamic>.from(r as Map));
  }

  /// Gastos entre dos días (ambos incluidos), del más nuevo al más viejo.
  Future<List<Gasto>> list({required DateTime from, required DateTime to, int limit = 2000}) async {
    final rows = await supa
        .from('expenses')
        .select()
        .gte('spent_at', inicioDia(from))
        .lt('spent_at', finDia(to))
        .order('spent_at', ascending: false)
        .limit(limit);
    return rows.map(Gasto.fromMap).toList();
  }
}
