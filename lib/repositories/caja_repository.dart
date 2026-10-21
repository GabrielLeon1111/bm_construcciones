import '../config/supabase_config.dart';
import '../models/caja.dart';

/// Caja: todo pasa por funciones del servidor (abrir_caja, resumen_caja, cerrar_caja),
/// que validan los montos y no duplican la operación si se toca dos veces.
class CajaRepository {
  /// La caja abierta con lo vendido hasta ahora, o null si no hay ninguna abierta.
  Future<Caja?> abierta() async {
    final r = await supa.rpc('resumen_caja');
    return r == null ? null : Caja.fromMap(Map<String, dynamic>.from(r as Map));
  }

  Future<Caja> abrir(int monto, {required String idempotencyKey}) async {
    final r = await supa.rpc('abrir_caja', params: {'p_monto': monto, 'p_idempotency_key': idempotencyKey});
    return Caja.fromMap(Map<String, dynamic>.from(r as Map));
  }

  /// Cierra con el conteo de cada billete y moneda. El servidor calcula efectivo,
  /// transferencias, lo esperado y si sobra o falta.
  Future<Caja> cerrar(String cajaId, Map<int, int> conteo, {required String idempotencyKey}) async {
    final r = await supa.rpc('cerrar_caja', params: {
      'p_caja': cajaId,
      'p_conteo': {for (final e in conteo.entries) '${e.key}': e.value},
      'p_idempotency_key': idempotencyKey,
    });
    return Caja.fromMap(Map<String, dynamic>.from(r as Map));
  }

  /// Retiro de dinero (efectivo o transferencia). El servidor valida los topes.
  Future<RetiroCaja> retirar(
    String cajaId,
    int monto, {
    required String metodo,
    required String recibe,
    String? descripcion,
    required String idempotencyKey,
  }) async {
    final r = await supa.rpc('retirar_caja', params: {
      'p_caja': cajaId,
      'p_monto': monto,
      'p_metodo': metodo,
      'p_recibe': recibe,
      'p_descripcion': descripcion,
      'p_idempotency_key': idempotencyKey,
    });
    return RetiroCaja.fromMap(Map<String, dynamic>.from(r as Map));
  }

  Future<Caja> get(String id) async {
    final r = await supa.rpc('caja', params: {'p_id': id});
    return Caja.fromMap(Map<String, dynamic>.from(r as Map));
  }

  /// Aperturas y cierres (solo el administrador).
  Future<List<Caja>> list({int limit = 200}) async {
    final rows = await supa.from('cash_sessions').select('*, cash_withdrawals(*)').order('opened_at', ascending: false).limit(limit);
    return rows.map(Caja.fromMap).toList();
  }
}
