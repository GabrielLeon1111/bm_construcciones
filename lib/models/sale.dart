import 'doc_line.dart';
import '../utils/formato.dart';
import 'json.dart';

class Sale {
  final String id;
  final int number;
  final DateTime createdAt;
  final String? clientId;
  final String? clientName;
  final String? clientPhone;
  final String? clientDocument;
  final String? clientAddress;
  final String paymentMethod;
  final int subtotal;
  final int discount;
  final int total;
  final int costTotal;
  final String? notes;
  final String? quoteId;
  final String status;
  final String? voidReason;
  final List<DocLine> items;

  /// Lo que el cliente devolvió (monto y costo): no cuenta en ventas ni ganancias.
  final int returnedAmount;
  final int returnedCost;

  /// Cuánto entró en efectivo y cuánto por transferencia (en mixto, las dos partes).
  final int paidCash;
  final int paidTransfer;

  /// En efectivo: con cuánto pagó y el vuelto.
  final int? cashReceived;
  final int changeAmount;

  /// Nombre y apellido de quien hizo la venta (lo pone el servidor).
  final String? sellerName;

  const Sale({
    required this.id,
    required this.number,
    required this.createdAt,
    this.clientId,
    this.clientName,
    this.clientPhone,
    this.clientDocument,
    this.clientAddress,
    required this.paymentMethod,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.costTotal,
    this.notes,
    this.quoteId,
    required this.status,
    this.voidReason,
    this.items = const [],
    this.returnedAmount = 0,
    this.returnedCost = 0,
    this.paidCash = 0,
    this.paidTransfer = 0,
    this.cashReceived,
    this.changeAmount = 0,
    this.sellerName,
  });

  factory Sale.fromMap(Map<String, dynamic> m) {
    final rawItems = (m['sale_items'] as List?) ?? const [];
    final items = rawItems.cast<Map<String, dynamic>>().toList()
      ..sort((a, b) => toInt(a['position']).compareTo(toInt(b['position'])));
    return Sale(
      id: m['id'] as String,
      number: toInt(m['number']),
      createdAt: toDate(m['created_at']),
      clientId: m['client_id'] as String?,
      clientName: textOrNull(m['client_name']),
      clientPhone: textOrNull(m['client_phone']),
      clientDocument: textOrNull(m['client_document']),
      clientAddress: textOrNull(m['client_address']),
      paymentMethod: m['payment_method'] as String,
      subtotal: toInt(m['subtotal']),
      discount: toInt(m['discount']),
      total: toInt(m['total']),
      costTotal: toInt(m['cost_total']),
      notes: textOrNull(m['notes']),
      quoteId: m['quote_id'] as String?,
      status: m['status'] as String,
      voidReason: textOrNull(m['void_reason']),
      items: items.map(DocLine.fromMap).toList(),
      returnedAmount: toInt(m['returned_amount']),
      returnedCost: toInt(m['returned_cost']),
      paidCash: toInt(m['paid_cash']),
      paidTransfer: toInt(m['paid_transfer']),
      cashReceived: m['cash_received'] == null ? null : toInt(m['cash_received']),
      changeAmount: toInt(m['change_amount']),
      sellerName: textOrNull(m['seller_name']),
    );
  }

  bool get isVoided => status == 'anulada';
  /// "Efectivo", "Transferencia" o "Mixto: efectivo Gs. X + transferencia Gs. Y".
  String get detallePago => paymentMethod == 'mixto'
      ? 'Mixto: efectivo ${gs(paidCash)} + transferencia ${gs(paidTransfer)}'
      : metodoPagoTexto(paymentMethod);

  bool get hasReturns => returnedAmount > 0 || items.any((l) => l.returnedQty > 0);
  bool get canReturn => !isVoided && items.any((l) => l.returnable > 0.0001);

  /// Lo que quedó vendido, sin lo devuelto.
  int get netTotal => total - returnedAmount;
  int get profit => netTotal - (costTotal - returnedCost);
}
