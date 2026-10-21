import 'package:flutter/foundation.dart';

/// Aviso global de "cambiaron los datos" (venta, compra, ajuste, anulación).
/// Las pantallas con listas lo escuchan y se recargan solas.
class RefreshBus extends ChangeNotifier {
  int _version = 0;
  int get version => _version;

  void changed() {
    _version++;
    notifyListeners();
  }
}
