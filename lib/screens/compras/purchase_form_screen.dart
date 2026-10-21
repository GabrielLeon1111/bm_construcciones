import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/product.dart';
import '../../models/purchase.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/purchase_repository.dart';
import '../../security/registro_seguro.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../utils/validacion.dart';
import '../../widgets/common.dart';
import '../../widgets/product_picker.dart';
import '../../widgets/supplier_picker.dart';
import '../inventario/product_form_screen.dart';
import 'purchase_detail_screen.dart';

/// Cargar una compra al proveedor: suma stock y recalcula el costo promedio.
class PurchaseFormScreen extends StatefulWidget {
  const PurchaseFormScreen({super.key, this.initialProduct});
  final Product? initialProduct;

  @override
  State<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends State<PurchaseFormScreen> {
  final _supplier = TextEditingController();
  final _invoice = TextEditingController();
  final _notes = TextEditingController();
  final _supplierFocus = FocusNode();
  final List<PurchaseItem> _items = [];
  bool _saving = false;

  /// Día de la compra (el de la factura). Por defecto hoy; se puede elegir un día anterior.
  DateTime _dia = _hoy();
  static DateTime _hoy() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }
  final _formKey = GlobalKey<FormState>();

  /// Clave de la operación: dura todo el formulario (ver DraftDocument.idempotencyKey).
  final String _key = const Uuid().v4();

  int get _total => _items.fold(0, (a, i) => a + i.lineTotal);

