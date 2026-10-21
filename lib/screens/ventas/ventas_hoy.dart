import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/doc_line.dart';
import '../../models/sale.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/sale_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/client_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';
import '../inventario/inventory_tables.dart';
import 'sale_detail_screen.dart';

enum _Filtro { todas, efectivo, transferencia, mixto, anuladas }

/// Ventas del día: resumen (vendido, efectivo, transferencia) y una tabla con cada
/// material vendido, como el panel de Movimientos de Inventario.
/// Muestra solo el día de hoy: a las 00:00 se reinicia sola.
///
/// Con [embebido] (en Inicio) va sin su propio scroll ni el resumen: solo la tabla.
class VentasHoyPanel extends StatefulWidget {
  const VentasHoyPanel({super.key, this.embebido = false});
  final bool embebido;

  @override
  State<VentasHoyPanel> createState() => _VentasHoyPanelState();
}

class _VentasHoyPanelState extends State<VentasHoyPanel> {
  final _key = GlobalKey<ReloadingFutureState<List<Sale>>>();
  _Filtro _filtro = _Filtro.todas;
  String _q = '';
  DateTime _dia = _hoy();
  Timer? _reloj;

  static DateTime _hoy() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    // A las 00:00 cambia el día: la tabla vuelve a empezar vacía y se avisa al
    // resto de la app (Inicio vuelve a calcular "Vendido hoy").
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) {
      final hoy = _hoy();
      if (hoy != _dia && mounted) {
        setState(() => _dia = hoy);
        context.read<RefreshBus>().changed();
      }
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  bool _pasaFiltro(Sale s) => switch (_filtro) {
    _Filtro.todas => true,
    _Filtro.anuladas => s.isVoided,
    _Filtro.efectivo => !s.isVoided && s.paymentMethod == 'efectivo',
    _Filtro.transferencia => !s.isVoided && s.paymentMethod == 'transferencia',
    _Filtro.mixto => !s.isVoided && s.paymentMethod == 'mixto',
  };

  @override
  Widget build(BuildContext context) {
    return ReloadingFuture<List<Sale>>(
      key: _key,
      contexto: 'ventasDeHoy',
      load: () => context.read<SaleRepository>().list(from: _dia, to: _dia, limit: 1000),
      builder: (context, ventas, reload) {
        final filtradas = ventas
            .where(_pasaFiltro)
            .where((s) => _q.isEmpty || coincide('${s.number} ${nroDoc(s.number)} ${s.clientName ?? ''} ${s.sellerName ?? ''} ${s.items.map((i) => i.description).join(' ')}', _q))
            .toList();
        final tabla = filtradas.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 24),
                child: EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: ventas.isEmpty ? 'Todavía no hubo ventas hoy' : 'Ninguna venta coincide',
                ),
              )
            : VentasDelDiaTable(ventas: filtradas, onChanged: reload, puedeAnular: context.read<AuthProvider>().esAdmin);
        if (widget.embebido) {
          return ventas.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('Todavía no hubo ventas hoy.', style: TextStyle(color: AppColors.muted)),
                  ),
                )
              : tabla;
        }
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              _Resumen(ventas: ventas, dia: _dia),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por cliente, vendedor, N° o material'),
                onChanged: (v) => setState(() => _q = v),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final f in _Filtro.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(switch (f) {
                            _Filtro.todas => 'Todas',
                            _Filtro.efectivo => 'Efectivo',
                            _Filtro.transferencia => 'Transferencia',
                            _Filtro.mixto => 'Mixto',
                            _Filtro.anuladas => 'Anuladas',
                          }),
                          selected: _filtro == f,
                          onSelected: (_) => setState(() => _filtro = f),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              tabla,
            ],
          ),
        );
      },
    );
  }
}

/// Totales del día: vendido (sin anuladas ni devoluciones), cantidad de ventas
/// y cuánto entró en efectivo y por transferencia.
class _Resumen extends StatelessWidget {
  const _Resumen({required this.ventas, required this.dia});
  final List<Sale> ventas;
  final DateTime dia;

