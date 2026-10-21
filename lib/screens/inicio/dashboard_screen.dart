import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/reports.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/report_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';
import '../ventas/sales_screen.dart';
import '../ventas/ventas_hoy.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hoy = fechaLarga.format(DateTime.now());
    final nombre = context.select<AuthProvider, String?>((a) => a.nombre);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(nombre == null ? 'Inicio' : 'Bienvenido $nombre', maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${hoy[0].toUpperCase()}${hoy.substring(1)}', style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
      body: ReloadingFuture<DashboardData>(
        contexto: 'dashboard',
        load: () => context.read<ReportRepository>().dashboard(),
        builder: (context, d, reload) => RefreshIndicator(
          onRefresh: reload,
          child: LayoutBuilder(builder: (context, c) {
            final twoCols = c.maxWidth >= 860;
            final left = [
              _TodayHero(d: d),
              // Cada venta de hoy (se reinicia a las 00:00).
              SectionTitle(
                'Ventas de hoy',
                trailing: TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesScreen())),
                  child: const Text('Ver todo'),
                ),
              ),
              const VentasHoyPanel(embebido: true),
              const SizedBox(height: 12),
              _PeriodRow(d: d),
              const SizedBox(height: 12),
              _MonthCompare(d: d),
              const SectionTitle('Evolución de 12 meses'),
              _MonthlyBars(series: d.series),
              const SectionTitle('Cobros del mes'),
              _PaymentsCard(p: d.payments),
            ];
            final right = [
              // El inventario (invertido, agotados) se ve en la pestaña Inventario, no en el inicio.
              if (!twoCols)
                const SectionTitle('Por categoría (este mes)')
              else
                const SectionTitle('Por categoría (este mes)', padding: EdgeInsets.fromLTRB(4, 0, 4, 10)),
              _CategoryCard(items: d.byCategory),
              const SectionTitle('Más vendidos (este mes)'),
              _TopProducts(items: d.topProducts),
            ];
            if (twoCols) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
                    const SizedBox(width: 20),
                    Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
                  ],
                ),
              );
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [...left, ...right],
            );
          }),
        ),
      ),
    );
  }
}

class _TodayHero extends StatelessWidget {
  const _TodayHero({required this.d});
  final DashboardData d;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(right: -18, bottom: -24, child: Icon(Icons.foundation_rounded, size: 150, color: Colors.white.withValues(alpha: 0.05))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('VENDIDO HOY', style: TextStyle(color: AppColors.yellow, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 12.5)),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(gs(d.today.sales),
                      style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800, height: 1.05, fontFeatures: [FontFeature.tabularFigures()])),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 18,
                  runSpacing: 6,
                  children: [
                    _heroStat(Icons.trending_up_rounded, 'Ganancia', gs(d.today.profit)),
                    _heroStat(Icons.receipt_long_rounded, 'Ventas', '${d.today.count}'),
                  ],
                ),
                // Gastos de hoy y lo que queda de verdad (ganancia − gastos).
                if (d.today.expenses > 0) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 18,
                    runSpacing: 6,
                    children: [
                      _heroStat(Icons.request_quote_outlined, 'Gastos', '− ${gs(d.today.expenses)}'),
                      _heroStat(Icons.savings_outlined, 'Ganancia real', _conSigno(d.today.realProfit)),
                    ],
                  ),
                ],
                // Cuánto entró hoy en cada forma de pago (los mixtos se reparten).
                const SizedBox(height: 10),
                Wrap(
                  spacing: 18,
                  runSpacing: 6,
                  children: [
                    _heroStat(Icons.payments_outlined, 'Efectivo', gs(d.paymentsToday.efectivo)),
                    _heroStat(Icons.account_balance_outlined, 'Transferencia', gs(d.paymentsToday.transferencia)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _conSigno(int v) => v < 0 ? '− ${gs(-v)}' : gs(v);

  Widget _heroStat(IconData icon, String label, String value) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.yellow),
          const SizedBox(width: 6),
          Text('$label ', style: const TextStyle(color: Colors.white60, fontSize: 14)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
        ],
      );
}

class _PeriodRow extends StatelessWidget {
  const _PeriodRow({required this.d});
  final DashboardData d;

