import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/doc_line.dart';
import '../models/product.dart';
import '../providers/catalog_provider.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import '../utils/validacion.dart';
import 'common.dart';

/// Hoja para cargar o editar una línea de venta/presupuesto.
/// - Con producto: cantidad (acepta 1/2), precio editable y opción REGALO.
/// - Línea libre (sin producto): además descripción y unidad (ej: Flete).
Future<DocLine?> showLineSheet(BuildContext context, {Product? product, DocLine? existing, double alreadyInDoc = 0, bool checkStock = true}) {
  return showModalBottomSheet<DocLine>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _LineSheet(product: product, existing: existing, alreadyInDoc: alreadyInDoc, checkStock: checkStock),
  );
}

class _LineSheet extends StatefulWidget {
  const _LineSheet({this.product, this.existing, required this.alreadyInDoc, required this.checkStock});
  final Product? product;
  final DocLine? existing;
  final double alreadyInDoc;
  final bool checkStock;

  @override
  State<_LineSheet> createState() => _LineSheetState();
}

class _LineSheetState extends State<_LineSheet> {
  final _form = GlobalKey<FormState>();
  late final bool _free = widget.product == null && (widget.existing?.isFree ?? true);
  late final _desc = TextEditingController(text: widget.existing?.description ?? '');

  /// Arena, piedra bruta (por carga): se vende en tercios o la carga completa.
  /// El monto se calcula solo dividiendo el precio de la carga (1/3 de 900.000 = 300.000)
  /// y se puede cambiar. En el comprobante sale ese monto en las dos columnas.
  late final bool _porCarga = widget.product?.soldByLoad ?? false;
  late final int _precioCarga = widget.product?.salePrice ?? 0;

  /// Triturada (por kilo): se puede vender por kilos o por toneladas.
  late final bool _porKilo = widget.product != null && widget.product!.unit == 'kg' && !_porCarga && !(widget.existing?.priceIsTotal ?? false);
  bool _enToneladas = false;

  late final _qty = TextEditingController(text: widget.existing == null ? (_porCarga ? '1/3' : '1') : cantidad(widget.existing!.quantity));

  /// Por unidad (ladrillos, cemento, tejas...): solo números enteros, sin 1/2 ni 2,5.
  /// Las líneas libres (flete, mano de obra) aceptan cualquier cantidad.
  late final bool _enteros = widget.product != null && !widget.product!.cantidadLibre;

  /// Lo escrito en el precio es el monto de toda la línea.
  late final bool _porLinea = _porCarga || (widget.existing?.priceIsTotal ?? false);

  /// Se tocó el monto a mano: ya no se recalcula al cambiar la cantidad.
  late bool _montoEditado = widget.existing != null;
  late final _price = TextEditingController(text: _textoInicialPrecio());
  late String _unit = widget.existing?.unit ?? widget.product?.unit ?? 'unidad';
  late bool _gift = widget.existing?.isGift ?? false;

  /// Descuento de esta línea: 'no', 'pct' (porcentaje) o 'monto' (guaraníes).
  late String _tipoDesc = widget.existing?.discountPct != null
      ? 'pct'
      : ((widget.existing?.discountAmount ?? 0) > 0 ? 'monto' : 'no');
  late final _descuento = TextEditingController(
    text: widget.existing?.discountPct != null
        ? widget.existing!.discountPct!.round().toString()
        : ((widget.existing?.discountAmount ?? 0) > 0 ? miles(widget.existing!.discountAmount) : ''),
  );

  int get _pctValue => int.tryParse(_descuento.text.trim()) ?? 0;

  /// Descuento en guaraníes según lo elegido.
  int get _descuentoValor {
    if (_gift || _tipoDesc == 'no') return 0;
    final bruto = _totalLinea;
    final d = _tipoDesc == 'pct' ? (bruto * _pctValue / 100).round() : (leerMonto(_descuento.text) ?? 0);
    return d.clamp(0, bruto);
  }

  double get _qtyValue => leerCantidad(_qty.text) ?? 0;
  int get _priceValue => leerMonto(_price.text) ?? 0;

  /// Cantidad en la unidad del producto (las toneladas se pasan a kilos).
  double get _qtyBase => _porKilo && _enToneladas ? _qtyValue * 1000 : _qtyValue;

