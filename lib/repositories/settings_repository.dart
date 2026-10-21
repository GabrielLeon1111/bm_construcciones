import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/business_settings.dart';

class SettingsRepository {
  Future<BusinessSettings> get() async {
    final row = await supa.from('business_settings').select().eq('id', 1).maybeSingle();
    return row == null ? const BusinessSettings() : BusinessSettings.fromMap(row);
  }

  Future<BusinessSettings> update(BusinessSettings s) async {
    final row = await supa.from('business_settings').update(s.toEditable()).eq('id', 1).select().single();
    return BusinessSettings.fromMap(row);
  }

  // Sube el logo al bucket público "business" y devuelve su URL.
  // Se usa un nombre nuevo cada vez para que no quede la versión vieja en caché.
  Future<String> uploadLogo(Uint8List bytes, String extension) async {
    final ext = extension.toLowerCase().replaceAll('jpg', 'jpeg');
    final path = 'logo_${DateTime.now().millisecondsSinceEpoch}.${ext == 'jpeg' ? 'jpg' : ext}';
    await supa.storage.from('business').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: 'image/$ext', upsert: true),
        );
    return supa.storage.from('business').getPublicUrl(path);
  }

  Future<bool> isMember() async => (await supa.rpc('is_member')) as bool? ?? false;

  Future<bool> licenseOk() async => (await supa.rpc('license_ok')) as bool? ?? true;
}
