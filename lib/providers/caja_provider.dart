import 'package:flutter/foundation.dart';
import '../models/caja.dart';
import '../repositories/caja_repository.dart';
import '../security/registro_seguro.dart';

enum EstadoCaja { cargando, abierta, cerrada, desconocido }

/// La caja del negocio, compartida por toda la app. Vive en el servidor: si se
/// sale de la app o se cierra la pestaña, al volver se recupera la misma caja
/// abierta. Solo se cierra cuando alguien toca "Cerrar caja".
class CajaProvider extends ChangeNotifier {
  CajaProvider(this._repo);
  final CajaRepository _repo;

  EstadoCaja _estado = EstadoCaja.cargando;
  Caja? _caja;

  EstadoCaja get estado => _estado;

  /// La caja abierta (con lo vendido hasta la última consulta), o null.
  Caja? get caja => _caja;

  /// Sin caja abierta no se cobra. Si no se pudo consultar (sin señal), no se
  /// traba la venta: el servidor igual lo controla al registrarla.
  bool get bloqueaVentas => _estado == EstadoCaja.cerrada;

  Future<void> cargar() async {
    try {
      _caja = await _repo.abierta();
      _estado = _caja == null ? EstadoCaja.cerrada : EstadoCaja.abierta;
    } catch (e) {
      registrarError('estadoCaja', e);
      if (_estado == EstadoCaja.cargando) _estado = EstadoCaja.desconocido;
    }
    notifyListeners();
  }

  /// Después de abrir, cerrar o retirar.
  void actualizar(Caja? c) {
    _caja = c != null && c.abierta ? c : null;
    _estado = _caja == null ? EstadoCaja.cerrada : EstadoCaja.abierta;
    notifyListeners();
  }

  void limpiar() {
    _caja = null;
    _estado = EstadoCaja.cargando;
    notifyListeners();
  }
}
