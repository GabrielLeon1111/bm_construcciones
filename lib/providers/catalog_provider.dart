import 'package:flutter/foundation.dart';
import '../models/client.dart';
import '../models/product.dart';
import '../repositories/client_repository.dart';
import '../repositories/product_repository.dart';
import '../security/registro_seguro.dart';

/// Productos y clientes en memoria, para buscar rápido al vender o presupuestar.
/// Se recarga después de cada venta, compra o ajuste.
class CatalogProvider extends ChangeNotifier {
  CatalogProvider(this._products, this._clients);

  final ProductRepository _products;
  final ClientRepository _clients;

  List<Product> _productList = const [];
  List<Client> _clientList = const [];
  bool _loading = false;
  String? _error;

  List<Product> get products => _productList;

  /// Cargas que quedan de cada producto por carga (solo administrador).
  Map<String, double> _cargas = const {};
  double? cargasDe(String productId) => _cargas[productId];
  List<Product> get activeProducts => _productList.where((p) => p.active).toList();
  List<Client> get clients => _clientList;
  bool get loading => _loading;
  String? get error => _error;

  List<String> get categories {
    final set = <String>{for (final p in _productList) p.category};
    return set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  List<String> get brands {
    final set = <String>{for (final p in _productList) if (p.brand != null) p.brand!};
    return set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Product? productById(String? id) {
    if (id == null) return null;
    for (final p in _productList) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> cargarTodo() => Future.wait([cargarProductos(), cargarClientes()]);

  Future<void> cargarProductos() async {
    _loading = true;
    notifyListeners();
    try {
      _productList = await _products.list();
      _error = null;
      try {
        _cargas = await _products.cargasRestantes();
      } catch (e) {
        registrarError('cargasRestantes', e);
      }
    } catch (e) {
      registrarError('cargarProductos', e);
      _error = mensajeErrorSeguro(e, 'No se pudieron cargar los productos.');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> cargarClientes() async {
    try {
      _clientList = await _clients.list();
      notifyListeners();
    } catch (e) {
      registrarError('cargarClientes', e);
    }
  }

  void upsertClient(Client c) {
    _clientList = [..._clientList.where((x) => x.id != c.id), c]
      ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    notifyListeners();
  }

  void removeClient(String id) {
    _clientList = _clientList.where((x) => x.id != id).toList();
    notifyListeners();
  }
}

/// Búsqueda sin importar mayúsculas ni tildes: "cano" encuentra "Caño".
String normalizar(String s) {
  const a = 'áàäâãéèëêíìïîóòöôõúùüûñ';
  const b = 'aaaaaeeeeiiiiooooouuuun';
  final lower = s.toLowerCase();
  final buf = StringBuffer();
  for (final ch in lower.split('')) {
    final i = a.indexOf(ch);
    buf.write(i >= 0 ? b[i] : ch);
  }
  return buf.toString();
}

bool coincide(String texto, String busqueda) {
  final t = normalizar(texto);
  return normalizar(busqueda).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).every(t.contains);
}
