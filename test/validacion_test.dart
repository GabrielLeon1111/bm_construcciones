import 'package:bm_construcciones/utils/formato.dart';
import 'package:bm_construcciones/utils/validacion.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simula escribir [texto] letra por letra en un campo con [f].
String escribir(TextInputFormatter f, String texto) {
  var v = TextEditingValue.empty;
  for (final ch in texto.split('')) {
    final nuevo = v.text + ch;
    v = f.formatEditUpdate(v, TextEditingValue(text: nuevo, selection: TextSelection.collapsed(offset: nuevo.length)));
  }
  return v.text;
}

void main() {
  group('cantidad mientras se escribe', () {
    final f = CantidadInputFormatter();
    test('pone el punto de miles', () {
      expect(escribir(f, '3000'), '3.000');
      expect(escribir(f, '125000'), '125.000');
    });
    test('el punto del teclado es la coma decimal', () {
      expect(escribir(f, '2.5'), '2,5');
      expect(escribir(f, '2,5'), '2,5');
      expect(escribir(f, '1500,75'), '1.500,75');
    });
    test('fracciones quedan como están', () {
      expect(escribir(f, '1/2'), '1/2');
      expect(escribir(f, '1 1/2'), '1 1/2');
    });
    test('no deja escribir letras ni más de 3 decimales', () {
      expect(escribir(f, '2a'), '2');
      expect(escribir(f, '2,1234'), '2,123');
    });
    test('lo escrito se lee bien', () {
      expect(leerCantidad(escribir(f, '3000')), 3000);
      expect(leerCantidad(escribir(f, '2.5')), 2.5);
      expect(leerCantidad(escribir(f, '1500,75')), 1500.75);
    });
  });

  group('validadores', () {
    test('cantidad', () {
      final v = validarCantidad();
      expect(v(''), isNotNull);
      expect(v('0'), isNotNull);
      expect(v('abc'), isNotNull);
      expect(v('200.000'), isNotNull); // pasa el máximo
      expect(v('1/2'), isNull);
      expect(v('3.000'), isNull);
      expect(validarCantidad(permitirCero: true)('0'), isNull);
    });
    test('monto', () {
      final v = validarMonto();
      expect(v(''), isNotNull);
      expect(v('0'), isNotNull);
      expect(v('1.000.000.000'), isNotNull); // pasa el máximo
      expect(v('70.000'), isNull);
      expect(validarMonto(min: 0)('0'), isNull);
      expect(validarMonto(obligatorio: false, min: 0, max: 50000)('60.000'), isNotNull);
    });
    test('teléfono de Paraguay', () {
      expect(validarTelefono(''), isNull);
      expect(validarTelefono('', obligatorio: true), isNotNull);
      expect(validarTelefono('0981 123456'), isNull);
      expect(validarTelefono('+595 981 123456'), isNull);
      expect(validarTelefono('021 123456'), isNull);
      expect(validarTelefono('981123456'), isNotNull);
      expect(validarTelefono('0981'), isNotNull);
      expect(validarTelefono('0981-abc'), isNotNull);
    });
    test('CI y RUC', () {
      expect(validarDocumento(''), isNull);
      expect(validarDocumento('1.234.567'), isNull);
      expect(validarDocumento('1234567-8'), isNull);
      expect(validarDocumento('80012345-6'), isNull);
      expect(validarDocumento('12'), isNotNull);
      expect(validarDocumento('1234567-89'), isNotNull);
      expect(validarRuc('1234567'), isNotNull);
      expect(validarRuc('80012345-6'), isNull);
    });
    test('email', () {
      expect(validarEmail(''), isNull);
      expect(validarEmail('', obligatorio: true), isNotNull);
      expect(validarEmail('bm@gmail.com'), isNull);
      expect(validarEmail('bm@gmail'), isNotNull);
      expect(validarEmail("x'; drop table sales;--@a.com"), isNotNull);
    });
    test('texto', () {
      final v = validarTexto(campo: 'el nombre', obligatorio: true, max: 10);
      expect(v(''), isNotNull);
      expect(v('   '), isNotNull);
      expect(v('a'), isNotNull);
      expect(v('---'), isNotNull);
      expect(v('Juan'), isNull);
      expect(v('Juan Pérez García'), isNotNull);
    });
  });

  test('limpia caracteres invisibles y espacios de más', () {
    expect(limpiarTexto('  Juan​   Pérez\u0000 '), 'Juan Pérez');
    // Marca de "texto de derecha a izquierda" (se usa para disfrazar textos).
    expect(limpiarTexto('Hola${String.fromCharCode(0x202E)}mundo'), 'Holamundo');
    expect(limpiarTexto('a\n\n\n\nb', multilinea: true), 'a\n\nb');
    expect(limpiarTexto('a\nb'), 'a b');
  });
}
