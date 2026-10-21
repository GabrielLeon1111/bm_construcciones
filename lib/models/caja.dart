import 'json.dart';

/// Billetes y monedas que se cuentan al cerrar la caja (de mayor a menor).
const billetesCaja = [100000, 50000, 20000, 10000, 5000, 2000];
const monedasCaja = [1000, 500, 100, 50];
const denominacionesCaja = [...billetesCaja, ...monedasCaja];

/// Monto mínimo para abrir la caja.
const aperturaMinimaCaja = 20000;

/// Total contado según la cantidad de cada billete y moneda.
int totalContado(Map<int, int> conteo) => conteo.entries.fold(0, (a, e) => a + e.key * e.value);

/// Retiro de dinero de la caja: quién entregó (el que abrió), quién recibió y el monto.
class RetiroCaja {
  final String id;
  final int number;
  final int cajaNumber;
  final int amount;

  /// 'efectivo' o 'transferencia'.
  final String method;
  final String receivedByName;
  final String? description;
  final String givenByName;
  final String createdByName;
  final DateTime createdAt;

  const RetiroCaja({
    required this.id,
    required this.number,
    this.cajaNumber = 0,
    required this.amount,
    this.method = 'efectivo',
    required this.receivedByName,
    this.description,
    required this.givenByName,
    required this.createdByName,
    required this.createdAt,
  });

  factory RetiroCaja.fromMap(Map<String, dynamic> m) => RetiroCaja(
        id: m['id'] as String,
        number: toInt(m['number']),
        cajaNumber: toInt(m['caja_number']),
        amount: toInt(m['amount']),
        method: (m['method'] as String?) ?? 'efectivo',
        receivedByName: (m['received_by_name'] as String?) ?? '—',
        description: textOrNull(m['description']),
        givenByName: (m['given_by_name'] as String?) ?? '—',
        createdByName: (m['created_by_name'] as String?) ?? '—',
        createdAt: toDate(m['created_at']),
      );

  bool get enEfectivo => method == 'efectivo';
  String get metodoTexto => enEfectivo ? 'Efectivo' : 'Transferencia';
}

/// Una caja (abierta o cerrada). Con la caja abierta, los totales son "hasta ahora".
class Caja {
  final String id;
  final int number;
  final String status;
  final String openedByName;
  final String? openedByUsername;
  final String openedByRole;
  final DateTime openedAt;
  final int openingAmount;
  final String? closedByName;
  final String? closedByUsername;
  final DateTime? closedAt;
  final int salesCount;
  final int cashSales;
  final int transferSales;

  /// Retiros de dinero (se descuentan del efectivo que debería haber).
  final int withdrawalsTotal;
  final int withdrawalsCash;
  final int withdrawalsTransfer;
  final List<RetiroCaja> retiros;

  /// Efectivo que debería haber: inicial + ventas en efectivo − retiros en efectivo.
  final int expectedCash;

  /// Transferencias que quedan: ventas por transferencia − retiros por transferencia.
  final int expectedTransfer;
  final Map<int, int> denominations;
  final int? countedCash;
  final int? difference;

  const Caja({
    required this.id,
    required this.number,
    required this.status,
    required this.openedByName,
    this.openedByUsername,
    required this.openedByRole,
    required this.openedAt,
    required this.openingAmount,
    this.closedByName,
    this.closedByUsername,
    this.closedAt,
    this.salesCount = 0,
    this.cashSales = 0,
    this.transferSales = 0,
    this.withdrawalsTotal = 0,
    this.withdrawalsCash = 0,
    this.withdrawalsTransfer = 0,
    this.retiros = const [],
    this.expectedCash = 0,
    this.expectedTransfer = 0,
    this.denominations = const {},
    this.countedCash,
    this.difference,
  });

  bool get abierta => status == 'abierta';
  int get totalVendido => cashSales + transferSales;

  /// Lo que todavía se puede retirar: en efectivo, hasta el monto de apertura (entre
  /// todos los retiros); por transferencia, hasta lo que entró por transferencia.
  int disponibleParaRetiro(String metodo) => metodo == 'efectivo'
      ? (openingAmount - withdrawalsCash).clamp(0, openingAmount)
      : (transferSales - withdrawalsTransfer).clamp(0, transferSales < 0 ? 0 : transferSales);

  factory Caja.fromMap(Map<String, dynamic> m) {
    final d = m['denominations'];
    final w = (m['withdrawals'] ?? m['cash_withdrawals']) as List?;
    final retiros = [for (final e in w ?? const []) RetiroCaja.fromMap(Map<String, dynamic>.from(e as Map))]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return Caja(
      id: m['id'] as String,
      number: toInt(m['number']),
      status: m['status'] as String,
      openedByName: (m['opened_by_name'] as String?) ?? 'Sin nombre',
      openedByUsername: textOrNull(m['opened_by_username']),
      openedByRole: (m['opened_by_role'] as String?) ?? 'vendedor',
      openedAt: toDate(m['opened_at']),
      openingAmount: toInt(m['opening_amount']),
      closedByName: textOrNull(m['closed_by_name']),
      closedByUsername: textOrNull(m['closed_by_username']),
      closedAt: toDateOrNull(m['closed_at']),
      salesCount: toInt(m['sales_count']),
      cashSales: toInt(m['cash_sales']),
      transferSales: toInt(m['transfer_sales']),
      // En la lista del administrador (cajas abiertas) los totales se suman de los retiros.
      withdrawalsTotal: m['withdrawals_total'] != null ? toInt(m['withdrawals_total']) : retiros.fold(0, (a, r) => a + r.amount),
      withdrawalsCash:
          m['withdrawals_cash'] != null ? toInt(m['withdrawals_cash']) : retiros.where((r) => r.enEfectivo).fold(0, (a, r) => a + r.amount),
      withdrawalsTransfer: m['withdrawals_transfer'] != null
          ? toInt(m['withdrawals_transfer'])
          : retiros.where((r) => !r.enEfectivo).fold(0, (a, r) => a + r.amount),
      retiros: retiros,
      expectedCash: toInt(m['expected_cash']),
      expectedTransfer: toInt(m['expected_transfer']),
      denominations: d is Map ? {for (final e in d.entries) int.parse(e.key as String): toInt(e.value)} : const {},
      countedCash: m['counted_cash'] == null ? null : toInt(m['counted_cash']),
      difference: m['difference'] == null ? null : toInt(m['difference']),
    );
  }
}
