import 'package:intl/intl.dart';
import '../utils/formato.dart';
import 'json.dart';

/// Una línea de venta o presupuesto. Puede venir del inventario (productId)
/// o ser libre (ej: "Flete", "Mano de obra"); las libres no mueven stock.
class DocLine {
  /// Id de la línea guardada (para devoluciones). null mientras se arma.
  final String? id;
  final String? productId;
  final String description;
  final String unit;
  final double quantity;
  final int unitPrice;
  final bool isGift;
  final int unitCost;

  /// Precio por línea: lo escrito es lo que se cobra por toda la línea
  /// (arena: 1/2 palada = Gs. 300.000), no un precio por unidad.
  final bool priceIsTotal;

  /// Cuánto de esta línea ya devolvió el cliente.
  final double returnedQty;

  /// Descuento de la línea: en porcentaje ([discountPct], se recalcula si cambia la
  /// cantidad) o un monto fijo en guaraníes ([discountAmount]).
  final double? discountPct;
  final int discountAmount;

  /// Stock disponible al momento de armar la línea (solo para avisar en pantalla).
  final double? stockAvailable;

  const DocLine({
    this.id,
    this.productId,
    required this.description,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    this.isGift = false,
    this.unitCost = 0,
    this.priceIsTotal = false,
    this.returnedQty = 0,
    this.stockAvailable,
    this.discountPct,
    this.discountAmount = 0,
  });

  factory DocLine.fromMap(Map<String, dynamic> m) => DocLine(
        id: m['id'] as String?,
        productId: m['product_id'] as String?,
        description: m['description'] as String,
        unit: (m['unit'] as String?) ?? 'unidad',
        quantity: toDouble(m['quantity']),
        unitPrice: toInt(m['unit_price']),
        isGift: (m['is_gift'] as bool?) ?? false,
        unitCost: toInt(m['unit_cost']),
        priceIsTotal: (m['price_is_total'] as bool?) ?? false,
        returnedQty: toDouble(m['returned_qty']),
        discountPct: m['discount_pct'] == null ? null : toDouble(m['discount_pct']),
        discountAmount: toInt(m['line_discount']),
      );

  /// Total sin descuento (cantidad × precio, o el monto de la línea).
  int get grossTotal => isGift ? 0 : (priceIsTotal ? unitPrice : (quantity * unitPrice).round());

  /// Descuento en guaraníes (nunca más que el total de la línea).
  int get discount {
    if (isGift) return 0;
    final d = discountPct != null ? (grossTotal * discountPct! / 100).round() : discountAmount;
    return d.clamp(0, grossTotal);
  }

  bool get hasDiscount => discount > 0;

  /// Total de la línea, ya con su descuento.
  int get lineTotal => grossTotal - discount;

  /// "Desc. 10% (−Gs. 15.000)" o "Desc. −Gs. 5.000" (para pantallas y comprobantes).
  String? get textoDescuento {
    if (!hasDiscount) return null;
    if (discountPct != null) return 'Desc. ${NumberFormat('#,##0.##', 'es').format(discountPct)}% (−${gs(discount)})';
    return 'Desc. −${gs(discount)}';
  }

  /// Lo que todavía se puede devolver.
  double get returnable => quantity - returnedQty;
  bool get isFree => productId == null;
  bool get exceedsStock => stockAvailable != null && quantity > stockAvailable! + 0.0001;

  Map<String, dynamic> toRpc() => {
        if (productId != null) 'product_id': productId,
        'description': description,
        'unit': unit,
        'quantity': quantity,
        'unit_price': isGift ? 0 : unitPrice,
        'is_gift': isGift,
        if (priceIsTotal) 'price_is_total': true,
        if (hasDiscount) 'discount': discount,
        if (hasDiscount && discountPct != null) 'discount_pct': discountPct,
      };

  /// Para guardar la venta en curso en el celular (no se pierde si se corta la señal).
  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'description': description,
        'unit': unit,
        'quantity': quantity,
        'unit_price': unitPrice,
        'is_gift': isGift,
        'price_is_total': priceIsTotal,
        'stock_available': stockAvailable,
        'discount_pct': discountPct,
        'discount_amount': discountAmount,
      };

  factory DocLine.fromJson(Map<String, dynamic> m) => DocLine(
        productId: m['product_id'] as String?,
        description: m['description'] as String,
        unit: (m['unit'] as String?) ?? 'unidad',
        quantity: toDouble(m['quantity']),
        unitPrice: toInt(m['unit_price']),
        isGift: (m['is_gift'] as bool?) ?? false,
        priceIsTotal: (m['price_is_total'] as bool?) ?? false,
        stockAvailable: m['stock_available'] == null ? null : toDouble(m['stock_available']),
        discountPct: m['discount_pct'] == null ? null : toDouble(m['discount_pct']),
        discountAmount: toInt(m['discount_amount']),
      );

  DocLine copyWith({double? quantity, int? unitPrice, bool? isGift, String? description, String? unit, double? stockAvailable}) =>
      DocLine(
        id: id,
        productId: productId,
        description: description ?? this.description,
        unit: unit ?? this.unit,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        isGift: isGift ?? this.isGift,
        unitCost: unitCost,
        priceIsTotal: priceIsTotal,
        returnedQty: returnedQty,
        stockAvailable: stockAvailable ?? this.stockAvailable,
        discountPct: discountPct,
        discountAmount: discountAmount,
      );
}