  @override
  Widget build(BuildContext context) {
    final activas = ventas.where((s) => !s.isVoided).toList();
    final vendido = activas.fold<int>(0, (a, s) => a + s.netTotal);
    final efectivo = activas.fold<int>(0, (a, s) => a + s.paidCash);
    final transferencia = activas.fold<int>(0, (a, s) => a + s.paidTransfer);
    final devuelto = activas.fold<int>(0, (a, s) => a + s.returnedAmount);
    final anuladas = ventas.length - activas.length;

    Widget dato(IconData icono, String titulo, String valor) => Expanded(
      child: Row(
        children: [
          Icon(icono, color: AppColors.yellow, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(valor, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VENDIDO HOY · ${fechaLarga.format(dia).toUpperCase()}',
            style: const TextStyle(color: AppColors.yellow, fontWeight: FontWeight.w800, letterSpacing: 1.1, fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(gs(vendido), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
          ),
          Text(
            '${activas.length} ${activas.length == 1 ? 'venta' : 'ventas'}'
            '${anuladas > 0 ? ' · $anuladas anulada${anuladas == 1 ? '' : 's'}' : ''}'
            '${devuelto > 0 ? ' · devuelto ${gs(devuelto)}' : ''}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              dato(Icons.payments_outlined, 'Efectivo', gs(efectivo)),
              const SizedBox(width: 12),
              dato(Icons.account_balance_outlined, 'Transferencia', gs(transferencia)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            context.read<AuthProvider>().esAdmin
                ? 'Se reinicia sola a las 00:00. Las de otros días: Más → Ventas → Historial.'
                : 'Se reinicia sola a las 00:00.',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Tabla de ventas del día: una fila por material vendido.
/// Hora, N°, Producto, Cantidad, Precio, Total, Cliente, Pago, Estado y Acciones
/// (Ver detalle, Asociar cliente, Anular).
class VentasDelDiaTable extends StatelessWidget {
  const VentasDelDiaTable({super.key, required this.ventas, required this.onChanged, this.puedeAnular = true});
  final List<Sale> ventas;
  final Future<void> Function() onChanged;

  /// Solo el administrador anula ventas.
  final bool puedeAnular;

  Future<void> _accion(BuildContext context, String a, Sale s) async {
    switch (a) {
      case 'detalle':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: s.id)));
        await onChanged();
      case 'cliente':
        final pick = await pickClient(context);
        if (pick == null || !context.mounted) return;
        await runSafe(context, 'asociarCliente', () async {
          await context.read<SaleRepository>().setClient(s.id, pick.client?.id);
          await onChanged();
        }, ok: pick.client == null ? 'La venta quedó sin cliente' : 'Cliente asociado: ${pick.client!.fullName}');
      case 'anular':
        final motivo = await pedirMotivo(
          context,
          titulo: 'Anular venta N° ${nroDoc(s.number)}',
          ayuda: 'Se anula toda la venta (${gs(s.netTotal)}): el stock vuelve y deja de contar en las ganancias. Queda en el historial.',
        );
        if (motivo == null || !context.mounted) return;
        await runSafe(context, 'anularVentaDelDia', () async {
          await context.read<SaleRepository>().voidSale(s.id, motivo);
          if (!context.mounted) return;
          await context.read<CatalogProvider>().cargarProductos();
          if (context.mounted) context.read<RefreshBus>().changed();
          await onChanged();
        }, ok: 'Venta anulada');
    }
  }

  EtiquetaEstado _estado(Sale s, DocLine l) {
    if (s.isVoided) return const EtiquetaEstado('Anulada', AppColors.red, AppColors.redSoft);
    if (l.returnedQty >= l.quantity - 0.0001 && l.returnedQty > 0) {
      return const EtiquetaEstado('Devuelta', AppColors.orange, AppColors.orangeSoft);
    }
    if (l.returnedQty > 0) {
      return EtiquetaEstado('Devolvió ${cantidad(l.returnedQty)}', AppColors.orange, AppColors.orangeSoft);
    }
    return const EtiquetaEstado('Vendida', AppColors.green, Color(0xFFE6F4EA));
  }

  @override
  Widget build(BuildContext context) {
    return tablaDeslizable(
      DataTable(
        headingRowColor: const WidgetStatePropertyAll(Color(0xFFF1F3EC)),
        headingTextStyle: estiloEncabezadoTabla,
        dataRowMinHeight: 52,
        dataRowMaxHeight: 60,
        columnSpacing: 24,
        columns: const [
          // Primero lo que importa en el celular: a quién, cuánto, estado y anular.
          DataColumn(label: Text('Hora')),
          DataColumn(label: Text('N°')),
          DataColumn(label: Text('Cliente')),
          DataColumn(label: Text('Total venta'), numeric: true),
          DataColumn(label: Text('Estado')),
          DataColumn(label: Text('Acciones')),
          DataColumn(label: Text('Producto')),
          DataColumn(label: Text('Cantidad'), numeric: true),
          DataColumn(label: Text('Precio'), numeric: true),
          DataColumn(label: Text('Subtotal'), numeric: true),
          DataColumn(label: Text('Pago')),
          DataColumn(label: Text('Vendedor')),
        ],
        rows: [
          for (final s in ventas)
            for (var i = 0; i < s.items.length; i++)
              () {
                final l = s.items[i];
                final tachado = s.isVoided ? const TextStyle(decoration: TextDecoration.lineThrough, color: AppColors.muted) : null;
                return DataRow(
                  // La primera línea de cada venta lleva hora, cliente, total y acciones; las demás quedan livianas.
                  color: WidgetStatePropertyAll(i == 0 ? null : const Color(0xFFFAFAF7)),
                  cells: [
                    DataCell(Text(i == 0 ? hora.format(s.createdAt) : '', style: const TextStyle(fontWeight: FontWeight.w700))),
                    DataCell(Text(i == 0 ? nroDoc(s.number) : '', style: estiloNumerosTabla)),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(i == 0 ? (s.clientName ?? 'Sin cliente') : '', overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    DataCell(Text(
                      i == 0 ? gs(s.netTotal) : '',
                      style: estiloNumerosTabla.copyWith(fontWeight: FontWeight.w900, fontSize: 15).merge(tachado),
                    )),
                    DataCell(_estado(s, l)),
                    DataCell(
                      i != 0
                          ? const SizedBox.shrink()
                          : PopupMenuButton<String>(
                              tooltip: 'Acciones',
                              icon: const Icon(Icons.more_vert),
                              onSelected: (a) => _accion(context, a, s),
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'detalle', child: Text('Ver detalle')),
                                if (!s.isVoided) const PopupMenuItem(value: 'cliente', child: Text('Asociar cliente')),
                                // Anular: solo el administrador (el servidor también lo controla).
                                if (!s.isVoided && puedeAnular)
                                  const PopupMenuItem(value: 'anular', child: Text('Anular venta', style: TextStyle(color: AppColors.red))),
                              ],
                            ),
                    ),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Text(
                          l.isGift ? '${l.description} (regalo)' : l.description,
                          style: const TextStyle(fontWeight: FontWeight.w700).merge(tachado),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text(
                      '−${cantidad(l.quantity)} ${unidadPlural(l.unit, l.quantity)}',
                      style: estiloNumerosTabla.copyWith(fontWeight: FontWeight.w800, color: AppColors.blue).merge(tachado),
                    )),
                    DataCell(Text(l.priceIsTotal ? 'por línea' : gs(l.unitPrice), style: estiloNumerosTabla.merge(tachado))),
                    DataCell(Text(gs(l.lineTotal), style: estiloNumerosTabla.merge(tachado))),
                    DataCell(Text(i == 0 ? metodoPagoTexto(s.paymentMethod) : '')),
                    DataCell(Text(i == 0 ? (s.sellerName ?? '—') : '')),
                  ],
                );
              }(),
        ],
      ),
    );
  }
}
