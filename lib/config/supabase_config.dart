import 'package:supabase_flutter/supabase_flutter.dart';

/// Las credenciales se inyectan al compilar desde el archivo `.env`
/// (ignorado por Git), por ejemplo:
///   flutter run --dart-define-from-file=.env
/// Ver `.env.example`.
class SupabaseConfig {
  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get configurado => url.isNotEmpty && publishableKey.isNotEmpty;

  static Future<void> init() async {
    if (!configurado) {
      throw StateError(
        'Faltan SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY. '
        'Copiá .env.example a .env, completalo y ejecutá con --dart-define-from-file=.env',
      );
    }
    await Supabase.initialize(url: url, publishableKey: publishableKey);
  }
}

SupabaseClient get supa => Supabase.instance.client;

/// Administrador según la sesión (app_metadata, que solo cambia el servidor).
/// Solo decide de dónde leer: el servidor vuelve a verificarlo en cada consulta.
bool get sesionEsAdmin => supa.auth.currentUser?.appMetadata['role'] == 'admin';