  String _textoInicialPrecio() {
    final e = widget.existing;
    if (e != null) return e.unitPrice == 0 ? '' : miles(e.unitPrice);
    if (_porCarga) return _montoCarga(widget.existing == null ? '1/3' : '');
    final v = widget.product?.salePrice ?? 0;
    return v == 0 ? '' : miles(v);
  }

  /// Ayuda debajo de la cantidad: cuántas cargas quedan (si se sabe) y las fracciones.
  String _ayudaCarga(BuildContext context) {
    final quedan = context.watch<CatalogProvider>().cargasDe(widget.product!.id);
    const fracciones = '1/4 · 1/3 · 1/2 · carga completa: 1';
    return quedan == null ? 'Un cuarto: $fracciones' : 'Quedan ${cantidad(quedan)} ${unidadPlural('carga', quedan)} · $fracciones';
  }

  /// Fracción de carga × precio de la carga, redondeado a Gs. 1.000 para cobrar
  /// cómodo en efectivo (1/3 de 650.000 = 216.666 → 217.000). Se puede cambiar.
  String _montoCarga(String cantidadTexto) {
    final q = leerCantidadExacta(cantidadTexto) ?? 0;
    if (_precioCarga <= 0 || q <= 0) return '';
    return miles((q * _precioCarga / 1000).round() * 1000);
  }

  void _alCambiarCantidad() {
    if (_porCarga && !_montoEditado) _price.text = _montoCarga(_qty.text);
    setState(() {});
  }

  void _cambiarUnidadKilo(bool toneladas) {
    // Se convierten la cantidad y el precio ya escritos.
    final q = _qtyValue;
    final pr = _priceValue;
    setState(() {
      _enToneladas = toneladas;
      if (q > 0) _qty.text = cantidad(toneladas ? q / 1000 : q * 1000);
      if (pr > 0) _price.text = miles(toneladas ? pr * 1000 : (pr / 1000).round());
    });
  }

  double? get _available {
    final p = widget.product;
    if (p != null && p.soldByLoad) return null; // por carga: no hay stock que limite
    if (p != null) return p.stock - widget.alreadyInDoc; // en la unidad del producto (kg)
    return widget.existing?.stockAvailable == null ? null : widget.existing!.stockAvailable! - widget.alreadyInDoc;
  }

  void _setQty(String v) {
    _qty.text = v;
    _alCambiarCantidad();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    if (!_gift && _tipoDesc != 'no') {
      final error = _validarDescuento(_descuento.text);
      if (error != null) {
        showSnack(context, error, error: true);
        return;
      }
    }
    if (!_gift && _totalLinea > montoMaximo) {
      showSnack(context, 'El total de la línea pasa de ${gs(montoMaximo)}. Revisá la cantidad y el precio.', error: true);
      return;
    }
    final base = widget.existing;
    final p = widget.product;
    // Por toneladas: se guarda en kilos. Si el precio por tonelada no da un precio por kilo
    // exacto, se guarda el monto de la línea para no perder guaraníes por redondeo.
    final toneladas = _porKilo && _enToneladas;
    final porLinea = _porLinea || (toneladas && _priceValue % 1000 != 0);
    final precio = _gift ? 0 : (porLinea ? _totalLinea : (toneladas ? _priceValue ~/ 1000 : _priceValue));
    final line = DocLine(
      productId: p?.id ?? base?.productId,
      description: _free ? limpiarTexto(_desc.text) : (base?.description ?? p!.displayName),
      unit: _unit,
      quantity: _qtyBase,
      unitPrice: precio,
      priceIsTotal: porLinea && !_gift,
      isGift: _gift,
      stockAvailable: p == null ? base?.stockAvailable : p.stockParaVenta,
      discountPct: !_gift && _tipoDesc == 'pct' && _pctValue > 0 ? _pctValue.toDouble() : null,
      discountAmount: !_gift && _tipoDesc == 'monto' ? _descuentoValor : 0,
    );
    Navigator.pop(context, line);
  }

