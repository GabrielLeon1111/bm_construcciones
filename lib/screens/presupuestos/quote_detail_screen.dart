import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/quote.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/draft_document.dart';
import '../../providers/refresh_bus.dart';
import '../../providers/settings_provider.dart';
import '../../repositories/quote_repository.dart';
import '../../services/pdf_documento.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/doc_actions.dart';
import '../../widgets/reloading_future.dart';
import '../shell/home_shell.dart';
import '../ventas/sale_detail_screen.dart';
import 'quote_editor_screen.dart';

class QuoteDetailScreen extends StatelessWidget {
  const QuoteDetailScreen({super.key, required this.quoteId});
  final String quoteId;

  Future<void> _toSale(BuildContext context, Quote q) async {
    final cart = context.read<DraftDocument>();
    if (!cart.isEmpty) {
      final ok = await confirmar(context,
          titulo: 'Hay una venta en curso', mensaje: 'Se reemplaza la venta que estabas armando por este presupuesto.', si: 'Reemplazar');
      if (!ok || !context.mounted) return;
    }
    final catalog = context.read<CatalogProvider>();
    await catalog.cargarProductos();
    if (!context.mounted) return;
    cart.loadQuote(q, lookup: catalog.productById, forSale: true);
    HomeShell.irAVender(context);
  }

  Future<void> _cancel(BuildContext context, Quote q) async {
    final ok = await confirmar(context, titulo: 'Anular presupuesto', mensaje: 'Queda en el historial como anulado.', si: 'Anular', peligro: true);
    if (!ok || !context.mounted) return;
    await runSafe(context, 'anularPresupuesto', () async {
      await context.read<QuoteRepository>().cancel(q.id);
      if (context.mounted) context.read<RefreshBus>().changed();
    }, ok: 'Presupuesto anulado');
  }

  @override
  Widget build(BuildContext context) {
    return ReloadingFuture<Quote>(
      contexto: 'detallePresupuesto',
      load: () => context.read<QuoteRepository>().get(quoteId),
      builder: (context, q, reload) {
        final negocio = context.read<SettingsProvider>().settings;
        final datos = DatosDocumento.dePresupuesto(q);
        final catalog = context.watch<CatalogProvider>();
        final sinStock = q.items.where((l) {
          final p = catalog.productById(l.productId);
          return p != null && p.stock < l.quantity;
        }).toList();

        return Scaffold(
          appBar: AppBar(
            title: Text('Presupuesto N° ${nroDoc(q.number)}'),
            actions: [
              if (q.isPending) ...[
                IconButton(
                  tooltip: 'Editar',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuoteEditorScreen(quote: q))),
                ),
                PopupMenuButton<String>(
                  onSelected: (_) => _cancel(context, q),
                  itemBuilder: (_) => const [PopupMenuItem(value: 'cancel', child: Text('Anular presupuesto', style: TextStyle(color: AppColors.red)))],
                ),
              ],
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  _StatusBanner(q: q),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          KeyValueRow('Cliente', q.displayClient),
                          if (q.client?.phone != null) KeyValueRow('WhatsApp', q.client!.phone!),
                          KeyValueRow('Fecha', fechaHora.format(q.createdAt)),
                          if (q.sellerName != null) KeyValueRow('Hecho por', q.sellerName!),
                          if (q.version > 1) KeyValueRow('Última edición', fechaHora.format(q.updatedAt)),
                          KeyValueRow('Válido hasta', q.validUntil == null ? '—' : fechaCorta.format(q.validUntil!)),
                          if (q.notes != null) KeyValueRow('Observaciones', q.notes!),
                        ],
                      ),
                    ),
                  ),
                  const SectionTitle('Materiales'),
                  DocLinesView(lines: q.items),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          if (q.discount > 0) ...[
                            KeyValueRow('Subtotal', gs(q.subtotal)),
                            KeyValueRow('Descuento', '− ${gs(q.discount)}', valueColor: AppColors.red),
                          ],
                          const SizedBox(height: 6),
                          TotalDestacado(etiqueta: 'TOTAL DEL PRESUPUESTO', monto: q.total),
                        ],
                      ),
                    ),
                  ),
                  if (q.isPending) ...[
                    const SizedBox(height: 16),
                    if (sinStock.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppColors.orangeSoft, borderRadius: BorderRadius.circular(10)),
                        child: Text(
                          'Ojo: hoy no alcanza el stock de ${sinStock.map((l) => l.description).join(', ')}. Podés ajustar la cantidad al convertir.',
                          style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w600),
                        ),
                      ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.ink, foregroundColor: Colors.white, minimumSize: const Size(0, 54)),
                      onPressed: () => _toSale(context, q),
                      icon: const Icon(Icons.point_of_sale_rounded, color: AppColors.yellow),
                      label: const Text('Convertir en venta'),
                    ),
                  ],
                  const SectionTitle('Compartir presupuesto'),
                  DocActions(
                    fileName: datos.nombreArchivo,
                    shareText: 'Presupuesto N° ${nroDoc(q.number)} - ${negocio.name}',
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

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.q});
  final Quote q;

  @override
  Widget build(BuildContext context) {
    final (text, color, bg) = switch (q.status) {
      'vendido' => ('Vendido: ya se convirtió en venta', AppColors.green, AppColors.greenSoft),
      'anulado' => ('Anulado', AppColors.red, AppColors.redSoft),
      _ => q.isExpired
          ? ('Vencido el ${fechaCorta.format(q.validUntil!)} (igual se puede editar o vender)', AppColors.orange, AppColors.orangeSoft)
          : ('Pendiente', AppColors.blue, AppColors.blueSoft),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700))),
          if (q.saleId != null)
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: q.saleId!))),
              child: const Text('Ver venta'),
            ),
        ],
      ),
    );
  }
}
