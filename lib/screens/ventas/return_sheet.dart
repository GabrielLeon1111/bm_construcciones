import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/doc_line.dart';
import '../../models/sale.dart';
import '../../repositories/sale_repository.dart';
import '../../security/registro_seguro.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../utils/validacion.dart';
import '../../widgets/common.dart';

/// Devolución parcial: el cliente devuelve parte del material.
/// El material vuelve al stock y ese monto deja de contar en ventas y ganancias.
Future<bool> showReturnSheet(BuildContext context, Sale sale) async {
  final r = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => _ReturnSheet(sale: sale));
  return r ?? false;
}

class _ReturnSheet extends StatefulWidget {
  const _ReturnSheet({required this.sale});
  final Sale sale;

  @override
  State<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<_ReturnSheet> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late final List<DocLine> _lines = widget.sale.items.where((l) => l.id != null && l.returnable > 0.0001).toList();
  late final Map<String, TextEditingController> _qty = {for (final l in _lines) l.id!: TextEditingController()};
  bool _saving = false;
  /// Clave de la operación: un doble toque o reintento no devuelve dos veces.
  final String _key = const Uuid().v4();

  static const _motivos = ['Le sobró material', 'Se cargó mal', 'Producto fallado', 'Cambió de idea'];

  double _cant(DocLine l) => leerCantidad(_qty[l.id!]!.text) ?? 0;

  /// Lo que se le devuelve al cliente por esa línea (con el descuento repartido).
  int _monto(DocLine l) {
    final s = widget.sale;
    final q = _cant(l);
    if (q <= 0 || l.quantity <= 0 || s.subtotal <= 0) return 0;
    return (l.lineTotal * s.total / s.subtotal * q / l.quantity).round();
  }

  int get _total => _lines.fold(0, (a, l) => a + _monto(l));

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final cantidades = {for (final l in _lines) l.id!: _cant(l)}..removeWhere((_, v) => v <= 0);
    if (cantidades.isEmpty) {
      showSnack(context, 'Escribí cuánto devuelve de al menos un material.', error: true);
      return;
    }
    final ok = await confirmar(
      context,
      titulo: 'Registrar devolución',
      mensaje: 'El material vuelve al stock y se descuentan ${gs(_total)} de esta venta.\n\nLe devolvés al cliente: ${gs(_total)}',
      si: 'Sí, registrar',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await context.read<SaleRepository>().returnItems(widget.sale.id, cantidades, limpiarTexto(_reason.text), idempotencyKey: _key);
      if (!mounted) return;
      showSnack(context, 'Devolución registrada: ${gs(_total)}');
      Navigator.pop(context, true);
    } catch (e) {
      registrarError('devolucion', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e, 'No se pudo registrar la devolución.'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Devolución', style: Theme.of(context).textTheme.titleLarge),
              Text('Venta N° ${nroDoc(widget.sale.number)} · escribí cuánto devuelve de cada material',
                  style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 14),
              for (final l in _lines) ...[
                Text(l.description, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _qty[l.id!],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [CantidadInputFormatter()],
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    labelText: '¿Cuánto devuelve?',
                    hintText: 'Máximo ${cantidad(l.returnable)}',
                    suffixText: unidadPlural(l.unit, 2),
                    helperText: _monto(l) > 0 ? 'Se descuenta ${gs(_monto(l))}' : 'Dejalo vacío si no devuelve nada de esto',
                  ),
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) return null;
                    final q = leerCantidad(v!);
                    if (q == null || q < 0) return 'Cantidad no válida';
                    if (q > l.returnable + 0.0001) return 'Máximo ${cantidad(l.returnable)}';
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _reason,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: formatoTexto(Largo.motivo),
                decoration: const InputDecoration(labelText: 'Motivo *', hintText: 'Ej: le sobró material (o tocá uno de abajo)'),
                validator: validarTexto(campo: 'el motivo', obligatorio: true, min: 3, max: Largo.motivo),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final m in _motivos) ActionChip(label: Text(m), onPressed: () => setState(() => _reason.text = m))],
              ),
              if (_total > 0) ...[
                const SizedBox(height: 14),
                TotalDestacado(etiqueta: 'LE DEVOLVÉS', monto: _total),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Icon(Icons.assignment_return_outlined),
                label: const Text('Registrar devolución'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
