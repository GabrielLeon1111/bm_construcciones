import 'dart:io';

import 'package:bm_construcciones/models/caja.dart';
import 'package:bm_construcciones/models/doc_line.dart';
import 'package:bm_construcciones/models/gasto.dart';
import 'package:bm_construcciones/models/product.dart';
import 'package:bm_construcciones/models/purchase.dart';
import 'package:bm_construcciones/models/reports.dart';
import 'package:bm_construcciones/models/sale.dart';
import 'package:bm_construcciones/providers/auth_provider.dart';
import 'package:bm_construcciones/providers/caja_provider.dart';
import 'package:bm_construcciones/providers/catalog_provider.dart';
import 'package:bm_construcciones/providers/draft_document.dart';
import 'package:bm_construcciones/providers/refresh_bus.dart';
import 'package:bm_construcciones/providers/settings_provider.dart';
import 'package:bm_construcciones/repositories/caja_repository.dart';
import 'package:bm_construcciones/repositories/client_repository.dart';
import 'package:bm_construcciones/repositories/gasto_repository.dart';
import 'package:bm_construcciones/repositories/product_repository.dart';
import 'package:bm_construcciones/repositories/purchase_repository.dart';
import 'package:bm_construcciones/repositories/report_repository.dart';
import 'package:bm_construcciones/repositories/sale_repository.dart';
import 'package:bm_construcciones/repositories/settings_repository.dart';
import 'package:bm_construcciones/screens/caja/caja_screen.dart';
import 'package:bm_construcciones/screens/gastos/gastos_screen.dart';
import 'package:bm_construcciones/screens/inicio/dashboard_screen.dart';
import 'package:bm_construcciones/screens/reportes/report_screen.dart';
import 'package:bm_construcciones/screens/vender/sell_screen.dart';
import 'package:bm_construcciones/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// =================================================================
//  CAPTURAS DEL README (con datos de ejemplo, nunca datos reales).
//  Solo corre si se pide:
//    CAPTURAS=1 flutter test --update-goldens test/capturas_readme_test.dart
//  Las imágenes quedan en docs/capturas/.
// =================================================================

final _hoy = DateTime.now();
DateTime _a(int h, int m) => DateTime(_hoy.year, _hoy.month, _hoy.day, h, m);

const _productos = [
  Product(id: 'p1', name: 'Cemento Vallemi 50 kg', category: 'Cemento', unit: 'bolsa', stock: 84, avgCost: 70000, salePrice: 75000, minStock: 20, active: true),
  Product(id: 'p2', name: 'Varilla de hierro del 8', category: 'Hierros', unit: 'unidad', stock: 120, avgCost: 27000, salePrice: 40000, minStock: 30, active: true),
  Product(id: 'p3', name: 'Ladrillo común', category: 'Ladrillos', unit: 'unidad', stock: 6500, avgCost: 580, salePrice: 750, minStock: 1000, active: true),
  Product(id: 'p4', name: 'Arena lavada', category: 'Arena y piedra', unit: 'carga', stock: 3.5, avgCost: 400000, salePrice: 600000, minStock: 1, active: true, soldByLoad: true),
  Product(id: 'p5', name: 'Cal hidratada', category: 'Cal', unit: 'bolsa', stock: 40, avgCost: 25000, salePrice: 32000, minStock: 10, active: true),
];

Sale _venta(int n, DateTime cuando, List<DocLine> lineas, {String pago = 'efectivo', String? cliente, String vendedor = 'María Gómez'}) {
  final total = lineas.fold<int>(0, (a, l) => a + l.lineTotal);
  return Sale(
    id: 's$n',
    number: n,
    createdAt: cuando,
    clientName: cliente,
    paymentMethod: pago,
    subtotal: total,
    discount: 0,
    total: total,
    costTotal: 0,
    status: 'activa',
    items: lineas,
    paidCash: pago == 'transferencia' ? 0 : total,
    paidTransfer: pago == 'transferencia' ? total : 0,
    sellerName: vendedor,
  );
}

final _ventas = [
  _venta(128, _a(15, 40), const [
    DocLine(productId: 'p1', description: 'Cemento Vallemi 50 kg', unit: 'bolsa', quantity: 16, unitPrice: 70000),
  ], cliente: 'Carlos Benítez', pago: 'transferencia'),
  _venta(127, _a(11, 5), const [
    DocLine(productId: 'p4', description: 'Arena lavada', unit: 'carga', quantity: 0.5, unitPrice: 300000, priceIsTotal: true),
  ], vendedor: 'Pedro Ruiz'),
  _venta(126, _a(8, 20), const [
    DocLine(productId: 'p3', description: 'Ladrillo común', unit: 'unidad', quantity: 1000, unitPrice: 750),
  ], cliente: 'Ana Martínez'),
];

