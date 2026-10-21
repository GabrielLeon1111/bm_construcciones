import 'dart:io';
import 'package:bm_construcciones/models/business_settings.dart';
import 'package:bm_construcciones/models/doc_line.dart';
import 'package:bm_construcciones/services/pdf_documento.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Genera el comprobante de ejemplo (mismos datos que el talonario) para
/// revisar el diseño. Con PDF_OUT=ruta se guarda el archivo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    Intl.defaultLocale = 'es';
    await initializeDateFormatting('es');
  });

  const lineas = [
    DocLine(description: 'Arena lavada', unit: 'camión', quantity: 0.5, unitPrice: 600000),
    DocLine(description: 'Triturada', unit: 'kg', quantity: 3000, unitPrice: 170),
    DocLine(description: 'Varilla 8', unit: 'unidad', quantity: 2, unitPrice: 40000),
    DocLine(description: 'Varilla 4', unit: 'unidad', quantity: 2, unitPrice: 20000),
    DocLine(description: 'Cemento', unit: 'bolsa', quantity: 2, unitPrice: 70000),
    DocLine(description: 'Cal', unit: 'bolsa', quantity: 2, unitPrice: 30000),
    DocLine(description: 'Caño de 100', unit: 'unidad', quantity: 3, unitPrice: 75000),
    DocLine(description: 'Murocal', unit: 'lt', quantity: 1, unitPrice: 0, isGift: true),
  ];

  test('el total de las líneas coincide con el talonario', () {
    expect(lineas.fold<int>(0, (a, l) => a + l.lineTotal), 1355000);
  });

  for (final tipo in TipoDocumento.values) {
    test('genera el PDF de ${tipo.name}', () async {
      final datos = DatosDocumento(
        tipo: tipo,
        numero: 12,
        fecha: DateTime(2026, 10, 18),
        cliente: tipo == TipoDocumento.venta ? 'Juan Pérez' : null,
        documento: tipo == TipoDocumento.venta ? '1.234.567' : null,
        lineas: lineas,
        subtotal: 1355000,
        descuento: tipo == TipoDocumento.presupuesto ? 55000 : 0,
        total: tipo == TipoDocumento.presupuesto ? 1300000 : 1355000,
        metodoPago: 'efectivo',
        validoHasta: DateTime(2026, 10, 25),
      );
      final bytes = await generarDocumentoPdf(datos, const BusinessSettings(receiptNote: 'Gracias por su compra'));
      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

      final out = Platform.environment['PDF_OUT'];
      if (out != null) {
        await File('$out${Platform.pathSeparator}ejemplo_${tipo.name}.pdf').writeAsBytes(bytes);
      }
    });
  }
}
