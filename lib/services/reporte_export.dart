import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/business_settings.dart';
import '../models/purchase.dart';
import '../models/reports.dart';
import '../models/sale.dart';
import '../utils/formato.dart';
import 'pdf_fuentes.dart';

String nombreReporte(SalesReport r, String ext) =>
    'Reporte_${fechaCorta.format(r.from).replaceAll('/', '-')}_al_${fechaCorta.format(r.to).replaceAll('/', '-')}.$ext';

/// Arqueo y reporte de ventas en PDF.
Future<Uint8List> reportePdf(SalesReport r, BusinessSettings negocio, List<Sale> ventas) async {
  final f = await PdfRecursos.cargar();
  const amarillo = PdfColor.fromInt(0xFFF5B700);
  const carbon = PdfColor.fromInt(0xFF1C1F23);
  const gris = PdfColor.fromInt(0xFF6B6F76);
  const linea = PdfColor.fromInt(0xFFE2DED6);

  pw.Widget kpi(String label, int valor, {bool destacado = false}) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 6),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: destacado ? carbon : PdfColors.white,
            border: pw.Border.all(color: destacado ? carbon : linea),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label.toUpperCase(), style: pw.TextStyle(font: f.bold, fontSize: 7.5, color: destacado ? amarillo : gris, letterSpacing: 0.6)),
              pw.SizedBox(height: 3),
              pw.Text(gs(valor), style: pw.TextStyle(font: f.black, fontSize: 12.5, color: destacado ? PdfColors.white : carbon)),
            ],
          ),
        ),
      );

  final (ini, resto) = negocio.brandParts;
  final doc = pw.Document(title: nombreReporte(r, 'pdf'), author: negocio.name, theme: f.theme);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(30),
      header: (c) => c.pageNumber == 1
          ? pw.SizedBox()
          : pw.Text('Reporte ${fechaCorta.format(r.from)} – ${fechaCorta.format(r.to)}', style: pw.TextStyle(font: f.regular, fontSize: 8, color: gris)),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Página ${c.pageNumber} de ${c.pagesCount}', style: pw.TextStyle(font: f.regular, fontSize: 8, color: gris)),
      ),
      build: (c) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(ini, style: pw.TextStyle(font: f.serif, fontSize: 34)),
            pw.SizedBox(width: 8),
            pw.Padding(padding: const pw.EdgeInsets.only(bottom: 5), child: pw.Text(resto.toUpperCase(), style: pw.TextStyle(font: f.serif, fontSize: 14))),
            pw.Spacer(),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('ARQUEO Y REPORTE DE VENTAS', style: pw.TextStyle(font: f.black, fontSize: 12)),
              pw.Text('${fechaCorta.format(r.from)} al ${fechaCorta.format(r.to)}', style: pw.TextStyle(font: f.regular, fontSize: 10, color: gris)),
            ]),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Container(height: 3, color: amarillo),
        pw.SizedBox(height: 14),
        pw.Row(children: [
          kpi('Invertido en compras', r.invested),
          kpi('Vendido', r.sales),
          kpi('Costo de lo vendido', r.cost),
          kpi('Ganancia de ventas', r.profit),
        ]),
        pw.SizedBox(height: 8),
        pw.Row(children: [
          kpi('Gastos del negocio', r.expenses.total),
          kpi('Pérdida por averiados', r.damaged),
          kpi('Ganancia real', r.realProfit, destacado: true),
        ]),
        pw.SizedBox(height: 10),
        pw.Text(
          '${r.count} ventas · ${r.purchasesCount} compras${r.discounts > 0 ? ' · descuentos ${gs(r.discounts)}' : ''}'
          ' · ganancia real = ganancia de ventas − gastos − averiados'
          '${r.voidedCount > 0 ? ' · ${r.voidedCount} ventas anuladas (no suman)' : ''}'
          '${r.marginPct != null ? ' · margen ${r.marginPct!.toStringAsFixed(1)}%' : ''}',
          style: pw.TextStyle(font: f.regular, fontSize: 9.5, color: gris),
        ),
        pw.SizedBox(height: 16),
        if (r.expenses.porCategoria.isNotEmpty) ...[
          pw.Text('GASTOS POR CATEGORÍA', style: pw.TextStyle(font: f.black, fontSize: 10, letterSpacing: 0.6)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: linea, width: 0.6),
            headerStyle: pw.TextStyle(font: f.bold, fontSize: 9.5),
            cellStyle: pw.TextStyle(font: f.regular, fontSize: 9.5),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F1EC)),
            cellAlignments: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight},
            headers: ['Categoría', 'Cantidad', 'Monto'],
            data: [
              for (final c in r.expenses.porCategoria) [c.category, '${c.count}', gs(c.amount)],
              ['Total', '${r.expenses.count}', gs(r.expenses.total)],
            ],
          ),
          pw.SizedBox(height: 16),
        ],
        pw.Text('COBROS POR MÉTODO', style: pw.TextStyle(font: f.black, fontSize: 10, letterSpacing: 0.6)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(color: linea, width: 0.6),
          headerStyle: pw.TextStyle(font: f.bold, fontSize: 9.5),
          cellStyle: pw.TextStyle(font: f.regular, fontSize: 9.5),
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F1EC)),
          cellAlignments: {1: pw.Alignment.centerRight},
          headers: ['Método', 'Monto'],
          data: [
            ['Efectivo', gs(r.payments.efectivo)],
            ['Transferencia', gs(r.payments.transferencia)],
            if (r.payments.qr > 0) ['QR', gs(r.payments.qr)],
            ['Total', gs(r.payments.total)],
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Text('GANANCIA POR PRODUCTO', style: pw.TextStyle(font: f.black, fontSize: 10, letterSpacing: 0.6)),
        pw.SizedBox(height: 6),
        if (r.products.isEmpty)
          pw.Text('Sin ventas en el período.', style: pw.TextStyle(font: f.regular, fontSize: 9.5, color: gris))
        else
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: linea, width: 0.6),
            headerStyle: pw.TextStyle(font: f.bold, fontSize: 9),
            cellStyle: pw.TextStyle(font: f.regular, fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F1EC)),
            cellAlignments: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
            headers: ['Producto', 'Cantidad', 'Vendido', 'Costo', 'Ganancia'],
            data: [
              for (final p in r.products)
                [p.name, '${cantidad(p.quantity)} ${p.unit ?? ''}', miles(p.sales), miles(p.cost), miles(p.profit)],
              ['TOTAL', '', miles(r.sales), miles(r.cost), miles(r.profit)],
            ],
          ),
        if (ventas.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Text('DETALLE DE VENTAS', style: pw.TextStyle(font: f.black, fontSize: 10, letterSpacing: 0.6)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: linea, width: 0.6),
            headerStyle: pw.TextStyle(font: f.bold, fontSize: 8.5),
            cellStyle: pw.TextStyle(font: f.regular, fontSize: 8.5),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F1EC)),
            cellAlignments: {4: pw.Alignment.centerRight, 5: pw.Alignment.centerRight},
            headers: ['N°', 'Fecha', 'Cliente', 'Pago', 'Total', 'Ganancia'],
            data: [
              for (final s in ventas.where((s) => !s.isVoided))
                [nroDoc(s.number), fechaHora.format(s.createdAt), s.clientName ?? '—', metodoPagoTexto(s.paymentMethod), miles(s.total), miles(s.profit)],
            ],
          ),
        ],
      ],
    ),
  );
  return doc.save();
}

