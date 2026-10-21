import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/purchase.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/purchase_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';

class PurchaseDetailScreen extends StatelessWidget {
  const PurchaseDetailScreen({super.key, required this.purchaseId});
  final String purchaseId;

  Future<void> _void(BuildContext context, Purchase p) async {
    final motivo = await pedirMotivo(
      context,
      titulo: 'Anular compra',
      ayuda: 'Se descuenta el stock que entró con esta compra y se recalcula el costo promedio. Si ya se vendió parte, no se puede anular.',
    );
    if (motivo == null || !context.mounted) return;
    await runSafe(context, 'anularCompra', () async {
      await context.read<PurchaseRepository>().voidPurchase(p.id, motivo);
      if (!context.mounted) return;
      context.read<CatalogProvider>().cargarProductos();
      context.read<RefreshBus>().changed();
    }, ok: 'Compra anulada');
  }

  @override
  Widget build(BuildContext context) {
    return ReloadingFuture<Purchase>(
      contexto: 'detalleCompra',
      load: () => context.read<PurchaseRepository>().get(purchaseId),
      builder: (context, p, reload) => Scaffold(
        appBar: AppBar(
          title: Text('Compra N° ${nroDoc(p.number)}'),
          actions: [
            if (!p.isVoided)
              PopupMenuButton<String>(
                onSelected: (_) => _void(context, p),
                itemBuilder: (_) => const [PopupMenuItem(value: 'void', child: Text('Anular compra', style: TextStyle(color: AppColors.red)))],
              ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                if (p.isVoided)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(10)),
                    child: Text('ANULADA${p.voidReason == null ? '' : ' · ${p.voidReason}'}',
                        style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w800)),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        KeyValueRow('Día de la compra', fechaCorta.format(p.purchasedOn)),
                        KeyValueRow('Cargada', fechaHora.format(p.createdAt)),
                        KeyValueRow('Proveedor', p.supplier ?? '—'),
                        KeyValueRow('Factura', p.invoiceNumber ?? '—'),
                        if (p.notes != null) KeyValueRow('Notas', p.notes!),
                      ],
                    ),
                  ),
                ),
                const SectionTitle('Materiales'),
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < p.items.length; i++) ...[
                        if (i > 0) const Divider(indent: 16, endIndent: 16),
                        ListTile(
                          title: Text(p.items[i].productName),
                          subtitle: Text(
                            '${cantidad(p.items[i].quantity)} ${unidadPlural(p.items[i].unit, p.items[i].quantity)} × ${gs(p.items[i].unitCost)}'
                            '${p.items[i].newSalePrice == null ? '' : ' · precio nuevo ${gs(p.items[i].newSalePrice!)}'}',
                          ),
                          trailing: Text(miles(p.items[i].lineTotal), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(child: Padding(padding: const EdgeInsets.all(16), child: KeyValueRow('TOTAL', gs(p.total), bold: true, big: true))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
