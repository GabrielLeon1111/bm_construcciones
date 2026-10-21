import 'json.dart';

class PurchaseItem {
  final String productId;
  final String productName;
  final String unit;
  final double quantity;
  final int unitCost;
  final int? newSalePrice;

  const PurchaseItem({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.unitCost,
    this.newSalePrice,
  });

  factory PurchaseItem.fromMap(Map<String, dynamic> m) => PurchaseItem(
        productId: m['product_id'] as String,
        productName: m['product_name'] as String,
        unit: m['unit'] as String,
        quantity: toDouble(m['quantity']),
        unitCost: toInt(m['unit_cost']),
        newSalePrice: m['new_sale_price'] == null ? null : toInt(m['new_sale_price']),
      );

  int get lineTotal => (quantity * unitCost).round();

  Map<String, dynamic> toRpc() => {
        'product_id': productId,
        'quantity': quantity,
        'unit_cost': unitCost,
        if (newSalePrice != null) 'new_sale_price': newSalePrice,
      };
}

class Purchase {
  final String id;
  final int number;
  final String? supplier;
  final String? invoiceNumber;
  final String? notes;
  final int total;
  final String status;
  final String? voidReason;
  final DateTime createdAt;

  /// Día en que se compró (el de la factura); puede ser anterior al día en que se cargó.
  final DateTime purchasedOn;
  final List<PurchaseItem> items;

  const Purchase({
    required this.id,
    required this.number,
    this.supplier,
    this.invoiceNumber,
    this.notes,
    required this.total,
    required this.status,
    this.voidReason,
    required this.createdAt,
    required this.purchasedOn,
    this.items = const [],
  });

  factory Purchase.fromMap(Map<String, dynamic> m) {
    final raw = ((m['purchase_items'] as List?) ?? const []).cast<Map<String, dynamic>>().toList()
      ..sort((a, b) => toInt(a['position']).compareTo(toInt(b['position'])));
    return Purchase(
      id: m['id'] as String,
      number: toInt(m['number']),
      supplier: textOrNull(m['supplier']),
      invoiceNumber: textOrNull(m['invoice_number']),
      notes: textOrNull(m['notes']),
      total: toInt(m['total']),
      status: m['status'] as String,
      voidReason: textOrNull(m['void_reason']),
      createdAt: toDate(m['created_at']),
      purchasedOn: m['purchased_on'] == null ? toDate(m['created_at']) : DateTime.parse(m['purchased_on'] as String),
      items: raw.map(PurchaseItem.fromMap).toList(),
    );
  }

  bool get isVoided => status == 'anulada';
}
