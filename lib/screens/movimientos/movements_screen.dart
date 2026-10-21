import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/stock_movement.dart';
import '../../providers/catalog_provider.dart';
import '../../repositories/movement_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';
import '../compras/purchase_detail_screen.dart';
import '../inventario/inventory_tables.dart';
import '../ventas/sale_detail_screen.dart';

/// Historial de movimientos (desde "Más"): la misma tabla que en Inventario.
class MovementsScreen extends StatelessWidget {
  const MovementsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Movimientos')),
    body: const MovementsPanel(),
  );
}

/// Panel de movimientos: buscador, filtro por tipo y tabla con cada entrada,
/// salida o ajuste (cantidad, costos, stock y totales antes y después).
class MovementsPanel extends StatefulWidget {
  const MovementsPanel({super.key});

  @override
  State<MovementsPanel> createState() => _MovementsPanelState();
}

class _MovementsPanelState extends State<MovementsPanel> {
  String? _type;
  String _q = '';
  final _key = GlobalKey<ReloadingFutureState<List<StockMovement>>>();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por producto o motivo'),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('Todos'),
                  selected: _type == null,
                  onSelected: (_) {
                    setState(() => _type = null);
                    _key.currentState?.reload();
                  },
                ),
              ),
              for (final e in tiposMovimiento.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: _type == e.key,
                    onSelected: (_) {
                      setState(() => _type = e.key);
                      _key.currentState?.reload();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ReloadingFuture<List<StockMovement>>(
            key: _key,
            contexto: 'movimientos',
            load: () => context.read<MovementRepository>().list(type: _type),
            builder: (context, movs, reload) {
              final list = _q.isEmpty ? movs : movs.where((m) => coincide('${m.productName ?? ''} ${m.reason ?? ''} ${m.typeLabel}', _q)).toList();
              if (list.isEmpty) return const EmptyState(icon: Icons.swap_vert_rounded, title: 'Sin movimientos');
              return RefreshIndicator(
                onRefresh: reload,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [MovementsTable(movements: list, onChanged: reload)],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class MovementTile extends StatelessWidget {
  const MovementTile({super.key, required this.m, required this.unit, this.showProduct = true});
  final StockMovement m;
  final String unit;
  final bool showProduct;

  (IconData, Color) get _style => switch (m.type) {
    'compra' => (Icons.south_west_rounded, AppColors.green),
    'venta' => (Icons.north_east_rounded, AppColors.blue),
    'ajuste' => (Icons.tune_rounded, AppColors.orange),
    'averia' => (Icons.heart_broken_outlined, AppColors.red),
    _ => (Icons.undo_rounded, AppColors.red),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _style;
    final qty = '${m.isEntry ? '+' : '−'}${cantidad(m.quantity.abs())}';
    final detalle = <String>[
      fechaHora.format(m.createdAt),
      'stock ${cantidad(m.stockBefore)} → ${cantidad(m.stockAfter)}',
      if (m.type == 'compra' && m.unitCost != null) 'costo ${gs(m.unitCost!)}',
      if (m.type == 'averia' && m.unitCost != null) 'pérdida ${gs((m.quantity.abs() * m.unitCost!).round())}',
      if (m.type == 'venta' && m.unitPrice != null) 'precio ${gs(m.unitPrice!)}',
      if (m.avgCostBefore != m.avgCostAfter) 'promedio ${miles(m.avgCostBefore)} → ${miles(m.avgCostAfter)}',
    ].join(' · ');

    return ListTile(
      onTap: m.saleId != null
          ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: m.saleId!)))
          : m.purchaseId != null
          ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseDetailScreen(purchaseId: m.purchaseId!)))
          : null,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(showProduct ? (m.productName ?? 'Producto') : m.typeLabel),
      subtitle: Text([if (showProduct) m.typeLabel, detalle, if (m.reason != null) 'Motivo: ${m.reason}'].join('\n')),
      isThreeLine: true,
      trailing: Text(
        qty,
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: m.isEntry ? AppColors.green : AppColors.red),
      ),
    );
  }
}
