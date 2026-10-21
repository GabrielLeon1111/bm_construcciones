import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../models/stock_movement.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/product_repository.dart';
import '../../repositories/purchase_repository.dart';
import '../../repositories/sale_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/client_picker.dart';
import '../../widgets/common.dart';
import '../compras/purchase_detail_screen.dart';
import '../compras/purchase_form_screen.dart';
import '../ventas/sale_detail_screen.dart';
import 'adjust_stock_sheet.dart';
import 'damaged_sheet.dart';
import 'product_detail_screen.dart';
import 'product_form_screen.dart';

const estiloEncabezadoTabla = TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 13);
const estiloNumerosTabla = TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontSize: 14);

/// Tabla con scroll horizontal (en el celular se desliza de costado, nada queda apretado).
/// En pantallas anchas ocupa todo el ancho; en angostas se desliza.
Widget tablaDeslizable(Widget tabla) => Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(constraints: BoxConstraints(minWidth: c.maxWidth), child: tabla),
        ),
      ),
    );

/// Etiqueta de estado con color (Disponible, Por agotarse, Agotado...).
class EtiquetaEstado extends StatelessWidget {
  const EtiquetaEstado(this.texto, this.color, this.fondo, {super.key});
  final String texto;
  final Color color;
  final Color fondo;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(20)),
        child: Text(texto, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      );
}

EtiquetaEstado _estadoProducto(Product p) {
  if (!p.active) return const EtiquetaEstado('Inactivo', AppColors.muted, AppColors.concrete);
  if (p.soldByLoad) return const EtiquetaEstado('Por carga', AppColors.blue, AppColors.blueSoft);
  if (p.isOut) return const EtiquetaEstado('Agotado', AppColors.red, AppColors.redSoft);
  if (p.isLow) return const EtiquetaEstado('Por agotarse', AppColors.orange, AppColors.orangeSoft);
  return const EtiquetaEstado('Disponible', AppColors.green, Color(0xFFE6F4EA));
}

// ======================================================================
//  PRODUCTOS
// ======================================================================

/// Tabla de productos: Producto, Marca, Categoría, Stock, Costo prom., Precio venta,
/// Valorizado, Estado y Acciones. Con casillas para activar/desactivar varios a la vez.
class ProductsTable extends StatefulWidget {
  const ProductsTable({super.key, required this.products});
  final List<Product> products;

  @override
  State<ProductsTable> createState() => _ProductsTableState();
}

class _ProductsTableState extends State<ProductsTable> {
  final Set<String> _sel = {};

  Future<void> _refrescar() async {
    await context.read<CatalogProvider>().cargarProductos();
    if (mounted) context.read<RefreshBus>().changed();
  }

