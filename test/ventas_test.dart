import 'package:bm_construcciones/models/doc_line.dart';
import 'package:bm_construcciones/models/sale.dart';
import 'package:bm_construcciones/utils/formato.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tercios de carga se leen y se muestran', () {
    expect(cantidad(leerCantidad('1/3')!), '1/3');
    expect(cantidad(leerCantidad('2/3')!), '2/3');
    expect(cantidad(leerCantidad('1 1/3')!), '1 1/3');
    // El monto se calcula con la fracción exacta: 1/3 de 900.000 = 300.000 justo.
    expect((leerCantidadExacta('1/3')! * 900000).round(), 300000);
    expect((leerCantidadExacta('2/3')! * 900000).round(), 600000);
    expect((leerCantidadExacta('1 1/3')! * 900000).round(), 1200000);
    // Arena a Gs. 600.000 la carga: un cuarto = 150.000, media = 300.000, tres cuartos = 450.000.
    expect((leerCantidadExacta('1/4')! * 600000).round(), 150000);
    expect((leerCantidadExacta('1/2')! * 600000).round(), 300000);
    expect((leerCantidadExacta('3/4')! * 600000).round(), 450000);
    expect(cantidad(leerCantidad('1/4')!), '1/4');
  });

  test('precio por línea: lo escrito es el total, como en el talonario', () {
    const arena = DocLine(description: 'Arena lavada', unit: 'carga', quantity: 0.333, unitPrice: 300000, priceIsTotal: true);
    expect(arena.lineTotal, 300000);
    expect(arena.toRpc()['price_is_total'], isTrue);
    const cemento = DocLine(description: 'Cemento', unit: 'bolsa', quantity: 2, unitPrice: 70000);
    expect(cemento.lineTotal, 140000);
    expect(cemento.toRpc().containsKey('price_is_total'), isFalse);
  });

  test('una devolución no cuenta en lo vendido ni en la ganancia', () {
    final s = Sale.fromMap({
      'id': 's1', 'number': 5, 'created_at': '2026-10-18T12:00:00Z', 'payment_method': 'efectivo',
      'subtotal': 280000, 'discount': 0, 'total': 280000, 'cost_total': 220000, 'status': 'activa',
      'returned_amount': 70000, 'returned_cost': 55000,
      'sale_items': [
        {'id': 'l1', 'position': 1, 'description': 'Cemento', 'unit': 'bolsa', 'quantity': 4, 'unit_price': 70000,
         'unit_cost': 55000, 'is_gift': false, 'returned_qty': 1},
      ],
    });
    expect(s.netTotal, 210000);
    expect(s.profit, 45000); // 3 bolsas × (70.000 − 55.000)
    expect(s.items.first.returnable, 3);
    expect(s.canReturn, isTrue);
  });
}
