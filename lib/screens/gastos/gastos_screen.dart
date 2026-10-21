import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/gasto.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/gasto_repository.dart';
import '../../security/registro_seguro.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../utils/validacion.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';

enum _Periodo { hoy, semana, mes, mesAnterior, rango }

/// Gastos del negocio (solo administrador): alquiler, sueldos, flete, luz, combustible...
/// Se ven por día, semana o mes, con el total por categoría, y se filtran por categoría.
/// Los gastos se restan de la ganancia en Reportes y en el Inicio (ganancia real).
class GastosScreen extends StatefulWidget {
  const GastosScreen({super.key});

  @override
  State<GastosScreen> createState() => _GastosScreenState();
}

class _GastosScreenState extends State<GastosScreen> {
  _Periodo _periodo = _Periodo.mes;
  late DateTimeRange _rango = _rangoDe(_Periodo.mes);
  String? _categoria;

  DateTimeRange _rangoDe(_Periodo p) {
    final now = DateTime.now();
    final hoy = DateTime(now.year, now.month, now.day);
    return switch (p) {
      _Periodo.hoy => DateTimeRange(start: hoy, end: hoy),
      _Periodo.semana => DateTimeRange(start: hoy.subtract(Duration(days: hoy.weekday - 1)), end: hoy),
      _Periodo.mes => DateTimeRange(start: DateTime(now.year, now.month, 1), end: hoy),
      _Periodo.mesAnterior => DateTimeRange(start: DateTime(now.year, now.month - 1, 1), end: DateTime(now.year, now.month, 0)),
      _Periodo.rango => _rango,
    };
  }

  String get _textoPeriodo => switch (_periodo) {
        _Periodo.hoy => 'Hoy',
        _Periodo.semana => 'Esta semana',
        _Periodo.mes => 'Este mes',
        _Periodo.mesAnterior => 'Mes anterior',
        _Periodo.rango => 'Fechas elegidas',
      };

