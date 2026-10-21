import 'json.dart';

class StockMovement {
  final String id;
  final String productId;
  final String? productName;
  final String? productUnit;
  /// Costo promedio y precio de venta actuales del producto (para la tabla de movimientos).
  final int? productAvgCost;
  final int? productSalePrice;
  final String type;
  final double quantity;
  final double stockBefore;
  final double stockAfter;
  final int? unitCost;
  final int avgCostBefore;
  final int avgCostAfter;
  final int? unitPrice;
  final String? saleId;
  final String? purchaseId;
  final String? reason;
  final DateTime createdAt;

  const StockMovement({
    required this.id,
    required this.productId,
    this.productName,
    this.productUnit,
    this.productAvgCost,
    this.productSalePrice,
    required this.type,
    required this.quantity,
    required this.stockBefore,
    required this.stockAfter,
    this.unitCost,
    required this.avgCostBefore,
    required this.avgCostAfter,
    this.unitPrice,
    this.saleId,
    this.purchaseId,
    this.reason,
    required this.createdAt,
  });

  factory StockMovement.fromMap(Map<String, dynamic> m) {
    final p = m['products'];
    return StockMovement(
      id: m['id'] as String,
      productId: m['product_id'] as String,
      productName: p is Map ? p['name'] as String? : null,
      productUnit: p is Map ? p['unit'] as String? : null,
      productAvgCost: p is Map && p['avg_cost'] != null ? toInt(p['avg_cost']) : null,
      productSalePrice: p is Map && p['sale_price'] != null ? toInt(p['sale_price']) : null,
      // Los averiados se guardan como ajuste con subtipo 'averia'.
      type: (m['movement_subtype'] as String?) ?? m['movement_type'] as String,
      quantity: toDouble(m['quantity']),
      stockBefore: toDouble(m['stock_before']),
      stockAfter: toDouble(m['stock_after']),
      unitCost: m['unit_cost'] == null ? null : toInt(m['unit_cost']),
      avgCostBefore: toInt(m['avg_cost_before']),
      avgCostAfter: toInt(m['avg_cost_after']),
      unitPrice: m['unit_price'] == null ? null : toInt(m['unit_price']),
      saleId: m['sale_id'] as String?,
      purchaseId: m['purchase_id'] as String?,
      reason: textOrNull(m['reason']),
      createdAt: toDate(m['created_at']),
    );
  }

  bool get isEntry => quantity > 0;

  String get typeLabel => switch (type) {
        'compra' => 'Compra',
        'venta' => 'Venta',
        'ajuste' => 'Ajuste',
        'averia' => 'Averiado',
        'anulacion_venta' => 'Venta anulada',
        'anulacion_compra' => 'Compra anulada',
        _ => type,
      };
}

const tiposMovimiento = {
  'compra': 'Compras',
  'venta': 'Ventas',
  'ajuste': 'Ajustes',
  'averia': 'Averiados',
  'anulacion_venta': 'Ventas anuladas',
  'anulacion_compra': 'Compras anuladas',
};
