// =================================================================
//  HUELLA / FACE ID
//  Igual que en La Casa del Barbero: la biometría NO guarda la contraseña,
//  solo desbloquea la sesión que ya está abierta en este celular.
//  Si está activada, se pide al abrir la app y al volver a ella.
// =================================================================
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class BiometriaService {
  static const _clave = 'biometria_activada';

  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// El celular tiene huella o Face ID configurada (en la web o la PC, no).
  Future<bool> disponible() async {
    try {
      return await _auth.canCheckBiometrics && await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> activada() async {
    try {
      return await _storage.read(key: _clave) == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> activar(bool valor) => _storage.write(key: _clave, value: valor.toString());

  /// Pide la huella / Face ID. Devuelve true si la persona se identificó.
  Future<bool> verificar() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Desbloqueá BM. Construcciones',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
