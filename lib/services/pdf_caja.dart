import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/business_settings.dart';
import '../models/caja.dart';
import '../utils/formato.dart';
import 'pdf_fuentes.dart';

const _negro = PdfColors.black;
const _gris = PdfColor.fromInt(0xFF555555);
const _verde = PdfColor.fromInt(0xFF1E7B34);
const _rojo = PdfColor.fromInt(0xFFC62828);

String nombreArchivoCaja(Caja c) => 'Arqueo_caja_${nroDoc(c.number)}.pdf';

String _rol(String rol) => rol == 'admin' ? 'Administrador' : 'Vendedor';

/// Comprobante de arqueo de caja (una hoja): apertura y cierre (quién y cuándo),
/// retiros, conteo de billetes y monedas, efectivo y transferencias (lo que entró,
/// lo retirado y lo que queda), si sobra o falta, y las firmas.
Future<Uint8List> generarArqueoPdf(Caja c, BusinessSettings negocio) async {
  final r = await PdfRecursos.cargar();
  final logo = await PdfRecursos.logo(negocio.logoUrl);
  pw.TextStyle t(double size, {pw.Font? font, PdfColor color = _negro, double spacing = 0}) =>
      pw.TextStyle(font: font ?? r.regular, fontSize: size, color: color, letterSpacing: spacing);
  final borde = pw.TableBorder.all(color: _negro, width: 0.7);
  const celda = pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1.8);

  pw.Widget titulo(String texto) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 9, bottom: 4),
        child: pw.Text(texto.toUpperCase(), style: t(10, font: r.black, spacing: 1)),
      );

  pw.Widget fila(String etiqueta, String valor, {bool fuerte = false, PdfColor color = _negro}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.3),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text(etiqueta, style: t(9.8, font: fuerte ? r.bold : r.regular))),
          pw.Text(valor, style: t(fuerte ? 11 : 9.8, font: fuerte ? r.black : r.medium, color: color)),
        ]),
      );

  pw.Widget dato(String etiqueta, String valor) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.RichText(
          text: pw.TextSpan(children: [
            pw.TextSpan(text: '$etiqueta: ', style: t(9.6, font: r.bold)),
            pw.TextSpan(text: valor, style: t(9.6)),
          ]),
        ),
      );

  pw.Widget txt(String s, {bool derecha = false, bool fuerte = false}) => pw.Padding(
        padding: celda,
        child: pw.Text(s, textAlign: derecha ? pw.TextAlign.right : pw.TextAlign.left, style: t(9, font: fuerte ? r.bold : r.regular)),
      );

  const fondoTitulo = pw.BoxDecoration(color: PdfColor.fromInt(0xFFEFEFEF));

  // ---------- Encabezado ----------
  final encabezado = pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(negocio.name, style: t(19, font: r.serif)),
            if (negocio.city.isNotEmpty || negocio.phone.isNotEmpty)
              pw.Text([negocio.city, if (negocio.phone.isNotEmpty) 'Cel. ${negocio.phone}'].where((e) => e.isNotEmpty).join(' · '),
                  style: t(9.5, color: _gris)),
            pw.SizedBox(height: 6),
            pw.Text('ARQUEO DE CAJA N° ${nroDoc(c.number)}', style: t(16, font: r.black, spacing: 0.4)),
            if (c.abierta) pw.Text('CAJA TODAVÍA ABIERTA (resumen parcial)', style: t(9.5, font: r.bold, color: _rojo)),
          ],
        ),
      ),
      if (logo != null) pw.SizedBox(height: 58, width: 58, child: pw.Image(logo, fit: pw.BoxFit.contain)),
    ],
  );

  // ---------- Apertura y cierre ----------
  final aperturaCierre = pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            titulo('Apertura'),
            dato('Abrió', c.openedByName),
            if (c.openedByUsername != null) dato('Usuario', c.openedByUsername!),
            dato('Cargo', _rol(c.openedByRole)),
            dato('Fecha y hora', fechaHora.format(c.openedAt)),
            dato('Monto inicial', gs(c.openingAmount)),
          ],
        ),
      ),
      pw.SizedBox(width: 20),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            titulo('Cierre'),
            dato('Cerró', c.closedByName ?? '—'),
            if (c.closedByUsername != null) dato('Usuario', c.closedByUsername!),
            dato('Fecha y hora', c.closedAt == null ? '—' : fechaHora.format(c.closedAt!)),
            dato('Ventas', '${c.salesCount} · total ${gs(c.totalVendido)}'),
            dato('Por método', 'efectivo ${gs(c.cashSales)} · transf. ${gs(c.transferSales)}'),
          ],
        ),
      ),
    ],
  );

  // ---------- Retiros de dinero ----------
  final retiros = c.retiros.isEmpty
      ? pw.Text('No hubo retiros de dinero.', style: t(9.5, color: _gris))
      : pw.Table(
          border: borde,
          columnWidths: const {
            0: pw.FlexColumnWidth(0.8),
            1: pw.FlexColumnWidth(1.3),
            2: pw.FlexColumnWidth(2),
            3: pw.FlexColumnWidth(2.6),
            4: pw.FlexColumnWidth(1.4),
          },
          children: [
            pw.TableRow(
              decoration: fondoTitulo,
              children: [txt('Hora', fuerte: true), txt('Forma', fuerte: true), txt('Recibió', fuerte: true), txt('Descripción', fuerte: true), txt('Monto', derecha: true, fuerte: true)],
            ),
            for (final w in c.retiros)
              pw.TableRow(children: [
                txt(hora.format(w.createdAt)),
                txt(w.metodoTexto),
                txt(w.receivedByName),
                txt(w.description ?? '—'),
                txt(gs(w.amount), derecha: true),
              ]),
          ],
        );

  // ---------- Conteo: billetes y monedas lado a lado ----------
  pw.Widget tablaConteo(String tituloTabla, List<int> valores) => pw.Table(
        border: borde,
        columnWidths: const {0: pw.FlexColumnWidth(1.4), 1: pw.FlexColumnWidth(0.9), 2: pw.FlexColumnWidth(1.5)},
        children: [
          pw.TableRow(decoration: fondoTitulo, children: [txt(tituloTabla, fuerte: true), txt('Cant.', derecha: true, fuerte: true), txt('Subtotal', derecha: true, fuerte: true)]),
          for (final v in valores)
            pw.TableRow(children: [
              txt(gs(v)),
              txt('${c.denominations[v] ?? 0}', derecha: true),
              txt(gs((c.denominations[v] ?? 0) * v), derecha: true),
            ]),
        ],
      );

  final conteo = pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: tablaConteo('Billetes', billetesCaja)),
          pw.SizedBox(width: 14),
          pw.Expanded(child: tablaConteo('Monedas', monedasCaja)),
        ],
      ),
      pw.SizedBox(height: 4),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('TOTAL CONTADO: ${c.countedCash == null ? '—' : gs(c.countedCash!)}', style: t(11, font: r.black)),
      ),
    ],
  );

  // ---------- Resultado: efectivo y transferencia lado a lado ----------
  final dif = c.difference ?? 0;
  pw.Widget caja(List<pw.Widget> hijos) => pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.9)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: hijos),
      );

  final resultado = pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: caja([
          pw.Text('EFECTIVO', style: t(9.5, font: r.black, spacing: 1)),
          fila('Monto inicial', gs(c.openingAmount)),
          fila('+ Ventas en efectivo', gs(c.cashSales)),
          fila('− Retirado en efectivo', gs(c.withdrawalsCash)),
          fila('= Debería haber', gs(c.expectedCash), fuerte: true),
          fila('Contado', c.countedCash == null ? '—' : gs(c.countedCash!), fuerte: true),
          pw.Divider(height: 6, thickness: 0.6),
          fila(
            c.countedCash == null ? 'Diferencia' : (dif == 0 ? 'CAJA CUADRADA' : (dif > 0 ? 'SOBRA' : 'FALTA')),
            c.countedCash == null ? '—' : gs(dif.abs()),
            fuerte: true,
            color: c.countedCash == null || dif == 0 ? _negro : (dif > 0 ? _verde : _rojo),
          ),
        ]),
      ),
      pw.SizedBox(width: 14),
      pw.Expanded(
        child: caja([
          pw.Text('TRANSFERENCIA (no está en la caja)', style: t(9.5, font: r.black, spacing: 1)),
          fila('Ventas por transferencia', gs(c.transferSales)),
          fila('− Retirado por transferencia', gs(c.withdrawalsTransfer)),
          fila('= Queda', gs(c.expectedTransfer), fuerte: true),
        ]),
      ),
    ],
  );

  // ---------- Firmas ----------
  pw.Widget firma(String rotulo, String? nombre) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 34),
          pw.Container(height: 0.8, color: _negro),
          pw.SizedBox(height: 3),
          pw.Text('Firma', style: t(8.5, color: _gris)),
          pw.SizedBox(height: 4),
          pw.Text(rotulo, style: t(9.6, font: r.bold)),
          pw.SizedBox(height: 3),
          nombre != null
              ? pw.Text(nombre, style: t(9.6))
              : pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Nombre y apellido:', style: t(8.5, color: _gris)),
                  pw.SizedBox(height: 14),
                  pw.Container(height: 0.5, color: _gris),
                ]),
        ],
      );

  final firmas = pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(child: firma('Abrió la caja', '${c.openedByName}${c.openedByUsername == null ? '' : ' (${c.openedByUsername})'}')),
      pw.SizedBox(width: 40),
      pw.Expanded(child: firma('Recibió el comprobante', null)),
    ],
  );

  final doc = pw.Document(title: nombreArchivoCaja(c), author: negocio.name, theme: r.theme);
  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.fromLTRB(34, 26, 34, 24), theme: r.theme),
      build: (_) => [
        encabezado,
        pw.SizedBox(height: 4),
        pw.Divider(thickness: 1, height: 8),
        aperturaCierre,
        titulo('Retiros de dinero'),
        retiros,
        titulo('Conteo de billetes y monedas'),
        conteo,
        titulo('Resultado del arqueo'),
        resultado,
        firmas,
        pw.SizedBox(height: 8),
        pw.Text('Impreso el ${fechaHora.format(DateTime.now())}', style: t(8, color: _gris)),
      ],
    ),
  );
  return doc.save();
}

