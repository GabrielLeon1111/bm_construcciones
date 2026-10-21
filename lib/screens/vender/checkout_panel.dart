import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../models/sale.dart';
import '../../providers/caja_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/draft_document.dart';
import '../../providers/refresh_bus.dart';
import '../../repositories/sale_repository.dart';
import '../../security/registro_seguro.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../utils/validacion.dart';
import '../../widgets/client_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/doc_editor.dart';
import '../../widgets/line_sheet.dart';
import '../../widgets/product_picker.dart';
import 'sale_done_screen.dart';

/// Agrega un producto a la venta en curso: pide cantidad y precio. Avisa si está agotado.
Future<void> agregarAlCarrito(BuildContext context, Product p) async {
  final cart = context.read<DraftDocument>();
  if (p.isOut) {
    showSnack(context, '"${p.name}" está agotado. Cargá una compra para tener stock.', error: true);
    return;
  }
  final line = await showLineSheet(context, product: p, alreadyInDoc: cart.qtyOf(p.id));
  if (line == null) return;
  cart.addProduct(p, line.quantity,
      price: line.unitPrice, gift: line.isGift, priceIsTotal: line.priceIsTotal, discountPct: line.discountPct, discountAmount: line.discountAmount);
  if (context.mounted) showSnack(context, 'Agregado: ${cantidad(line.quantity)} ${unidadPlural(p.unit, line.quantity)} de ${p.name}');
}

/// Pantalla completa de cobro (celular).
class CheckoutScreen extends StatelessWidget {
  const CheckoutScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Confirmar venta')),
    body: const CheckoutPanel(),
  );
}

