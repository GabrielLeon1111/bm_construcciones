import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../config/supabase_config.dart';
import 'sale_repository.dart';
import '../models/client.dart';
import '../models/quote.dart';
import '../models/sale.dart';

class ClientRepository {
  Future<List<Client>> list() async {
    final rows = await supa.from('clients').select().order('full_name');
    return rows.map(Client.fromMap).toList();
  }

  // El id lo genera el formulario al abrirse: un doble toque o un reintento
  // choca con la clave primaria y devuelve el cliente ya creado.
  Future<Client> create(String id, Client data) async {
    try {
      final row = await supa.from('clients').insert({'id': id, ...data.toEditable()}).select().single();
      return Client.fromMap(row);
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
      final row = await supa.from('clients').select().eq('id', id).single();
      return Client.fromMap(row);
    }
  }

  Future<Client> update(String id, Client data) async {
    final row = await supa.from('clients').update(data.toEditable()).eq('id', id).select().single();
    return Client.fromMap(row);
  }

  Future<void> delete(String id) => supa.from('clients').delete().eq('id', id);

  /// Todo lo que compró y lo que se le presupuestó.
  Future<(List<Sale>, List<Quote>)> history(String clientId) async {
    final sales = await SaleRepository().byClient(clientId);
    final quotes = await supa
        .from('quotes')
        .select('*, quote_items(*)')
        .eq('client_id', clientId)
        .order('created_at', ascending: false);
    return (sales, quotes.map(Quote.fromMap).toList());
  }
}