String nombreArchivoRetiro(RetiroCaja w) => 'Retiro_caja_${nroDoc(w.number)}.pdf';

/// Comprobante de retiro de dinero: monto, quién entregó (el que abrió la caja),
/// quién recibió, descripción y las dos firmas.
Future<Uint8List> generarRetiroPdf(RetiroCaja w, BusinessSettings negocio) async {
  final r = await PdfRecursos.cargar();
  final logo = await PdfRecursos.logo(negocio.logoUrl);
  pw.TextStyle t(double size, {pw.Font? font, PdfColor color = _negro, double spacing = 0}) =>
      pw.TextStyle(font: font ?? r.regular, fontSize: size, color: color, letterSpacing: spacing);

  pw.Widget dato(String etiqueta, String valor) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.RichText(
          text: pw.TextSpan(children: [
            pw.TextSpan(text: '$etiqueta: ', style: t(11, font: r.bold)),
            pw.TextSpan(text: valor, style: t(11)),
          ]),
        ),
      );

  pw.Widget firma(String rotulo, String nombre) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 50),
          pw.Container(height: 0.8, color: _negro),
          pw.SizedBox(height: 4),
          pw.Text('Firma', style: t(9, color: _gris)),
          pw.SizedBox(height: 6),
          pw.Text(rotulo, style: t(10, font: r.bold)),
          pw.SizedBox(height: 3),
          pw.Text(nombre, style: t(10.5)),
        ],
      );

  final doc = pw.Document(title: nombreArchivoRetiro(w), author: negocio.name, theme: r.theme);
  doc.addPage(
    pw.Page(
      pageTheme: pw.PageTheme(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30), theme: r.theme),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(negocio.name, style: t(20, font: r.serif)),
                    if (negocio.city.isNotEmpty || negocio.phone.isNotEmpty)
                      pw.Text([negocio.city, if (negocio.phone.isNotEmpty) 'Cel. ${negocio.phone}'].where((e) => e.isNotEmpty).join(' · '),
                          style: t(10, color: _gris)),
                    pw.SizedBox(height: 10),
                    pw.Text('RETIRO DE DINERO N° ${nroDoc(w.number)}', style: t(17, font: r.black, spacing: 0.4)),
                    if (w.cajaNumber > 0) pw.Text('De la caja N° ${nroDoc(w.cajaNumber)}', style: t(10.5, color: _gris)),
                  ],
                ),
              ),
              if (logo != null) pw.SizedBox(height: 70, width: 70, child: pw.Image(logo, fit: pw.BoxFit.contain)),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
            child: pw.Row(children: [
              pw.Expanded(child: pw.Text('MONTO RETIRADO', style: t(13, font: r.black, spacing: 0.6))),
              pw.Text(gs(w.amount), style: t(22, font: r.black)),
            ]),
          ),
          pw.SizedBox(height: 12),
          dato('Fecha y hora', fechaHora.format(w.createdAt)),
          dato('Forma', w.metodoTexto),
          dato('Entregó (abrió la caja)', w.givenByName),
          dato('Recibió', w.receivedByName),
          dato('Descripción', w.description ?? '—'),
          if (w.createdByName != w.givenByName) dato('Registrado por', w.createdByName),
          pw.SizedBox(height: 30),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: firma('Entregó', w.givenByName)),
              pw.SizedBox(width: 40),
              pw.Expanded(child: firma('Recibió', w.receivedByName)),
            ],
          ),
          pw.Spacer(),
          pw.Text('Impreso el ${fechaHora.format(DateTime.now())}', style: t(8.5, color: _gris)),
        ],
      ),
    ),
  );
  return doc.save();
}
