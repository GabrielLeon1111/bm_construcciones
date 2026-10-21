import 'package:bm_construcciones/models/client.dart';
import 'package:bm_construcciones/models/product.dart';
import 'package:bm_construcciones/providers/draft_document.dart';
import 'package:bm_construcciones/security/bloqueo_login.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Product _p(String id) => Product(
      id: id,
      name: 'Ladrillo $id',
      category: 'Ladrillos',
      unit: 'unidad',
      stock: 1000,
      avgCost: 500,
      salePrice: 900,
      minStock: 0,
      active: true,
    );

Future<void> _esperarGuardado() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('venta guardada en el celular (sin señal no se pierde)', () {
    test('vuelve igual al reabrir: materiales, cliente, pago y la MISMA clave', () async {
      final a = DraftDocument(storageKey: 'venta_en_curso');
      a.addProduct(_p('1'), 100);
      a.client = const Client(id: 'c1', fullName: 'Juan Pérez', phone: '0981 123456');
      a.discount = 5000;
      a.notes = 'entregar el lunes';
      a.paymentMethod = 'mixto';
      a.guardarPago({'mixEfectivo': '40.000', 'mixTransfer': '45.000'});
      a.marcarCobroPendiente(true);
      await _esperarGuardado();

      // "Se cerró la app": otro borrador lee lo guardado.
      final b = DraftDocument(storageKey: 'venta_en_curso');
      await b.restaurar();
      expect(b.lines.single.quantity, 100);
      expect(b.lines.single.unitPrice, 900);
      expect(b.client?.fullName, 'Juan Pérez');
      expect(b.discount, 5000);
      expect(b.notes, 'entregar el lunes');
      expect(b.paymentMethod, 'mixto');
      expect(b.pagoCampos['mixEfectivo'], '40.000');
      expect(b.cobroPendiente, isTrue);
      // Misma clave: si la venta ya había entrado, el servidor no la duplica.
      expect(b.idempotencyKey, a.idempotencyKey);
      expect(b.total, 85000);
    });

    test('al terminar la venta se borra lo guardado', () async {
      final a = DraftDocument(storageKey: 'venta_en_curso');
      a.addProduct(_p('1'), 10);
      await _esperarGuardado();
      a.clear();
      await _esperarGuardado();
      final b = DraftDocument(storageKey: 'venta_en_curso');
      await b.restaurar();
      expect(b.isEmpty, isTrue);
      expect(b.cobroPendiente, isFalse);
    });

    test('un dato guardado dañado no traba la app', () async {
      SharedPreferences.setMockInitialValues({'venta_en_curso': '{roto'});
      final b = DraftDocument(storageKey: 'venta_en_curso');
      await b.restaurar();
      expect(b.isEmpty, isTrue);
    });

    test('el presupuesto (sin storageKey) no se guarda', () async {
      final q = DraftDocument();
      q.addProduct(_p('1'), 5);
      await _esperarGuardado();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });
  });

  group('bloqueo por intentos fallidos', () {
    test('avisa desde el 2.º intento y bloquea al 5.º por 30 minutos', () async {
      final b = BloqueoLogin();
      expect(mensajeIntentoFallido(await b.registrarFallo()), isNot(contains('quedan')));
      expect(mensajeIntentoFallido(await b.registrarFallo()), contains('Te quedan 3 intentos'));
      expect(mensajeIntentoFallido(await b.registrarFallo()), contains('Te quedan 2 intentos'));
      expect(mensajeIntentoFallido(await b.registrarFallo()), contains('Te queda 1 intento'));
      expect(await b.bloqueadoHasta(), isNull);
      expect(mensajeIntentoFallido(await b.registrarFallo()), contains('bloqueada 30 minutos'));
      final hasta = await b.bloqueadoHasta();
      expect(hasta, isNotNull);
      final minutos = hasta!.difference(DateTime.now()).inMinutes;
      expect(minutos, inInclusiveRange(29, 30));
    });

    test('entrar bien reinicia los intentos', () async {
      final b = BloqueoLogin();
      await b.registrarFallo();
      await b.registrarFallo();
      await b.reiniciar();
      expect(mensajeIntentoFallido(await b.registrarFallo()), isNot(contains('quedan')));
    });

    test('pasado el bloqueo vuelve a tener 5 intentos', () async {
      final vencido = DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({'login_fallos': 5, 'login_bloqueado_hasta': vencido});
      final b = BloqueoLogin();
      expect(await b.bloqueadoHasta(), isNull);
      expect(await b.registrarFallo(), 1);
    });
  });
}
