import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/doc_line.dart';
import '../../models/sale.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/refresh_bus.dart';
import '../../providers/settings_provider.dart';
import '../../repositories/sale_repository.dart';
import '../../services/pdf_documento.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/doc_actions.dart';
import '../../widgets/reloading_future.dart';
import 'return_sheet.dart';

class SaleDetailScreen extends StatelessWidget {
  const SaleDetailScreen({super.key, required this.saleId});
  final String saleId;

  Future<void> _void(BuildContext context, Sale s) async {
    final motivo = await pedirMotivo(
      context,
      titulo: 'Anular venta N° ${nroDoc(s.number)}',
      ayuda: 'Para cuando la venta se cargó mal o el cliente devuelve todo: el stock vuelve al inventario y la venta deja de sumar en '
          'ventas y ganancias. Queda en el historial como anulada.',
    );
    if (motivo == null || !context.mounted) return;
    await runSafe(context, 'anularVenta', () async {
      await context.read<SaleRepository>().voidSale(s.id, motivo);
      if (!context.mounted) return;
      context.read<CatalogProvider>().cargarProductos();
      context.read<RefreshBus>().changed();
    }, ok: 'Venta anulada');
  }

  @override
  Widget build(BuildContext context) {
    return ReloadingFuture<Sale>(
      contexto: 'detalleVenta',
      load: () => context.read<SaleRepository>().get(saleId),
      builder: (context, s, reload) {
        Future<void> devolver() async {
          final ok = await showReturnSheet(context, s);
          if (!ok || !context.mounted) return;
          context.read<CatalogProvider>().cargarProductos();
          context.read<RefreshBus>().changed();
          await reload();
        }

        final negocio = context.read<SettingsProvider>().settings;
        final datos = DatosDocumento.deVenta(s);
        // El vendedor no ve costos ni ganancias, y no anula ni hace devoluciones.
        final esAdmin = context.read<AuthProvider>().esAdmin;
        return Scaffold(
          appBar: AppBar(
            title: Text('Venta N° ${nroDoc(s.number)}'),
            actions: [
              if (!s.isVoided && esAdmin)
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'void') _void(context, s);
                    if (v == 'return') devolver();
                  },
                  itemBuilder: (_) => [
                    if (s.canReturn)
                      const PopupMenuItem(
                          value: 'return', child: ListTile(leading: Icon(Icons.assignment_return_outlined), title: Text('Devolución (parte)'))),
                    const PopupMenuItem(value: 'void', child: ListTile(leading: Icon(Icons.block, color: AppColors.red), title: Text('Anular venta'))),
                  ],
                ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  if (s.isVoided)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(10)),
                      child: Text('ANULADA${s.voidReason == null ? '' : ' · ${s.voidReason}'}',
                          style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w800)),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          KeyValueRow('Fecha', fechaHora.format(s.createdAt)),
                          if (s.sellerName != null) KeyValueRow('Atendido por', s.sellerName!),
                          KeyValueRow('Cliente', s.clientName ?? 'Sin nombre'),
                          if (s.clientDocument != null) KeyValueRow('CI / RUC', s.clientDocument!),
                          if (s.clientPhone != null) KeyValueRow('Teléfono', s.clientPhone!),
                          KeyValueRow('Pago', s.detallePago),
                          if (s.cashReceived != null) KeyValueRow('Pagó con', gs(s.cashReceived!)),
                          if (s.changeAmount > 0) KeyValueRow('Vuelto', gs(s.changeAmount), bold: true),
                          if (s.notes != null) KeyValueRow('Observaciones', s.notes!),
                        ],
                      ),
                    ),
                  ),
                  const SectionTitle('Materiales'),
                  DocLinesView(lines: s.items),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          if (s.discount > 0) ...[
                            KeyValueRow('Subtotal', gs(s.subtotal)),
                            KeyValueRow('Descuento', '− ${gs(s.discount)}', valueColor: AppColors.red),
                          ],
                          const SizedBox(height: 6),
                          TotalDestacado(etiqueta: 'TOTAL A PAGAR', monto: s.total, detalle: 'Pago: ${s.detallePago}'),
                          const SizedBox(height: 6),
                          if (s.returnedAmount > 0) ...[
                            KeyValueRow('Devuelto por el cliente', '− ${gs(s.returnedAmount)}', valueColor: AppColors.red),
                            KeyValueRow('Quedó vendido', gs(s.netTotal), bold: true),
                          ],
                          if (esAdmin) ...[
                            const Divider(height: 18),
                            KeyValueRow('Costo de la mercadería', gs(s.costTotal - s.returnedCost)),
                            KeyValueRow('Ganancia', gs(s.profit), valueColor: s.profit >= 0 ? AppColors.green : AppColors.red, bold: true),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (!s.isVoided && esAdmin) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (s.canReturn) ...[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: devolver,
                              icon: const Icon(Icons.assignment_return_outlined),
                              label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Devolución')),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
                            onPressed: () => _void(context, s),
                            icon: const Icon(Icons.block),
                            label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Anular venta')),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SectionTitle('Comprobante'),
                  DocActions(
                    fileName: datos.nombreArchivo,
                    shareText: 'Nota de venta N° ${nroDoc(s.number)} - ${negocio.name}',
                    build: () => generarDocumentoPdf(datos, negocio),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Lista de líneas de solo lectura (venta o presupuesto guardado).
class DocLinesView extends StatelessWidget {
  const DocLinesView({super.key, required this.lines});
  final List<DocLine> lines;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const Divider(indent: 14, endIndent: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(lines[i].isGift ? '' : cantidad(lines[i].quantity), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lines[i].isGift
                              ? 'REGALO ${cantidad(lines[i].quantity)} ${lines[i].description}'
                              : lines[i].description,
                          style: TextStyle(fontWeight: FontWeight.w700, color: lines[i].isGift ? AppColors.green : AppColors.ink),
                        ),
                        if (!lines[i].isGift)
                          Text(
                              lines[i].priceIsTotal
                                  ? unidadPlural(lines[i].unit, lines[i].quantity)
                                  : '${unidadPlural(lines[i].unit, lines[i].quantity)} × ${gs(lines[i].unitPrice)}',
                              style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                        if (lines[i].textoDescuento != null)
                          Text(lines[i].textoDescuento!,
                              style: const TextStyle(color: AppColors.green, fontSize: 13, fontWeight: FontWeight.w700)),
                        if (lines[i].returnedQty > 0)
                          Text('Devolvió ${cantidad(lines[i].returnedQty)}',
                              style: const TextStyle(color: AppColors.red, fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  Text(lines[i].isGift ? '' : miles(lines[i].lineTotal), style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
