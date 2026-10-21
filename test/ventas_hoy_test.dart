import 'package:bm_construcciones/models/doc_line.dart';
import 'package:bm_construcciones/models/sale.dart';
import 'package:bm_construcciones/screens/ventas/ventas_hoy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

Sale _venta(int n, {String pago = 'efectivo', String estado = 'activa', List<DocLine>? items, double devuelto = 0}) {
  final lineas = items ??
      [
        DocLine(productId: 'p1', description: 'Ladrillo Común', unit: 'unidad', quantity: 500, unitPrice: 900, returnedQty: devuelto),
        const DocLine(productId: 'p2', description: 'Cemento Vallemi', unit: 'unidad', quantity: 10, unitPrice: 62000),
      ];
  final total = lineas.fold<int>(0, (a, l) => a + l.lineTotal);
  return Sale(
    id: 's$n',
    number: n,
    createdAt: DateTime(2026, 10, 19, 8 + n, 15),
    clientName: n == 1 ? 'Juan Pérez' : null,
    paymentMethod: pago,
    subtotal: total,
    discount: 0,
    total: total,
    costTotal: 0,
    status: estado,
    items: lineas,
    paidCash: pago == 'transferencia' ? 0 : total,
    paidTransfer: pago == 'transferencia' ? total : 0,
  );
}

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'es';
    await initializeDateFormatting('es');
  });

  testWidgets('tabla de ventas del día: una fila por material, estados y totales', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final ventas = [
      _venta(1),
      _venta(2, pago: 'transferencia', devuelto: 100),
      _venta(3, estado: 'anulada', items: const [
        DocLine(productId: 'p3', description: 'Arena', unit: 'carga', quantity: 1, unitPrice: 300000, priceIsTotal: true),
      ]),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ListView(children: [VentasDelDiaTable(ventas: ventas, onChanged: () async {})])),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Encabezados como en Movimientos de Inventario.
    for (final c in ['Hora', 'N°', 'Cliente', 'Total venta', 'Estado', 'Acciones', 'Producto', 'Cantidad', 'Precio', 'Subtotal', 'Pago', 'Vendedor']) {
      expect(find.text(c), findsOneWidget);
    }
    // Una fila por material: 2 + 2 + 1.
    expect(find.text('Ladrillo Común'), findsNWidgets(2));
    expect(find.text('Arena'), findsOneWidget);
    expect(find.text('Juan Pérez'), findsOneWidget);
    expect(find.text('Anulada'), findsOneWidget);
    expect(find.text('Devolvió 100'), findsOneWidget);
    expect(find.text('Transferencia'), findsOneWidget);
    // Acciones solo en la primera fila de cada venta.
    expect(find.byIcon(Icons.more_vert), findsNWidgets(3));
  });
}
