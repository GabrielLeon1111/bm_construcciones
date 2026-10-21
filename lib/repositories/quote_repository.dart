import '../config/supabase_config.dart';
import '../models/doc_line.dart';
import '../models/quote.dart';
import 'rangos.dart';

class QuoteRepository {
  static const _select = '*, quote_items(*), clients(*)';

  // RPC save_quote: crea o edita (al editar se guarda una versión nueva de las líneas).
  // La clave se exige también al editar, así un reintento no crea otra versión.
  Future<Quote> save({
    String? quoteId,
    required List<DocLine> lines,
    String? clientId,
    int discount = 0,
    String? notes,
    DateTime? validUntil,
    required String idempotencyKey,
  }) async {
    final row = await supa.rpc('save_quote', params: {
      'p_items': lines.map((l) => l.toRpc()).toList(),
      'p_quote_id': quoteId,
      'p_client_id': clientId,
      'p_discount': discount,
      'p_notes': notes,
      'p_valid_until': validUntil == null ? null : fechaSql(validUntil),
      'p_idempotency_key': idempotencyKey,
    });
    return get((row as Map<String, dynamic>)['id'] as String);
  }

  /// Id del presupuesto nuevo que ya se guardó con esa clave (si el servidor respondió BM409).
  Future<String?> findIdByKey(String idempotencyKey) async {
    final row = await supa.from('quotes').select('id').eq('idempotency_key', idempotencyKey).maybeSingle();
    return row?['id'] as String?;
  }

  Future<Quote> get(String id) async {
    final row = await supa.from('quotes').select(_select).eq('id', id).single();
    return Quote.fromMap(row);
  }

  Future<List<Quote>> list({String? status, int limit = 200}) async {
    var q = supa.from('quotes').select(_select);
    if (status != null) q = q.eq('status', status);
    final rows = await q.order('created_at', ascending: false).limit(limit);
    return rows.map(Quote.fromMap).toList();
  }

  Future<void> cancel(String id) => supa.rpc('cancel_quote', params: {'p_quote_id': id});
}
