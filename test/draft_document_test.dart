import 'package:bm_construcciones/models/product.dart';
import 'package:bm_construcciones/models/quote.dart';
import 'package:bm_construcciones/providers/draft_document.dart';
import 'package:flutter_test/flutter_test.dart';

Product _p(String id, {double stock = 10, int price = 70000}) => Product(
      id: id,
      name: 'Producto $id',
      category: 'General',
      unit: 'bolsa',
      stock: stock,
      avgCost: 50000,
      salePrice: price,
      minStock: 2,
      active: true,
    );

void main() {
  test('suma líneas, regalos y descuento', () {
    final d = DraftDocument();
    d.addProduct(_p('a'), 2);
    d.addProduct(_p('b', price: 300000), 0.5);
    d.addProduct(_p('c'), 1, gift: true);
    d.addFreeLine('Flete', 1, 50000);
    expect(d.subtotal, 140000 + 150000 + 0 + 50000);
    d.discount = 40000;
    expect(d.total, 300000);
    // El descuento no puede superar el subtotal.
    d.discount = 9999999;
    expect(d.total, 0);
  });

  test('agrupa el mismo producto al mismo precio y detecta falta de stock', () {
    final d = DraftDocument();
    final p = _p('a', stock: 3);
    d.addProduct(p, 2);
    d.addProduct(p, 2);
    expect(d.itemCount, 1);
    expect(d.qtyOf('a'), 4);
    expect(d.hasStockProblems, isTrue);
  });

  // Si la venta entró pero la respuesta se perdió, el reintento tiene que llevar
  // la misma clave aunque se haya tocado el carrito: así el servidor no la duplica
  // (y si los datos cambiaron, la rechaza con BM409 en vez de registrar otra).
  test('la clave dura todo el borrador: editar no la cambia', () {
    final d = DraftDocument();
    final k = d.idempotencyKey;
    d.addProduct(_p('a'), 1);
    d.addProduct(_p('b'), 2);
    d.updateLine(0, d.lines[0].copyWith(quantity: 3));
    d.removeLine(1);
    d.addFreeLine('Flete', 1, 50000);
    d.moveLine(1, 0);
    d.paymentMethod = 'qr';
    d.discount = 1000;
    d.client = null;
    d.validUntil = DateTime(2026, 12, 31);
    d.notes = 'entregar el lunes';
    expect(d.idempotencyKey, k);
  });

  test('empezar otro borrador genera una clave nueva', () {
    final d = DraftDocument();
    d.addProduct(_p('a'), 1);
    final k1 = d.idempotencyKey;
    d.clear();
    expect(d.isEmpty, isTrue);
    expect(d.idempotencyKey, isNot(k1));
    final k2 = d.idempotencyKey;
    d.loadQuote(
      Quote.fromMap({
        'id': 'q1', 'number': 7, 'status': 'pendiente', 'version': 1,
        'subtotal': 70000, 'discount': 0, 'total': 70000,
        'created_at': '2026-10-18T12:00:00Z', 'updated_at': '2026-10-18T12:00:00Z',
        'quote_items': [
          {'version': 1, 'position': 1, 'product_id': 'a', 'description': 'Cemento', 'unit': 'bolsa',
           'quantity': 1, 'unit_price': 70000, 'is_gift': false, 'line_total': 70000},
        ],
      }),
      lookup: (_) => null,
      forSale: true,
    );
    expect(d.idempotencyKey, isNot(k2));
  });

  // Arena, piedra...: se venden por palada sin stock que limite.
  test('producto por carga nunca queda sin stock ni bloquea la venta', () {
    const arena = Product(
      id: 'arena', name: 'Arena lavada', category: 'Áridos', unit: 'palada',
      stock: 0, avgCost: 0, salePrice: 100000, minStock: 0, active: true, soldByLoad: true,
    );
    expect(arena.isOut, isFalse);
    expect(arena.isLow, isFalse);
    expect(arena.stockParaVenta, isNull);
    final d = DraftDocument();
    d.addProduct(arena, 2.25);
    expect(d.hasStockProblems, isFalse);
    expect(d.total, 225000);
  });

  test('regalo va con precio cero al servidor', () {
    final d = DraftDocument();
    d.addProduct(_p('a'), 1, gift: true);
    expect(d.lines.single.toRpc()['unit_price'], 0);
    expect(d.lines.single.toRpc()['is_gift'], true);
  });
}
