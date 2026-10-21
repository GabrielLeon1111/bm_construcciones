import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/product.dart';
import '../../repositories/product_repository.dart';
import '../../security/registro_seguro.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../utils/validacion.dart';
import '../../widgets/common.dart';

/// Averiados: mercadería que se rompió, se mojó o venció.
/// Se pregunta cuántas y por qué; se descuenta del stock y queda la pérdida registrada.
Future<bool> showDamagedSheet(BuildContext context, Product p) async {
  if (p.stock <= 0) {
    showSnack(context, 'No hay stock de "${p.name}" para marcar como averiado.', error: true);
    return false;
  }
  final r = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => _DamagedSheet(product: p));
  return r ?? false;
}

class _DamagedSheet extends StatefulWidget {
  const _DamagedSheet({required this.product});
  final Product product;

  @override
  State<_DamagedSheet> createState() => _DamagedSheetState();
}

class _DamagedSheetState extends State<_DamagedSheet> {
  final _form = GlobalKey<FormState>();
  final _qty = TextEditingController();
  final _reason = TextEditingController();
  bool _saving = false;
  /// Clave de la operación: un doble toque o reintento no descuenta dos veces.
  final String _key = const Uuid().v4();

  static const _motivos = ['Se rompió', 'Se mojó', 'Venció', 'Llegó dañado', 'Se perdió'];

  double get _cantidad => leerCantidad(_qty.text) ?? 0;

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final p = widget.product;
    final q = _cantidad;
    final motivo = limpiarTexto(_reason.text);
    final ok = await confirmar(
      context,
      titulo: 'Registrar averiados',
      mensaje: 'Se descuentan ${cantidad(q)} ${unidadPlural(p.unit, q)} de ${p.name} (motivo: $motivo).\n\n'
          'Pérdida: ${gs((q * p.avgCost).round())}',
      si: 'Sí, descontar',
      peligro: true,
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await context.read<ProductRepository>().registerDamage(p.id, q, motivo, idempotencyKey: _key);
      if (!mounted) return;
      showSnack(context, 'Listo: ${cantidad(q)} ${unidadPlural(p.unit, q)} marcadas como averiadas');
      Navigator.pop(context, true);
    } catch (e) {
      registrarError('averiados', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e, 'No se pudo registrar. Intentá de nuevo.'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final q = _cantidad;
    final perdida = (q * p.avgCost).round();
    final plural = unidadPlural(p.unit, 2);
    final cuantas = const {'unidad', 'bolsa', 'barra', 'caja', 'carga'}.contains(p.unit) ? 'Cuántas' : 'Cuántos';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.heart_broken_outlined, color: AppColors.red),
                  const SizedBox(width: 8),
                  Text('Averiados', style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              Text('${p.name} · hay ${cantidad(p.stock)} ${unidadPlural(p.unit, p.stock)}', style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _qty,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [p.cantidadLibre ? CantidadInputFormatter() : MilesInputFormatter()],
                style: const TextStyle(fontWeight: FontWeight.w700),
                decoration: InputDecoration(labelText: '¿$cuantas $plural se averiaron?', hintText: 'Ej: 2', suffixText: plural),
                validator: (v) {
                  final err = validarCantidad(soloEnteros: !p.cantidadLibre)(v);
                  if (err != null) return err;
                  if ((leerCantidad(v ?? '') ?? 0) > p.stock + 0.0001) return 'No puede ser más de lo que hay (${cantidad(p.stock)})';
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _reason,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: formatoTexto(Largo.motivo),
                decoration: const InputDecoration(labelText: '¿Qué pasó? *', hintText: 'Ej: se rompieron al bajar del camión (o tocá uno de abajo)'),
                validator: validarTexto(campo: 'qué pasó', obligatorio: true, min: 3, max: Largo.motivo),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final m in _motivos) ActionChip(label: Text(m), onPressed: () => setState(() => _reason.text = m))],
              ),
              if (q > 0 && p.avgCost > 0)
                Container(
                  margin: const EdgeInsets.only(top: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(10)),
                  child: Text('Pérdida: ${gs(perdida)} (lo que te costaron)', style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w800)),
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white, minimumSize: const Size(0, 52)),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Icon(Icons.remove_circle_outline_rounded),
                label: const Text('Descontar averiados'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
