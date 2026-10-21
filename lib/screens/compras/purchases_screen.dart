import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/purchase.dart';
import '../../repositories/purchase_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';
import 'purchase_detail_screen.dart';
import 'purchase_form_screen.dart';

/// Compras: mercadería que entra al negocio.
class PurchasesScreen extends StatelessWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compras')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_compra',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseFormScreen())),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva compra'),
      ),
      body: ReloadingFuture<List<Purchase>>(
        contexto: 'listaCompras',
        load: () => context.read<PurchaseRepository>().list(limit: 300),
        builder: (context, list, reload) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.local_shipping_outlined,
              title: 'Todavía no cargaste compras',
              message: 'Cada compra al proveedor suma stock y actualiza el costo promedio.',
            );
          }
          final now = DateTime.now();
          final delMes = list.where((p) => !p.isVoided && p.purchasedOn.year == now.year && p.purchasedOn.month == now.month);
          final totalMes = delMes.fold<int>(0, (a, p) => a + p.total);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              itemCount: list.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('COMPRADO EN ${mesAnio.format(now).toUpperCase()}',
                                  style: const TextStyle(color: AppColors.yellow, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1)),
                              const SizedBox(height: 4),
                              Text(gs(totalMes), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 26)),
                              Text('${delMes.length} compras', style: const TextStyle(color: Colors.white60)),
                            ],
                          ),
                        ),
                        const Icon(Icons.local_shipping_rounded, color: Colors.white24, size: 48),
                      ],
                    ),
                  );
                }
                final p = list[i - 1];
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseDetailScreen(purchaseId: p.id))),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Flexible(child: Text(p.supplier ?? 'Sin proveedor', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5))),
                                  const SizedBox(width: 8),
                                  if (p.isVoided) const Pill('Anulada', color: AppColors.red),
                                ]),
                                Text('${fechaCorta.format(p.purchasedOn)}${p.invoiceNumber == null ? '' : ' · Fact. ${p.invoiceNumber}'}',
                                    style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                                Text(p.items.map((e) => e.productName).join(', '), maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                              ],
                            ),
                          ),
                          Text(gs(p.total),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                decoration: p.isVoided ? TextDecoration.lineThrough : null,
                                color: p.isVoided ? AppColors.muted : AppColors.ink,
                              )),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
