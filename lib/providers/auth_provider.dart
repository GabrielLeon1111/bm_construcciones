import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../repositories/empleado_repository.dart';
import '../repositories/settings_repository.dart';
import '../security/biometria.dart';
import '../security/bloqueo_login.dart';
import '../security/registro_seguro.dart';

enum EstadoSesion { cargando, sinSesion, noHabilitado, lista }

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._settings);

  final SettingsRepository _settings;
  StreamSubscription<AuthState>? _sub;
  EstadoSesion _estado = EstadoSesion.cargando;
  EstadoSesion get estado => _estado;

  /// 5 contraseñas incorrectas seguidas → 30 minutos sin poder intentar.
  final BloqueoLogin bloqueoLogin = BloqueoLogin();

  /// Huella / Face ID (como en La Casa del Barbero).
  final BiometriaService biometria = BiometriaService();
  bool _bloqueado = false;

  /// Hay sesión abierta pero falta la huella / Face ID para entrar.
  bool get bloqueado => _bloqueado;

  bool _recienIngreso = false;

  /// true una sola vez, justo después de entrar con email y contraseña
  /// (para ofrecer activar la huella / Face ID).
  bool consumirRecienIngreso() {
    final r = _recienIngreso;
    _recienIngreso = false;
    return r;
  }
  String? get email => supa.auth.currentUser?.email;

  /// Usuario del empleado ("juan.perez"); null si entra con email.
  String? get usuario {
    final e = email;
    return e != null && e.endsWith('@$dominioEmpleados') ? e.split('@').first : null;
  }

  // Rol y nombre según la base (app_members). Si no hay internet al abrir,
  // se usa lo que guarda la sesión (app_metadata, que solo cambia el servidor).
  String? _rolMiembro;
  String? _nombreMiembro;

  /// Nombre para el saludo ("Bienvenido Cesar").
  String? get nombre {
    if (_nombreMiembro != null) return _nombreMiembro;
    final n = supa.auth.currentUser?.userMetadata?['full_name'];
    return n is String && n.trim().isNotEmpty ? n.trim() : null;
  }

  /// Administrador: todo. Vendedor: solo Vender y Presupuesto.
  /// (El servidor controla igual cada operación: esto solo ordena las pantallas.)
  bool get esAdmin => (_rolMiembro ?? supa.auth.currentUser?.appMetadata['role']) == 'admin';

  Future<void> iniciar() async {
    _sub = supa.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) {
        _set(EstadoSesion.sinSesion);
      }
    });
    if (supa.auth.currentSession == null) {
      _set(EstadoSesion.sinSesion);
    } else {
      // Con la huella activada, se pide antes de mostrar los datos.
      _bloqueado = await biometria.activada();
      await _verificarMiembro();
      notifyListeners();
    }
  }

  /// Cuándo se mandó la app al fondo (para no pedir la huella por salir un segundo).
  DateTime? _enFondoDesde;

  /// La app pasó al fondo: se anota la hora.
  void marcarEnFondo() => _enFondoDesde ??= DateTime.now();

  /// Volvió a la app: con la huella activada, se bloquea solo si estuvo en el fondo
  /// más de un minuto (compartir un comprobante o la propia ventana de la huella
  /// no cuentan).
  Future<void> bloquearSiCorresponde() async {
    final desde = _enFondoDesde;
    _enFondoDesde = null;
    if (desde == null || DateTime.now().difference(desde) < const Duration(minutes: 1)) return;
    if (_estado != EstadoSesion.lista || _bloqueado) return;
    if (await biometria.activada()) {
      _bloqueado = true;
      notifyListeners();
    }
  }

  void desbloquear() {
    if (!_bloqueado) return;
    _bloqueado = false;
    notifyListeners();
  }

  Future<void> _verificarMiembro() async {
    try {
      final ok = await _settings.isMember();
      if (ok) await _cargarMiembro();
      _set(ok ? EstadoSesion.lista : EstadoSesion.noHabilitado);
    } catch (e) {
      registrarError('verificarMiembro', e);
      // Sin internet al abrir: se deja pasar; cada operación vuelve a validar en el servidor.
      _set(EstadoSesion.lista);
    }
  }

  Future<void> _cargarMiembro() async {
    try {
      final uid = supa.auth.currentUser?.id;
      if (uid == null) return;
      final row = await supa.from('app_members').select('role, full_name').eq('user_id', uid).maybeSingle();
      _rolMiembro = row?['role'] as String?;
      _nombreMiembro = (row?['full_name'] as String?)?.trim();
    } catch (e) {
      registrarError('cargarMiembro', e);
    }
  }

  /// Devuelve null si entró bien, o el mensaje para mostrar.
  /// [email] puede ser el email o el usuario del empleado ("juan.perez").
  Future<String?> ingresar(String email, String password) async {
    // Bloqueada por intentos fallidos: ni se consulta al servidor.
    if (await bloqueoLogin.bloqueadoHasta() != null) {
      return mensajeIntentoFallido(BloqueoLogin.maxIntentos);
    }
    try {
      await supa.auth.signInWithPassword(email: emailDeUsuario(email), password: password);
      await bloqueoLogin.reiniciar();
      _bloqueado = false;
      await _verificarMiembro();
      if (_estado == EstadoSesion.noHabilitado) {
        await supa.auth.signOut();
        _set(EstadoSesion.sinSesion);
        return 'Tu usuario todavía no está habilitado para usar la app. Pedile acceso al administrador.';
      }
      _recienIngreso = true;
      // Siempre se avisa a la pantalla: si ya había sesión (entró con contraseña
      // desde la pantalla de la huella), el estado no cambia y no se movía de ahí.
      notifyListeners();
      return null;
    } catch (e) {
      registrarError('ingresar', e);
      // Solo cuenta como intento fallido la contraseña o el email incorrecto
      // (no la falta de internet).
      if (esCredencialIncorrecta(e)) {
        return mensajeIntentoFallido(await bloqueoLogin.registrarFallo());
      }
      return mensajeErrorSeguro(e, 'No se pudo iniciar sesión. Intentá de nuevo.');
    }
  }

  Future<void> salir() async {
    try {
      await supa.auth.signOut();
    } catch (e) {
      registrarError('salir', e);
    }
    _bloqueado = false;
    _rolMiembro = null;
    _nombreMiembro = null;
    _set(EstadoSesion.sinSesion);
  }

  void _set(EstadoSesion e) {
    if (_estado == e) return;
    _estado = e;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
