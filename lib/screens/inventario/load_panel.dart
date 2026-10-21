import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/load_status.dart';
import '../../models/product.dart';
import '../../providers/catalog_provider.dart';
import '../../repositories/product_repository.dart';
import '../../security/registro_seguro.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../compras/purchase_form_screen.dart';

/// Cuenta de la carga para productos que se compran por carga (arena, piedra...):
/// cuánto se pagó, cuánto se vendió, cuánto falta para recuperar y las cargas anteriores.
class LoadPanel extends StatefulWidget {
  const LoadPanel({super.key, required this.product, required this.onChanged});
  final Product product;
  final Future<void> Function() onChanged;

  @override
  State<LoadPanel> createState() => _LoadPanelState();
}

class _LoadPanelState extends State<LoadPanel> {
  late Future<LoadStatus> _future = _cargar();
  bool _closing = false;

  Future<LoadStatus> _cargar() => context.read<ProductRepository>().loadStatus(widget.product.id);

  Future<void> _refrescar() async {
    setState(() => _future = _cargar());
    await widget.onChanged();
  }

  Future<void> _nuevaCarga() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseFormScreen(initialProduct: widget.product)));
    if (mounted) await _refrescar();
  }

  Future<void> _terminar(OpenLoad o) async {
    final resultado = o.profit >= 0 ? 'Ganaste ${gs(o.profit)}' : 'Perdiste ${gs(-o.profit)}';
    final ok = await confirmar(
      context,
      titulo: '¿Se terminó la carga?',
      mensaje: 'Pagaste ${gs(o.paid)} y vendiste ${gs(o.sold)}.\n$resultado con esta carga.\n\n'
          'Se cierra la cuenta y la próxima compra empieza una carga nueva.',
      si: 'Sí, se terminó',
    );
    if (!ok || !mounted) return;
    setState(() => _closing = true);
    try {
      await context.read<ProductRepository>().closeLoad(widget.product.id);
      if (!mounted) return;
      showSnack(context, 'Carga cerrada. $resultado');
      await _refrescar();
    } catch (e) {
      registrarError('cerrarCarga', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e, 'No se pudo cerrar la carga. Intentá de nuevo.'), error: true);
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LoadStatus>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          registrarError('estadoCarga', snap.error!);
          return ErrorRetry(message: mensajeErrorSeguro(snap.error!, 'No se pudo cargar la cuenta de la carga.'), onRetry: _refrescar);
        }
        final st = snap.data!;
        final o = st.open;
        final unidad = widget.product.unit;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(14)),
              child: o == null
                  ? const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SIN CARGA ABIERTA', style: TextStyle(color: AppColors.yellow, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 12)),
                        SizedBox(height: 6),
                        Text('Cuando llegue la próxima carga, tocá "Llegó una carga" y poné cuánto pagaste.',
                            style: TextStyle(color: Colors.white, fontSize: 15)),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CARGA DESDE EL ${fechaCorta.format(o.openedAt)}',
                            style: const TextStyle(color: AppColors.yellow, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 12)),
                        const SizedBox(height: 10),
                        _fila('Pagaste por la carga', gs(o.paid)),
                        _fila('Vendido hasta ahora', gs(o.sold)),
                        // Lo comprado menos lo vendido de esta carga.
                        if (context.watch<CatalogProvider>().cargasDe(widget.product.id) case final q?)
                          _fila('Quedan', '${cantidad(q)} ${unidadPlural('carga', q)}'),
                        _fila('Vendiste', '${cantidad(o.quantity)} ${unidadPlural(unidad, o.quantity)} · ${o.sales} ventas'),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: o.progress,
                            minHeight: 12,
                            backgroundColor: Colors.white24,
                            color: o.recovered ? AppColors.green : AppColors.yellow,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          o.paid == 0
                              ? 'Todavía no cargaste lo que pagaste por esta carga.'
                              : o.recovered
                                  ? 'Ya recuperaste lo pagado. Ganancia: ${gs(o.profit)}'
                                  : 'Te falta vender ${gs(o.toRecover)} para recuperar lo pagado',
                          style: TextStyle(
                            color: o.recovered ? const Color(0xFF7BE0A0) : Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 10),
            FilaCampos(
              anchoMinimo: 420,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _nuevaCarga,
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: Text(o == null ? 'Llegó una carga' : 'Llegó otra carga'),
                  ),
                ),
                const SizedBox(width: 10),
                if (o != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _closing ? null : () => _terminar(o),
                      icon: _closing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.flag_outlined),
                      label: const Text('Se terminó la carga'),
                    ),
                  ),
              ],
            ),
            if (o != null)
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text('Si llega otra carga antes de terminar esta, se suma a la misma (es la misma pila).',
                    style: TextStyle(color: AppColors.muted, fontSize: 13)),
              ),
            const SectionTitle('Cargas anteriores'),
            if (st.closed.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Todavía no se cerró ninguna carga.', style: TextStyle(color: AppColors.muted))))
            else
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < st.closed.length; i++) ...[
                      if (i > 0) const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        title: Text('${fechaCorta.format(st.closed[i].openedAt)} al ${fechaCorta.format(st.closed[i].closedAt)}'),
                        subtitle: Text('Pagaste ${gs(st.closed[i].paid)} · vendiste ${gs(st.closed[i].sold)}'),
                        trailing: Text(
                          '${st.closed[i].profit >= 0 ? '+' : '−'}${miles(st.closed[i].profit.abs())}',
                          style: TextStyle(fontWeight: FontWeight.w800, color: st.closed[i].profit >= 0 ? AppColors.green : AppColors.red),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _fila(String label, String valor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: Colors.white70))),
            Text(valor, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ),
      );
}