  @override
  Widget build(BuildContext context) {
    final items = [('Semana', d.week), ('Mes', d.month), ('Año', d.year)];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(items[i].$1.toUpperCase(), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.muted)),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(miles(items[i].$2.sales), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('+${miles(items[i].$2.profit)} ganancia', style: const TextStyle(fontSize: 12.5, color: AppColors.green, fontWeight: FontWeight.w600)),
                    ),
                    if (items[i].$2.expenses > 0) ...[
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text('−${miles(items[i].$2.expenses)} gastos', style: const TextStyle(fontSize: 12.5, color: AppColors.red, fontWeight: FontWeight.w600)),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '= ${items[i].$2.realProfit < 0 ? '−' : ''}${miles(items[i].$2.realProfit.abs())} real',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MonthCompare extends StatelessWidget {
  const _MonthCompare({required this.d});
  final DashboardData d;

  @override
  Widget build(BuildContext context) {
    final pct = d.monthChangePct;
    final up = (pct ?? 0) >= 0;
    final color = up ? AppColors.green : AppColors.red;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Este mes vs. el anterior', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('${gs(d.month.sales)}  ·  antes ${gs(d.prevMonth.sales)}', style: const TextStyle(color: AppColors.muted)),
                ],
              ),
            ),
            if (pct == null)
              const Pill('Sin datos previos', color: AppColors.muted)
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 18, color: color),
                    Text('${pct.abs().toStringAsFixed(1)}%', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MonthlyBars extends StatelessWidget {
  const _MonthlyBars({required this.series});
  final List<MonthPoint> series;

  @override
  Widget build(BuildContext context) {
    final max = series.fold<int>(0, (a, p) => p.sales > a ? p.sales : a);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
        child: Column(
          children: [
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < series.length; i++)
                    Expanded(
                      child: Tooltip(
                        message: '${mesAnio.format(series[i].month)}\nVendido ${gs(series[i].sales)}\nGanancia ${gs(series[i].profit)}',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _Bar(
                            sales: series[i].sales,
                            profit: series[i].profit,
                            max: max,
                            current: i == series.length - 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final p in series)
                  Expanded(
                    child: Text(mesCorto.format(p.month).replaceAll('.', ''),
                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Legend(color: Color(0xFFD8D3C8), label: 'Vendido'),
                SizedBox(width: 16),
                _Legend(color: AppColors.ink, label: 'Ganancia'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.sales, required this.profit, required this.max, required this.current});
  final int sales;
  final int profit;
  final int max;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final h = c.maxHeight;
      final sh = max == 0 ? 0.0 : (sales / max * h).clamp(sales > 0 ? 3.0 : 0.0, h);
      final ph = max == 0 ? 0.0 : (profit.clamp(0, sales) / max * h).clamp(0.0, h);
      return Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            height: sh,
            decoration: BoxDecoration(
              color: current ? AppColors.yellow : const Color(0xFFD8D3C8),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ),
          Container(
            height: ph,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: const BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.vertical(top: Radius.circular(3))),
          ),
        ],
      );
    });
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
        ],
      );
}

class _PaymentsCard extends StatelessWidget {
  const _PaymentsCard({required this.p});
  final Payments p;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Efectivo', p.efectivo, AppColors.green, Icons.payments_outlined),
      ('Transferencia', p.transferencia, AppColors.blue, Icons.account_balance_outlined),
      if (p.qr > 0) ('QR', p.qr, AppColors.orange, Icons.qr_code_2_rounded),
    ];
    final total = p.total;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 12,
                child: total == 0
                    ? Container(color: AppColors.concrete)
                    : Row(children: [
                        for (final it in items)
                          if (it.$2 > 0) Expanded(flex: it.$2, child: Container(color: it.$3)),
                      ]),
              ),
            ),
            const SizedBox(height: 12),
            for (final it in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(it.$4, size: 20, color: it.$3),
                    const SizedBox(width: 10),
                    Expanded(child: Text(it.$1, style: const TextStyle(fontSize: 15))),
                    Text(gs(it.$2), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    SizedBox(
                      width: 52,
                      child: Text(total == 0 ? '' : '${(it.$2 / total * 100).round()}%',
                          textAlign: TextAlign.right, style: const TextStyle(color: AppColors.muted)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.items});
  final List<NamedAmount> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Todavía no hay ventas este mes.', style: TextStyle(color: AppColors.muted))));
    }
    final max = items.fold<int>(0, (a, e) => e.sales > a ? e.sales : a);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final it in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                        Text(gs(it.sales), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: max == 0 ? 0 : it.sales / max,
                        minHeight: 8,
                        backgroundColor: AppColors.concrete,
                        color: AppColors.yellow,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text('Ganancia ${gs(it.profit)}', style: const TextStyle(fontSize: 12.5, color: AppColors.green)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopProducts extends StatelessWidget {
  const _TopProducts({required this.items});
  final List<NamedAmount> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Todavía no hay ventas este mes.', style: TextStyle(color: AppColors.muted))));
    }
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(indent: 16, endIndent: 16),
            ListTile(
              leading: CircleAvatar(
                radius: 15,
                backgroundColor: i == 0 ? AppColors.yellow : AppColors.concrete,
                child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
              ),
              title: Text(items[i].name),
              subtitle: Text('${cantidad(items[i].quantity)} ${unidadPlural(items[i].unit ?? 'unidad', items[i].quantity)}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(gs(items[i].sales), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('+${miles(items[i].profit)}', style: const TextStyle(fontSize: 12.5, color: AppColors.green)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