  Future<void> _elegir(_Periodo p) async {
    if (p == _Periodo.rango) {
      final now = DateTime.now();
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 3),
        lastDate: DateTime(now.year, now.month, now.day),
        initialDateRange: _rango,
        helpText: 'Elegí el rango',
      );
      if (r == null) return;
      _rango = r;
    } else {
      _rango = _rangoDe(p);
    }
    setState(() => _periodo = p);
  }

  Future<void> _nuevo() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const GastoFormScreen()));
    if (ok == true && mounted) context.read<RefreshBus>().changed();
  }

  @override
  Widget build(BuildContext context) {
    final r = _rango;
    return Scaffold(
      appBar: AppBar(title: const Text('Gastos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevo,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Registrar gasto'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final p in _Periodo.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: p == _Periodo.rango ? const Icon(Icons.date_range, size: 18) : null,
                      label: Text(switch (p) {
                        _Periodo.hoy => 'Hoy',
                        _Periodo.semana => 'Semana',
                        _Periodo.mes => 'Mes',
                        _Periodo.mesAnterior => 'Mes anterior',
                        _Periodo.rango => 'Elegir fechas',
                      }),
                      selected: _periodo == p,
                      onSelected: (_) => _elegir(p),
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
                Flexible(
                  child: Text(
                    r.start == r.end ? fechaCorta.format(r.start) : '${fechaCorta.format(r.start)} al ${fechaCorta.format(r.end)}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReloadingFuture<List<Gasto>>(
              key: ValueKey(r),
              contexto: 'listaGastos',
              load: () => context.read<GastoRepository>().list(from: r.start, to: r.end),
              builder: (context, gastos, reload) => RefreshIndicator(onRefresh: reload, child: _contenido(gastos)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contenido(List<Gasto> gastos) {
    final resumen = GastosResumen.deLista(gastos);
    final cat = _categoria;
    final filtrados = cat == null ? gastos : gastos.where((g) => g.category == cat).toList();
    final totalFiltrado = filtrados.where((g) => !g.anulado).fold(0, (s, g) => s + g.amount);
    final variosDias = _rango.start != _rango.end;

    // Agrupados por día (el más nuevo primero), con el total de cada día.
    final porDia = <DateTime, List<Gasto>>{};
    for (final g in filtrados) {
      porDia.putIfAbsent(DateTime(g.spentAt.year, g.spentAt.month, g.spentAt.day), () => []).add(g);
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            _TotalGastos(
              titulo: 'Gastos · $_textoPeriodo',
              total: cat == null ? resumen.total : totalFiltrado,
              detalle: cat == null
                  ? '${resumen.count} ${resumen.count == 1 ? 'gasto' : 'gastos'}'
                  : 'Solo $cat · de ${gs(resumen.total)} en total',
            ),
            if (resumen.porCategoria.isNotEmpty) ...[
              const SectionTitle('Por categoría'),
              _PorCategoria(
                resumen: resumen,
                seleccionada: cat,
                onTap: (c) => setState(() => _categoria = _categoria == c ? null : c),
              ),
            ],
            SectionTitle(
              cat == null ? 'Detalle' : 'Detalle · $cat',
              trailing: cat == null
                  ? null
                  : TextButton.icon(
                      onPressed: () => setState(() => _categoria = null),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Ver todas'),
                    ),
            ),
            _FiltroCategorias(
              presentes: {for (final g in gastos) g.category},
              seleccionada: cat,
              onChanged: (c) => setState(() => _categoria = c),
            ),
            const SizedBox(height: 8),
            if (filtrados.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    cat == null ? 'No hay gastos en este período. Tocá "Registrar gasto" para cargar uno.' : 'No hay gastos de $cat en este período.',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
              )
            else
              for (final dia in porDia.entries) ...[
                if (variosDias)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(_tituloDia(dia.key), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.muted)),
                        ),
                        Text(
                          gs(dia.value.where((g) => !g.anulado).fold(0, (s, g) => s + g.amount)),
                          style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < dia.value.length; i++) ...[
                        if (i > 0) const Divider(indent: 64),
                        _GastoTile(gasto: dia.value[i], onTap: () => _verDetalle(dia.value[i])),
                      ],
                    ],
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }

  String _tituloDia(DateTime d) {
    final now = DateTime.now();
    final hoy = DateTime(now.year, now.month, now.day);
    final dif = hoy.difference(d).inDays;
    final f = fechaLarga.format(d);
    final txt = '${f[0].toUpperCase()}${f.substring(1)}';
    return dif == 0 ? 'Hoy · $txt' : (dif == 1 ? 'Ayer · $txt' : txt);
  }

  Future<void> _verDetalle(Gasto g) async {
    final anular = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _IconoCategoria(g.category),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(g.category, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  ),
                  if (g.anulado) const Pill('Anulado', color: AppColors.red, background: AppColors.redSoft),
                ],
              ),
              const SizedBox(height: 14),
              KeyValueRow('Monto', gs(g.amount), bold: true, big: true),
              KeyValueRow('Fecha y hora', fechaHora.format(g.spentAt)),
              if (g.description != null) KeyValueRow('Descripción', g.description!),
              KeyValueRow('N° de factura', g.invoiceNumber ?? '—'),
              KeyValueRow('Gasto N°', nroDoc(g.number)),
              if (g.createdByName != null) KeyValueRow('Cargado por', g.createdByName!),
              KeyValueRow('Cargado el', fechaHora.format(g.createdAt)),
              if (g.anulado) ...[
                KeyValueRow('Motivo de anulación', g.voidReason ?? '—', valueColor: AppColors.red),
                if (g.voidedAt != null) KeyValueRow('Anulado el', fechaHora.format(g.voidedAt!)),
              ],
              const SizedBox(height: 16),
              if (!g.anulado)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red)),
                  onPressed: () => Navigator.pop(c, true),
                  icon: const Icon(Icons.block_rounded),
                  label: const Text('Anular este gasto'),
                ),
            ],
          ),
        ),
      ),
    );
    if (anular != true || !mounted) return;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Anular gasto',
      ayuda: '${g.category} · ${gs(g.amount)}. Deja de restar en los reportes, pero queda en el historial.',
    );
    if (motivo == null || !mounted) return;
    await runSafe(context, 'anularGasto', () async {
      await context.read<GastoRepository>().anular(g.id, motivo);
      if (mounted) context.read<RefreshBus>().changed();
    }, ok: 'Gasto anulado');
  }
}

class _TotalGastos extends StatelessWidget {
  const _TotalGastos({required this.titulo, required this.total, required this.detalle});
  final String titulo;
  final int total;
  final String detalle;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo.toUpperCase(),
                style: const TextStyle(color: AppColors.yellow, fontWeight: FontWeight.w800, letterSpacing: 1.1, fontSize: 12.5)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(gs(total),
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
            ),
            const SizedBox(height: 2),
            Text(detalle, style: const TextStyle(color: Colors.white60)),
          ],
        ),
      );
}

