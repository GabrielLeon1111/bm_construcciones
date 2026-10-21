import 'json.dart';

/// Unidades de venta habituales en un corralón.
const unidadesProducto = ['unidad', 'bolsa', 'metro', 'kg', 'm²', 'm³', 'lt', 'barra', 'caja', 'rollo', 'carga', 'camión', 'palada'];

class Product {
  final String id;
  final String name;
  final String category;
  final String? brand;
  final String unit;
  final double stock;
  final int avgCost;
  final int salePrice;
  final double minStock;
  final bool active;
  final String? notes;
  /// Se compra por carga (arena, piedra...): no cuenta stock, se lleva la cuenta por carga.
  final bool soldByLoad;

  const Product({
    required this.id,
    required this.name,
    required this.category,
    this.brand,
    required this.unit,
    required this.stock,
    required this.avgCost,
    required this.salePrice,
    required this.minStock,
    required this.active,
    this.notes,
    this.soldByLoad = false,
  });

  factory Product.fromMap(Map<String, dynamic> m) => Product(
        id: m['id'] as String,
        name: m['name'] as String,
        category: (m['category'] as String?) ?? 'General',
        brand: textOrNull(m['brand']),
        unit: (m['unit'] as String?) ?? 'unidad',
        stock: toDouble(m['stock']),
        avgCost: toInt(m['avg_cost']),
        salePrice: toInt(m['sale_price']),
        minStock: toDouble(m['min_stock']),
        active: (m['active'] as bool?) ?? true,
        notes: textOrNull(m['notes']),
        soldByLoad: (m['sold_by_load'] as bool?) ?? false,
      );

  /// Solo los campos que la app puede editar (stock y costo cambian por funciones).
  Map<String, dynamic> toEditable() => {
        'name': name.trim(),
        'category': category.trim().isEmpty ? 'General' : category.trim(),
        'brand': textOrNull(brand),
        'unit': unit,
        'sale_price': salePrice,
        'min_stock': minStock,
        'active': active,
        'notes': textOrNull(notes),
        'sold_by_load': soldByLoad,
      };

  String get displayName => brand == null ? name : '$name · $brand';
  int get capital => (stock * avgCost).round();
  bool get isOut => !soldByLoad && stock <= 0;
  bool get isLow => !soldByLoad && !isOut && stock <= minStock;

  /// Cantidad libre (fracciones y decimales): solo arena y piedra bruta (por carga) y la
  /// triturada (por kilo / tonelada). Todo lo demás se vende por unidad, en números enteros.
  bool get cantidadLibre => soldByLoad || unit == 'kg';

  /// Stock que limita la venta (null = sin límite, como los productos por carga).
  double? get stockParaVenta => soldByLoad ? null : stock;
  double? get marginPct => salePrice > 0 ? (salePrice - avgCost) / salePrice * 100 : null;
}
