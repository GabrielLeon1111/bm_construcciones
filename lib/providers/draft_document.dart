import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/client.dart';
import '../models/doc_line.dart';
import '../models/product.dart';
import '../models/quote.dart';

const _uuid = Uuid();

/// Borrador de una venta o presupuesto: líneas, cliente, descuento y notas.
/// La venta en curso vive en un único DraftDocument global, así no se pierde
/// al cambiar de pestaña.
///
/// Con [storageKey] (la venta), todo se guarda en el celular a cada cambio:
/// si se corta la señal, se cierra la app o el celular recarga la página,
/// la venta vuelve tal cual (materiales, cliente, pago y la MISMA clave, así
/// al reintentar no se registra dos veces).
class DraftDocument extends ChangeNotifier {
  DraftDocument({this.storageKey});

  final String? storageKey;
  final List<DocLine> _lines = [];

  /// Se tocó "Cobrar" y no llegó la respuesta (sin señal): no se sabe si entró.
  /// Al volver se consulta al servidor con la clave antes de cobrar de nuevo.
  bool _cobroPendiente = false;
  bool get cobroPendiente => _cobroPendiente;

  /// Lo escrito en el pago (con cuánto paga, efectivo / transferencia del mixto).
  Map<String, String> _pagoCampos = {};
  Map<String, String> get pagoCampos => Map.unmodifiable(_pagoCampos);
  Client? _client;
  int _discount = 0;
  /// Observaciones (se guardan en el celular al escribir).
  String _notes = '';
  String get notes => _notes;
  set notes(String v) {
    _notes = v;
    _guardar();
  }
  String _paymentMethod = 'efectivo';
  String? _quoteId;
  int? _quoteNumber;
  DateTime? _validUntil;

  /// Clave de la operación: la misma venta o presupuesto no se registra dos veces
  /// (doble toque, reintento tras un corte de internet). Dura todo el borrador:
  /// NO cambia al editar líneas, porque si la venta ya se guardó y la respuesta
  /// se perdió, una clave nueva la duplicaría. Si se reintenta con otros datos,
  /// el servidor lo rechaza (BM409). Solo se renueva al empezar otro borrador.
  String _idempotencyKey = _uuid.v4();

  List<DocLine> get lines => List.unmodifiable(_lines);
  Client? get client => _client;
  int get discount => _discount;
  String get paymentMethod => _paymentMethod;
  String? get quoteId => _quoteId;
  int? get quoteNumber => _quoteNumber;
  DateTime? get validUntil => _validUntil;
  String get idempotencyKey => _idempotencyKey;

  bool get isEmpty => _lines.isEmpty;
  int get itemCount => _lines.length;
  int get subtotal => _lines.fold(0, (a, l) => a + l.lineTotal);
  // Sin `1 << 62`: en la versión web los enteros son de 32 bits para esa cuenta y daba 0.
  int get total => subtotal - _discount < 0 ? 0 : subtotal - _discount;
  bool get hasStockProblems => _lines.any((l) => l.exceedsStock);

  /// Cantidad de un producto ya cargada (sumando líneas), para validar stock.
  double qtyOf(String productId) =>
      _lines.where((l) => l.productId == productId).fold(0.0, (a, l) => a + l.quantity);

  void _changed() => notifyListeners();

  @override
  void notifyListeners() {
    super.notifyListeners();
    _guardar();
  }

  void marcarCobroPendiente(bool v) {
    _cobroPendiente = v;
    _guardar();
  }

  /// Guarda lo escrito en el pago (sin redibujar: lo maneja la pantalla).
  void guardarPago(Map<String, String> campos) {
    _pagoCampos = Map.of(campos);
    _guardar();
  }

  Map<String, dynamic> _toJson() => {
        'v': 1,
        'lines': _lines.map((l) => l.toJson()).toList(),
        'client': _client == null ? null : {'id': _client!.id, ..._client!.toEditable()},
        'discount': _discount,
        'notes': notes,
        'payment_method': _paymentMethod,
        'quote_id': _quoteId,
        'quote_number': _quoteNumber,
        'valid_until': _validUntil?.toIso8601String(),
        'key': _idempotencyKey,
        'pendiente': _cobroPendiente,
        'pago': _pagoCampos,
      };

