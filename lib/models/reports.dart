import 'gasto.dart';
import 'json.dart';

class PeriodTotals {
  final int sales;
  final int profit;
  final int count;
  /// Gastos del negocio en el período (alquiler, sueldos, flete...).
  final int expenses;
  const PeriodTotals(this.sales, this.profit, this.count, {this.expenses = 0});

  factory PeriodTotals.fromMap(Object? m, {Object? gastos}) {
    final map = (m as Map?) ?? const {};
    return PeriodTotals(toInt(map['sales']), toInt(map['profit']), toInt(map['count']), expenses: GastosResumen.fromMap(gastos).total);
  }

  /// Ganancia menos los gastos del negocio.
  int get realProfit => profit - expenses;
}

class Payments {
  final int efectivo;
  final int transferencia;
  final int qr;
  const Payments(this.efectivo, this.transferencia, this.qr);

  factory Payments.fromMap(Object? m) {
    final map = (m as Map?) ?? const {};
    return Payments(toInt(map['efectivo']), toInt(map['transferencia']), toInt(map['qr']));
  }

  int get total => efectivo + transferencia + qr;
}

class NamedAmount {
  final String name;
  final String? unit;
  final String? category;
  final double quantity;
  final int sales;
  final int cost;
  final int profit;
  const NamedAmount({required this.name, this.unit, this.category, this.quantity = 0, required this.sales, this.cost = 0, required this.profit});

  factory NamedAmount.fromMap(Map<String, dynamic> m) => NamedAmount(
        name: (m['name'] ?? m['category'] ?? '') as String,
        unit: m['unit'] as String?,
        category: m['category'] as String?,
        quantity: toDouble(m['quantity']),
        sales: toInt(m['sales']),
        cost: toInt(m['cost']),
        profit: toInt(m['profit']),
      );
}

class MonthPoint {
  final DateTime month;
  final int sales;
  final int profit;
  const MonthPoint(this.month, this.sales, this.profit);
}

class LowStockItem {
  final String id;
  final String name;
  final String unit;
  final double stock;
  final double minStock;
  const LowStockItem(this.id, this.name, this.unit, this.stock, this.minStock);
}

class DashboardData {
  final PeriodTotals today;
  final PeriodTotals week;
  final PeriodTotals month;
  final PeriodTotals prevMonth;
  final PeriodTotals year;
  final Payments payments;
  /// Lo cobrado hoy en efectivo y por transferencia.
  final Payments paymentsToday;
  final List<MonthPoint> series;
  final List<NamedAmount> byCategory;
  final List<NamedAmount> topProducts;
  final int capital;
  final int lowStock;
  final int outOfStock;
  final int productCount;
  final List<LowStockItem> lowStockList;

  const DashboardData({
    required this.today,
    required this.week,
    required this.month,
    required this.prevMonth,
    required this.year,
    required this.payments,
    this.paymentsToday = const Payments(0, 0, 0),
    required this.series,
    required this.byCategory,
    required this.topProducts,
    required this.capital,
    required this.lowStock,
    required this.outOfStock,
    required this.productCount,
    required this.lowStockList,
  });

  factory DashboardData.fromMap(Map<String, dynamic> m) {
    final inv = (m['inventory'] as Map?) ?? const {};
    List<Map<String, dynamic>> list(String k) => ((m[k] as List?) ?? const []).cast<Map<String, dynamic>>();
    final gastos = (m['expenses'] as Map?) ?? const {};
    return DashboardData(
      today: PeriodTotals.fromMap(m['today'], gastos: gastos['today']),
      week: PeriodTotals.fromMap(m['week'], gastos: gastos['week']),
      month: PeriodTotals.fromMap(m['month'], gastos: gastos['month']),
      prevMonth: PeriodTotals.fromMap(m['prev_month']),
      year: PeriodTotals.fromMap(m['year'], gastos: gastos['year']),
      payments: Payments.fromMap(m['payments']),
      paymentsToday: Payments.fromMap(m['payments_today']),
      series: list('series')
          .map((e) => MonthPoint(DateTime.parse('${e['month']}-01'), toInt(e['sales']), toInt(e['profit'])))
          .toList(),
      byCategory: list('by_category').map(NamedAmount.fromMap).toList(),
      topProducts: list('top_products').map(NamedAmount.fromMap).toList(),
      capital: toInt(inv['capital']),
      lowStock: toInt(inv['low_stock']),
      outOfStock: toInt(inv['out_of_stock']),
      productCount: toInt(inv['products']),
      lowStockList: list('low_stock_list')
          .map((e) => LowStockItem(e['id'] as String, e['name'] as String, e['unit'] as String, toDouble(e['stock']), toDouble(e['min_stock'])))
          .toList(),
    );
  }

  /// Variación % de ventas del mes contra el anterior (null si no hay base).
  double? get monthChangePct => prevMonth.sales == 0 ? null : (month.sales - prevMonth.sales) / prevMonth.sales * 100;
}

class SalesReport {
  final DateTime from;
  final DateTime to;
  final int invested;
  final int purchasesCount;
  /// Lo que costó la mercadería marcada como averiada en el período.
  final int damaged;
  /// Lo que devolvieron los clientes en el período (ya descontado de lo vendido).
  final int returned;
  final int sales;
  final int cost;
  final int profit;
  final int discounts;
  final int count;
  final int voidedCount;
  final Payments payments;
  final List<NamedAmount> products;
  /// Gastos del negocio del período, por categoría.
  final GastosResumen expenses;

  const SalesReport({
    required this.from,
    required this.to,
    required this.invested,
    required this.purchasesCount,
    this.damaged = 0,
    this.returned = 0,
    required this.sales,
    required this.cost,
    required this.profit,
    required this.discounts,
    required this.count,
    required this.voidedCount,
    required this.payments,
    required this.products,
    this.expenses = GastosResumen.vacio,
  });

  factory SalesReport.fromMap(DateTime from, DateTime to, Map<String, dynamic> m) => SalesReport(
        from: from,
        to: to,
        invested: toInt(m['invested']),
        purchasesCount: toInt(m['purchases_count']),
        damaged: toInt(m['damaged']),
        returned: toInt(m['returned']),
        sales: toInt(m['sales']),
        cost: toInt(m['cost']),
        profit: toInt(m['profit']),
        discounts: toInt(m['discounts']),
        count: toInt(m['count']),
        voidedCount: toInt(m['voided_count']),
        payments: Payments.fromMap(m['payments']),
        products: ((m['products'] as List?) ?? const []).cast<Map<String, dynamic>>().map(NamedAmount.fromMap).toList(),
        expenses: GastosResumen.fromMap(m['expenses']),
      );

  /// Ganancia real: la ganancia de las ventas menos los gastos del negocio y lo averiado.
  int get realProfit => profit - expenses.total - damaged;

  double? get marginPct => sales == 0 ? null : profit / sales * 100;
}
