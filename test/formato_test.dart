import 'package:bm_construcciones/utils/formato.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'es';
    await initializeDateFormatting('es');
  });

  group('cantidad', () {
    test('muestra fracciones como en el talonario', () {
      expect(cantidad(0.5), '1/2');
      expect(cantidad(0.25), '1/4');
      expect(cantidad(1.5), '1 1/2');
      expect(cantidad(2.75), '2 3/4');
    });

    test('enteros con punto de miles y decimales con coma', () {
      expect(cantidad(2), '2');
      expect(cantidad(3000), '3.000');
      expect(cantidad(2.4), '2,4');
      expect(cantidad(0.125), '0,125');
    });
  });

  group('leerCantidad', () {
    test('entiende fracciones', () {
      expect(leerCantidad('1/2'), 0.5);
      expect(leerCantidad('1 1/2'), 1.5);
      expect(leerCantidad(' 3/4 '), 0.75);
      expect(leerCantidad('1/0'), isNull);
    });

    test('entiende coma decimal y punto de miles', () {
      expect(leerCantidad('2,5'), 2.5);
      expect(leerCantidad('2.5'), 2.5);
      expect(leerCantidad('3.000'), 3000);
      expect(leerCantidad('3000'), 3000);
      expect(leerCantidad('1.234,5'), 1234.5);
    });

    test('rechaza texto inválido', () {
      expect(leerCantidad(''), isNull);
      expect(leerCantidad('abc'), isNull);
    });
  });

  test('montos', () {
    expect(miles(1355000), '1.355.000');
    expect(gs(1355000), 'Gs. 1.355.000');
    expect(leerMonto('1.355.000'), 1355000);
    expect(leerMonto(''), isNull);
    expect(nroDoc(12), '000012');
  });

  test('WhatsApp con prefijo de Paraguay', () {
    expect(telefonoWhatsapp('0981 000000'), '595981000000');
    expect(telefonoWhatsapp('+595 981 123456'), '595981123456');
    expect(telefonoWhatsapp(''), isNull);
  });

  test('unidades en plural', () {
    expect(unidadPlural('bolsa', 2), 'bolsas');
    expect(unidadPlural('bolsa', 1), 'bolsa');
    expect(unidadPlural('unidad', 3), 'unidades');
    expect(unidadPlural('kg', 3000), 'kg');
  });
}
