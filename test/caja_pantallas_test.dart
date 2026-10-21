import 'package:bm_construcciones/models/caja.dart';
import 'package:bm_construcciones/providers/caja_provider.dart';
import 'package:bm_construcciones/repositories/caja_repository.dart';
import 'package:bm_construcciones/screens/caja/caja_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// Repositorio falso: no toca el servidor.
class _RepoFalso extends CajaRepository {
  @override
  Future<Caja?> abierta() async => null;
}

final _caja = Caja(
  id: 'c1',
  number: 1,
  status: 'abierta',
  openedByName: 'Juan Pérez',
  openedByRole: 'vendedor',
  openedAt: DateTime(2026, 10, 21, 8),
  openingAmount: 100000,
  salesCount: 2,
  cashSales: 75000,
  transferSales: 7500,
  withdrawalsCash: 50000,
  withdrawalsTransfer: 5000,
  withdrawalsTotal: 55000,
  expectedCash: 125000,
  expectedTransfer: 2500,
);

Widget _app(Widget hijo) {
  final repo = _RepoFalso();
  return MultiProvider(
    providers: [
      Provider<CajaRepository>.value(value: repo),
      ChangeNotifierProvider(create: (_) => CajaProvider(repo)),
    ],
    child: MaterialApp(home: hijo),
  );
}

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'es';
    await initializeDateFormatting('es');
  });

  testWidgets('cierre en el celular: con una cantidad ya se puede cerrar', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 2200 * 3); // ancho de celular, alto para ver todo
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(CierreCajaScreen(caja: _caja)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Escribí lo que contaste para cerrar'), findsOneWidget);
    expect(find.text('= Debería haber en la caja'), findsOneWidget);
    expect(find.text('= Queda en transferencias'), findsOneWidget);

    // Solo números: las letras no entran.
    final campos = find.byType(TextFormField);
    expect(campos, findsNWidgets(10));
    await tester.enterText(campos.first, '1a\$2');
    await tester.pump();
    expect(tester.widget<EditableText>(find.byType(EditableText).first).controller.text, '12');

    // Completar todo: 1 de 100.000, 1 de 20.000, 1 de 5.000 = 125.000 → cuadrada.
    const valores = ['1', '0', '1', '0', '1', '0', '0', '0', '0', '0'];
    for (var i = 0; i < 10; i++) {
      await tester.enterText(campos.at(i), valores[i]);
    }
    await tester.pumpAndSettle();
    expect(find.text('Confirmar cierre'), findsOneWidget);
    expect(find.text('Caja cuadrada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retiro en el celular: tope y nombre solo con letras', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 2200 * 3); // ancho de celular, alto para ver todo
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(RetiroCajaScreen(caja: _caja)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Efectivo: hasta 50.000 (100.000 de apertura − 50.000 ya retirado).
    expect(find.textContaining('hasta Gs. 50.000'), findsOneWidget);

    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), '60000');
    await tester.enterText(campos.at(1), 'Pedro 123 Gómez!');
    await tester.pump();
    expect(tester.widget<EditableText>(find.byType(EditableText).at(1)).controller.text, 'Pedro  Gómez');
    await tester.tap(find.text('Retirar y ver comprobante'));
    await tester.pumpAndSettle();
    expect(find.text('No puede pasar de Gs. 50.000'), findsOneWidget);

    // Por transferencia: hasta 2.500.
    await tester.tap(find.text('Transferencia'));
    await tester.pumpAndSettle();
    expect(find.textContaining('hasta Gs. 2.500'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
