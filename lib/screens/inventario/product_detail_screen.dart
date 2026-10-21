import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../models/purchase.dart';
import '../../models/stock_movement.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/product_repository.dart';
import '../../repositories/purchase_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';
import '../compras/purchase_detail_screen.dart';
import '../compras/purchase_form_screen.dart';
import '../movimientos/movements_screen.dart';
import 'adjust_stock_sheet.dart';
import 'damaged_sheet.dart';
import 'load_panel.dart';
import 'product_form_screen.dart';

class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.productId});
  final String productId;

  Future<(Product, List<StockMovement>, List<Purchase>)> _load(BuildContext context) async {
    final repo = context.read<ProductRepository>();
    final compras = context.read<PurchaseRepository>();
    final results = await Future.wait([repo.get(productId), repo.movements(productId), compras.byProduct(productId)]);
    return (results[0] as Product, results[1] as List<StockMovement>, results[2] as List<Purchase>);
  }

  Future<void> _afterChange(BuildContext context) async {
    await context.read<CatalogProvider>().cargarProductos();
    if (context.mounted) context.read<RefreshBus>().changed();
  }

  Future<void> _menu(BuildContext context, String action, Product p) async {
    final repo = context.read<ProductRepository>();
    switch (action) {
      case 'toggle':
        await runSafe(context, 'activarProducto', () async {
          await repo.setActive(p.id, !p.active);
          if (context.mounted) await _afterChange(context);
        }, ok: p.active ? 'Producto desactivado: ya no aparece para vender' : 'Producto activado');
      case 'delete':
        final ok = await confirmar(
          context,
          titulo: 'Eliminar producto',
          mensaje: 'Solo se puede eliminar si nunca tuvo movimientos. Si ya se vendió o compró, desactivalo.',
          si: 'Eliminar',
          peligro: true,
        );
        if (!ok || !context.mounted) return;
        final done = await runSafe(context, 'eliminarProducto', () => repo.delete(p.id), ok: 'Producto eliminado');
        if (done && context.mounted) {
          await _afterChange(context);
          if (context.mounted) Navigator.pop(context);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ReloadingFuture<(Product, List<StockMovement>, List<Purchase>)>(
      contexto: 'detalleProducto',
      load: () => _load(context),
      builder: (context, data, reload) {
        final (p, movs, compras) = data;
        return Scaffold(
          appBar: AppBar(
            title: Text(p.name),
            actions: [
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(product: p))),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => _menu(context, v, p),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'toggle', child: Text(p.active ? 'Desactivar' : 'Activar')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Eliminar', style: TextStyle(color: AppColors.red)),
                  ),
                ],
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: RefreshIndicator(
                onRefresh: reload,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    if (!p.active)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppColors.orangeSoft, borderRadius: BorderRadius.circular(10)),
                        child: const Text(
                          'Producto inactivo: no aparece para vender.',
                          style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700),
                        ),
                      ),
                    Text([p.category, p.brand].whereType<String>().join(' · '), style: const TextStyle(color: AppColors.muted)),
                    if (p.notes != null && p.notes!.isNotEmpty) Text(p.notes!, style: const TextStyle(fontStyle: FontStyle.italic)),
                    const SizedBox(height: 12),
                    if (p.soldByLoad)
                      LoadPanel(product: p, onChanged: () => _afterChange(context))
                    else
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(14)),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'STOCK',
                                    style: TextStyle(color: AppColors.yellow, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 12),
                                  ),
                                  Text(
                                    '${cantidad(p.stock)} ${unidadPlural(p.unit, p.stock)}',
                                    style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800),
                                  ),
                                  Text('Mínimo: ${cantidad(p.minStock)}', style: const TextStyle(color: Colors.white60)),
                                ],
                              ),
                            ),
                            if (p.isOut)
                              const Pill('Agotado', color: Colors.white, background: AppColors.red)
                            else if (p.isLow)
                              const Pill('Por agotarse', color: AppColors.ink, background: AppColors.yellow),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            KeyValueRow('Precio de venta', '${gs(p.salePrice)} / ${p.unit}', bold: true),
                            if (!p.soldByLoad) KeyValueRow('Costo promedio', '${gs(p.avgCost)} / ${p.unit}'),
                            if (!p.soldByLoad)
                              KeyValueRow(
                                'Margen',
                                p.marginPct == null ? '—' : '${p.marginPct!.toStringAsFixed(1)}%',
                                valueColor: (p.marginPct ?? 0) >= 0 ? AppColors.green : AppColors.red,
                              ),
                            if (!p.soldByLoad) KeyValueRow('Invertido en stock', gs(p.capital)),
                          ],
                        ),
                      ),
                    ),
                    if (!p.soldByLoad) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseFormScreen(initialProduct: p))),
                        icon: const Icon(Icons.local_shipping_outlined),
                        label: const Text('Cargar compra'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final changed = await showAdjustStockSheet(context, p);
                                if (changed && context.mounted) await _afterChange(context);
                              },
                              icon: const Icon(Icons.tune_rounded),
                              label: const Text('Ajustar stock'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
                              onPressed: () async {
                                final changed = await showDamagedSheet(context, p);
                                if (changed && context.mounted) await _afterChange(context);
                              },
                              icon: const Icon(Icons.heart_broken_outlined),
                              label: const Text('Averiados'),
                            ),
                          ),
                        ],
                      ),
                      _ComprasDelProducto(compras: compras, unit: p.unit),
                      const SectionTitle('Historial de movimientos'),
                      if (movs.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(18),
                            child: Text('Sin movimientos todavía.', style: TextStyle(color: AppColors.muted)),
                          ),
                        )
                      else
                        Card(
                          child: Column(
                            children: [
                              for (var i = 0; i < movs.length; i++) ...[
                                if (i > 0) const Divider(indent: 16, endIndent: 16),
                                MovementTile(m: movs[i], unit: p.unit, showProduct: false),
                              ],
                            ],
                          ),
                        ),
                    ] else
                      _ComprasDelProducto(compras: compras, unit: p.unit),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A quién, con qué factura y qué día se compró este producto.
class _ComprasDelProducto extends StatelessWidget {
  const _ComprasDelProducto({required this.compras, required this.unit});
  final List<Purchase> compras;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Compras de este producto'),
        if (compras.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('Todavía no cargaste compras. Tocá "Cargar compra" para anotar proveedor, factura y día.',
                  style: TextStyle(color: AppColors.muted)),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < compras.length; i++) ...[
                  if (i > 0) const Divider(indent: 16, endIndent: 16),
                  _fila(context, compras[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _fila(BuildContext context, Purchase c) {
    final item = c.items.isEmpty ? null : c.items.first;
    final detalle = [
      fechaCorta.format(c.purchasedOn),
      if (c.invoiceNumber != null) 'Fact. ${c.invoiceNumber}',
    ].join(' · ');
    return ListTile(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseDetailScreen(purchaseId: c.id))),
      title: Row(children: [
        Flexible(child: Text(c.supplier ?? 'Sin proveedor', style: const TextStyle(fontWeight: FontWeight.w700))),
        if (c.isVoided) ...[const SizedBox(width: 8), const Pill('Anulada', color: AppColors.red)],
      ]),
      subtitle: Text(detalle),
      trailing: item == null
          ? null
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${cantidad(item.quantity)} ${unidadPlural(item.unit, item.quantity)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${gs(item.unitCost)} c/u', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ],
            ),
    );
  }
}