  @override
  void initState() {
    super.initState();
    if (widget.initialProduct != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _addItem(widget.initialProduct));
    }
  }

  @override
  void dispose() {
    _supplierFocus.dispose();
    super.dispose();
  }

  String get _diaTexto {
    final dif = _hoy().difference(_dia).inDays;
    final f = fechaCorta.format(_dia);
    return dif == 0 ? 'Hoy · $f' : (dif == 1 ? 'Ayer · $f' : f);
  }

  Future<void> _elegirDia() async {
    final hoy = _hoy();
    final d = await showDatePicker(
      context: context,
      helpText: '¿Qué día compraste?',
      initialDate: _dia,
      firstDate: DateTime(hoy.year - 2, hoy.month, hoy.day),
      lastDate: hoy,
    );
    if (d != null && mounted) setState(() => _dia = d);
  }

  Future<void> _elegirProveedor() async {
    final s = await pickSupplier(context);
    if (s != null && mounted) setState(() => _supplier.text = s.name);
  }

  /// Producto que no está en el inventario: se crea en el momento y se agrega a esta compra.
  Future<void> _productoNuevo() async {
    final p = await Navigator.push<Product>(context, MaterialPageRoute(builder: (_) => const ProductFormScreen(desdeCompra: true)));
    if (p != null && mounted) await _addItem(p);
  }

  Future<void> _addItem([Product? preset, int? editIndex]) async {
    final p = preset ?? await pickProduct(context, showCost: true, permitirCrear: true);
    if (p == null || !mounted) return;
    final item = await showModalBottomSheet<PurchaseItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ItemSheet(product: p, existing: editIndex == null ? null : _items[editIndex]),
    );
    if (item == null) return;
    setState(() {
      if (editIndex == null) {
        _items.add(item);
      } else {
        _items[editIndex] = item;
      }
    });
  }

  Future<void> _save() async {
    if (_items.isEmpty || _saving) return;
    if (!_formKey.currentState!.validate()) return;
    if (_total > montoMaximo) {
      showSnack(context, 'El total pasa de ${gs(montoMaximo)}. Dividí la compra en dos.', error: true);
      return;
    }
    final ok = await confirmar(
      context,
      titulo: 'Registrar compra',
      mensaje: 'Entran ${_items.length} ${_items.length == 1 ? 'material' : 'materiales'} por un total de ${gs(_total)}.\n'
          'Día de la compra: ${_diaTexto.toLowerCase()}. El stock se actualiza ahora.',
      si: 'Registrar',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    final repo = context.read<PurchaseRepository>();
    try {
      final purchase = await repo.create(
        items: _items,
        supplier: limpiarTexto(_supplier.text),
        invoiceNumber: limpiarTexto(_invoice.text),
        notes: limpiarTexto(_notes.text, multilinea: true),
        purchasedOn: _dia,
        idempotencyKey: _key,
      );
      if (!mounted) return;
      await context.read<CatalogProvider>().cargarProductos();
      if (!mounted) return;
      context.read<RefreshBus>().changed();
      showSnack(context, 'Compra registrada: el stock ya está actualizado');
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PurchaseDetailScreen(purchaseId: purchase.id)));
    } catch (e) {
      registrarError('guardarCompra', e);
      // La compra ya había entrado y después se cambió el formulario: se muestra la registrada.
      if (esYaRegistrada(e)) {
        final previa = await repo.findIdByKey(_key).catchError((Object _) => null);
        if (!mounted) return;
        showSnack(context, mensajeErrorSeguro(e), error: true);
        if (previa != null) {
          await context.read<CatalogProvider>().cargarProductos();
          if (!mounted) return;
          context.read<RefreshBus>().changed();
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PurchaseDetailScreen(purchaseId: previa)));
        }
        return;
      }
      if (mounted) showSnack(context, mensajeErrorSeguro(e, 'No se pudo registrar la compra.'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva compra')),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      // Proveedor guardado (se elige de la lista o se crea uno nuevo).
                      TextFormField(
                        controller: _supplier,
                        readOnly: true,
                        onTap: _elegirProveedor,
                        decoration: InputDecoration(
                          labelText: 'Proveedor (opcional)',
                          hintText: 'Tocá para elegir o crear uno',
                          prefixIcon: const Icon(Icons.store_outlined),
                          suffixIcon: _supplier.text.isEmpty
                              ? const Icon(Icons.arrow_drop_down_rounded)
                              : IconButton(
                                  tooltip: 'Quitar proveedor',
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () => setState(() => _supplier.clear()),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _invoice,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z-]')), LengthLimitingTextInputFormatter(Largo.factura)],
                        decoration: const InputDecoration(
                          labelText: 'N° de factura (opcional)',
                          hintText: 'Ej: 001-001-0001234',
                          prefixIcon: Icon(Icons.receipt_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Día de la compra: hoy, salvo que se cargue una factura de otro día.
                      InkWell(
                        onTap: _elegirDia,
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Día de la compra',
                            helperText: 'Si la factura es de otro día, tocá para cambiarlo',
                            prefixIcon: Icon(Icons.event_outlined),
                            suffixIcon: Icon(Icons.arrow_drop_down_rounded),
                          ),
                          child: Text(_diaTexto, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                      SectionTitle(
                        'Materiales que entran',
                        trailing: TextButton.icon(onPressed: _productoNuevo, icon: const Icon(Icons.add, size: 18), label: const Text('Producto nuevo')),
                      ),
                      if (_items.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.line, width: 1.5),
                            borderRadius: BorderRadius.circular(AppTheme.radius),
                          ),
                          child: const Text(
                            'Agregá los materiales de la factura.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.muted),
                          ),
                        )
                      else
                        Card(
                          child: Column(
                            children: [
                              for (var i = 0; i < _items.length; i++) ...[
                                if (i > 0) const Divider(indent: 14, endIndent: 14),
                                ListTile(
                                  onTap: () => _addItem(catalog.productById(_items[i].productId), i),
                                  title: Text(_items[i].productName),
                                  subtitle: Text(
                                    '${cantidad(_items[i].quantity)} ${unidadPlural(_items[i].unit, _items[i].quantity)} × ${gs(_items[i].unitCost)}'
                                    '${_items[i].newSalePrice == null ? '' : '\nNuevo precio de venta: ${gs(_items[i].newSalePrice!)}'}',
                                  ),
                                  isThreeLine: _items[i].newSalePrice != null,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(miles(_items[i].lineTotal), style: const TextStyle(fontWeight: FontWeight.w800)),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.muted),
                                        onPressed: () => setState(() => _items.removeAt(i)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(onPressed: () => _addItem(), icon: const Icon(Icons.add_rounded), label: const Text('Agregar material')),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _notes,
                        textCapitalization: TextCapitalization.sentences,
                        inputFormatters: formatoTexto(Largo.notas),
                        decoration: const InputDecoration(labelText: 'Notas (opcional)', hintText: 'Ej: llegó con 2 bolsas rotas'),
                        validator: validarTexto(campo: 'las notas', max: Largo.notas, multilinea: true),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                    onPressed: _items.isEmpty || _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Icon(Icons.check_circle_outline_rounded),
                    label: Text(_items.isEmpty ? 'Agregá materiales' : 'Registrar compra · ${gs(_total)}', style: const TextStyle(fontSize: 17)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({required this.product, this.existing});
  final Product product;
  final PurchaseItem? existing;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  final _form = GlobalKey<FormState>();
  // Por carga (arena, piedra bruta): arranca en 1 carga.
  late final _qty = TextEditingController(
    text: widget.existing != null ? cantidad(widget.existing!.quantity) : (widget.product.soldByLoad ? '1' : ''),
  );
  late final _cost = TextEditingController(
    text: widget.existing != null
        ? miles(widget.existing!.unitCost)
        : (!widget.product.soldByLoad && widget.product.avgCost > 0 ? miles(widget.product.avgCost) : ''),
  );

  /// Triturada (por kilo): se compra por toneladas; el stock queda en kilos.
  late final bool _porKilo = widget.product.unit == 'kg' && !widget.product.soldByLoad;
  late bool _enToneladas = _porKilo && widget.existing == null;

  // En productos por kilo el precio de venta se escribe por tonelada.
  late final _price = TextEditingController(text: widget.existing?.newSalePrice == null ? '' : miles(widget.existing!.newSalePrice! * (_porKilo ? 1000 : 1)));
  late bool _changePrice = widget.existing?.newSalePrice != null || (!widget.product.soldByLoad && widget.product.salePrice == 0);

  /// false: lo que escribe es por cada una · true: es el total que pagó.
  bool _pagoTotal = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    // Por carga (arena, piedra...): cuántas cargas y cuánto se pagó por cada una.
    final porCarga = p.soldByLoad;
    final factor = _porKilo && _enToneladas ? 1000 : 1;
    // Cantidad en la unidad del producto (toneladas → kilos).
    final q = (leerCantidad(_qty.text) ?? 0) * factor;
    final escrito = leerMonto(_cost.text) ?? 0;
    // Costo por unidad: si cargó el total, se divide por la cantidad.
    final c = _pagoTotal ? (q > 0 ? (escrito / q).round() : 0) : (escrito / factor).round();
    final unidadCompra = _porKilo && _enToneladas ? 'tonelada' : p.unit;
    final plural = unidadPlural(unidadCompra, 2);
    final cuantas = const {'unidad', 'bolsa', 'barra', 'caja', 'carga', 'tonelada'}.contains(unidadCompra) ? 'Cuántas' : 'Cuántos';
    final precioEscrito = leerMonto(_price.text);
    final precioNuevo = precioEscrito == null ? null : (_porKilo ? (precioEscrito / 1000).round() : precioEscrito);
    final newAvg = (p.stock + q) > 0 ? ((p.stock * p.avgCost + q * c) / (p.stock + q)).round() : c;
    final price = _changePrice ? (precioNuevo ?? p.salePrice) : p.salePrice;
    final margin = price > 0 ? (price - newAvg) / price * 100 : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(p.name, style: Theme.of(context).textTheme.titleLarge),
              Text(
                porCarga
                    ? 'Se compra por carga. Si hay una carga abierta, se suma a esa (misma pila).'
                    : 'Hay ${cantidad(p.stock)} ${unidadPlural(p.unit, p.stock)} · costo promedio ${gs(p.avgCost)}',
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              ...[
                if (_porKilo) ...[
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: true, label: Text('Compré por toneladas')),
                      ButtonSegment(value: false, label: Text('Por kilos')),
                    ],
                    selected: {_enToneladas},
                    onSelectionChanged: (v) => setState(() => _enToneladas = v.first),
                  ),
                  const SizedBox(height: 12),
                ],
                FilaCampos(
                  anchoMinimo: porCarga ? 0 : 520,
                  children: [
                    Expanded(
                      child: CantidadField(
                        controller: _qty,
                        label: porCarga ? '¿Cuántas cargas?' : '¿$cuantas $plural compraste?',
                        ayuda: porCarga ? 'Ej: 1, 2 o 3' : null,
                        enteros: !p.cantidadLibre,
                        suffix: plural,
                        autofocus: !porCarga,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MontoField(
                        controller: _cost,
                        autofocus: porCarga,
                        label: porCarga
                            ? (_pagoTotal ? '¿Cuánto en total?' : '¿Cuánto por carga?')
                            : (_pagoTotal ? '¿Cuánto pagaste en total?' : '¿Cuánto pagaste por cada $unidadCompra?'),
                        onChanged: (_) => setState(() {}),
                        hint: porCarga ? 'Ej: 400.000' : (_pagoTotal ? 'Ej: 550.000' : 'Ej: 55.000'),
                        validator: validarMonto(campo: 'cuánto pagaste (si fue sin cargo, poné 0)', min: 0),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: false, label: Text('Por cada $unidadCompra', overflow: TextOverflow.ellipsis)),
                    const ButtonSegment(value: true, label: Text('En total')),
                  ],
                  selected: {_pagoTotal},
                  onSelectionChanged: (sel) => setState(() => _pagoTotal = sel.first),
                ),
                if (_pagoTotal && q > 0 && escrito > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _porKilo ? 'Cada kilo te salió ${gs(c)} (${gs(c * 1000)} la tonelada)' : 'Cada ${p.unit} te salió ${gs(c)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _changePrice,
                onChanged: (v) => setState(() => _changePrice = v),
                title: const Text('Cambiar el precio de venta'),
                subtitle: Text(
                  p.salePrice == 0
                      ? 'Todavía no tiene precio de venta (opcional)'
                      : _porKilo
                      ? 'Ahora: ${gs(p.salePrice * 1000)} la tonelada'
                      : 'Ahora: ${gs(p.salePrice)} por ${p.unit}',
                ),
              ),
              if (_changePrice)
                MontoField(
                  controller: _price,
                  label: _porKilo ? '¿A cuánto vendés la tonelada?' : '¿A cuánto lo vas a vender ahora?',
                  hint: 'Ej: 70.000',
                  onChanged: (_) => setState(() {}),
                  // Opcional: si queda vacío, el producto sigue sin precio y se pone al vender.
                  validator: (v) => _changePrice ? validarMonto(campo: 'el precio', obligatorio: p.salePrice > 0)(v) : null,
                ),
              if (porCarga && q > 0 && c > 0)
                Container(
                  margin: const EdgeInsets.only(top: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.yellowSoft, borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ESTA COMPRA', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1)),
                      const SizedBox(height: 6),
                      KeyValueRow('Cargas', '${cantidad(q)} ${unidadPlural('carga', q)} a ${gs(c)} cada una'),
                      KeyValueRow('Total pagado', gs((q * c).round()), bold: true),
                      if (price > 0)
                        KeyValueRow(
                          'Ganancia por carga (vendiendo a ${gs(price)})',
                          gs(price - c),
                          valueColor: price >= c ? AppColors.green : AppColors.red,
                        ),
                    ],
                  ),
                ),
              if (!porCarga && q > 0 && c > 0)
                Container(
                  margin: const EdgeInsets.only(top: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.yellowSoft, borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('DESPUÉS DE ESTA COMPRA', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1)),
                      const SizedBox(height: 6),
                      KeyValueRow('Stock', '${cantidad(p.stock + q)} ${unidadPlural(p.unit, p.stock + q)}'),
                      KeyValueRow('Costo promedio', gs(newAvg), bold: true),
                      KeyValueRow(
                        'Margen con ${gs(price)}',
                        margin == null ? '—' : '${margin.toStringAsFixed(1)}%',
                        valueColor: (margin ?? 0) >= 0 ? AppColors.green : AppColors.red,
                      ),
                      KeyValueRow('Subtotal de la línea', gs((q * c).round())),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () {
                  if (!_form.currentState!.validate()) return;
                  if (q * c > montoMaximo) {
                    showSnack(context, 'El subtotal pasa de ${gs(montoMaximo)}. Revisá la cantidad y el costo.', error: true);
                    return;
                  }
                  Navigator.pop(
                    context,
                    PurchaseItem(
                      productId: p.id,
                      productName: p.name,
                      unit: porCarga ? 'carga' : p.unit,
                      quantity: q,
                      unitCost: c,
                      newSalePrice: _changePrice && (precioNuevo ?? 0) > 0 ? precioNuevo : null,
                    ),
                  );
                },
                child: Text(widget.existing == null ? 'Agregar' : 'Guardar cambios'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