/// Detalle de la venta en curso: materiales, cliente, método de pago y total.
class CheckoutPanel extends StatefulWidget {
  const CheckoutPanel({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<CheckoutPanel> createState() => _CheckoutPanelState();
}

class _CheckoutPanelState extends State<CheckoutPanel> with WidgetsBindingObserver {
  bool _saving = false;
  bool _verificando = false;
  late final TextEditingController _notes;

  // Pago: efectivo (con cuánto paga → vuelto) o mixto (parte y parte).
  final _recibido = TextEditingController();
  final _mixEfectivo = TextEditingController();
  final _mixTransfer = TextEditingController();
  bool _transferEditada = false;

  int get _recibidoValor => leerMonto(_recibido.text) ?? 0;
  int get _mixEfectivoValor => leerMonto(_mixEfectivo.text) ?? 0;
  int get _mixTransferValor => leerMonto(_mixTransfer.text) ?? 0;

  /// Se puede cobrar: efectivo cubre el total; mixto suma exactamente el total.
  bool _pagoOk(DraftDocument cart) => switch (cart.paymentMethod) {
    'efectivo' => _recibidoValor >= cart.total,
    'mixto' => _mixEfectivoValor + _mixTransferValor == cart.total,
    _ => true,
  };

  /// Por qué todavía no se puede cobrar (para el botón).
  String _faltaPago(DraftDocument cart) => switch (cart.paymentMethod) {
    'efectivo' => _recibido.text.trim().isEmpty ? 'Poné con cuánto paga' : 'No alcanza: faltan ${gs(cart.total - _recibidoValor)}',
    'mixto' =>
      _mixEfectivoValor + _mixTransferValor < cart.total
          ? 'Falta ${gs(cart.total - _mixEfectivoValor - _mixTransferValor)}'
          : 'Sobra ${gs(_mixEfectivoValor + _mixTransferValor - cart.total)}',
    _ => '',
  };

  @override
  void initState() {
    super.initState();
    final cart = context.read<DraftDocument>();
    _notes = TextEditingController(text: cart.notes);
    // Lo escrito en el pago vuelve tal cual (se guarda en el celular).
    final pago = cart.pagoCampos;
    _recibido.text = pago['recibido'] ?? '';
    _mixEfectivo.text = pago['mixEfectivo'] ?? '';
    _mixTransfer.text = pago['mixTransfer'] ?? '';
    _transferEditada = pago['transferEditada'] == '1';
    for (final c in [_recibido, _mixEfectivo, _mixTransfer]) {
      c.addListener(_guardarPago);
    }
    WidgetsBinding.instance.addObserver(this);
    // Se cortó la señal al cobrar: antes de nada, se pregunta al servidor si entró.
    if (cart.cobroPendiente) WidgetsBinding.instance.addPostFrameCallback((_) => _verificarPendiente());
  }

  void _guardarPago() => context.read<DraftDocument>().guardarPago({
    'recibido': _recibido.text,
    'mixEfectivo': _mixEfectivo.text,
    'mixTransfer': _mixTransfer.text,
    'transferEditada': _transferEditada ? '1' : '0',
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver a la app (por ejemplo, volvió la señal) se revisa la venta pendiente.
    if (state == AppLifecycleState.resumed && mounted && context.read<DraftDocument>().cobroPendiente) {
      _verificarPendiente();
    }
  }

  /// La venta quedó "pendiente" (se tocó Cobrar y no llegó la respuesta).
  /// Se busca en el servidor por su clave: si entró, se muestra como hecha
  /// (no se cobra de nuevo); si no entró, queda lista para volver a cobrar.
  Future<void> _verificarPendiente() async {
    if (_verificando || _saving) return;
    final cart = context.read<DraftDocument>();
    if (!cart.cobroPendiente) return;
    setState(() => _verificando = true);
    try {
      final previa = await context.read<SaleRepository>().findByKey(cart.idempotencyKey);
      if (!mounted) return;
      if (previa != null) {
        showSnack(context, 'La venta N° ${nroDoc(previa.number)} sí se había registrado. No hace falta cobrarla de nuevo.');
        _done(cart, previa);
      } else {
        cart.marcarCobroPendiente(false);
        showSnack(context, 'La venta no llegó a registrarse. Está todo cargado: revisá y tocá Cobrar.');
      }
    } catch (e) {
      registrarError('verificarVentaPendiente', e);
      // Sigue sin señal: queda pendiente, con todo guardado.
    } finally {
      if (mounted) setState(() => _verificando = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notes.dispose();
    _recibido.dispose();
    _mixEfectivo.dispose();
    _mixTransfer.dispose();
    super.dispose();
  }

  /// Mixto: al escribir el efectivo, la transferencia se completa con lo que falta
  /// (si no se tocó a mano).
  void _alCambiarMixEfectivo(DraftDocument cart) {
    if (!_transferEditada) {
      final resto = cart.total - _mixEfectivoValor;
      _mixTransfer.text = resto > 0 ? miles(resto) : '';
    }
    setState(() {});
  }

  void _cambiarMixto(DraftDocument cart, bool mixto) {
    setState(() {
      cart.paymentMethod = mixto ? 'mixto' : 'efectivo';
      _transferEditada = false;
      _mixEfectivo.clear();
      _mixTransfer.clear();
    });
  }

  /// Sección de pago: Efectivo / Transferencia y la casilla "Pago mixto".
  List<Widget> _seccionPago(DraftDocument cart) {
    final mixto = cart.paymentMethod == 'mixto';
    final total = cart.total;
    final vuelto = _recibidoValor - total;
    // Billetes sugeridos para "con cuánto paga": justo y redondeos hacia arriba.
    final sugeridos = <int>{
      total,
      for (final m in const [10000, 50000, 100000]) ((total + m - 1) ~/ m) * m,
    }.where((v) => v >= total && v > 0).toList()..sort();
    return [
      // Con "Pago mixto" marcado se ocultan los botones (se cargan las dos partes abajo).
      if (!mixto)
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'efectivo', label: Text('Efectivo'), icon: Icon(Icons.payments_outlined)),
            ButtonSegment(value: 'transferencia', label: Text('Transferencia'), icon: Icon(Icons.account_balance_outlined)),
          ],
          selected: {mixto ? 'efectivo' : cart.paymentMethod},
          onSelectionChanged: mixto ? null : (sel) => setState(() => cart.paymentMethod = sel.first),
        ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: mixto,
        onChanged: (v) => _cambiarMixto(cart, v ?? false),
        title: const Text('Pago mixto', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text('Una parte en efectivo y otra por transferencia'),
      ),
      if (cart.paymentMethod == 'efectivo') ...[
        MontoField(
          controller: _recibido,
          label: '¿Con cuánto paga?',
          hint: 'Ej: ${miles(sugeridos.isEmpty ? 100000 : sugeridos.last)}',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in sugeridos)
              ActionChip(label: Text(v == total ? 'Justo · ${miles(v)}' : miles(v)), onPressed: () => setState(() => _recibido.text = miles(v))),
          ],
        ),
        if (_recibido.text.trim().isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: vuelto >= 0 ? const Color(0xFFE6F4EA) : AppColors.redSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Text(
                  vuelto >= 0 ? 'VUELTO' : 'FALTAN',
                  style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, color: vuelto >= 0 ? AppColors.green : AppColors.red),
                ),
                const Spacer(),
                Text(
                  gs(vuelto.abs()),
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26, color: vuelto >= 0 ? AppColors.green : AppColors.red),
                ),
              ],
            ),
          ),
      ],
      if (mixto) ...[
        FilaCampos(
          children: [
            Expanded(
              child: MontoField(controller: _mixEfectivo, label: 'En efectivo', hint: 'Ej: 40.000', onChanged: (_) => _alCambiarMixEfectivo(cart)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MontoField(
                controller: _mixTransfer,
                label: 'Por transferencia',
                hint: 'Ej: 100.000',
                onChanged: (_) {
                  setState(() => _transferEditada = true);
                  _guardarPago();
                },
              ),
            ),
          ],
        ),
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _pagoOk(cart) ? const Color(0xFFE6F4EA) : AppColors.orangeSoft, borderRadius: BorderRadius.circular(12)),
          child: Text(
            _pagoOk(cart) ? 'Cubre justo el total: ${gs(total)}' : '${_faltaPago(cart)} para llegar a ${gs(total)} (tiene que dar justo)',
            style: TextStyle(fontWeight: FontWeight.w800, color: _pagoOk(cart) ? AppColors.green : AppColors.orange),
          ),
        ),
      ],
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Text('Solo se anota cómo pagó; la app no cobra.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
      ),
    ];
  }

  Future<void> _confirm() async {
    final cart = context.read<DraftDocument>();
    if (cart.isEmpty) return;
    if (context.read<CajaProvider>().bloqueaVentas) {
      showSnack(context, 'Tu caja está cerrada. Abrila (arriba, "Abrir caja") para poder cobrar.', error: true);
      return;
    }
    if (cart.hasStockProblems) {
      showSnack(context, 'Hay materiales sin stock suficiente. Corregí las cantidades marcadas en rojo.', error: true);
      return;
    }
    if (_saving) return;
    final notas = limpiarTexto(_notes.text, multilinea: true);
    if (notas.length > Largo.notas) {
      showSnack(context, 'Las observaciones son muy largas (máximo ${Largo.notas} letras).', error: true);
      return;
    }
    if (cart.total <= 0 && !cart.lines.every((l) => l.isGift)) {
      showSnack(context, 'El total no puede ser cero. Revisá los precios o el descuento.', error: true);
      return;
    }
    if (cart.subtotal > montoMaximo) {
      showSnack(context, 'El total pasa de ${gs(montoMaximo)}. Dividí la venta en dos.', error: true);
      return;
    }
    if (!_pagoOk(cart)) {
      showSnack(context, _faltaPago(cart), error: true);
      return;
    }
    final metodo = cart.paymentMethod;
    final detallePago = switch (metodo) {
      'efectivo' => 'Efectivo · paga con ${gs(_recibidoValor)} · vuelto ${gs(_recibidoValor - cart.total)}',
      'mixto' => 'Mixto · efectivo ${gs(_mixEfectivoValor)} + transferencia ${gs(_mixTransferValor)}',
      _ => metodoPagoTexto(metodo),
    };
    // Anti-error: siempre se muestra el resumen antes de registrar.
    final ok = await confirmar(
      context,
      titulo: 'Confirmar venta',
      mensaje:
          '${cart.itemCount} ${cart.itemCount == 1 ? 'material' : 'materiales'}'
          ' · ${cart.client?.fullName ?? 'Sin cliente'}\n'
          'Pago: $detallePago\n\n'
          'TOTAL A PAGAR: ${gs(cart.total)}\n\n'
          'El stock se descuenta ahora.',
      si: 'Sí, registrar',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    final repo = context.read<SaleRepository>();
    // Desde acá, si se corta la señal no se sabe si entró: queda "pendiente"
    // (guardado en el celular con la misma clave) hasta confirmarlo.
    cart.marcarCobroPendiente(true);
    try {
      final sale = await repo.create(
        lines: cart.lines,
        paymentMethod: cart.paymentMethod,
        clientId: cart.client?.id,
        discount: cart.discount,
        notes: notas,
        quoteId: cart.quoteId,
        idempotencyKey: cart.idempotencyKey,
        paidCash: metodo == 'mixto' ? _mixEfectivoValor : null,
        paidTransfer: metodo == 'mixto' ? _mixTransferValor : null,
        cashReceived: metodo == 'efectivo' ? _recibidoValor : null,
      );
      if (!mounted) return;
      _done(cart, sale);
    } catch (e) {
      registrarError('confirmarVenta', e);
      if (!mounted) return;
      // La venta ya había entrado (se cortó la respuesta) y después se cambió el carrito:
      // no se registra otra; se muestra la que quedó guardada.
      if (esYaRegistrada(e)) {
        final previa = await repo.findByKey(cart.idempotencyKey).catchError((Object _) => null);
        if (!mounted) return;
        showSnack(context, mensajeErrorSeguro(e), error: true);
        if (previa != null) _done(cart, previa);
        return;
      }
      // El servidor respondió con un error (stock, datos...): seguro que NO entró.
      final rechazada = esRechazoDelServidor(e);
      if (!rechazada) {
        // Sin señal o se perdió la respuesta: la venta queda guardada y pendiente.
        if (mounted) await _avisoSinSenal();
        return;
      }
      cart.marcarCobroPendiente(false);
      // Si el problema fue de stock, se refresca para marcar las líneas.
      final catalog = context.read<CatalogProvider>();
      await catalog.cargarProductos();
      cart.refreshStock(catalog.productById);
      if (mounted) showSnack(context, mensajeErrorSeguro(e, 'No se pudo registrar la venta. Intentá de nuevo.'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _avisoSinSenal() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.wifi_off_rounded, color: AppColors.orange, size: 36),
      title: const Text('Se cortó la señal'),
      content: const Text(
        'La venta NO se perdió: quedó guardada en este celular con todo lo cargado '
        '(materiales, cliente y pago).\n\n'
        'Cuando vuelva la señal tocá "Reintentar cobro". La app revisa primero si ya '
        'se había registrado, así nunca se cobra dos veces.',
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Entendido'))],
    ),
  );

  void _done(DraftDocument cart, Sale sale) {
    context.read<CajaProvider>().cargar();
    cart.clear();
    _notes.clear();
    _recibido.clear();
    _mixEfectivo.clear();
    _mixTransfer.clear();
    _transferEditada = false;
    context.read<CatalogProvider>().cargarProductos();
    context.read<RefreshBus>().changed();
    final nav = Navigator.of(context);
    if (!widget.embedded) nav.pop();
    nav.push(MaterialPageRoute(builder: (_) => SaleDoneScreen(sale: sale)));
  }

  Future<void> _buscarYAgregar(BuildContext context) async {
    final p = await pickProduct(context);
    if (p != null && context.mounted) await agregarAlCarrito(context, p);
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<DraftDocument>();
    final cajaCerrada = context.watch<CajaProvider>().bloqueaVentas;

    final content = ListView(
      padding: EdgeInsets.fromLTRB(16, widget.embedded ? 16 : 4, 16, 24),
      children: [
        if (widget.embedded)
          Row(
            children: [
              const Spacer(),
              if (!cart.isEmpty)
                TextButton(
                  onPressed: () async {
                    final ok = await confirmar(
                      context,
                      titulo: 'Vaciar venta',
                      mensaje: cart.cobroPendiente
                          ? 'Ojo: esta venta se estaba cobrando cuando se cortó la señal y puede que ya esté registrada. '
                                'Si la vaciás, revisala en Ventas antes de cobrarla otra vez.'
                          : 'Se quitan todos los materiales cargados.',
                      si: 'Vaciar',
                      peligro: cart.cobroPendiente,
                    );
                    if (ok) {
                      cart.clear();
                      _recibido.clear();
                      _mixEfectivo.clear();
                      _mixTransfer.clear();
                    }
                  },
                  child: const Text('Vaciar'),
                ),
            ],
          ),
        if (cart.cobroPendiente)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.orangeSoft, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                _verificando
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.orange))
                    : const Icon(Icons.wifi_off_rounded, color: AppColors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _verificando
                        ? 'Revisando si la venta ya se había registrado...'
                        : 'Se cortó la señal al cobrar. La venta está guardada: tocá "Reintentar cobro". No se cobra dos veces.',
                    style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        if (cart.quoteNumber != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.blueSoft, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                const Icon(Icons.request_quote_outlined, color: AppColors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Viene del presupuesto N° ${nroDoc(cart.quoteNumber!)}. Podés ajustarlo antes de confirmar.',
                    style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        // Buscar por nombre y agregar: abre la lista con el buscador listo para escribir.
        if (widget.embedded) ...[
          const SizedBox(height: 12),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _buscarYAgregar(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.yellow, width: 2),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.search, color: AppColors.ink),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Buscar producto por nombre para agregar', style: TextStyle(color: AppColors.muted, fontSize: 15)),
                    ),
                    Icon(Icons.add_circle_rounded, color: AppColors.ink),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SectionTitle('Materiales', padding: EdgeInsets.fromLTRB(4, 16, 4, 10)),
        DocLinesEditor(draft: cart),
        const SectionTitle('Cliente'),
        ClientPickerField(client: cart.client, onChanged: (c) => cart.client = c),
        const SectionTitle('Total'),
        DocTotals(draft: cart),
        const SectionTitle('Método de pago'),
        ..._seccionPago(cart),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 2,
          inputFormatters: formatoTexto(Largo.notas),
          decoration: const InputDecoration(labelText: 'Observaciones (opcional)', hintText: 'Ej: entregar el lunes en la obra'),
          onChanged: (v) => cart.notes = v,
        ),
      ],
    );

    return Column(
      children: [
        Expanded(child: content),
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
                onPressed: cart.isEmpty || _saving || _verificando || cajaCerrada || !_pagoOk(cart) ? null : _confirm,
                icon: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Icon(Icons.check_circle_outline_rounded),
                label: Text(
                  cajaCerrada && !cart.isEmpty
                      ? 'Abrí tu caja para cobrar'
                      : cart.isEmpty
                      ? 'Agregá materiales'
                      : !_pagoOk(cart)
                      ? _faltaPago(cart)
                      : cart.cobroPendiente
                      ? 'Reintentar cobro · ${gs(cart.total)}'
                      : 'Cobrar · ${gs(cart.total)}',
                  style: const TextStyle(fontSize: 17),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
