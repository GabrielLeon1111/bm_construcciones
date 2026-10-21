import 'package:bm_construcciones/models/doc_line.dart';
import 'package:bm_construcciones/models/product.dart';
import 'package:bm_construcciones/providers/draft_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'es';
    await initializeDateFormatting('es');
  });

  test('descuento en porcentaje: se recalcula con la cantidad', () {
    const l = DocLine(description: 'Cemento', unit: 'unidad', quantity: 2, unitPrice: 75000, discountPct: 10);
    expect(l.grossTotal, 150000);
    expect(l.discount, 15000);
    expect(l.lineTotal, 135000);
    expect(l.textoDescuento, 'Desc. 10% (−Gs. 15.000)');
    expect(l.copyWith(quantity: 4).lineTotal, 270000); // 300.000 − 10%
    expect(l.toRpc()['discount'], 15000);
    expect(l.toRpc()['discount_pct'], 10);
  });

  test('descuento en monto: fijo y nunca más que el total', () {
    const l = DocLine(description: 'Ladrillo', unit: 'unidad', quantity: 100, unitPrice: 750, discountAmount: 500);
    expect(l.lineTotal, 74500);
    expect(l.textoDescuento, 'Desc. −Gs. 500');
    expect(l.toRpc().containsKey('discount_pct'), isFalse);
    const tope = DocLine(description: 'X', unit: 'unidad', quantity: 1, unitPrice: 1000, discountAmount: 5000);
    expect(tope.lineTotal, 0);
    const regalo = DocLine(description: 'X', unit: 'unidad', quantity: 1, unitPrice: 1000, isGift: true, discountAmount: 500);
    expect(regalo.discount, 0);
  });

  test('venta: descuento por producto y además descuento al total', () {
    final d = DraftDocument();
    final cemento = Product(id: 'c', name: 'Cemento', category: 'Cementos', unit: 'unidad', stock: 10, avgCost: 70000, salePrice: 75000, minStock: 0, active: true);
    final ladrillo = Product(id: 'l', name: 'Ladrillo', category: 'Ladrillos', unit: 'unidad', stock: 2000, avgCost: 580, salePrice: 750, minStock: 0, active: true);
    d.addProduct(cemento, 2, discountPct: 10);
    d.addProduct(ladrillo, 100, discountAmount: 500);
    d.addProduct(ladrillo, 10); // sin descuento: línea aparte de la que tiene descuento
    expect(d.lines.length, 3);
    expect(d.subtotal, 135000 + 74500 + 7500);
    d.discount = 1000;
    expect(d.total, 216000);
  });

  test('lo guardado en el celular conserva el descuento', () {
    const l = DocLine(description: 'Cemento', unit: 'unidad', quantity: 2, unitPrice: 75000, discountPct: 10);
    final r = DocLine.fromJson(l.toJson());
    expect(r.lineTotal, 135000);
    final s = DocLine.fromMap({'description': 'Cemento', 'unit': 'unidad', 'quantity': 2, 'unit_price': 75000, 'line_discount': 15000, 'discount_pct': 10});
    expect(s.lineTotal, 135000);
  });
}