/// Cuánto se gastó en cada categoría, con una barra. Tocar una filtra el detalle.
class _PorCategoria extends StatelessWidget {
  const _PorCategoria({required this.resumen, required this.seleccionada, required this.onTap});
  final GastosResumen resumen;
  final String? seleccionada;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final max = resumen.porCategoria.isEmpty ? 1 : resumen.porCategoria.first.amount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            for (final c in resumen.porCategoria)
              InkWell(
                onTap: () => onTap(c.category),
                child: Container(
                  color: seleccionada == c.category ? AppColors.yellowSoft : null,
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                  child: Row(
                    children: [
                      Icon(iconoGasto(c.category), size: 20, color: AppColors.ink),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text('${c.category} (${c.count})',
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                                const SizedBox(width: 8),
                                Text(gs(c.amount), style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                              ],
                            ),
                            const SizedBox(height: 5),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: max == 0 ? 0 : c.amount / max,
                                minHeight: 6,
                                backgroundColor: AppColors.concrete,
                                valueColor: const AlwaysStoppedAnimation(AppColors.yellow),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 40,
                        child: Text(
                          resumen.total == 0 ? '' : '${(c.amount / resumen.total * 100).round()}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Chips para filtrar el detalle por categoría (solo las que tienen gastos en el período).
class _FiltroCategorias extends StatelessWidget {
  const _FiltroCategorias({required this.presentes, required this.seleccionada, required this.onChanged});
  final Set<String> presentes;
  final String? seleccionada;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cats = [for (final c in categoriasGasto) if (presentes.contains(c.$1) || c.$1 == seleccionada) c];
    if (cats.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(label: const Text('Todas'), selected: seleccionada == null, onSelected: (_) => onChanged(null)),
          ),
          for (final c in cats)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(c.$2, size: 18),
                label: Text(c.$1),
                selected: seleccionada == c.$1,
                onSelected: (_) => onChanged(seleccionada == c.$1 ? null : c.$1),
              ),
            ),
        ],
      ),
    );
  }
}

class _IconoCategoria extends StatelessWidget {
  const _IconoCategoria(this.categoria, {this.apagado = false});
  final String categoria;
  final bool apagado;

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: apagado ? AppColors.concrete : AppColors.yellowSoft, borderRadius: BorderRadius.circular(10)),
        child: Icon(iconoGasto(categoria), color: apagado ? AppColors.muted : AppColors.ink),
      );
}

