import 'json.dart';

/// Carga abierta de un producto que se compra por carga (arena, piedra...).
class OpenLoad {
  final DateTime openedAt;
  final int paid;
  final int sold;
  final double quantity;
  final int purchases;
  final int sales;

  const OpenLoad({required this.openedAt, required this.paid, required this.sold, required this.quantity, required this.purchases, required this.sales});

  factory OpenLoad.fromMap(Map<String, dynamic> m) => OpenLoad(
        openedAt: toDate(m['opened_at']),
        paid: toInt(m['paid']),
        sold: toInt(m['sold']),
        quantity: toDouble(m['quantity']),
        purchases: toInt(m['purchases']),
        sales: toInt(m['sales']),
      );

  /// Lo que falta vender para recuperar lo pagado (0 si ya se recuperó).
  int get toRecover => paid > sold ? paid - sold : 0;
  int get profit => sold - paid;
  bool get recovered => paid > 0 && sold >= paid;

  /// Avance hacia recuperar lo pagado, de 0 a 1.
  double get progress => paid <= 0 ? 1 : (sold / paid).clamp(0, 1).toDouble();
}

class ClosedLoad {
  final DateTime openedAt;
  final DateTime closedAt;
  final int paid;
  final int sold;

  const ClosedLoad({required this.openedAt, required this.closedAt, required this.paid, required this.sold});

  factory ClosedLoad.fromMap(Map<String, dynamic> m) => ClosedLoad(
        openedAt: toDate(m['opened_at']),
        closedAt: toDate(m['closed_at']),
        paid: toInt(m['paid']),
        sold: toInt(m['sold']),
      );

  int get profit => sold - paid;
}

class LoadStatus {
  final OpenLoad? open;
  final List<ClosedLoad> closed;

  const LoadStatus({this.open, this.closed = const []});

  factory LoadStatus.fromMap(Map<String, dynamic> m) => LoadStatus(
        open: m['open'] is Map<String, dynamic> ? OpenLoad.fromMap(m['open'] as Map<String, dynamic>) : null,
        closed: ((m['closed'] as List?) ?? const []).cast<Map<String, dynamic>>().map(ClosedLoad.fromMap).toList(),
      );
}