class _Auth extends AuthProvider {
  _Auth() : super(SettingsRepository());
  @override
  String? get nombre => 'Gabriel';
  @override
  bool get esAdmin => true;
}

class _Reportes extends ReportRepository {
  @override
  Future<DashboardData> dashboard() async => DashboardData.fromMap({
        'today': {'sales': 2170000, 'profit': 512000, 'count': 3},
        'week': {'sales': 9850000, 'profit': 2310000, 'count': 17},
        'month': {'sales': 38400000, 'profit': 8960000, 'count': 64},
        'prev_month': {'sales': 33100000, 'profit': 7700000, 'count': 58},
        'year': {'sales': 312500000, 'profit': 71800000, 'count': 540},
        'payments': {'efectivo': 21300000, 'transferencia': 17100000},
        'payments_today': {'efectivo': 1050000, 'transferencia': 1120000},
        'series': [
          for (var i = 11; i >= 0; i--)
            {
              'month': DateFormat('yyyy-MM').format(DateTime(_hoy.year, _hoy.month - i)),
              'sales': 18000000 + ((11 - i) * 1700000) + (i.isEven ? 2500000 : 0),
              'profit': 4100000 + ((11 - i) * 400000),
            },
        ],
        'by_category': [
          {'category': 'Cemento', 'sales': 14200000, 'profit': 1100000},
          {'category': 'Hierros', 'sales': 9800000, 'profit': 3150000},
          {'category': 'Arena y piedra', 'sales': 8400000, 'profit': 2800000},
          {'category': 'Ladrillos', 'sales': 6000000, 'profit': 1910000},
        ],
        'top_products': [
          {'name': 'Cemento Vallemi 50 kg', 'sales': 14200000, 'profit': 1100000},
          {'name': 'Varilla de hierro del 8', 'sales': 9800000, 'profit': 3150000},
          {'name': 'Arena lavada', 'sales': 8400000, 'profit': 2800000},
        ],
        'expenses': {
          'today': {'total': 180000},
          'week': {'total': 650000},
          'month': {'total': 4350000},
          'year': {'total': 39800000},
        },
      });

  @override
  Future<SalesReport> salesReport(DateTime from, DateTime to) async => SalesReport.fromMap(from, to, {
        'invested': 24600000,
        'purchases_count': 9,
        'sales': 38400000,
        'cost': 29440000,
        'profit': 8960000,
        'discounts': 245000,
        'count': 64,
        'payments': {'efectivo': 21300000, 'transferencia': 17100000},
        'products': [
          {'name': 'Varilla de hierro del 8', 'unit': 'unidad', 'quantity': 245, 'sales': 9800000, 'cost': 6650000, 'profit': 3150000},
          {'name': 'Arena lavada', 'unit': 'carga', 'quantity': 14, 'sales': 8400000, 'cost': 5600000, 'profit': 2800000},
          {'name': 'Ladrillo común', 'unit': 'unidad', 'quantity': 8000, 'sales': 6000000, 'cost': 4640000, 'profit': 1360000},
          {'name': 'Cemento Vallemi 50 kg', 'unit': 'bolsa', 'quantity': 189, 'sales': 14200000, 'cost': 12550000, 'profit': 1650000},
        ],
        'expenses': {
          'total': 4350000,
          'count': 7,
          'by_category': [
            {'category': 'Alquiler', 'amount': 2000000, 'count': 1},
            {'category': 'Pago a empleados', 'amount': 1500000, 'count': 2},
            {'category': 'Combustible', 'amount': 450000, 'count': 3},
            {'category': 'Luz (ANDE)', 'amount': 400000, 'count': 1},
          ],
        },
      });
}

class _Ventas extends SaleRepository {
  @override
  Future<List<Sale>> list({DateTime? from, DateTime? to, int limit = 200}) async => _ventas;
}

class _Compras extends PurchaseRepository {
  @override
  Future<List<Purchase>> list({DateTime? from, DateTime? to, int limit = 200}) async => const [];
}

class _Productos extends ProductRepository {
  @override
  Future<List<Product>> list({bool includeInactive = true}) async => _productos;
}

final _caja = Caja(
  id: 'c1',
  number: 42,
  status: 'abierta',
  openedByName: 'María Gómez',
  openedByRole: 'vendedor',
  openedAt: _a(7, 30),
  openingAmount: 200000,
  salesCount: 3,
  cashSales: 1050000,
  transferSales: 1120000,
  withdrawalsCash: 100000,
  withdrawalsTransfer: 0,
  withdrawalsTotal: 100000,
  expectedCash: 1150000,
  expectedTransfer: 1120000,
);

class _Cajas extends CajaRepository {
  @override
  Future<Caja?> abierta() async => _caja;
}