class _GastoTile extends StatelessWidget {
  const _GastoTile({required this.gasto, required this.onTap});
  final Gasto gasto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = gasto;
    final linea2 = [
      hora.format(g.spentAt),
      if (g.invoiceNumber != null) 'Fact. ${g.invoiceNumber}',
      if (g.anulado) 'ANULADO',
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.fromLTRB(12, 2, 14, 2),
      leading: _IconoCategoria(g.category, apagado: g.anulado),
      title: Text(g.description ?? g.category, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w600, color: g.anulado ? AppColors.muted : null)),
      subtitle: Text(g.description == null ? linea2 : '${g.category} · $linea2', maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(
        gs(g.amount),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: g.anulado ? AppColors.muted : AppColors.red,
          decoration: g.anulado ? TextDecoration.lineThrough : null,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

// =================================================================
//  REGISTRAR UN GASTO
// =================================================================

class GastoFormScreen extends StatefulWidget {
  const GastoFormScreen({super.key});

  @override
  State<GastoFormScreen> createState() => _GastoFormScreenState();
}

class _GastoFormScreenState extends State<GastoFormScreen> {
  final _form = GlobalKey<FormState>();
  final _monto = TextEditingController();
  final _desc = TextEditingController();
  final _factura = TextEditingController();
  String? _categoria;
  bool _faltaCategoria = false;
  bool _guardando = false;
  late DateTime _dia;
  late TimeOfDay _hora;

  /// Clave del gasto: tocar dos veces o reintentar sin señal no lo carga dos veces.
  final String _key = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dia = DateTime(now.year, now.month, now.day);
    _hora = TimeOfDay(hour: now.hour, minute: now.minute);
  }

  @override
  void dispose() {
    _monto.dispose();
    _desc.dispose();
    _factura.dispose();
    super.dispose();
  }

  DateTime get _fecha => DateTime(_dia.year, _dia.month, _dia.day, _hora.hour, _hora.minute);

  String get _diaTexto {
    final now = DateTime.now();
    final dif = DateTime(now.year, now.month, now.day).difference(_dia).inDays;
    final f = fechaCorta.format(_dia);
    return dif == 0 ? 'Hoy · $f' : (dif == 1 ? 'Ayer · $f' : f);
  }

  Future<void> _elegirDia() async {
    final now = DateTime.now();
    final hoy = DateTime(now.year, now.month, now.day);
    final d = await showDatePicker(
      context: context,
      helpText: '¿Qué día fue el gasto?',
      initialDate: _dia,
      firstDate: DateTime(hoy.year - 2, hoy.month, hoy.day + 1),
      lastDate: hoy,
    );
    if (d != null && mounted) setState(() => _dia = d);
  }

  Future<void> _elegirHora() async {
    final h = await showTimePicker(
      context: context,
      helpText: '¿A qué hora?',
      initialTime: _hora,
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (h != null && mounted) setState(() => _hora = h);
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    setState(() => _faltaCategoria = _categoria == null);
    final valido = _form.currentState!.validate();
    if (!valido || _categoria == null) {
      showSnack(context, _categoria == null ? 'Elegí la categoría del gasto.' : 'Revisá los datos marcados en rojo.', error: true);
      return;
    }
    if (_fecha.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      showSnack(context, 'La fecha y hora no pueden ser posteriores a ahora.', error: true);
      return;
    }
    setState(() => _guardando = true);
    try {
      final desc = limpiarTexto(_desc.text);
      final fact = _factura.text.trim();
      await context.read<GastoRepository>().registrar(
            categoria: _categoria!,
            monto: leerMonto(_monto.text) ?? 0,
            descripcion: desc.isEmpty ? null : desc,
            factura: fact.isEmpty ? null : fact,
            fecha: _fecha,
            idempotencyKey: _key,
          );
      if (!mounted) return;
      showSnack(context, 'Gasto guardado: $_categoria · ${gs(leerMonto(_monto.text) ?? 0)}');
      Navigator.pop(context, true);
    } catch (e) {
      registrarError('registrarGasto', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e, 'No se pudo guardar el gasto. Intentá de nuevo.'), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar gasto')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                SectionTitle('¿En qué se gastó? *', padding: const EdgeInsets.fromLTRB(4, 8, 4, 10)),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in categoriasGasto)
                      ChoiceChip(
                        avatar: Icon(c.$2, size: 18),
                        label: Text(c.$1),
                        selected: _categoria == c.$1,
                        onSelected: (_) => setState(() {
                          _categoria = c.$1;
                          _faltaCategoria = false;
                        }),
                      ),
                  ],
                ),
                if (_faltaCategoria)
                  const Padding(
                    padding: EdgeInsets.only(top: 8, left: 4),
                    child: Text('Elegí una categoría', style: TextStyle(color: AppColors.red, fontSize: 12.5)),
                  ),
                const SizedBox(height: 20),
                MontoField(
                  controller: _monto,
                  label: '¿Cuánto se gastó? *',
                  hint: 'Ej: 150.000',
                  validator: validarMonto(campo: 'cuánto se gastó'),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: InkWell(
                        onTap: _elegirDia,
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Día', prefixIcon: Icon(Icons.event_outlined)),
                          child: Text(_diaTexto, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: InkWell(
                        onTap: _elegirHora,
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Hora', prefixIcon: Icon(Icons.schedule_rounded)),
                          child: Text(
                            '${_hora.hour.toString().padLeft(2, '0')}:${_hora.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 6, 12, 0),
                  child: Text('Si el gasto fue otro día u otra hora, tocá para cambiarlo.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _desc,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: formatoTexto(200),
                  maxLines: 2,
                  minLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'Descripción (opcional)',
                    hintText: 'Ej: nafta para el camión, sueldo de Juan',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                  validator: validarTexto(campo: 'la descripción', max: 200),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _factura,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z-]')), LengthLimitingTextInputFormatter(Largo.factura)],
                  decoration: const InputDecoration(
                    labelText: 'N° de factura (opcional)',
                    hintText: 'Ej: 001-001-0001234',
                    prefixIcon: Icon(Icons.receipt_outlined),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _guardando ? null : _guardar,
                    icon: _guardando
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : const Icon(Icons.check_rounded),
                    label: const Text('Guardar gasto', style: TextStyle(fontSize: 17)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