/// Mismo reporte en Excel: Resumen, Productos, Ventas y Compras.
Uint8List reporteExcel(SalesReport r, List<Sale> ventas, List<Purchase> compras) {
  final book = xls.Excel.createExcel();
  final bold = xls.CellStyle(bold: true);
  xls.CellValue txt(String s) => xls.TextCellValue(s);
  xls.CellValue num_(num n) => n is int ? xls.IntCellValue(n) : xls.DoubleCellValue(n.toDouble());

  void header(xls.Sheet sh, List<String> cols) {
    sh.appendRow(cols.map(txt).toList());
    for (var i = 0; i < cols.length; i++) {
      sh.cell(xls.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: sh.maxRows - 1)).cellStyle = bold;
    }
  }

  final resumen = book['Resumen'];
  resumen.appendRow([txt('Período'), txt('${fechaCorta.format(r.from)} al ${fechaCorta.format(r.to)}')]);
  resumen.appendRow([txt('Invertido en compras'), num_(r.invested)]);
  resumen.appendRow([txt('Vendido'), num_(r.sales)]);
  resumen.appendRow([txt('Costo de lo vendido'), num_(r.cost)]);
  resumen.appendRow([txt('Ganancia de ventas'), num_(r.profit)]);
  resumen.appendRow([txt('Pérdida por averiados'), num_(r.damaged)]);
  resumen.appendRow([txt('Gastos del negocio'), num_(r.expenses.total)]);
  resumen.appendRow([txt('Ganancia real (ganancia − gastos − averiados)'), num_(r.realProfit)]);
  resumen.appendRow([txt('Devoluciones (ya descontadas)'), num_(r.returned)]);
  resumen.appendRow([txt('Descuentos'), num_(r.discounts)]);
  resumen.appendRow([txt('Cantidad de ventas'), num_(r.count)]);
  resumen.appendRow([txt('Ventas anuladas'), num_(r.voidedCount)]);
  resumen.appendRow([txt('Cantidad de compras'), num_(r.purchasesCount)]);
  resumen.appendRow([txt('')]);
  resumen.appendRow([txt('Efectivo'), num_(r.payments.efectivo)]);
  resumen.appendRow([txt('Transferencia'), num_(r.payments.transferencia)]);
  if (r.payments.qr > 0) resumen.appendRow([txt('QR'), num_(r.payments.qr)]);

  if (r.expenses.porCategoria.isNotEmpty) {
    final gastos = book['Gastos'];
    header(gastos, ['Categoría', 'Cantidad', 'Monto']);
    for (final c in r.expenses.porCategoria) {
      gastos.appendRow([txt(c.category), num_(c.count), num_(c.amount)]);
    }
    gastos.appendRow([txt('Total'), num_(r.expenses.count), num_(r.expenses.total)]);
  }

  final prod = book['Productos'];
  header(prod, ['Producto', 'Categoría', 'Unidad', 'Cantidad', 'Vendido', 'Costo', 'Ganancia']);
  for (final p in r.products) {
    prod.appendRow([txt(p.name), txt(p.category ?? ''), txt(p.unit ?? ''), num_(p.quantity), num_(p.sales), num_(p.cost), num_(p.profit)]);
  }

  final vs = book['Ventas'];
  header(vs, ['N°', 'Fecha', 'Cliente', 'Pago', 'Subtotal', 'Descuento', 'Total', 'Costo', 'Ganancia', 'Estado']);
  for (final s in ventas) {
    vs.appendRow([
      num_(s.number),
      txt(fechaHora.format(s.createdAt)),
      txt(s.clientName ?? ''),
      txt(metodoPagoTexto(s.paymentMethod)),
      num_(s.subtotal),
      num_(s.discount),
      num_(s.total),
      num_(s.costTotal),
      num_(s.profit),
      txt(s.isVoided ? 'Anulada' : 'Activa'),
    ]);
  }

  final cs = book['Compras'];
  header(cs, ['N°', 'Fecha', 'Proveedor', 'Factura', 'Producto', 'Cantidad', 'Costo unit.', 'Subtotal', 'Estado']);
  for (final c in compras) {
    for (final i in c.items) {
      cs.appendRow([
        num_(c.number),
        txt(fechaHora.format(c.createdAt)),
        txt(c.supplier ?? ''),
        txt(c.invoiceNumber ?? ''),
        txt(i.productName),
        num_(i.quantity),
        num_(i.unitCost),
        num_(i.lineTotal),
        txt(c.isVoided ? 'Anulada' : 'Activa'),
      ]);
    }
  }

  book.delete('Sheet1');
  book.setDefaultSheet('Resumen');
  return Uint8List.fromList(book.encode()!);
}
