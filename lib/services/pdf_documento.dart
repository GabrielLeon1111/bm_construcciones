import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/business_settings.dart';
import '../models/doc_line.dart';
import '../models/quote.dart';
import '../models/sale.dart';
import '../utils/formato.dart';
import 'pdf_fuentes.dart';

enum TipoDocumento { venta, presupuesto }

/// Datos que necesita el comprobante, vengan de una venta o de un presupuesto.
class DatosDocumento {
  final TipoDocumento tipo;
  final int numero;
  final DateTime fecha;
  final String? cliente;
  final String? documento;
  final String? telefono;
  final String? direccion;
  final List<DocLine> lineas;
  final int subtotal;
  final int descuento;
  final int total;
  final String? metodoPago;
  /// Texto del pago para el comprobante (ej: "Mixto: efectivo Gs. 40.000 + transferencia Gs. 100.000").
  final String? detallePago;
  final DateTime? validoHasta;
  final String? notas;
  final bool anulado;

  /// Quién atendió (nombre y apellido del empleado).
  final String? vendedor;

  const DatosDocumento({
    required this.tipo,
    required this.numero,
    required this.fecha,
    this.cliente,
    this.documento,
    this.telefono,
    this.direccion,
    required this.lineas,
    required this.subtotal,
    required this.descuento,
    required this.total,
    this.metodoPago,
    this.detallePago,
    this.validoHasta,
    this.notas,
    this.anulado = false,
    this.vendedor,
  });

  factory DatosDocumento.deVenta(Sale s) => DatosDocumento(
        tipo: TipoDocumento.venta,
        numero: s.number,
        fecha: s.createdAt,
        cliente: s.clientName,
        documento: s.clientDocument,
        telefono: s.clientPhone,
        direccion: s.clientAddress,
        lineas: s.items,
        subtotal: s.subtotal,
        descuento: s.discount,
        total: s.total,
        metodoPago: s.paymentMethod,
        detallePago: s.detallePago,
        notas: s.notes,
        anulado: s.isVoided,
        vendedor: s.sellerName,
      );

  factory DatosDocumento.dePresupuesto(Quote q) => DatosDocumento(
        tipo: TipoDocumento.presupuesto,
        numero: q.number,
        fecha: q.createdAt,
        vendedor: q.sellerName,
        cliente: q.client?.fullName ?? q.clientName,
        documento: q.client?.document,
        telefono: q.client?.phone,
        direccion: q.client?.address,
        lineas: q.items,
        subtotal: q.subtotal,
        descuento: q.discount,
        total: q.total,
        validoHasta: q.validUntil,
        notas: q.notes,
        anulado: q.status == 'anulado',
      );

  String get nombreArchivo =>
      '${tipo == TipoDocumento.venta ? 'Venta' : 'Presupuesto'}_${nroDoc(numero)}${cliente == null ? '' : '_${cliente!.split(' ').first}'}.pdf';
}

const _negro = PdfColors.black;
const _gris = PdfColor.fromInt(0xFF555555);
const _resaltador = PdfColor.fromInt(0xFFFFF200);
const _filasMinimas = 12;

