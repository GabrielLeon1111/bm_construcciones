import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/purchase.dart';
import '../../models/reports.dart';
import '../../models/sale.dart';
import '../../providers/settings_provider.dart';
import '../../repositories/purchase_repository.dart';
import '../../repositories/report_repository.dart';
import '../../repositories/sale_repository.dart';
import '../../security/registro_seguro.dart';
import '../../services/compartir.dart';
import '../../services/reporte_export.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';

enum _Preset { semana, mes, mesAnterior, rango }

class _Datos {
  const _Datos(this.report, this.sales, this.purchases);
  final SalesReport report;
  final List<Sale> sales;
  final List<Purchase> purchases;
}

/// Arqueo y reporte: elegir semana, mes o un rango y ver cuánto se invirtió,
/// vendió, costó lo vendido y se ganó, con la ganancia de cada producto.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  _Preset _preset = _Preset.mes;
  late DateTimeRange _range = _rangeFor(_Preset.mes);
  Future<_Datos>? _future;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTimeRange _rangeFor(_Preset p) {
    final now = DateTime.now();
    final hoy = DateTime(now.year, now.month, now.day);
    return switch (p) {
      _Preset.semana => DateTimeRange(start: hoy.subtract(Duration(days: hoy.weekday - 1)), end: hoy),
      _Preset.mes => DateTimeRange(start: DateTime(now.year, now.month, 1), end: hoy),
      _Preset.mesAnterior => DateTimeRange(start: DateTime(now.year, now.month - 1, 1), end: DateTime(now.year, now.month, 0)),
      _Preset.rango => _range,
    };
  }

  void _load() {
    final reports = context.read<ReportRepository>();
    final sales = context.read<SaleRepository>();
    final purchases = context.read<PurchaseRepository>();
    final r = _range;
    setState(() {
      _future = () async {
        final res = await Future.wait([
          reports.salesReport(r.start, r.end),
          sales.list(from: r.start, to: r.end, limit: 2000),
          purchases.list(from: r.start, to: r.end, limit: 1000),
        ]);
        return _Datos(res[0] as SalesReport, res[1] as List<Sale>, res[2] as List<Purchase>);
      }();
    });
  }

  Future<void> _select(_Preset p) async {
    if (p == _Preset.rango) {
      final now = DateTime.now();
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 3),
        lastDate: DateTime(now.year, now.month, now.day),
        initialDateRange: _range,
        helpText: 'Elegí el rango',
      );
      if (r == null) return;
      _range = r;
    } else {
      _range = _rangeFor(p);
    }
    _preset = p;
    _load();
  }

  Future<void> _export(_Datos d, {required bool excel, required bool share}) async {
    final key = '${excel ? 'x' : 'p'}${share ? 's' : 'd'}';
    setState(() => _busy = key);
    try {
      final negocio = context.read<SettingsProvider>().settings;
      final bytes = excel ? reporteExcel(d.report, d.sales, d.purchases) : await reportePdf(d.report, negocio, d.sales);
      final name = nombreReporte(d.report, excel ? 'xlsx' : 'pdf');
      const xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      if (share) {
        await compartirArchivo(bytes, name, texto: 'Reporte ${negocio.name}', mime: excel ? xlsxMime : 'application/pdf');
      } else {
        final path = await guardarArchivo(bytes, name, esPdf: !excel);
        if (path != null && mounted) showSnack(context, 'Guardado en Descargas');
      }
    } catch (e) {
      registrarError('exportarReporte', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e, 'No se pudo generar el archivo.'), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reportes y arqueo')),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final p in _Preset.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: p == _Preset.rango ? const Icon(Icons.date_range, size: 18) : null,
                      label: Text(switch (p) {
                        _Preset.semana => 'Esta semana',
                        _Preset.mes => 'Este mes',
                        _Preset.mesAnterior => 'Mes anterior',
                        _Preset.rango => 'Elegir fechas',
                      }),
                      selected: _preset == p,
                      onSelected: (_) => _select(p),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.muted),
                const SizedBox(width: 6),
                Text('${fechaCorta.format(_range.start)} al ${fechaCorta.format(_range.end)}', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<_Datos>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (snap.hasError) {
                  registrarError('reporte', snap.error!);
                  return ErrorRetry(message: mensajeErrorSeguro(snap.error!, 'Revisá tu conexión.'), onRetry: _load);
                }
                final d = snap.data!;
                final r = d.report;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      children: [
                        GridView.count(
                          crossAxisCount: MediaQuery.sizeOf(context).width >= 700 ? 3 : 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.7,
                          children: [
                            _Kpi('Invertido en compras', r.invested, Icons.local_shipping_outlined, sub: '${r.purchasesCount} compras'),
                            _Kpi('Vendido', r.sales, Icons.point_of_sale_outlined, sub: '${r.count} ventas'),
                            _Kpi('Costo de lo vendido', r.cost, Icons.inventory_2_outlined),
                            _Kpi('Ganancia de ventas', r.profit, Icons.trending_up_rounded,
                                sub: r.marginPct == null ? null : 'margen ${r.marginPct!.toStringAsFixed(1)}%'),
                            _Kpi('Gastos del negocio', r.expenses.total, Icons.request_quote_outlined,
                                sub: '${r.expenses.count} ${r.expenses.count == 1 ? 'gasto' : 'gastos'}', negativo: true),
                            _Kpi('Ganancia real', r.realProfit, Icons.savings_outlined,
                                dark: true, sub: r.damaged > 0 ? 'ganancia − gastos − averiados' : 'ganancia − gastos'),
                          ],
                        ),
                        if (r.damaged > 0)
                          Container(
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(10)),
                            child: Text(
                              'Pérdida por averiados: ${gs(r.damaged)} (ya restada de la ganancia real)',
                              style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w700),
                            ),
                          ),
                        if (r.discounts > 0 || r.voidedCount > 0 || r.returned > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              [
                                if (r.returned > 0) 'Devoluciones: ${gs(r.returned)} (ya descontadas)',
                                if (r.discounts > 0) 'Descuentos dados: ${gs(r.discounts)}',
                                if (r.voidedCount > 0) '${r.voidedCount} ventas anuladas (no suman)',
                              ].join(' · '),
                              style: const TextStyle(color: AppColors.muted),
                            ),
                          ),
                        if (r.expenses.porCategoria.isNotEmpty) ...[
                          const SectionTitle('Gastos por categoría'),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  for (final c in r.expenses.porCategoria) KeyValueRow('${c.category} (${c.count})', gs(c.amount)),
                                  const Divider(height: 18),
                                  KeyValueRow('Total de gastos', gs(r.expenses.total), bold: true, valueColor: AppColors.red),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SectionTitle('Arqueo: cobros por método'),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                KeyValueRow('Efectivo', gs(r.payments.efectivo)),
                                KeyValueRow('Transferencia', gs(r.payments.transferencia)),
                                if (r.payments.qr > 0) KeyValueRow('QR', gs(r.payments.qr)),
                                const Divider(height: 18),
                                KeyValueRow('Total cobrado', gs(r.payments.total), bold: true),
                              ],
                            ),
                          ),
                        ),
                        const SectionTitle('Ganancia por producto'),
                        if (r.products.isEmpty)
                          const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Sin ventas en este período.', style: TextStyle(color: AppColors.muted))))
                        else
                          Card(
                            child: Column(
                              children: [
                                for (var i = 0; i < r.products.length; i++) ...[
                                  if (i > 0) const Divider(indent: 16, endIndent: 16),
                                  ListTile(
                                    title: Text(r.products[i].name),
                                    subtitle: Text(
                                        '${cantidad(r.products[i].quantity)} ${unidadPlural(r.products[i].unit ?? 'unidad', r.products[i].quantity)} · vendido ${gs(r.products[i].sales)} · costo ${gs(r.products[i].cost)}'),
                                    trailing: Text(gs(r.products[i].profit),
                                        style: TextStyle(fontWeight: FontWeight.w800, color: r.products[i].profit >= 0 ? AppColors.green : AppColors.red)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        const SectionTitle('Exportar'),
                        Row(
                          children: [
                            Expanded(child: _exportBtn(d, excel: false, share: true, icon: Icons.picture_as_pdf_outlined, label: 'PDF · Compartir')),
                            const SizedBox(width: 10),
                            Expanded(child: _exportBtn(d, excel: false, share: false, icon: Icons.download_rounded, label: 'PDF · Descargar')),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _exportBtn(d, excel: true, share: true, icon: Icons.table_chart_outlined, label: 'Excel · Compartir')),
                            const SizedBox(width: 10),
                            Expanded(child: _exportBtn(d, excel: true, share: false, icon: Icons.download_rounded, label: 'Excel · Descargar')),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _exportBtn(_Datos d, {required bool excel, required bool share, required IconData icon, required String label}) {
    final key = '${excel ? 'x' : 'p'}${share ? 's' : 'd'}';
    return OutlinedButton.icon(
      onPressed: _busy != null ? null : () => _export(d, excel: excel, share: share),
      icon: _busy == key ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon),
      label: Text(label),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.icon, {this.sub, this.dark = false, this.negativo = false});
  final String label;
  final int value;
  final IconData icon;
  final String? sub;
  final bool dark;

  /// Se muestra en rojo con signo menos (gastos).
  final bool negativo;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : AppColors.ink;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? AppColors.ink : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: dark ? AppColors.ink : AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: dark ? AppColors.yellow : AppColors.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: dark ? AppColors.yellow : AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              negativo && value > 0 ? '− ${gs(value)}' : (value < 0 ? '− ${gs(-value)}' : gs(value)),
              style: TextStyle(color: negativo && value > 0 ? AppColors.red : (value < 0 && !dark ? AppColors.red : fg), fontWeight: FontWeight.w800, fontSize: 20),
            ),
          ),
          if (sub != null) Text(sub!, style: TextStyle(color: dark ? Colors.white60 : AppColors.muted, fontSize: 12)),
        ],
      ),
    );
  }
}
