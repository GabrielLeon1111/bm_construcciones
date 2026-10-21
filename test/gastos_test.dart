import 'package:bm_construcciones/models/gasto.dart';
import 'package:bm_construcciones/models/reports.dart';
import 'package:bm_construcciones/providers/refresh_bus.dart';
import 'package:bm_construcciones/repositories/gasto_repository.dart';
import 'package:bm_construcciones/screens/gastos/gastos_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// Repositorio falso: guarda en memoria, no toca el servidor.
class _RepoFalso extends GastoRepository {
  final gastos = <Gasto>[];
  final claves = <String>[];

  @override
  Future<List<Gasto>> list({required DateTime from, required DateTime to, int limit = 2000}) async =>
      [...gastos]..sort((a, b) => b.spentAt.compareTo(a.spentAt));

  @override
  Future<Gasto> registrar({
    required String categoria,
    required int monto,
    String? descripcion,
    String? factura,
    required DateTime fecha,
    required String idempotencyKey,
  }) async {
    claves.add(idempotencyKey);
    final g = Gasto(
      id: 'g${gastos.length + 1}',
      number: gastos.length + 1,
      category: categoria,
      amount: monto,
      description: descripcion,
      invoiceNumber: factura,
      spentAt: fecha,
      createdAt: DateTime.now(),
      createdByName: 'Admin',
    );
    gastos.add(g);
    return g;
  }
}

Gasto _g(String id, String cat, int monto, DateTime cuando, {String status = 'activo', String? desc, String? fact}) => Gasto(
      id: id,
      number: 1,
      category: cat,
      amount: monto,
      description: desc,
      invoiceNumber: fact,
      spentAt: cuando,
      status: status,
      createdAt: cuando,
    );

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'es';
    await initializeDateFormatting('es');
  });

  test('resumen: suma por categoría y los anulados no cuentan', () {
    final hoy = DateTime.now();
    final r = GastosResumen.deLista([
      _g('1', 'Combustible', 150000, hoy),
      _g('2', 'Combustible', 100000, hoy),
      _g('3', 'Luz (ANDE)', 300000, hoy),
      _g('4', 'Alquiler', 2000000, hoy, status: 'anulado'),
    ]);
    expect(r.total, 550000);
    expect(r.count, 3);
    expect(r.porCategoria.first.category, 'Luz (ANDE)');
    expect(r.porCategoria[1].amount, 250000);
    expect(r.porCategoria[1].count, 2);
  });

  test('reporte: ganancia real = ganancia − gastos − averiados', () {
    final r = SalesReport.fromMap(DateTime(2026, 10, 1), DateTime(2026, 10, 21), {
      'sales': 5000000,
      'cost': 3000000,
      'profit': 2000000,
      'damaged': 100000,
      'expenses': {
        'total': 450000,
        'count': 2,
        'by_category': [
          {'category': 'Luz (ANDE)', 'amount': 300000, 'count': 1},
          {'category': 'Combustible', 'amount': 150000, 'count': 1},
        ],
      },
    });
    expect(r.expenses.total, 450000);
    expect(r.expenses.porCategoria.length, 2);
    expect(r.realProfit, 2000000 - 450000 - 100000);

    // Sin gastos (servidor viejo): no rompe.
    final sin = SalesReport.fromMap(DateTime(2026, 10, 1), DateTime(2026, 10, 21), {'profit': 1000});
    expect(sin.realProfit, 1000);
  });

  test('inicio: gastos de hoy, semana, mes y año', () {
    final d = DashboardData.fromMap({
      'today': {'sales': 900000, 'profit': 200000, 'count': 3},
      'month': {'sales': 9000000, 'profit': 2000000, 'count': 30},
      'expenses': {
        'today': {'total': 250000},
        'month': {'total': 2500000},
      },
    });
    expect(d.today.expenses, 250000);
    expect(d.today.realProfit, -50000);
    expect(d.month.realProfit, -500000);
    expect(d.week.expenses, 0);
  });

  testWidgets('gastos en el celular: lista, filtro por categoría y registrar uno', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final repo = _RepoFalso()
      ..gastos.addAll([
        _g('a', 'Combustible', 150000, now.subtract(const Duration(minutes: 30)), desc: 'Nafta camión', fact: '001-001-0001234'),
        _g('b', 'Luz (ANDE)', 300000, now.subtract(const Duration(minutes: 10))),
        _g('c', 'Alquiler', 2000000, now.subtract(const Duration(minutes: 5)), status: 'anulado'),
      ]);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RefreshBus()),
        Provider<GastoRepository>.value(value: repo),
      ],
      child: const MaterialApp(home: GastosScreen()),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Total del mes sin el anulado.
    expect(find.text('Gs. 450.000'), findsWidgets);
    expect(find.text('Nafta camión'), findsOneWidget);
    expect(find.textContaining('Fact. 001-001-0001234'), findsOneWidget);

    // Filtrar por Combustible tocando su fila en "Por categoría".
    await tester.tap(find.text('Combustible (1)'));
    await tester.pumpAndSettle();
    expect(find.text('DETALLE · COMBUSTIBLE'), findsOneWidget);
    expect(find.text('Gs. 150.000'), findsWidgets);
    await tester.tap(find.text('Ver todas'));
    await tester.pumpAndSettle();

    // Registrar: sin categoría no deja.
    await tester.tap(find.text('Registrar gasto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar gasto'));
    await tester.pumpAndSettle();
    expect(find.text('Elegí una categoría'), findsOneWidget);
    expect(repo.claves, isEmpty);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Pago a empleados'));
    await tester.pumpAndSettle();
    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), '1500000');
    await tester.enterText(campos.at(1), 'Sueldo de octubre');
    await tester.enterText(campos.at(2), '001-002-55 ?');
    await tester.pump();
    expect(tester.widget<EditableText>(find.byType(EditableText).at(2)).controller.text, '001-002-55');
    await tester.tap(find.text('Guardar gasto'));
    await tester.pumpAndSettle();

    expect(repo.claves.length, 1);
    expect(repo.gastos.last.category, 'Pago a empleados');
    expect(repo.gastos.last.amount, 1500000);
    expect(repo.gastos.last.invoiceNumber, '001-002-55');
    // De vuelta en la lista, ya aparece y suma.
    expect(find.text('Sueldo de octubre'), findsOneWidget);
    expect(find.text('Gs. 1.950.000'), findsWidgets); // total y subtotal del día
    expect(tester.takeException(), isNull);
  });
}
