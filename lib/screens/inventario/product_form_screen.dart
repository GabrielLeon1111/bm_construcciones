import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/product.dart';
import '../../models/purchase.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/product_repository.dart';
import '../../repositories/purchase_repository.dart';
import '../../security/registro_seguro.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../utils/validacion.dart';
import '../../widgets/common.dart';

/// Alta o edición de producto, en preguntas simples:
///   1. ¿Qué producto es?  nombre ("Bolsa de cemento Vallemi"), categoría y descripción breve
///   2. ¿Cuántas compraste? / ¿Cuánto pagaste?  (solo al crear; entra como compra)
///   3. ¿A cuánto la vas a vender?
///   Aviso de poco stock (opcional).
/// La unidad (bolsa, kg, metro...) no se pregunta: se deduce del nombre.
/// Arena, piedra bruta... se compran "por carga": no cuentan stock, se venden en
/// tercios (1/3, 2/3) o la carga completa y la app divide el precio de la carga.
/// Triturada: se compra por tonelada y se vende por kilo o por tonelada (stock en kg).
/// Después de creado, el stock solo cambia con compras, ajustes o averiados.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.product, this.desdeCompra = false});
  final Product? product;

  /// Se crea desde una compra: sin el paso de cantidades (las pone la compra),
  /// el precio de venta es opcional y al guardar devuelve el producto creado.
  final bool desdeCompra;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

/// Unidades que se cuentan en femenino ("¿Cuántas bolsas…?").
const _femeninas = {'unidad', 'bolsa', 'barra', 'caja', 'carga', 'tonelada'};

String _cuantas(String unidad) => _femeninas.contains(unidad) ? 'Cuántas' : 'Cuántos';

/// Pistas para elegir sola la unidad y la categoría a partir del nombre.
// Todo se vende por unidad. Solo la triturada va por kilo (y se compra/vende por tonelada o kilo);
// la arena y la piedra bruta van por carga (ver _pistasPorCarga).
const _pistasUnidad = {
  'triturada': 'kg',
};

/// Materiales que se compran por carga y se venden en tercios o la carga completa.
/// (La triturada no: se compra por tonelada y se vende por kilo.)
const _pistasPorCarga = ['arena', 'piedra', 'ripio', 'tierra', 'granza', 'relleno', 'cascote', 'tosca'];

/// Se venden por unidad con stock: nunca por carga ni por tercios (no se pregunta).
const _pistasPorUnidad = ['ladrillo', 'teja', 'tejuel', 'bloque', 'baldosa', 'azulejo', 'cerámica', 'ceramica'];

