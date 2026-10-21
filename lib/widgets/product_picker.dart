import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../providers/catalog_provider.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import '../utils/validacion.dart';
import '../screens/inventario/product_form_screen.dart';
import 'common.dart';

/// Lista de productos con buscador y filtro por categoría.
/// Se usa embebida (pantalla Vender) o dentro de una hoja (presupuestos, compras).
class ProductBrowser extends StatefulWidget {
  const ProductBrowser({
    super.key,
    required this.onPick,
    this.showCost = false,
    this.trailingFor,
    this.autofocus = false,
    this.resetAfterPick = false,
    this.onCrear,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 120),
  });

  /// Si se pasa, muestra "Crear producto nuevo" (para compras de algo que no está en el inventario).
  final VoidCallback? onCrear;

  final FutureOr<void> Function(Product) onPick;
  /// Después de elegir, limpia el buscador y lo deja listo para el próximo producto.
  final bool resetAfterPick;
  final bool showCost;
  final bool autofocus;
  final Widget? Function(Product p)? trailingFor;
  final EdgeInsets padding;

  @override
  State<ProductBrowser> createState() => _ProductBrowserState();
}

class _ProductBrowserState extends State<ProductBrowser> {
  String _q = '';
  String? _cat;
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _pick(Product p) async {
    await widget.onPick(p);
    if (!mounted || !widget.resetAfterPick) return;
    _ctrl.clear();
    setState(() => _q = '');
    _focus.requestFocus();
  }

  /// Enter en el buscador: si hay un solo resultado, lo abre.
  void _submitSearch(List<Product> list) {
    if (list.length == 1) {
      _pick(list.first);
    } else if (list.isNotEmpty && _q.isNotEmpty) {
      showSnack(context, 'Hay ${list.length} productos con "$_q". Tocá el que querés o escribí más.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final cats = catalog.categories;
    var list = catalog.activeProducts;
    if (_cat != null) list = list.where((p) => p.category == _cat).toList();
    if (_q.isNotEmpty) list = list.where((p) => coincide('${p.name} ${p.brand ?? ''} ${p.category} ${p.notes ?? ''}', _q)).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            autofocus: widget.autofocus,
            textInputAction: TextInputAction.search,
            inputFormatters: formatoTexto(Largo.nombre),
            onSubmitted: (_) => _submitSearch(list),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar (ej: cemento)',
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _ctrl.clear();
                        setState(() => _q = '');
                      }),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        if (widget.onCrear != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              onPressed: widget.onCrear,
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('¿No está? Crear producto nuevo'),
            ),
          ),
        if (cats.length > 1)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: const Text('Todos'), selected: _cat == null, onSelected: (_) => setState(() => _cat = null)),
                ),
                for (final c in cats)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(c), selected: _cat == c, onSelected: (_) => setState(() => _cat = _cat == c ? null : c)),
                  ),
              ],
            ),
          ),
        Expanded(
          child: catalog.loading && catalog.products.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: catalog.products.isEmpty ? 'Todavía no hay productos' : 'No se encontró "$_q"',
                      message: catalog.products.isEmpty ? 'Cargalos desde Inventario.' : null,
                    )
                  : RefreshIndicator(
                      onRefresh: catalog.cargarProductos,
                      child: ListView.separated(
                        padding: widget.padding.copyWith(top: 8),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => ProductTile(
                          product: list[i],
                          showCost: widget.showCost,
                          trailing: widget.trailingFor?.call(list[i]),
                          onTap: () => _pick(list[i]),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}

class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product, required this.onTap, this.showCost = false, this.trailing});
  final Product product;
  final VoidCallback onTap;
  final bool showCost;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = product;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      [p.category, p.brand].whereType<String>().join(' · '),
                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                    // Descripción breve: ayuda a distinguir productos parecidos.
                    if (p.notes != null && p.notes!.isNotEmpty)
                      Text(p.notes!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
                    const SizedBox(height: 6),
                    if (p.soldByLoad)
                      const Pill('Por carga', color: AppColors.blue)
                    else
                      StockPill(stock: p.stock, minStock: p.minStock, unit: p.unit),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Triturada y demás por kilo: se muestra por tonelada, que es como se habla.
                  Text(gs((showCost ? p.avgCost : p.salePrice) * (p.unit == 'kg' ? 1000 : 1)),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, fontFeatures: [FontFeature.tabularFigures()])),
                  Text(
                    showCost ? 'costo / ${p.unit == 'kg' ? 'tonelada' : p.unit}' : 'por ${p.unit == 'kg' ? 'tonelada' : p.unit}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

const _crearNuevo = 'crear';

/// Hoja para elegir un producto (presupuestos y compras).
/// Con [permitirCrear] se puede crear un producto nuevo en el momento y se devuelve ese.
Future<Product?> pickProduct(BuildContext context, {bool showCost = false, bool permitirCrear = false}) async {
  final r = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    builder: (c) => FractionallySizedBox(
      heightFactor: 0.9,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
        child: ProductBrowser(
          autofocus: true,
          showCost: showCost,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          onPick: (p) => Navigator.pop(c, p),
          onCrear: permitirCrear ? () => Navigator.pop(c, _crearNuevo) : null,
        ),
      ),
    ),
  );
  if (r is Product) return r;
  if (r == _crearNuevo && context.mounted) {
    return Navigator.push<Product>(context, MaterialPageRoute(builder: (_) => const ProductFormScreen(desdeCompra: true)));
  }
  return null;
}
