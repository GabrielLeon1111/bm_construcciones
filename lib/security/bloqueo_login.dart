// =================================================================
//  BLOQUEO POR INTENTOS FALLIDOS
//  Después de 5 contraseñas incorrectas seguidas la app no deja volver a
//  intentar durante 30 minutos. Se guarda en el celular, así cerrar y abrir
//  la app no reinicia la cuenta. Al entrar bien, se reinicia.
//  (Además, el servidor de Supabase limita los intentos por conexión.)
// =================================================================
import 'package:shared_preferences/shared_preferences.dart';

class BloqueoLogin {
  static const maxIntentos = 5;
  static const duracion = Duration(minutes: 30);

  static const _kFallos = 'login_fallos';
  static const _kHasta = 'login_bloqueado_hasta';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// Hasta cuándo está bloqueado (null = se puede intentar).
  /// Si el bloqueo ya pasó, se borra y vuelve a tener los 5 intentos.
  Future<DateTime?> bloqueadoHasta() async {
    try {
      final p = await _prefs;
      final ms = p.getInt(_kHasta);
      if (ms == null) return null;
      final hasta = DateTime.fromMillisecondsSinceEpoch(ms);
      // Si el reloj se atrasó a mano (hasta queda a más de 30 min), se respeta igual el máximo.
      final tope = DateTime.now().add(duracion);
      if (hasta.isAfter(DateTime.now())) return hasta.isAfter(tope) ? tope : hasta;
      await p.remove(_kHasta);
      await p.remove(_kFallos);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Anota un intento fallido y devuelve cuántos van seguidos.
  /// Al llegar a [maxIntentos] queda bloqueado por [duracion].
  Future<int> registrarFallo() async {
    try {
      final p = await _prefs;
      final n = (p.getInt(_kFallos) ?? 0) + 1;
      await p.setInt(_kFallos, n);
      if (n >= maxIntentos) {
        await p.setInt(_kHasta, DateTime.now().add(duracion).millisecondsSinceEpoch);
      }
      return n;
    } catch (_) {
      return 1;
    }
  }

  Future<void> reiniciar() async {
    try {
      final p = await _prefs;
      await p.remove(_kFallos);
      await p.remove(_kHasta);
    } catch (_) {}
  }
}

/// Texto para un intento fallido. Desde el 2.º se avisa cuántos quedan.
String mensajeIntentoFallido(int fallos) {
  final quedan = BloqueoLogin.maxIntentos - fallos;
  if (quedan <= 0) return 'Por seguridad, la app quedó bloqueada 30 minutos por 5 intentos fallidos.';
  if (fallos < 2) return 'Usuario o contraseña incorrectos. Revisá bien los datos.';
  if (quedan == 1) return 'Usuario o contraseña incorrectos. Te queda 1 intento: si fallás otra vez, la app se bloquea 30 minutos.';
  return 'Usuario o contraseña incorrectos. Te quedan $quedan intentos.';
}
