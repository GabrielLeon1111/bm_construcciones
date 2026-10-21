import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/doc_line.dart';
import '../providers/catalog_provider.dart';
import '../providers/draft_document.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import '../utils/validacion.dart';
import 'common.dart';
import 'line_sheet.dart';
import 'product_picker.dart';

/// Lista editable de líneas de un borrador (venta o presupuesto).
class DocLinesEditor extends StatelessWidget {
  const DocLinesEditor({super.key, required this.draft, this.checkStock = true, this.showAddButtons = true});
  final DraftDocument draft;
  final bool checkStock;
  final bool showAddButtons;

  Future<void> _edit(BuildContext context, int i) async {
    final line = draft.lines[i];
    final catalog = context.read<CatalogProvider>();
    final product = catalog.productById(line.productId);
    final others = line.productId == null ? 0.0 : draft.qtyOf(line.productId!) - line.quantity;
    final r = await showLineSheet(context, product: product, existing: line, alreadyInDoc: others, checkStock: checkStock);
    if (r != null) draft.updateLine(i, r);
  }

  Future<void> _addProduct(BuildContext context) async {
    final p = await pickProduct(context);
    if (p == null || !context.mounted) return;
    if (checkStock && p.isOut) {
      showSnack(context, '"${p.name}" está agotado. Cargá una compra para tener stock.', error: true);
      return;
    }
    final r = await showLineSheet(context, product: p, alreadyInDoc: draft.qtyOf(p.id), checkStock: checkStock);
    if (r == null) return;
    draft.addProduct(p, r.quantity,
        price: r.unitPrice, gift: r.isGift, priceIsTotal: r.priceIsTotal, discountPct: r.discountPct, discountAmount: r.discountAmount);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) {
        final lines = draft.lines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (lines.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line, width: 1.5),
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                ),
                child: const Text('Todavía no agregaste materiales.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
              )
            else
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < lines.length; i++) ...[
                      if (i > 0) const Divider(indent: 14, endIndent: 14),
                      _LineRow(
                        line: lines[i],
                        checkStock: checkStock,
                        onTap: () => _edit(context, i),
                        onDelete: () => draft.removeLine(i),
                      ),
                    ],
                  ],
                ),
              ),
            if (showAddButtons) ...[
              const SizedBox(height: 10),
              // El flete y la mano de obra van incluidos en la venta: solo se agregan materiales.
              OutlinedButton.icon(
                onPressed: () => _addProduct(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Material'),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.onTap, required this.onDelete, required this.checkStock});
  final DocLine line;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool checkStock;

  @override
  Widget build(BuildContext context) {
    final over = checkStock && line.exceedsStock;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 48),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(color: over ? AppColors.redSoft : AppColors.concrete, borderRadius: BorderRadius.circular(8)),
              child: Text(
                cantidad(line.quantity),
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: over ? AppColors.red : AppColors.ink),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (line.isGift) const Padding(padding: EdgeInsets.only(right: 6), child: Pill('REGALO', color: AppColors.green)),
                      Flexible(child: Text(line.description, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                    ],
                  ),
                  Text(
                    over
                        ? 'Stock insuficiente (hay ${cantidad(line.stockAvailable!.clamp(0, double.infinity))})'
                        : line.isGift
                            ? unidadPlural(line.unit, line.quantity)
                            : line.priceIsTotal
                                ? unidadPlural(line.unit, line.quantity)
                                : '${unidadPlural(line.unit, line.quantity)} × ${gs(line.unitPrice)}${line.isFree ? ' · libre' : ''}',
                    style: TextStyle(color: over ? AppColors.red : AppColors.muted, fontSize: 13),
                  ),
                  if (line.textoDescuento != null)
                    Text(line.textoDescuento!, style: const TextStyle(color: AppColors.green, fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Text(line.isGift ? '—' : miles(line.lineTotal),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, fontFeatures: [FontFeature.tabularFigures()])),
            IconButton(
              tooltip: 'Quitar',
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.muted),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// Subtotal, descuento (editable) y el total resaltado.
class DocTotals extends StatelessWidget {
  const DocTotals({super.key, required this.draft, this.etiquetaTotal = 'TOTAL A PAGAR'});
  final DraftDocument draft;
  final String etiquetaTotal;

  Future<void> _editDiscount(BuildContext context) async {
    final ctrl = TextEditingController(text: draft.discount == 0 ? '' : miles(draft.discount));
    final form = GlobalKey<FormState>();
    final subtotal = draft.subtotal;
    Future<void> aplicar(BuildContext c) async {
      if (!form.currentState!.validate()) return;
      final monto = leerMonto(ctrl.text) ?? 0;
      // Anti-error: un descuento de más de la mitad casi siempre es un cero de más.
      if (monto * 2 > subtotal &&
          !await confirmar(c,
              titulo: '¿Descuento tan grande?',
              mensaje: 'Vas a descontar ${gs(monto)} de ${gs(subtotal)} (${(monto * 100 / subtotal).round()}%). ¿Está bien?',
              si: 'Sí, aplicar')) {
        return;
      }
      if (c.mounted) Navigator.pop(c, monto);
    }

    final r = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Descuento'),
        content: Form(
          key: form,
          child: MontoField(
            controller: ctrl,
            label: 'Monto a descontar',
            hint: 'Ej: 10.000',
            helper: 'Máximo ${gs(subtotal)} (el subtotal)',
            autofocus: true,
            validator: validarMonto(campo: 'el descuento', obligatorio: false, min: 0, max: subtotal),
            onSubmitted: (_) => aplicar(c),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 0), child: const Text('Sin descuento')),
          FilledButton(onPressed: () => aplicar(c), child: const Text('Aplicar')),
        ],
      ),
    );
    if (r != null) draft.discount = r;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            children: [
              KeyValueRow('Subtotal', gs(draft.subtotal)),
              InkWell(
                onTap: draft.isEmpty ? null : () => _editDiscount(context),
                child: Row(
                  children: [
                    const Expanded(child: Text('Descuento', style: TextStyle(color: AppColors.muted, fontSize: 15))),
                    Text(draft.discount == 0 ? 'Agregar' : '− ${gs(draft.discount)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: draft.discount == 0 ? AppColors.blue : AppColors.red,
                          decoration: draft.discount == 0 ? TextDecoration.underline : null,
                        )),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit_outlined, size: 16, color: AppColors.muted),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TotalDestacado(etiqueta: etiquetaTotal, monto: draft.total),
            ],
          ),
        ),
      ),
    );
  }
}