const _pistasCategoria = {
  'teja': 'Techos',
  'tejuel': 'Techos',
  'cemento': 'Cementos',
  'cal ': 'Cementos',
  'arena': 'Áridos',
  'piedra': 'Áridos',
  'triturada': 'Áridos',
  'ripio': 'Áridos',
  'varilla': 'Hierros',
  'hierro': 'Hierros',
  'alambre': 'Hierros',
  'ladrillo': 'Ladrillos y bloques',
  'bloque': 'Ladrillos y bloques',
  'caño': 'Caños y plomería',
  'cano': 'Caños y plomería',
  'codo': 'Caños y plomería',
  'cable': 'Electricidad',
  'murocal': 'Murocal',
  'poste': 'Postes',
  'bacha': 'Caños y plomería',
  'pintura': 'Pinturas',
  'látex': 'Pinturas',
  'latex': 'Pinturas',
};

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _category = TextEditingController(text: widget.product?.category ?? '');
  late final _brand = TextEditingController(text: widget.product?.brand ?? '');
  // Los productos por kilo muestran el precio por tonelada (más cómodo de escribir).
  late final _price = TextEditingController(
    text: widget.product == null || widget.product!.salePrice == 0
        ? ''
        : miles(widget.product!.unit == 'kg' ? widget.product!.salePrice * 1000 : widget.product!.salePrice),
  );
  late final _min = TextEditingController(text: widget.product == null ? '' : cantidad(widget.product!.minStock));

  /// Descripción breve para identificar el producto (se guarda en notas).
  late final _notes = TextEditingController(text: widget.product?.notes ?? '');
  final _qty = TextEditingController();
  final _paid = TextEditingController();
  final _catFocus = FocusNode();
  late String _unit = widget.product?.unit ?? 'unidad';
  bool _catElegida = false;

  /// true: lo que pagó es el total · false: es por cada una.
  bool _pagoTotal = true;
  late bool _porCarga = widget.product?.soldByLoad ?? false;
  bool _porCargaElegido = false;

  /// Ladrillos, tejas, tejuelones...: por unidad con stock, sin preguntar.
  bool _esPorUnidad = false;

  /// Productos por kilo (triturada): la compra y el precio se escriben por tonelada.
  bool _compraEnToneladas = true;
  bool _precioPorTonelada = true;
  bool _saving = false;

  /// Id del producto nuevo, fijo mientras la pantalla está abierta (evita duplicados).
  /// También es la clave de la compra inicial, así un reintento no la duplica.
  final String _newId = const Uuid().v4();

  bool get _isNew => widget.product == null;
  bool get _porKilo => _unit == 'kg' && !_porCarga;

  /// Cantidad escrita, en la unidad del producto (las toneladas se pasan a kg).
  double get _cantidad => (leerCantidad(_qty.text) ?? 0) * (_porKilo && _compraEnToneladas ? 1000 : 1);
  int get _pagado => leerMonto(_paid.text) ?? 0;

  /// Lo que costó cada una (si cargó el total, se divide).
  int get _costoUnitario {
    if (_cantidad <= 0) return 0;
    if (_pagoTotal) return (_pagado / _cantidad).round();
    return _porKilo && _compraEnToneladas ? (_pagado / 1000).round() : _pagado;
  }

  /// Precio de venta por unidad del producto (por kilo si se escribió por tonelada).
  int get _precio {
    final v = leerMonto(_price.text) ?? 0;
    return _porKilo && _precioPorTonelada ? (v / 1000).round() : v;
  }

  /// Nombre de la unidad en que se escribe la compra.
  String get _unidadCompra => _porKilo && _compraEnToneladas ? 'tonelada' : _unit;

  /// Lo que entra como compra al crear: por carga es 1 carga a lo que se pagó.
  double get _qtyCompra => _porCarga ? (_pagado > 0 ? 1 : 0) : _cantidad;
  int get _costoCompra => _porCarga ? _pagado : _costoUnitario;

  @override
  void dispose() {
    _catFocus.dispose();
    super.dispose();
  }

  /// Mientras escribe el nombre, sugiere unidad y categoría (si no las eligió a mano).
  void _alCambiarNombre(String v) {
    final t = ' ${v.toLowerCase()} ';
    setState(() {
      if (_isNew) {
        _esPorUnidad = _pistasPorUnidad.any(t.contains);
        if (_esPorUnidad) {
          _porCarga = false;
        } else if (!_porCargaElegido) {
          _porCarga = !t.contains('triturada') && _pistasPorCarga.any(t.contains);
        }
        _unit = 'unidad';
        for (final e in _pistasUnidad.entries) {
          if (t.contains(e.key)) {
            _unit = e.value;
            break;
          }
        }
        if (_porCarga) _unit = 'carga';
        if (_esPorUnidad) _unit = 'unidad';
      }
      if (!_catElegida && _isNew) {
        for (final e in _pistasCategoria.entries) {
          if (t.contains(e.key)) {
            _category.text = e.value;
            break;
          }
        }
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) {
      showSnack(context, 'Revisá los campos marcados en rojo.', error: true);
      return;
    }
    final qty = _isNew && !widget.desdeCompra ? _qtyCompra : 0.0;
    if (qty > 0 && qty * _costoCompra > montoMaximo) {
      showSnack(context, 'El total pagado pasa de ${gs(montoMaximo)}. Revisá los números.', error: true);
      return;
    }
    // Anti-error: vender por debajo de lo que costó.
    if (!_porCarga && qty > 0 && _precio > 0 && _precio < _costoUnitario) {
      final seguir = await confirmar(
        context,
        titulo: '¿Vender más barato de lo que costó?',
        mensaje: 'Cada $_unit te costó ${gs(_costoUnitario)} y lo vas a vender a ${gs(_precio)}. Perdés plata en cada venta.',
        si: 'Sí, está bien',
      );
      if (!seguir || !mounted) return;
    }

    setState(() => _saving = true);
    final nombre = limpiarTexto(_name.text);
    final data = Product(
      id: widget.product?.id ?? _newId,
      name: nombre,
      category: limpiarTexto(_category.text),
      brand: limpiarTexto(_brand.text).isEmpty ? null : limpiarTexto(_brand.text),
      unit: _porCarga ? 'carga' : _unit,
      soldByLoad: _porCarga,
      stock: 0,
      avgCost: 0,
      salePrice: _precio,
      minStock: leerCantidad(_min.text) ?? 0,
      active: widget.product?.active ?? true,
      notes: limpiarTexto(_notes.text),
    );
    try {
      final repo = context.read<ProductRepository>();
      final compras = context.read<PurchaseRepository>();
      Product? creado;
      if (_isNew) {
        creado = await repo.create(_newId, data);
        // Lo que compró entra como una compra: suma stock, fija el costo y cuenta como invertido.
        if (qty > 0) {
          await compras.create(
            items: [PurchaseItem(productId: _newId, productName: nombre, unit: _porCarga ? 'carga' : _unit, quantity: qty, unitCost: _costoCompra)],
            notes: _porCarga ? 'Primera carga' : 'Carga inicial del producto',
            idempotencyKey: _newId,
          );
        }
      } else {
        await repo.update(widget.product!.id, data);
      }
      if (!mounted) return;
      await context.read<CatalogProvider>().cargarProductos();
      if (!mounted) return;
      context.read<RefreshBus>().changed();
      if (widget.desdeCompra) {
        showSnack(context, 'Producto creado: ahora poné cuánto compraste');
        Navigator.pop(context, creado);
        return;
      }
      showSnack(
        context,
        !_isNew
            ? 'Cambios guardados'
            : _porCarga
            ? (qty > 0 ? 'Producto creado con la carga de ${gs(_pagado)}' : 'Producto creado')
            : (qty > 0 ? 'Producto creado con ${cantidad(qty)} ${unidadPlural(_unit, qty)} en stock' : 'Producto creado'),
      );
      Navigator.pop(context);
    } catch (e) {
      registrarError('guardarProducto', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e, 'No se pudo guardar el producto.'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _autocomplete(
    TextEditingController ctrl,
    FocusNode focusNode,
    List<String> options,
    String label, {
    String? Function(String?)? validator,
    String? hint,
    int max = Largo.categoria,
    VoidCallback? onEdit,
  }) {
    return RawAutocomplete<String>(
      textEditingController: ctrl,
      focusNode: focusNode,
      optionsBuilder: (v) => v.text.isEmpty ? options : options.where((o) => coincide(o, v.text)),
      fieldViewBuilder: (context, c, focus, onSubmit) => TextFormField(
        controller: c,
        focusNode: focus,
        textCapitalization: TextCapitalization.sentences,
        inputFormatters: formatoTexto(max),
        decoration: InputDecoration(labelText: label, hintText: hint),
        validator: validator,
        onChanged: (_) => onEdit?.call(),
      ),
      onSelected: (_) => onEdit?.call(),
      optionsViewBuilder: (context, onSelected, opts) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220, maxWidth: 360),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [for (final o in opts) ListTile(dense: true, title: Text(o), onTap: () => onSelected(o))],
            ),
          ),
        ),
      ),
    );
  }

  /// Bloque con título de pregunta grande.
  Widget _bloque(String numero, String titulo, List<Widget> children) => Container(
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: AppColors.yellow,
              child: Text(
                numero,
                style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.ink, fontSize: 13),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final catalog = context.read<CatalogProvider>();
    final cats = {...catalog.categories, ..._pistasCategoria.values}.toList()..sort();
    final plural = unidadPlural(_unit, 2);
    final qty = _cantidad;
    final costo = _costoUnitario;
    final ganancia = _precio - costo;

    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? (widget.desdeCompra ? 'Producto nuevo (compra)' : 'Nuevo producto') : 'Editar producto')),
      body: Form(
        key: _form,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: EdgeInsets.fromLTRB(margenLateral(context), 0, margenLateral(context), 32),
              children: [
                // ---------- 1. Qué es ----------
                _bloque('1', '¿Qué producto es?', [
                  TextFormField(
                    controller: _name,
                    autofocus: _isNew,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: formatoTexto(Largo.nombre),
                    decoration: const InputDecoration(labelText: 'Nombre del producto *', hintText: 'Ej: Bolsa de cemento Vallemi'),
                    validator: validarTexto(campo: 'el nombre', obligatorio: true, max: Largo.nombre),
                    onChanged: _alCambiarNombre,
                  ),
                  const SizedBox(height: 12),
                  _autocomplete(
                    _category,
                    _catFocus,
                    cats,
                    'Categoría (opcional)',
                    hint: 'Ej: Cementos',
                    validator: validarTexto(campo: 'la categoría', max: Largo.categoria),
                    onEdit: () => _catElegida = true,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notes,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: formatoTexto(Largo.descripcion),
                    decoration: const InputDecoration(
                      labelText: 'Descripción breve (opcional)',
                      hintText: 'Ej: bolsa de 50 kg, gris',
                      helperText: 'Para reconocerlo rápido al buscar',
                    ),
                    validator: validarTexto(campo: 'la descripción', max: Largo.descripcion),
                  ),
                  const SizedBox(height: 6),
                  if (_isNew && _esPorUnidad)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Se vende por unidad y se controla el stock.', style: TextStyle(color: AppColors.muted)),
                    )
                  else if (_isNew)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _porCarga,
                      onChanged: (v) => setState(() {
                        _porCarga = v;
                        _porCargaElegido = true;
                        if (v) {
                          _unit = 'carga';
                        } else {
                          _alCambiarNombre(_name.text);
                        }
                      }),
                      title: const Text('Se compra por carga', style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text(
                        'Arena, piedra bruta… Comprás por carga y vendés en tercios (1/3, 2/3) o la carga completa. '
                        'No cuenta stock: la app suma lo vendido hasta recuperar lo que pagaste.',
                      ),
                    )
                  else if (_porCarga)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Se compra por carga y se vende en tercios o la carga completa.', style: TextStyle(color: AppColors.muted)),
                    ),
                ]),

                // ---------- 2. Cantidades (solo al crear) ----------
                if (_isNew && !widget.desdeCompra && _porCarga)
                  _bloque('2', 'La carga', [
                    MontoField(controller: _paid, label: '¿Cuánto pagaste por la carga?', hint: 'Ej: 1.200.000', onChanged: (_) => setState(() {})),
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Cada venta (1/3, 2/3 o la carga completa) se va sumando hasta recuperar lo que pagaste. '
                        'Si todavía no llegó, dejalo vacío.',
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ),
                  ]),
                if (_isNew && !widget.desdeCompra && !_porCarga)
                  _bloque('2', 'Cantidades', [
                    if (_porKilo) ...[
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: true, label: Text('Compré por toneladas')),
                          ButtonSegment(value: false, label: Text('Por kilos')),
                        ],
                        selected: {_compraEnToneladas},
                        onSelectionChanged: (v) => setState(() => _compraEnToneladas = v.first),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilaCampos(
                      children: [
                        Expanded(
                          child: CantidadField(
                            controller: _qty,
                            label: '¿${_cuantas(_unidadCompra)} ${unidadPlural(_unidadCompra, 2)} compraste?',
                            enteros: !_porKilo,
                            suffix: unidadPlural(_unidadCompra, 2),
                            obligatorio: false,
                            allowZero: true,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MontoField(
                            controller: _paid,
                            label: _pagoTotal ? '¿Cuánto pagaste en total?' : '¿Cuánto pagaste por cada $_unidadCompra?',
                            hint: _pagoTotal ? 'Ej: 550.000' : 'Ej: 55.000',
                            onChanged: (_) => setState(() {}),
                            validator: (v) => qty > 0 ? validarMonto(campo: 'cuánto pagaste')(v) : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: [
                        const ButtonSegment(value: true, label: Text('Pagué en total')),
                        ButtonSegment(value: false, label: Text('Pagué por cada $_unidadCompra', overflow: TextOverflow.ellipsis)),
                      ],
                      selected: {_pagoTotal},
                      onSelectionChanged: (s) => setState(() => _pagoTotal = s.first),
                    ),
                    if (qty > 0 && _pagado > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppColors.yellowSoft, borderRadius: BorderRadius.circular(10)),
                        child: Text(
                          _pagoTotal
                              ? (_porKilo ? 'Cada kilo te salió ${gs(costo)} (${gs(costo * 1000)} la tonelada)' : 'Cada $_unit te salió ${gs(costo)}')
                              : 'En total pagaste ${gs((qty * costo).round())}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Si todavía no tenés, dejalo vacío. Después lo cargás desde Compras.',
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ),
                  ]),

                // ---------- 3. Precio de venta ----------
                _bloque(_isNew && !widget.desdeCompra ? '3' : '2', '¿A cuánto lo vas a vender?', [
                  if (_porKilo) ...[
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: true, label: Text('Precio por tonelada')),
                        ButtonSegment(value: false, label: Text('Por kilo')),
                      ],
                      selected: {_precioPorTonelada},
                      onSelectionChanged: (v) => setState(() {
                        // Se convierte lo ya escrito para no perderlo.
                        final actual = leerMonto(_price.text) ?? 0;
                        _precioPorTonelada = v.first;
                        if (actual > 0) _price.text = miles(_precioPorTonelada ? actual * 1000 : (actual / 1000).round());
                      }),
                    ),
                    const SizedBox(height: 12),
                  ],
                  MontoField(
                    controller: _price,
                    label: _porCarga
                        ? '¿A cuánto vendés la carga completa?${widget.desdeCompra ? '' : ' *'}'
                        : _porKilo
                        ? 'Precio de venta por ${_precioPorTonelada ? 'tonelada' : 'kilo'}${widget.desdeCompra ? ' (opcional)' : ' *'}'
                        : 'Precio de venta por $_unit${widget.desdeCompra ? ' (opcional)' : ' *'}',
                    hint: _porCarga ? 'Ej: 900.000' : (_porKilo && _precioPorTonelada ? 'Ej: 170.000' : 'Ej: 70.000'),
                    helper: _porCarga && _precio > 0
                        ? 'Al vender se divide solo: 1/3 = ${gs((_precio / 3).round())} · 2/3 = ${gs((_precio * 2 / 3).round())}'
                        : _porKilo && _precio > 0
                        ? '= ${gs(_precio)} el kilo · ${gs(_precio * 1000)} la tonelada'
                        : widget.desdeCompra
                        ? 'Lo podés poner ahora o después, al vender'
                        : null,
                    onChanged: (_) => setState(() {}),
                    validator: validarMonto(campo: 'el precio de venta', obligatorio: !widget.desdeCompra, min: widget.desdeCompra ? 0 : 1),
                  ),
                  if (!_porCarga && costo > 0 && _precio > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        ganancia >= 0
                            ? 'Ganás ${gs(ganancia)} por cada $_unit (${(ganancia * 100 / _precio).toStringAsFixed(0)}%)'
                            : 'Ojo: perdés ${gs(-ganancia)} por cada $_unit',
                        style: TextStyle(fontWeight: FontWeight.w700, color: ganancia >= 0 ? AppColors.green : AppColors.red),
                      ),
                    ),
                ]),

                if (!_isNew)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
                    child: Text('El stock no se cambia acá: usá Cargar compra, Ajustar stock o Averiados.', style: TextStyle(color: AppColors.muted)),
                  ),

                // ---------- Aviso de poco stock (no aplica a productos por carga) ----------
                if (!_porCarga)
                  Container(
                    margin: const EdgeInsets.only(top: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                      border: Border.all(color: AppColors.line),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      title: const Text('Aviso de poco stock (opcional)', style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('Te avisa cuando se está por terminar'),
                      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                      children: [
                        TextFormField(
                          controller: _min,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [_porKilo ? CantidadInputFormatter() : MilesInputFormatter()],
                          decoration: InputDecoration(
                            labelText: '¿Con ${_cuantas(_unit).toLowerCase()} te aviso que queda poco?',
                            hintText: 'Ej: 10',
                            suffixText: plural,
                          ),
                          validator: validarCantidad(obligatorio: false, permitirCero: true, soloEnteros: !_porKilo),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 22),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : Text(
                          _isNew ? (widget.desdeCompra ? 'Crear y seguir con la compra' : 'Guardar producto') : 'Guardar cambios',
                          style: const TextStyle(fontSize: 17),
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
