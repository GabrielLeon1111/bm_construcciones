import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../config/supabase_config.dart';
import '../models/supplier.dart';

class SupplierRepository {
  Future<List<Supplier>> list() async {
    final rows = await supa.from('suppliers').select().order('name');
    return rows.map(Supplier.fromMap).toList();
  }

  // El nombre es único (sin importar mayúsculas): si ya existe, se devuelve ese.
  // El id lo genera la pantalla, así un doble toque no lo duplica.
  Future<Supplier> create(String id, {required String name, String? phone, String? ruc}) async {
    try {
      final row = await supa.from('suppliers').insert({'id': id, 'name': name, 'phone': phone, 'ruc': ruc}).select().single();
      return Supplier.fromMap(row);
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
      // Comparación exacta sin mayúsculas: se escapan los comodines de ILIKE.
      final patron = name.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
      final row = await supa.from('suppliers').select().ilike('name', patron).limit(1).single();
      return Supplier.fromMap(row);
    }
  }
}