  Future<void> _guardar() async {
    final k = storageKey;
    if (k == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_lines.isEmpty && !_cobroPendiente && _client == null) {
        await prefs.remove(k);
      } else {
        await prefs.setString(k, jsonEncode(_toJson()));
      }
    } catch (_) {
      // Sin almacenamiento disponible: la venta sigue en memoria igual.
    }
  }

  /// Recupera la venta que quedó guardada (al abrir la app).
  Future<void> restaurar() async {
    final k = storageKey;
    if (k == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(k);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _lines
        ..clear()
        ..addAll(((m['lines'] as List?) ?? const []).map((e) => DocLine.fromJson(Map<String, dynamic>.from(e as Map))));
      final c = m['client'];
      _client = c == null ? null : Client.fromMap(Map<String, dynamic>.from(c as Map));
      _discount = (m['discount'] as num?)?.toInt() ?? 0;
      notes = (m['notes'] as String?) ?? '';
      _paymentMethod = (m['payment_method'] as String?) ?? 'efectivo';
      _quoteId = m['quote_id'] as String?;
      _quoteNumber = (m['quote_number'] as num?)?.toInt();
      _validUntil = m['valid_until'] == null ? null : DateTime.tryParse(m['valid_until'] as String);
      final key = m['key'] as String?;
      if (key != null && key.isNotEmpty) _idempotencyKey = key;
      _cobroPendiente = (m['pendiente'] as bool?) ?? false;
      _pagoCampos = Map<String, String>.from((m['pago'] as Map?) ?? const {});
      super.notifyListeners();
    } catch (_) {
      // Dato guardado dañado: se descarta para no trabar la app.
      try {
        (await SharedPreferences.getInstance()).remove(k);
      } catch (_) {}
    }
  }

  void addProduct(Product p, double qty, {int? price, bool gift = false, bool priceIsTotal = false, double? discountPct, int discountAmount = 0}) {
    final unitPrice = price ?? p.salePrice;
    final conDescuento = discountPct != null || discountAmount > 0;
    // Con precio por línea (arena...) o con descuento, cada una es su propia línea: no se suman cantidades.
    final i = priceIsTotal || conDescuento
        ? -1
        : _lines.indexWhere((l) => l.productId == p.id && l.isGift == gift && l.unitPrice == unitPrice && !l.priceIsTotal && !l.hasDiscount);
    if (i >= 0) {
      _lines[i] = _lines[i].copyWith(quantity: _lines[i].quantity + qty, stockAvailable: p.stockParaVenta);
    } else {
      _lines.add(DocLine(
        productId: p.id,
        description: p.displayName,
        unit: p.unit,
        quantity: qty,
        unitPrice: unitPrice,
        isGift: gift,
        priceIsTotal: priceIsTotal && !gift,
        stockAvailable: p.stockParaVenta,
        discountPct: gift ? null : discountPct,
        discountAmount: gift ? 0 : discountAmount,
      ));
    }
    _changed();
  }

  void addFreeLine(String description, double qty, int price, {String unit = 'unidad', bool gift = false}) {
    _lines.add(DocLine(description: description.trim(), unit: unit, quantity: qty, unitPrice: price, isGift: gift));
    _changed();
  }

  void updateLine(int index, DocLine line) {
    _lines[index] = line;
    _changed();
  }

  void removeLine(int index) {
    _lines.removeAt(index);
    if (_discount > subtotal) _discount = subtotal;
    _changed();
  }

  void moveLine(int from, int to) {
    final l = _lines.removeAt(from);
    _lines.insert(to > from ? to - 1 : to, l);
    _changed();
  }

  set client(Client? c) {
    _client = c;
    _changed();
  }

  set discount(int v) {
    _discount = v.clamp(0, subtotal);
    _changed();
  }

  set paymentMethod(String m) {
    _paymentMethod = m;
    _changed();
  }

  set validUntil(DateTime? d) {
    _validUntil = d;
    _changed();
  }

  /// Actualiza el stock disponible de cada línea con el catálogo recién cargado.
  void refreshStock(Product? Function(String id) lookup) {
    for (var i = 0; i < _lines.length; i++) {
      final id = _lines[i].productId;
      if (id == null) continue;
      final p = lookup(id);
      if (p != null) _lines[i] = _lines[i].copyWith(stockAvailable: p.stockParaVenta);
    }
    notifyListeners();
  }

  /// Carga un presupuesto para editarlo o convertirlo en venta.
  void loadQuote(Quote q, {required Product? Function(String id) lookup, bool forSale = false}) {
    _lines
      ..clear()
      ..addAll(q.items.map((l) {
        final p = l.productId == null ? null : lookup(l.productId!);
        return l.copyWith(stockAvailable: p?.stockParaVenta);
      }));
    _client = q.client;
    _discount = q.discount;
    notes = forSale ? '' : (q.notes ?? '');
    _quoteId = q.id;
    _quoteNumber = q.number;
    _validUntil = q.validUntil;
    _idempotencyKey = _uuid.v4();
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    _client = null;
    _discount = 0;
    notes = '';
    _paymentMethod = 'efectivo';
    _quoteId = null;
    _quoteNumber = null;
    _validUntil = null;
    _idempotencyKey = _uuid.v4();
    _cobroPendiente = false;
    _pagoCampos = {};
    notifyListeners();
  }
}