  String? _validarDescuento(String? v) {
    if (_gift || _tipoDesc == 'no') return null;
    final t = (v ?? '').trim();
    if (t.isEmpty) return _tipoDesc == 'pct' ? 'Escribí el porcentaje (ej: 10)' : 'Escribí el monto del descuento';
    if (_tipoDesc == 'pct') {
      final n = int.tryParse(t);
      if (n == null || n < 1 || n > 100) return 'Entre 1 y 100';
      return null;
    }
    final m = leerMonto(t) ?? 0;
    if (m <= 0) return 'Tiene que ser mayor a cero';
    if (m > _totalLinea) return 'No puede ser más que el total (${gs(_totalLinea)})';
    return null;
  }

  /// Total de la línea según el modo (monto por línea, por tonelada o por unidad).
  int get _totalLinea => _gift ? 0 : (_porLinea ? _priceValue : (_qtyValue * _priceValue).round());

  @override
  Widget build(BuildContext context) {
    final title = _free ? (widget.existing == null ? 'Línea libre' : 'Editar línea') : (widget.product?.displayName ?? widget.existing!.description);
    final available = _available;
    final over = widget.checkStock && available != null && _qtyBase > available + 0.0001;
    final total = _totalLinea;
    final precioUnidad = _porKilo && _enToneladas ? _priceValue / 1000 : _priceValue;
    final belowCost = !_gift && !_porLinea && widget.product != null && precioUnidad > 0 && precioUnidad < widget.product!.avgCost;
    final unidadVista = _porKilo && _enToneladas ? 'tonelada' : _unit;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (available != null && !_free)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Disponible: ${cantidad(available < 0 ? 0 : available)} ${unidadPlural(_unit, available)}',
                    style: TextStyle(color: over ? AppColors.red : AppColors.muted, fontWeight: FontWeight.w600),
                  ),
                ),
              if (_free)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Para cosas que no están en el inventario (flete, mano de obra…). No mueve stock.', style: TextStyle(color: AppColors.muted)),
                ),
              const SizedBox(height: 16),
              if (_free) ...[
                TextFormField(
                  controller: _desc,
                  autofocus: widget.existing == null,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: formatoTexto(Largo.descripcion),
                  decoration: const InputDecoration(labelText: 'Descripción *', hintText: 'Ej: Flete hasta la obra'),
                  validator: validarTexto(campo: 'qué es', obligatorio: true, max: Largo.descripcion),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: unidadesProducto.contains(_unit) ? _unit : 'unidad',
                  decoration: const InputDecoration(labelText: 'Unidad'),
                  items: [for (final u in unidadesProducto) DropdownMenuItem(value: u, child: Text(u))],
                  onChanged: (v) => setState(() => _unit = v ?? 'unidad'),
                ),
                const SizedBox(height: 12),
              ],
              if (_porKilo) ...[
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('Por kilos')),
                    ButtonSegment(value: true, label: Text('Por toneladas')),
                  ],
                  selected: {_enToneladas},
                  onSelectionChanged: (v) => _cambiarUnidadKilo(v.first),
                ),
                const SizedBox(height: 12),
              ],
              // Enter en la cantidad agrega la línea (carga rápida con el teclado).
              CantidadField(
                controller: _qty,
                label: _porCarga ? '¿Cuánto se lleva?' : 'Cantidad',
                enteros: _enteros,
                ayuda: _porCarga ? _ayudaCarga(context) : null,
                suffix: unidadPlural(unidadVista, _qtyValue),
                autofocus: !_free,
                onChanged: (_) => _alCambiarCantidad(),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_porCarga)
                    for (final (q, etiqueta) in const [('1/4', '1/4'), ('1/3', '1/3'), ('1/2', '1/2'), ('2/3', '2/3'), ('3/4', '3/4'), ('1', 'Carga completa'), ('2', '2 cargas')])
                      ActionChip(label: Text(etiqueta), onPressed: () => _setQty(q))
                  else if (_porKilo && !_enToneladas)
                    for (final q in const ['50', '100', '500', '1.000', '2.000', '5.000']) ActionChip(label: Text('$q kg'), onPressed: () => _setQty(q))
                  else
                    for (final q in _enteros
                        ? const ['1', '2', '5', '10', '20', '50', '100', '500', '1.000']
                        : const ['1/4', '1/2', '3/4', '1', '2', '5', '10', '50', '100'])
                      ActionChip(label: Text(q), onPressed: () => _setQty(q)),
                ],
              ),
              const SizedBox(height: 16),
              if (!_gift)
                MontoField(
                  controller: _price,
                  label: _porLinea ? '¿Cuánto cobrás por esto?' : 'Precio por $unidadVista',
                  hint: _porLinea ? 'Ej: 300.000' : (unidadVista == 'tonelada' ? 'Ej: 170.000' : 'Ej: 70.000'),
                  helper: _porCarga
                      ? (_precioCarga > 0
                            ? 'Carga completa: ${gs(_precioCarga)}. Se calcula solo; si cobraste distinto, cambialo.'
                            : 'Este producto no tiene precio de la carga: escribí cuánto cobrás.')
                      : _porLinea
                      ? 'Lo que cobrás por ${cantidad(_qtyValue)} ${unidadPlural(_unit, _qtyValue)}'
                      : widget.product != null && widget.product!.salePrice > 0 && precioUnidad != widget.product!.salePrice
                      ? 'Precio de lista: ${gs(widget.product!.salePrice)} el $_unit'
                      : null,
                  onChanged: (_) => setState(() => _montoEditado = true),
                  onSubmitted: (_) => _submit(),
                  validator: (v) => _gift ? null : validarMonto(campo: 'el precio (o marcalo como regalo)')(v),
                ),
              if (belowCost)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Ojo: este precio es menor a lo que te costó (${gs(widget.product!.avgCost)}). Perdés plata en esta línea.',
                    style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w600),
                  ),
                ),
              if (!_gift) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.sell_outlined, size: 20, color: AppColors.muted),
                    const SizedBox(width: 8),
                    const Text('Descuento', style: TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: const [
                        ButtonSegment(value: 'no', label: Text('No')),
                        ButtonSegment(value: 'pct', label: Text('%')),
                        ButtonSegment(value: 'monto', label: Text('Gs.')),
                      ],
                      selected: {_tipoDesc},
                      onSelectionChanged: (v) => setState(() {
                        _tipoDesc = v.first;
                        _descuento.clear();
                      }),
                    ),
                  ],
                ),
                if (_tipoDesc != 'no') ...[
                  const SizedBox(height: 10),
                  _tipoDesc == 'pct'
                      ? TextFormField(
                          controller: _descuento,
                          keyboardType: TextInputType.number,
                          // Solo números enteros de 1 a 100.
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                          decoration: const InputDecoration(labelText: 'Porcentaje de descuento', hintText: 'Ej: 10', suffixText: '%'),
                          validator: _validarDescuento,
                          onChanged: (_) => setState(() {}),
                        )
                      : MontoField(
                          controller: _descuento,
                          label: 'Monto del descuento',
                          hint: 'Ej: 5.000',
                          validator: _validarDescuento,
                          onChanged: (_) => setState(() {}),
                        ),
                ],
              ],
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _gift,
                onChanged: (v) => setState(() => _gift = v),
                title: const Text('Es un regalo'),
                subtitle: const Text('Sale en el comprobante como REGALO, sin precio'),
                secondary: const Icon(Icons.card_giftcard_rounded),
              ),
              const Divider(height: 24),
              if (!_gift && _descuentoValor > 0)
                Row(
                  children: [
                    Text('${gs(total)} − descuento', style: const TextStyle(color: AppColors.muted)),
                    const Spacer(),
                    Text('− ${gs(_descuentoValor)}', style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
                  ],
                ),
              Row(
                children: [
                  const Text('Total de la línea', style: TextStyle(color: AppColors.muted, fontSize: 15)),
                  const Spacer(),
                  Text(_gift ? 'REGALO' : gs(total - _descuentoValor), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
                ],
              ),
              if (over)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(10)),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: AppColors.red),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('No alcanza el stock. Podés seguir, pero la venta no se va a poder confirmar.', style: TextStyle(color: AppColors.red)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _submit,
                icon: Icon(widget.existing == null ? Icons.add_rounded : Icons.check_rounded),
                label: Text(widget.existing == null ? 'Agregar' : 'Guardar cambios'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
