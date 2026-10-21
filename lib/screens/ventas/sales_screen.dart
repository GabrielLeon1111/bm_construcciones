import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/sale.dart';
import '../../providers/catalog_provider.dart';
import '../../repositories/sale_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';
import 'sale_detail_screen.dart';
import 'ventas_hoy.dart';

enum _Rango { hoy, semana, mes, todo }

/// Ventas: lo vendido HOY en una tabla (se reinicia a las 00:00).
/// Las de días anteriores están en "Historial".
class SalesScreen extends StatelessWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Ventas de hoy'),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesHistoryScreen())),
          icon: const Icon(Icons.history_rounded),
          label: const Text('Historial'),
        ),
      ],
    ),
    body: const VentasHoyPanel(),
  );
}

/// Historial de ventas de otros días: para reimprimir o anular.
class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  _Rango _rango = _Rango.semana;
  String _q = '';
  final _key = GlobalKey<ReloadingFutureState<List<Sale>>>();

  DateTime? get _from {
    final now = DateTime.now();
    return switch (_rango) {
      _Rango.hoy => now,
      _Rango.semana => now.subtract(const Duration(days: 6)),
      _Rango.mes => DateTime(now.year, now.month, 1),
      _Rango.todo => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de ventas')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por cliente, N° o material'),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final r in _Rango.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(switch (r) { _Rango.hoy => 'Hoy', _Rango.semana => '7 días', _Rango.mes => 'Este mes', _Rango.todo => 'Todas' }),
                      selected: _rango == r,
                      onSelected: (_) {
                        setState(() => _rango = r);
                        _key.currentState?.reload();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ReloadingFuture<List<Sale>>(
              key: _key,
              contexto: 'listaVentas',
              load: () => context.read<SaleRepository>().list(from: _from, limit: _rango == _Rango.todo ? 500 : 300),
              builder: (context, sales, reload) {
                final list = _q.isEmpty
                    ? sales
                    : sales.where((s) => coincide('${s.number} ${nroDoc(s.number)} ${s.clientName ?? ''} ${s.items.map((i) => i.description).join(' ')}', _q)).toList();
                final active = list.where((s) => !s.isVoided);
                final total = active.fold<int>(0, (a, s) => a + s.netTotal);
                if (list.isEmpty) {
                  return const EmptyState(icon: Icons.receipt_long_outlined, title: 'No hay ventas en este período');
                }
                return RefreshIndicator(
                  onRefresh: reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: list.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      if (i == 0) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                          child: Text('${active.length} ventas · ${gs(total)}', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
                        );
                      }
                      return SaleTile(sale: list[i - 1]);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SaleTile extends StatelessWidget {
  const SaleTile({super.key, required this.sale});
  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final s = sale;
    final resumen = s.items.map((i) => i.description).take(3).join(', ') + (s.items.length > 3 ? '…' : '');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: s.id))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Column(
                children: [
                  Text(hora.format(s.createdAt), style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(fechaCorta.format(s.createdAt).substring(0, 5), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('N° ${nroDoc(s.number)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        if (s.isVoided) const Pill('Anulada', color: AppColors.red),
                      ],
                    ),
                    Text(s.clientName ?? 'Sin nombre', style: const TextStyle(fontSize: 14)),
                    Text(resumen, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(gs(s.netTotal),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                        decoration: s.isVoided ? TextDecoration.lineThrough : null,
                        color: s.isVoided ? AppColors.muted : AppColors.ink,
                      )),
                  Text(metodoPagoTexto(s.paymentMethod), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