  void _abrir(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w)).then((_) => _refrescar());

  Future<void> _accion(String a, Product p) async {
    final repo = context.read<ProductRepository>();
    switch (a) {
      case 'detalle':
        _abrir(ProductDetailScreen(productId: p.id));
      case 'editar':
        _abrir(ProductFormScreen(product: p));
      case 'compra':
        _abrir(PurchaseFormScreen(initialProduct: p));
      case 'ajustar':
        if (await showAdjustStockSheet(context, p)) await _refrescar();
      case 'averiados':
        if (await showDamagedSheet(context, p)) await _refrescar();
      case 'activo':
        await runSafe(context, 'activarProducto', () async {
          await repo.setActive(p.id, !p.active);
          await _refrescar();
        }, ok: p.active ? 'Producto desactivado: ya no aparece para vender' : 'Producto activado');
    }
  }

  Future<void> _masivo(bool activar) async {
    final ids = _sel.toList();
    final ok = await confirmar(
      context,
      titulo: activar ? 'Activar productos' : 'Desactivar productos',
      mensaje: activar
          ? 'Se activan ${ids.length} productos: vuelven a aparecer para vender.'
          : 'Se desactivan ${ids.length} productos: dejan de aparecer para vender (no se borra nada).',
      si: activar ? 'Activar' : 'Desactivar',
    );
    if (!ok || !mounted) return;
    final repo = context.read<ProductRepository>();
    await runSafe(context, 'masivoProductos', () async {
      for (final id in ids) {
        await repo.setActive(id, activar);
      }
      setState(_sel.clear);
      await _refrescar();
    }, ok: activar ? 'Productos activados' : 'Productos desactivados');
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.products;
    _sel.removeWhere((id) => !list.any((p) => p.id == id));
    // Arena, piedra bruta: cuántas cargas quedan (lo comprado menos lo vendido).
    final catalogo = context.watch<CatalogProvider>();
    double cargas(String id) => catalogo.cargasDe(id) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_sel.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Expanded(child: Text('${_sel.length} seleccionados', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                TextButton(onPressed: () => _masivo(true), child: const Text('Activar', style: TextStyle(color: AppColors.yellow))),
                TextButton(onPressed: () => _masivo(false), child: const Text('Desactivar', style: TextStyle(color: AppColors.yellow))),
                IconButton(onPressed: () => setState(_sel.clear), icon: const Icon(Icons.close, color: Colors.white70)),
              ],
            ),
          ),
        tablaDeslizable(
          DataTable(
            headingRowColor: const WidgetStatePropertyAll(Color(0xFFF1F3EC)),
            headingTextStyle: estiloEncabezadoTabla,
            dataRowMinHeight: 56,
            dataRowMaxHeight: 64,
            columnSpacing: 28,
            showCheckboxColumn: true,
            columns: const [
              DataColumn(label: Text('Producto')),
              DataColumn(label: Text('Marca')),
              DataColumn(label: Text('Categoría')),
              DataColumn(label: Text('Stock'), numeric: true),
              DataColumn(label: Text('Costo prom.'), numeric: true),
              DataColumn(label: Text('Precio venta'), numeric: true),
              DataColumn(label: Text('Valorizado'), numeric: true),
              DataColumn(label: Text('Estado')),
              DataColumn(label: Text('Acciones')),
            ],
            rows: [
              for (final p in list)
                DataRow(
                  selected: _sel.contains(p.id),
                  onSelectChanged: (v) => setState(() => v == true ? _sel.add(p.id) : _sel.remove(p.id)),
                  cells: [
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                      ),
                      onTap: () => _accion('detalle', p),
                    ),
                    DataCell(Text(p.brand ?? '—')),
                    DataCell(Text(p.category)),
                    DataCell(
                      p.soldByLoad
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(cantidad(cargas(p.id)), style: estiloNumerosTabla.copyWith(fontWeight: FontWeight.w800)),
                                Text(unidadPlural('carga', cargas(p.id)), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(cantidad(p.stock), style: estiloNumerosTabla.copyWith(fontWeight: FontWeight.w800)),
                                Text(unidadPlural(p.unit, p.stock), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                              ],
                            ),
                    ),
                    DataCell(Text(p.soldByLoad || p.avgCost == 0 ? '—' : gs(p.avgCost), style: estiloNumerosTabla)),
                    DataCell(Text(p.salePrice == 0 ? '—' : gs(p.salePrice), style: estiloNumerosTabla)),
                    DataCell(Text(p.soldByLoad ? '—' : gs(p.capital), style: estiloNumerosTabla)),
                    DataCell(_estadoProducto(p)),
                    DataCell(
                      PopupMenuButton<String>(
                        tooltip: 'Acciones',
                        icon: const Icon(Icons.more_horiz),
                        onSelected: (a) => _accion(a, p),
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'detalle', child: Text('Ver detalle')),
                          const PopupMenuItem(value: 'editar', child: Text('Editar')),
                          PopupMenuItem(value: 'compra', child: Text(p.soldByLoad ? 'Llegó una carga' : 'Cargar compra')),
                          if (!p.soldByLoad) const PopupMenuItem(value: 'ajustar', child: Text('Ajustar stock')),
                          if (!p.soldByLoad) const PopupMenuItem(value: 'averiados', child: Text('Averiados')),
                          PopupMenuItem(value: 'activo', child: Text(p.active ? 'Desactivar' : 'Activar')),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ======================================================================
//  MOVIMIENTOS
// ======================================================================

/// Colores por tipo de movimiento.
(Color, Color) _colorTipo(String tipo) => switch (tipo) {
      'venta' => (AppColors.blue, AppColors.blueSoft),
      'compra' => (AppColors.green, const Color(0xFFE6F4EA)),
      'ajuste' => (AppColors.orange, AppColors.orangeSoft),
      _ => (AppColors.red, AppColors.redSoft),
    };

/// Tabla de movimientos: Producto, Fecha, Cantidad, Tipo, Costo nuevo/anterior,
/// Stock nuevo/anterior, Total nuevo/anterior, Promedio actual, Precio venta y Acciones
/// (Ver detalle, Asociar cliente, Anular).
class MovementsTable extends StatelessWidget {
  const MovementsTable({super.key, required this.movements, required this.onChanged});
  final List<StockMovement> movements;
  final Future<void> Function() onChanged;

  Future<void> _accion(BuildContext context, String a, StockMovement m) async {
    switch (a) {
      case 'detalle':
        final Widget destino = m.saleId != null
            ? SaleDetailScreen(saleId: m.saleId!)
            : m.purchaseId != null
            ? PurchaseDetailScreen(purchaseId: m.purchaseId!)
            : ProductDetailScreen(productId: m.productId);
        await Navigator.push(context, MaterialPageRoute(builder: (_) => destino));
        await onChanged();
      case 'cliente':
        final pick = await pickClient(context);
        if (pick == null || !context.mounted) return;
        await runSafe(context, 'asociarCliente', () async {
          await context.read<SaleRepository>().setClient(m.saleId!, pick.client?.id);
          await onChanged();
        }, ok: pick.client == null ? 'La venta quedó sin cliente' : 'Cliente asociado: ${pick.client!.fullName}');
      case 'anular':
        final esVenta = m.saleId != null;
        final motivo = await pedirMotivo(
          context,
          titulo: esVenta ? 'Anular venta' : 'Anular compra',
          ayuda: esVenta
              ? 'Se anula toda la venta: el stock vuelve y deja de contar en las ganancias. Queda en el historial.'
              : 'Se anula toda la compra: el stock que entró se descuenta. Queda en el historial.',
        );
        if (motivo == null || !context.mounted) return;
        await runSafe(context, 'anularDesdeMovimiento', () async {
          if (esVenta) {
            await context.read<SaleRepository>().voidSale(m.saleId!, motivo);
          } else {
            await context.read<PurchaseRepository>().voidPurchase(m.purchaseId!, motivo);
          }
          if (!context.mounted) return;
          await context.read<CatalogProvider>().cargarProductos();
          if (context.mounted) context.read<RefreshBus>().changed();
          await onChanged();
        }, ok: esVenta ? 'Venta anulada' : 'Compra anulada');
    }
  }

  @override
  Widget build(BuildContext context) {
    String costo(int? v) => v == null || v == 0 ? '—' : gs(v);
    return tablaDeslizable(
      DataTable(
        headingRowColor: const WidgetStatePropertyAll(Color(0xFFF1F3EC)),
        headingTextStyle: estiloEncabezadoTabla,
        dataRowMinHeight: 52,
        dataRowMaxHeight: 60,
        columnSpacing: 26,
        columns: const [
          DataColumn(label: Text('Producto')),
          DataColumn(label: Text('Fecha')),
          DataColumn(label: Text('Cantidad'), numeric: true),
          DataColumn(label: Text('Tipo')),
          DataColumn(label: Text('Costo nuevo'), numeric: true),
          DataColumn(label: Text('Costo anterior'), numeric: true),
          DataColumn(label: Text('Stock nuevo'), numeric: true),
          DataColumn(label: Text('Stock anterior'), numeric: true),
          DataColumn(label: Text('Total nuevo'), numeric: true),
          DataColumn(label: Text('Total anterior'), numeric: true),
          DataColumn(label: Text('Promedio actual'), numeric: true),
          DataColumn(label: Text('Precio venta'), numeric: true),
          DataColumn(label: Text('Acciones')),
        ],
        rows: [
          for (final m in movements)
            () {
              final (color, fondo) = _colorTipo(m.type);
              final cambioCosto = m.avgCostBefore != m.avgCostAfter;
              final precio = m.unitPrice ?? m.productSalePrice;
              return DataRow(
                cells: [
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(m.productName ?? '—', style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  DataCell(Text(DateFormatoCorto.fecha(m.createdAt))),
                  DataCell(Text(
                    '${m.isEntry ? '+' : '−'}${cantidad(m.quantity.abs())}',
                    style: estiloNumerosTabla.copyWith(fontWeight: FontWeight.w800, color: m.isEntry ? AppColors.green : AppColors.blue),
                  )),
                  DataCell(EtiquetaEstado(m.typeLabel, color, fondo)),
                  DataCell(Text(cambioCosto ? costo(m.avgCostAfter) : '—', style: estiloNumerosTabla)),
                  DataCell(Text(cambioCosto ? costo(m.avgCostBefore) : '—', style: estiloNumerosTabla)),
                  DataCell(Text(cantidad(m.stockAfter), style: estiloNumerosTabla)),
                  DataCell(Text(cantidad(m.stockBefore), style: estiloNumerosTabla)),
                  DataCell(Text(gs((m.stockAfter * m.avgCostAfter).round()), style: estiloNumerosTabla)),
                  DataCell(Text(gs((m.stockBefore * m.avgCostBefore).round()), style: estiloNumerosTabla)),
                  DataCell(Text(costo(m.productAvgCost), style: estiloNumerosTabla)),
                  DataCell(Text(costo(precio), style: estiloNumerosTabla)),
                  DataCell(
                    PopupMenuButton<String>(
                      tooltip: 'Acciones',
                      icon: const Icon(Icons.more_vert),
                      onSelected: (a) => _accion(context, a, m),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'detalle', child: Text('Ver detalle')),
                        if (m.saleId != null && m.type == 'venta') const PopupMenuItem(value: 'cliente', child: Text('Asociar cliente')),
                        if ((m.saleId != null && m.type == 'venta') || (m.purchaseId != null && m.type == 'compra'))
                          const PopupMenuItem(value: 'anular', child: Text('Anular', style: TextStyle(color: AppColors.red))),
                      ],
                    ),
                  ),
                ],
              );
            }(),
        ],
      ),
    );
  }
}

/// Fecha corta para tablas: 16/10/26.
abstract final class DateFormatoCorto {
  static String fecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${(d.year % 100).toString().padLeft(2, '0')}';
}
