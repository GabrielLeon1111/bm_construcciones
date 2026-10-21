import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../providers/catalog_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../compras/purchase_form_screen.dart';
import '../compras/purchases_screen.dart';
import '../movimientos/movements_screen.dart';
import 'inventory_tables.dart';

enum _Filtro { todos, bajos, agotados, inactivos }

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _q = '';
  String? _cat;
  _Filtro _filtro = _Filtro.todos;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final all = catalog.products;
    final activos = all.where((p) => p.active).toList();
    final capital = activos.fold<int>(0, (a, p) => a + p.capital);
    final bajos = activos.where((p) => p.isLow).length;
    final agotados = activos.where((p) => p.isOut).length;

    Iterable<Product> list = switch (_filtro) {
      _Filtro.todos => activos,
      _Filtro.bajos => activos.where((p) => p.isLow),
      _Filtro.agotados => activos.where((p) => p.isOut),
      _Filtro.inactivos => all.where((p) => !p.active),
    };
    if (_cat != null) list = list.where((p) => p.category == _cat);
    if (_q.isNotEmpty) list = list.where((p) => coincide('${p.name} ${p.brand ?? ''} ${p.category} ${p.notes ?? ''}', _q));
    final items = list.toList();

    // Dos pestañas: Productos (tabla) y Movimientos (panel con el historial).
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Inventario'),
          bottom: const TabBar(
            labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            tabs: [
              Tab(text: 'Productos'),
              Tab(text: 'Movimientos'),
            ],
          ),
        ),
        // Sin "+ Producto": un producto solo se crea al cargar su compra
        // (Nueva compra → "Producto nuevo"), así siempre entra con costo y stock.
        body: TabBarView(
          children: [
            RefreshIndicator(
              onRefresh: catalog.cargarProductos,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(14)),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'INVERTIDO EN MERCADERÍA',
                                    style: TextStyle(color: AppColors.yellow, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1),
                                  ),
                                  const SizedBox(height: 4),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      gs(capital),
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 26),
                                    ),
                                  ),
                                  Text('${activos.length} productos activos · a costo promedio', style: const TextStyle(color: Colors.white60, fontSize: 13)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // ---------- Compras: la mercadería que entra ----------
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.local_shipping_outlined, color: AppColors.ink),
                                  SizedBox(width: 8),
                                  Text('Compras', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                ],
                              ),
                              const Padding(
                                padding: EdgeInsets.only(top: 2, bottom: 10),
                                child: Text(
                                  'Cargá la mercadería que te llega: el stock se actualiza solo.',
                                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseFormScreen())),
                                      icon: const Icon(Icons.add_rounded),
                                      label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Nueva compra')),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchasesScreen())),
                                      icon: const Icon(Icons.history_rounded),
                                      label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Ver compras')),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: TextField(
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar producto'),
                        onChanged: (v) => setState(() => _q = v),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          _chip('Todos', _Filtro.todos),
                          _chip('Por agotarse${bajos > 0 ? ' ($bajos)' : ''}', _Filtro.bajos),
                          _chip('Agotados${agotados > 0 ? ' ($agotados)' : ''}', _Filtro.agotados),
                          _chip('Inactivos', _Filtro.inactivos),
                          if (catalog.categories.length > 1) ...[
                            const VerticalDivider(width: 16, indent: 8, endIndent: 8),
                            for (final c in catalog.categories)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(label: Text(c), selected: _cat == c, onSelected: (_) => setState(() => _cat = _cat == c ? null : c)),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (catalog.loading && all.isEmpty)
                    const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
                  else if (catalog.error != null && all.isEmpty)
                    SliverFillRemaining(
                      child: ErrorRetry(message: catalog.error!, onRetry: catalog.cargarProductos),
                    )
                  else if (items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: all.isEmpty ? 'Todavía no cargaste productos' : 'No hay productos con ese filtro',
                        message: all.isEmpty ? 'Tocá "+ Producto" para cargar el primero.' : null,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      sliver: SliverToBoxAdapter(child: ProductsTable(products: items)),
                    ),
                ],
              ),
            ),
            const MovementsPanel(),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, _Filtro f) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(label: Text(label), selected: _filtro == f, onSelected: (_) => setState(() => _filtro = f)),
  );
}