class _Gastos extends GastoRepository {
  @override
  Future<List<Gasto>> list({required DateTime from, required DateTime to, int limit = 2000}) async {
    Gasto g(String id, String cat, int monto, DateTime cuando, {String? desc, String? fact}) =>
        Gasto(id: id, number: 1, category: cat, amount: monto, description: desc, invoiceNumber: fact, spentAt: cuando, createdAt: cuando);
    final d = _hoy.day;
    return [
      g('1', 'Combustible', 180000, _a(9, 15), desc: 'Gasoil para el camión de reparto', fact: '001-001-0004512'),
      if (d > 2) g('2', 'Pago a empleados', 750000, _a(18, 0).subtract(const Duration(days: 2)), desc: 'Quincena de Pedro'),
      if (d > 2) g('3', 'Luz (ANDE)', 400000, _a(10, 30).subtract(const Duration(days: 2)), fact: '0012345678'),
      if (d > 4) g('4', 'Combustible', 270000, _a(8, 0).subtract(const Duration(days: 4))),
      if (d > 5) g('5', 'Alquiler', 2000000, _a(9, 0).subtract(const Duration(days: 5)), desc: 'Alquiler del depósito'),
      if (d > 6) g('6', 'Repuestos y reparaciones', 350000, _a(14, 0).subtract(const Duration(days: 6)), desc: 'Cubierta de la carretilla'),
    ];
  }
}

Future<void> _cargarFuentes() async {
  Future<void> familia(String nombre, List<String> archivos) async {
    final f = FontLoader(nombre);
    for (final a in archivos) {
      f.addFont(rootBundle.load(a));
    }
    await f.load();
  }

  await familia('Barlow', [for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) 'assets/fonts/Barlow-$w.ttf']);
  await familia('DMSerif', ['assets/fonts/DMSerifDisplay-Regular.ttf']);
  final flutterRoot = File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final iconos = File('$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  final m = FontLoader('MaterialIcons')..addFont(iconos.readAsBytes().then((b) => ByteData.sublistView(b)));
  await m.load();
}

void main() {
  final pedidas = Platform.environment.containsKey('CAPTURAS');

  setUpAll(() async {
    Intl.defaultLocale = 'es';
    await initializeDateFormatting('es');
    if (pedidas) await _cargarFuentes();
  });

  Future<void> capturar(WidgetTester tester, String nombre, Widget pantalla,
      {DraftDocument? venta, double alto = 844, Future<void> Function()? antes}) async {
    tester.view.physicalSize = Size(390 * 2, alto * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final cajas = _Cajas();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RefreshBus()),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
        ChangeNotifierProvider(create: (_) => SettingsProvider(SettingsRepository())),
        ChangeNotifierProvider(create: (_) => CatalogProvider(_Productos(), ClientRepository())..cargarProductos()),
        ChangeNotifierProvider(create: (_) => CajaProvider(cajas)..cargar()),
        ChangeNotifierProvider.value(value: venta ?? DraftDocument()),
        Provider<ReportRepository>.value(value: _Reportes()),
        Provider<SaleRepository>.value(value: _Ventas()),
        Provider<PurchaseRepository>.value(value: _Compras()),
        Provider<CajaRepository>.value(value: cajas),
        Provider<GastoRepository>.value(value: _Gastos()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        home: pantalla,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    if (antes != null) {
      await antes();
      await tester.pumpAndSettle();
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../docs/capturas/$nombre.png'));
  }

  testWidgets('inicio', (t) => capturar(t, 'inicio', const DashboardScreen(), alto: 1000), skip: !pedidas);

  testWidgets('vender', (t) async {
    final venta = DraftDocument()
      ..addProduct(_productos[0], 10)
      ..addProduct(_productos[1], 12, discountPct: 10)
      ..addProduct(_productos[3], 0.5, price: 300000, priceIsTotal: true);
    await capturar(t, 'vender', const SellScreen(), venta: venta, alto: 1000);
  }, skip: !pedidas);

  testWidgets('cierre de caja', (t) async {
    // 1.150.000 contado: 10 de 100.000, 2 de 50.000, 2 de 20.000, 1 de 10.000.
    await capturar(t, 'cierre_caja', CierreCajaScreen(caja: _caja), alto: 1000, antes: () async {
      final campos = find.byType(TextFormField);
      const valores = ['10', '2', '2', '1'];
      for (var i = 0; i < valores.length; i++) {
        await t.enterText(campos.at(i), valores[i]);
      }
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }, skip: !pedidas);

  testWidgets('gastos', (t) => capturar(t, 'gastos', const GastosScreen(), alto: 1000), skip: !pedidas);

  testWidgets('reportes', (t) => capturar(t, 'reportes', const ReportScreen(), alto: 1000), skip: !pedidas);
}