/// Arma el PDF igual al talonario del negocio: encabezado con la marca a la
/// izquierda y celular/ciudad/logo a la derecha, y la tabla
/// Cantidad | Materiales | Precios Unitarios | TOTAL.
Future<Uint8List> generarDocumentoPdf(DatosDocumento d, BusinessSettings negocio) async {
  final r = await PdfRecursos.cargar();
  final logo = await PdfRecursos.logo(negocio.logoUrl);
  final (iniciales, resto) = negocio.brandParts;
  final esVenta = d.tipo == TipoDocumento.venta;

  final borde = pw.TableBorder.all(color: _negro, width: 0.9);
  pw.TextStyle t(double size, {pw.Font? font, PdfColor color = _negro, double spacing = 0}) =>
      pw.TextStyle(font: font ?? r.regular, fontSize: size, color: color, letterSpacing: spacing);

  // ---------- Encabezado ----------
  final encabezado = pw.Table(
    border: borde,
    columnWidths: const {0: pw.FlexColumnWidth(3.1), 1: pw.FlexColumnWidth(1.25)},
    children: [
      pw.TableRow(
        verticalAlignment: pw.TableCellVerticalAlignment.full,
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Text(
                    esVenta ? negocio.tagline.toUpperCase() : 'PRESUPUESTO',
                    style: t(25, font: r.black, spacing: 0.6),
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(iniciales, style: t(66, font: r.serif)),
                    pw.SizedBox(width: 14),
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 8),
                      child: pw.Text(resto.toUpperCase(), style: t(25, font: r.serif, spacing: 0.4)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                if (negocio.phone.isNotEmpty) ...[
                  pw.Text('CEL', style: t(10, font: r.medium, color: _gris, spacing: 1)),
                  pw.SizedBox(height: 2),
                  pw.Text(negocio.phone, style: t(19, font: r.black)),
                ],
                if (negocio.city.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(negocio.city.toUpperCase(), style: t(11, font: r.medium, color: _gris, spacing: 0.8)),
                ],
                if (logo != null) ...[
                  pw.SizedBox(height: 6),
                  pw.SizedBox(height: 100, child: pw.Image(logo, fit: pw.BoxFit.contain)),
                ],
              ],
            ),
          ),
        ],
      ),
    ],
  );

  // ---------- Datos del documento y del cliente ----------
  pw.Widget dato(String etiqueta, String? valor) => pw.RichText(
        text: pw.TextSpan(children: [
          pw.TextSpan(text: '$etiqueta: ', style: t(10, font: r.bold)),
          pw.TextSpan(text: (valor == null || valor.isEmpty) ? '—' : valor, style: t(10)),
        ]),
      );

  final datos = pw.Container(
    decoration: const pw.BoxDecoration(
      border: pw.Border(left: pw.BorderSide(width: 0.9), right: pw.BorderSide(width: 0.9)),
    ),
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 3,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              dato('Cliente', d.cliente ?? 'Sin nombre'),
              if (d.documento != null || d.telefono != null) ...[
                pw.SizedBox(height: 3),
                pw.Row(children: [
                  if (d.documento != null) dato('CI/RUC', d.documento),
                  if (d.documento != null && d.telefono != null) pw.SizedBox(width: 16),
                  if (d.telefono != null) dato('Tel', d.telefono),
                ]),
              ],
              if (d.direccion != null) ...[pw.SizedBox(height: 3), dato('Dirección', d.direccion)],
            ],
          ),
        ),
        pw.Expanded(
          flex: 2,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('${esVenta ? 'Nota de venta' : 'Presupuesto'} N° ${nroDoc(d.numero)}', style: t(11, font: r.black)),
              pw.SizedBox(height: 3),
              pw.Text('Fecha: ${fechaHora.format(d.fecha)}', style: t(10)),
              if (d.vendedor != null) ...[
                pw.SizedBox(height: 3),
                pw.Text('Atendido por: ${d.vendedor}', style: t(10)),
              ],
              if (esVenta && d.metodoPago != null) ...[
                pw.SizedBox(height: 3),
                pw.Text('Pago: ${d.detallePago ?? metodoPagoTexto(d.metodoPago!)}', style: t(10)),
              ],
              if (!esVenta && d.validoHasta != null) ...[
                pw.SizedBox(height: 3),
                pw.Text('Válido hasta: ${fechaCorta.format(d.validoHasta!)}', style: t(10, font: r.bold)),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  // ---------- Tabla de materiales ----------
  pw.Widget celda(String texto, {pw.TextAlign align = pw.TextAlign.left, pw.Font? font, double size = 11.5, PdfColor? fondo}) =>
      pw.Container(
        color: fondo,
        constraints: const pw.BoxConstraints(minHeight: 24),
        padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
        alignment: align == pw.TextAlign.right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        child: pw.Text(texto, textAlign: align, style: t(size, font: font ?? r.regular)),
      );

  final filas = <pw.TableRow>[
    pw.TableRow(children: [
      celda('Cantidad', font: r.bold),
      celda('Materiales', font: r.bold),
      celda('Precios Unitarios', font: r.bold, align: pw.TextAlign.right),
      celda('TOTAL', font: r.bold, align: pw.TextAlign.right),
    ]),
  ];

  for (final l in d.lineas) {
    if (l.isGift) {
      final unidad = l.unit == 'unidad' ? '' : ' ${unidadPlural(l.unit, l.quantity)}';
      filas.add(pw.TableRow(children: [
        celda(''),
        celda('REGALO ${cantidad(l.quantity)}$unidad ${l.description}'.toUpperCase(), font: r.medium),
        celda(''),
        celda(''),
      ]));
    } else {
      filas.add(pw.TableRow(children: [
        celda(cantidad(l.quantity)),
        celda(
          [
            l.unit == 'unidad' ? l.description : '${l.description} (${l.unit})',
            if (l.textoDescuento != null) l.textoDescuento!,
          ].join('\n'),
        ),
        celda(miles(l.unitPrice), align: pw.TextAlign.right),
        celda(miles(l.lineTotal), align: pw.TextAlign.right),
      ]));
    }
  }

  // Filas vacías para que se vea como la hoja del talonario.
  final extra = d.descuento > 0 ? 2 : 0;
  for (var i = d.lineas.length + extra; i < _filasMinimas - 1; i++) {
    filas.add(pw.TableRow(children: [celda(' '), celda(' '), celda(' '), celda(' ')]));
  }

  if (d.descuento > 0) {
    filas.add(pw.TableRow(children: [celda(''), celda(''), celda('subtotal', align: pw.TextAlign.right), celda(miles(d.subtotal), align: pw.TextAlign.right)]));
    filas.add(pw.TableRow(children: [celda(''), celda(''), celda('descuento', align: pw.TextAlign.right), celda('- ${miles(d.descuento)}', align: pw.TextAlign.right)]));
  }
  // Total resaltado: etiqueta y monto con fondo amarillo, en grande.
  filas.add(pw.TableRow(children: [
    celda(''),
    celda(esVenta ? 'TOTAL A PAGAR' : 'TOTAL DEL PRESUPUESTO', font: r.black, align: pw.TextAlign.right, size: 14, fondo: _resaltador),
    celda('Gs.', font: r.black, align: pw.TextAlign.right, size: 14, fondo: _resaltador),
    celda(miles(d.total), font: r.black, align: pw.TextAlign.right, size: 15, fondo: _resaltador),
  ]));

  final tabla = pw.Table(
    border: borde,
    columnWidths: const {
      0: pw.FlexColumnWidth(1.15),
      1: pw.FlexColumnWidth(4.1),
      2: pw.FlexColumnWidth(1.65),
      3: pw.FlexColumnWidth(1.6),
    },
    children: filas,
  );

  // ---------- Pie ----------
  final notaNegocio = esVenta ? negocio.receiptNote : negocio.quoteNote;
  final pie = pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      if (d.notas != null) ...[
        pw.SizedBox(height: 10),
        pw.Text('Observaciones: ${d.notas}', style: t(10)),
      ],
      if (notaNegocio != null) ...[
        pw.SizedBox(height: 6),
        pw.Text(notaNegocio, style: t(9.5, color: _gris)),
      ],
      pw.SizedBox(height: 14),
      pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              [negocio.name, if (negocio.ruc != null) 'RUC ${negocio.ruc}', if (negocio.address != null) negocio.address!, negocio.city]
                  .where((e) => e.isNotEmpty)
                  .join(' · '),
              style: t(8.5, color: _gris),
            ),
          ),
          pw.Text(esVenta ? 'Comprobante interno, no válido como factura.' : 'Presupuesto sin valor fiscal.', style: t(8.5, color: _gris)),
        ],
      ),
    ],
  );

  final doc = pw.Document(title: d.nombreArchivo, author: negocio.name, theme: r.theme);
  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 30, 32, 30),
        theme: r.theme,
        buildForeground: d.anulado
            ? (context) => pw.Center(
                  child: pw.Transform.rotate(
                    angle: 0.5,
                    child: pw.Opacity(
                      opacity: 0.22,
                      child: pw.Text(esVenta ? 'ANULADA' : 'ANULADO', style: t(110, font: r.black, color: PdfColors.red)),
                    ),
                  ),
                )
            : null,
      ),
      build: (context) => [encabezado, datos, tabla, pie],
    ),
  );
  return doc.save();
}

