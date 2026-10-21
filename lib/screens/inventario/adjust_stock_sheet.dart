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

/// Ajuste manual: se escribe cuánto hay realmente y el motivo.
Future<bool> showAdjustStockSheet(BuildContext context, Product p) async {
  final r = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => _AdjustSheet(product: p));
  return r ?? false;
}

class _AdjustSheet extends StatefulWidget {
  const _AdjustSheet({required this.product});
  final Product product;

  @override
  State<_AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends State<_AdjustSheet> {
  final _form = GlobalKey<FormState>();
  late final _stock = TextEditingController(text: cantidad(widget.product.stock));
  final _reason = TextEditingController();
  final _cost = TextEditingController();
  bool _saving = false;
  /// Clave del ajuste: un doble toque o reintento no ajusta dos veces.
  final String _key = const Uuid().v4();

  static const _motivos = ['Recuento', 'Rotura', 'Pérdida', 'Uso propio', 'Devolución de cliente', 'Stock inicial'];

  double get _new => leerCantidad(_stock.text) ?? widget.product.stock;
  double get _diff => _new - widget.product.stock;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_diff == 0) {
      showSnack(context, 'El stock ya es ese.', error: true);
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context.read<ProductRepository>().adjustStock(
            widget.product.id,
            _new,
            limpiarTexto(_reason.text),
            unitCost: _diff > 0 ? leerMonto(_cost.text) : null,
            idempotencyKey: _key,
          );
      if (mounted) {
        showSnack(context, 'Stock ajustado');
        Navigator.pop(context, true);
      }
    } catch (e) {
      registrarError('ajustarStock', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e, 'No se pudo ajustar el stock.'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Ajustar stock', style: Theme.of(context).textTheme.titleLarge),
              Text('${p.name} · ahora hay ${cantidad(p.stock)} ${unidadPlural(p.unit, p.stock)}', style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 16),
              CantidadField(
                controller: _stock,
                label: '¿Cuánto hay realmente?',
                suffix: unidadPlural(p.unit, 2),
                allowZero: true,
                autofocus: true,
                enteros: !p.cantidadLibre,
                onChanged: (_) => setState(() {}),
              ),
              if (_diff != 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _diff > 0 ? 'Entran ${cantidad(_diff)} ${unidadPlural(p.unit, _diff)}' : 'Salen ${cantidad(-_diff)} ${unidadPlural(p.unit, -_diff)}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: _diff > 0 ? AppColors.green : AppColors.red),
                  ),
                ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _reason,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: formatoTexto(Largo.motivo),
                decoration: const InputDecoration(labelText: 'Motivo *', hintText: 'Ej: Recuento, Rotura (o tocá uno de abajo)'),
                validator: validarTexto(campo: 'el motivo', obligatorio: true, min: 3, max: Largo.motivo),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final m in _motivos) ActionChip(label: Text(m), onPressed: () => setState(() => _reason.text = m))],
              ),
              if (_diff > 0) ...[
                const SizedBox(height: 14),
                MontoField(
                  controller: _cost,
                  label: 'Costo por ${p.unit} (opcional)',
                  hint: 'Ej: ${miles(p.avgCost > 0 ? p.avgCost : 55000)}',
                  helper: 'Si lo cargás, entra al costo promedio. Si no, se usa el actual (${gs(p.avgCost)}).',
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Guardar ajuste'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
