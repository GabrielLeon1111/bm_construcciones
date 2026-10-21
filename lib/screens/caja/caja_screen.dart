import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/caja.dart';
import '../../providers/caja_provider.dart';
import '../../providers/settings_provider.dart';
import '../../repositories/caja_repository.dart';
import '../../security/registro_seguro.dart';
import '../../services/pdf_caja.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../utils/validacion.dart';
import '../../widgets/common.dart';
import '../../widgets/doc_actions.dart';
import '../shell/home_shell.dart';

/// Caja: si no hay ninguna abierta, se abre con el monto inicial (y se va directo
/// a Vender). Si hay una abierta, muestra lo vendido, los retiros y los botones
/// para retirar dinero o cerrar la caja.
class CajaScreen extends StatefulWidget {
  const CajaScreen({super.key});

  @override
  State<CajaScreen> createState() => _CajaScreenState();
}

class _CajaScreenState extends State<CajaScreen> {
  @override
  void initState() {
    super.initState();
    context.read<CajaProvider>().cargar();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CajaProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Mi caja')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: RefreshIndicator(
            onRefresh: p.cargar,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                switch (p.estado) {
                  EstadoCaja.cargando => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
                  EstadoCaja.desconocido => ErrorRetry(message: 'No se pudo ver la caja. Revisá la conexión.', onRetry: p.cargar),
                  EstadoCaja.cerrada => const AperturaCajaPanel(),
                  EstadoCaja.abierta => _CajaAbierta(caja: p.caja!),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- Apertura ----------------

/// Panel para abrir la caja: en "Mi caja" y, con la caja cerrada, en lugar de Vender.

class AperturaCajaPanel extends StatefulWidget {
  const AperturaCajaPanel({super.key});

  @override
  State<AperturaCajaPanel> createState() => _AperturaState();
}

class _AperturaState extends State<AperturaCajaPanel> {
  final _form = GlobalKey<FormState>();
  final _monto = TextEditingController();
  bool _guardando = false;

  /// Clave de la apertura: tocar dos veces o reintentar no abre dos cajas.
  final String _key = const Uuid().v4();

  @override
  void dispose() {
    _monto.dispose();
    super.dispose();
  }

  Future<void> _abrir() async {
    if (_guardando || !_form.currentState!.validate()) return;
    final monto = leerMonto(_monto.text) ?? 0;
    final ok = await confirmar(context, titulo: 'Abrir caja', mensaje: 'Se abre la caja con ${gs(monto)} de cambio.', si: 'Abrir caja');
    if (!ok || !mounted) return;
    setState(() => _guardando = true);
    try {
      final caja = await context.read<CajaRepository>().abrir(monto, idempotencyKey: _key);
      if (!mounted) return;
      context.read<CajaProvider>().actualizar(caja);
      await context.read<CajaProvider>().cargar();
      if (!mounted) return;
      showSnack(context, 'Caja abierta con ${gs(monto)}. ¡A vender!');
      // Directo a Vender.
      HomeShell.irAVender(context);
    } catch (e) {
      registrarError('abrirCaja', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e, 'No se pudo abrir la caja.'), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(14)),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TU CAJA ESTÁ CERRADA', style: TextStyle(color: AppColors.yellow, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 12)),
                SizedBox(height: 6),
                Text('Para empezar a vender, abrí tu caja con el dinero de cambio que te dieron.', style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // Solo números (sin letras ni símbolos); se ve con separador de miles.
          MontoField(
            controller: _monto,
            autofocus: true,
            label: '¿Con cuánto abrís la caja?',
            hint: 'Ej: 100.000',
            validator: validarMonto(campo: 'el monto inicial', min: aperturaMinimaCaja),
            onSubmitted: (_) => _abrir(),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
            onPressed: _guardando ? null : _abrir,
            icon: _guardando
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.lock_open_rounded),
            label: const Text('Abrir caja'),
          ),
        ],
      ),
    );
  }
}

// ---------------- Caja abierta ----------------

class _CajaAbierta extends StatelessWidget {
  const _CajaAbierta({required this.caja});
  final Caja caja;

  @override
  Widget build(BuildContext context) {
    final c = caja;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CAJA ABIERTA · N° ${nroDoc(c.number)}',
                  style: const TextStyle(color: AppColors.yellow, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 12)),
              const SizedBox(height: 6),
              Text('Desde las ${hora.format(c.openedAt)} del ${fechaCorta.format(c.openedAt)}',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              Text('Abrió: ${c.openedByName}', style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const SectionTitle('Hasta ahora'),
        ResumenCajaCard(caja: c),
        if (c.retiros.isNotEmpty) ...[
          const SectionTitle('Retiros de dinero'),
          Card(
            child: Column(
              children: [
                for (final w in c.retiros)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.outbox_rounded, color: AppColors.orange),
                    title: Text('${gs(w.amount)} · ${w.metodoTexto} · ${w.receivedByName}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${hora.format(w.createdAt)}${w.description == null ? '' : ' · ${w.description}'}'),
                    trailing: const Icon(Icons.picture_as_pdf_outlined),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ComprobanteRetiroScreen(retiro: w))),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        BotonesCaja(caja: c),
      ],
    );
  }
}

/// Monto inicial, ventas, retiros y efectivo que debería haber.
class ResumenCajaCard extends StatelessWidget {
  const ResumenCajaCard({super.key, required this.caja});
  final Caja caja;

  @override
  Widget build(BuildContext context) {
    final c = caja;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ...filasEfectivo(c),
            const Divider(height: 18),
            ...filasTransferencia(c),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Las transferencias las calcula la app: no hace falta escribirlas.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ),
          ],
        ),
      ),
    );
  }
}

const _titulo = TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, letterSpacing: 1, color: AppColors.muted);

/// EFECTIVO: inicial + ventas − retiros = lo que debería haber.
List<Widget> filasEfectivo(Caja c) => [
      const Align(alignment: Alignment.centerLeft, child: Text('EFECTIVO', style: _titulo)),
      const SizedBox(height: 4),
      KeyValueRow('Monto inicial', gs(c.openingAmount)),
      KeyValueRow('+ Ventas en efectivo (${c.salesCount} ventas)', gs(c.cashSales)),
      KeyValueRow('− Retirado en efectivo', gs(c.withdrawalsCash), valueColor: c.withdrawalsCash > 0 ? AppColors.red : null),
      KeyValueRow('= Debería haber en la caja', gs(c.expectedCash), bold: true),
    ];

/// TRANSFERENCIA: ventas − retiros = lo que queda (no se cuenta, lo calcula la app).
List<Widget> filasTransferencia(Caja c) => [
      const Align(alignment: Alignment.centerLeft, child: Text('TRANSFERENCIA', style: _titulo)),
      const SizedBox(height: 4),
      KeyValueRow('Ventas por transferencia', gs(c.transferSales)),
      KeyValueRow('− Retirado por transferencia', gs(c.withdrawalsTransfer), valueColor: c.withdrawalsTransfer > 0 ? AppColors.red : null),
      KeyValueRow('= Queda en transferencias', gs(c.expectedTransfer), bold: true),
    ];

/// "Retiro de dinero" y "Cerrar caja" (en Caja y en Vender).
class BotonesCaja extends StatelessWidget {
  const BotonesCaja({super.key, required this.caja, this.compacto = false});
  final Caja caja;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final alto = Size(0, compacto ? 40 : 52);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: alto),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RetiroCajaScreen(caja: caja))),
            icon: const Icon(Icons.outbox_rounded),
            label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Retiro de dinero')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: alto),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CierreCajaScreen(caja: caja))),
            icon: const Icon(Icons.lock_rounded),
            label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Cerrar caja')),
          ),
        ),
      ],
    );
  }
}

// ---------------- Retiro de dinero ----------------

class RetiroCajaScreen extends StatefulWidget {
  const RetiroCajaScreen({super.key, required this.caja});
  final Caja caja;

  @override
  State<RetiroCajaScreen> createState() => _RetiroCajaScreenState();
}

class _RetiroCajaScreenState extends State<RetiroCajaScreen> {
  final _form = GlobalKey<FormState>();
  final _monto = TextEditingController();
  final _recibe = TextEditingController();
  final _desc = TextEditingController();
  bool _guardando = false;
  String _metodo = 'efectivo';

  /// Clave del retiro: tocar dos veces o reintentar no retira dos veces.
  final String _key = const Uuid().v4();

  @override
  void dispose() {
    _monto.dispose();
    _recibe.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _retirar() async {
    if (_guardando || !_form.currentState!.validate()) return;
    final monto = leerMonto(_monto.text) ?? 0;
    final recibe = limpiarTexto(_recibe.text);
    final ok = await confirmar(
      context,
      titulo: 'Retiro de dinero',
      mensaje: 'Se retiran ${gs(monto)} ${_metodo == 'efectivo' ? 'en efectivo' : 'por transferencia'}.\n'
          'Entrega: ${widget.caja.openedByName}\nRecibe: $recibe',
      si: 'Retirar',
    );
    if (!ok || !mounted) return;
    setState(() => _guardando = true);
    try {
      final w = await context.read<CajaRepository>().retirar(
            widget.caja.id,
            monto,
            metodo: _metodo,
            recibe: recibe,
            descripcion: limpiarTexto(_desc.text).isEmpty ? null : limpiarTexto(_desc.text),
            idempotencyKey: _key,
          );
      if (!mounted) return;
      context.read<CajaProvider>().cargar();
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ComprobanteRetiroScreen(retiro: w, recienHecho: true)));
    } catch (e) {
      registrarError('retiroCaja', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e, 'No se pudo registrar el retiro.'), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.caja;
    final max = c.disponibleParaRetiro(_metodo);
    final efectivo = _metodo == 'efectivo';
    return Scaffold(
      appBar: AppBar(title: const Text('Retiro de dinero')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.blueSoft, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    'Caja N° ${nroDoc(c.number)} · entrega ${c.openedByName}.\n'
                    '${efectivo ? 'En efectivo se puede retirar hasta ${gs(max)} (el monto de apertura${c.withdrawalsCash > 0 ? ', menos lo ya retirado' : ''}).' : 'Por transferencia se puede retirar hasta ${gs(max)} (lo que entró por transferencia${c.withdrawalsTransfer > 0 ? ', menos lo ya retirado' : ''}).'}',
                    style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'efectivo', label: Text('Efectivo'), icon: Icon(Icons.payments_outlined)),
                    ButtonSegment(value: 'transferencia', label: Text('Transferencia'), icon: Icon(Icons.account_balance_outlined)),
                  ],
                  selected: {_metodo},
                  onSelectionChanged: (v) => setState(() => _metodo = v.first),
                ),
                const SizedBox(height: 16),
                MontoField(
                  controller: _monto,
                  autofocus: true,
                  label: '¿Cuánto se retira? *',
                  hint: 'Ej: 50.000',
                  validator: (v) {
                    if (max <= 0) return efectivo ? 'Ya se retiró todo el monto de apertura.' : 'No hay transferencias para retirar.';
                    final err = validarMonto(campo: 'el monto a retirar')(v);
                    if (err != null) return err;
                    if ((leerMonto(v ?? '') ?? 0) > max) return 'No puede pasar de ${gs(max)}';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _recibe,
                  textCapitalization: TextCapitalization.words,
                  // Solo letras (sin números ni símbolos).
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[A-Za-zÁÉÍÓÚÜÑáéíóúüñ' .-]")), LengthLimitingTextInputFormatter(80)],
                  decoration: const InputDecoration(
                    labelText: '¿Quién recibe el dinero? *',
                    hintText: 'Nombre y apellido. Ej: Juan Pérez',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (v) {
                    final t = limpiarTexto(v ?? '');
                    if (t.isEmpty) return 'Escribí el nombre de quien recibe';
                    if (t.length < 3) return 'Muy corto: nombre y apellido';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _desc,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: formatoTexto(200),
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Descripción (opcional)', hintText: 'Ej: pago de flete, compra de agua'),
                  validator: validarTexto(campo: 'la descripción', max: 200),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
                  onPressed: _guardando || max <= 0 ? null : _retirar,
                  icon: _guardando
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Icon(Icons.outbox_rounded),
                  label: const Text('Retirar y ver comprobante'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Comprobante del retiro, listo para compartir, descargar o imprimir.
class ComprobanteRetiroScreen extends StatelessWidget {
  const ComprobanteRetiroScreen({super.key, required this.retiro, this.recienHecho = false});
  final RetiroCaja retiro;
  final bool recienHecho;

  @override
  Widget build(BuildContext context) {
    final w = retiro;
    final negocio = context.read<SettingsProvider>().settings;
    return Scaffold(
      appBar: AppBar(title: Text('Retiro N° ${nroDoc(w.number)}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (recienHecho)
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: const Color(0xFFE6F4EA), borderRadius: BorderRadius.circular(12)),
                  child: const Row(children: [
                    Icon(Icons.check_circle_rounded, color: AppColors.green),
                    SizedBox(width: 10),
                    Expanded(child: Text('Retiro registrado. El comprobante está listo para firmar.', style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w800))),
                  ]),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      KeyValueRow('Monto retirado', gs(w.amount), bold: true),
                      KeyValueRow('Forma', w.metodoTexto),
                      KeyValueRow('Fecha y hora', fechaHora.format(w.createdAt)),
                      KeyValueRow('Entregó (abrió la caja)', w.givenByName),
                      KeyValueRow('Recibió', w.receivedByName),
                      if (w.description != null) KeyValueRow('Descripción', w.description!),
                    ],
                  ),
                ),
              ),
              const SectionTitle('Comprobante (con lugar para las dos firmas)'),
              DocActions(
                fileName: nombreArchivoRetiro(w),
                shareText: 'Retiro de dinero N° ${nroDoc(w.number)} - ${negocio.name}',
                build: () => generarRetiroPdf(w, negocio),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- Cierre con el conteo ----------------

class CierreCajaScreen extends StatefulWidget {
  const CierreCajaScreen({super.key, required this.caja});
  final Caja caja;

  @override
  State<CierreCajaScreen> createState() => _CierreCajaScreenState();
}

class _CierreCajaScreenState extends State<CierreCajaScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<int, TextEditingController> _cant = {for (final d in denominacionesCaja) d: TextEditingController()};
  late Caja _caja = widget.caja;
  bool _guardando = false;

  /// Clave del cierre: si se corta la señal y se reintenta, no se cierra dos veces.
  final String _key = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    _actualizarTotales();
  }

  @override
  void dispose() {
    for (final c in _cant.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Trae lo vendido hasta este momento (pudo haber ventas mientras se cuenta).
  Future<void> _actualizarTotales() async {
    try {
      final c = await context.read<CajaRepository>().get(_caja.id);
      if (mounted && c.abierta) setState(() => _caja = c);
    } catch (e) {
      registrarError('totalesCaja', e);
    }
  }

  Map<int, int> get _conteo => {for (final e in _cant.entries) e.key: int.tryParse(e.value.text) ?? 0};
  int get _contado => totalContado(_conteo);

  Future<void> _confirmar() async {
    if (_guardando) return;
    // Hace falta al menos una cantidad escrita (las vacías cuentan como 0).
    if (!_form.currentState!.validate()) {
      showSnack(context, 'Revisá las cantidades: solo números.', error: true);
      return;
    }
    await _actualizarTotales();
    if (!mounted) return;
    final dif = _contado - _caja.expectedCash;
    final ok = await confirmar(
      context,
      titulo: 'Confirmar cierre',
      mensaje: 'Contaste ${gs(_contado)}.\n'
          'Debería haber ${gs(_caja.expectedCash)}.\n'
          '${dif == 0 ? 'La caja está cuadrada.' : (dif > 0 ? 'SOBRAN ${gs(dif)}.' : 'FALTAN ${gs(-dif)}.')}\n\n'
          'Después de cerrar no se puede cambiar.',
      si: 'Confirmar cierre',
    );
    if (!ok || !mounted) return;
    setState(() => _guardando = true);
    try {
      final cerrada = await context.read<CajaRepository>().cerrar(_caja.id, _conteo, idempotencyKey: _key);
      if (!mounted) return;
      context.read<CajaProvider>().cargar();
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ComprobanteCajaScreen(caja: cerrada, recienCerrada: true)));
    } catch (e) {
      registrarError('cerrarCaja', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e, 'No se pudo cerrar la caja.'), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Casilla del conteo: billete o moneda, cantidad y subtotal.
  Widget _casillaConteo(int valor) {
    final cant = int.tryParse(_cant[valor]!.text) ?? 0;
    final esBillete = valor >= 2000;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        color: cant > 0 ? AppColors.yellowSoft : const Color(0xFFF7F7F3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Billete verde / monedas doradas.
              Icon(
                esBillete ? Icons.payments_rounded : Icons.toll_rounded,
                size: 20,
                color: esBillete ? const Color(0xFF2E7D32) : const Color(0xFFC8962E),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(miles(valor), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _cant[valor],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            // Solo números: nada de letras, signos ni decimales.
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            decoration: const InputDecoration(
              hintText: '0',
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding: EdgeInsets.symmetric(vertical: 9),
              errorStyle: TextStyle(fontSize: 11),
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return null; // vacía = 0
              final n = int.tryParse(t);
              if (n == null) return 'Solo números';
              if (n > 100000) return 'Muy alto';
              return null;
            },
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),
          Text(
            gs(cant * valor),
            textAlign: TextAlign.center,
            style: TextStyle(color: cant > 0 ? AppColors.ink : AppColors.muted, fontSize: 12.5, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }

  /// Todos los billetes y monedas en un solo cuadro (2 columnas en el celular, más en pantallas anchas).
  Widget _grillaConteo() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, c) {
              final columnas = c.maxWidth >= 560 ? 5 : (c.maxWidth >= 420 ? 3 : 2);
              const sep = 10.0;
              final ancho = (c.maxWidth - sep * (columnas - 1)) / columnas;
              return Wrap(
                spacing: sep,
                runSpacing: sep,
                children: [for (final d in denominacionesCaja) SizedBox(width: ancho, child: _casillaConteo(d))],
              );
            },
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = _caja;
    final contado = _contado;
    final dif = contado - c.expectedCash;
    // Con al menos una cantidad escrita ya se puede cerrar; las casillas vacías cuentan como 0.
    final completo = _cant.values.any((e) => e.text.trim().isNotEmpty);
    return Scaffold(
      appBar: AppBar(title: Text('Cerrar caja N° ${nroDoc(c.number)} · ${c.openedByName}')),
      body: Form(
        key: _form,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      const Text('Contá el efectivo de la caja y escribí cuántos hay de cada uno. Los que no hay, dejalos vacíos.',
                          style: TextStyle(color: AppColors.muted)),
                      SectionTitle('Billetes y monedas', trailing: Text('Contado: ${gs(contado)}', style: const TextStyle(fontWeight: FontWeight.w800))),
                      _grillaConteo(),
                      const SectionTitle('Resultado'),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              ...filasEfectivo(c),
                              KeyValueRow('Efectivo contado', gs(contado), bold: true),
                              const Divider(height: 18),
                              KeyValueRow(
                                !completo ? 'Diferencia' : (dif == 0 ? 'Caja cuadrada' : (dif > 0 ? 'Sobra' : 'Falta')),
                                !completo ? 'Escribí lo contado' : gs(dif.abs()),
                                bold: true,
                                valueColor: !completo || dif == 0 ? null : (dif > 0 ? AppColors.green : AppColors.red),
                              ),
                              const Divider(height: 18),
                              ...filasTransferencia(c),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.line))),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                    onPressed: _guardando || !completo ? null : _confirmar,
                    icon: _guardando
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Icon(Icons.lock_rounded),
                    label: Text(completo ? 'Confirmar cierre' : 'Escribí lo que contaste para cerrar', style: const TextStyle(fontSize: 17)),
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

// ---------------- Comprobante del arqueo ----------------

/// Comprobante del arqueo: resumen y el PDF listo para compartir, descargar o imprimir.
class ComprobanteCajaScreen extends StatelessWidget {
  const ComprobanteCajaScreen({super.key, required this.caja, this.recienCerrada = false});
  final Caja caja;
  final bool recienCerrada;

  @override
  Widget build(BuildContext context) {
    final c = caja;
    final dif = c.difference ?? 0;
    final negocio = context.read<SettingsProvider>().settings;
    return Scaffold(
      appBar: AppBar(title: Text('Arqueo N° ${nroDoc(c.number)}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (recienCerrada)
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: const Color(0xFFE6F4EA), borderRadius: BorderRadius.circular(12)),
                  child: const Row(children: [
                    Icon(Icons.check_circle_rounded, color: AppColors.green),
                    SizedBox(width: 10),
                    Expanded(child: Text('Caja cerrada. El comprobante está listo.', style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w800))),
                  ]),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      KeyValueRow('Abrió', '${c.openedByName} · ${fechaHora.format(c.openedAt)}'),
                      KeyValueRow('Cerró', c.closedAt == null ? 'Todavía abierta' : '${c.closedByName ?? '—'} · ${fechaHora.format(c.closedAt!)}'),
                      const Divider(height: 18),
                      ...filasEfectivo(c),
                      KeyValueRow('Efectivo contado', c.countedCash == null ? '—' : gs(c.countedCash!), bold: true),
                      if (c.countedCash != null)
                        KeyValueRow(
                          dif == 0 ? 'Caja cuadrada' : (dif > 0 ? 'Sobra' : 'Falta'),
                          gs(dif.abs()),
                          bold: true,
                          valueColor: dif == 0 ? null : (dif > 0 ? AppColors.green : AppColors.red),
                        ),
                      const Divider(height: 18),
                      ...filasTransferencia(c),
                    ],
                  ),
                ),
              ),
              const SectionTitle('Comprobante'),
              DocActions(
                fileName: nombreArchivoCaja(c),
                shareText: 'Arqueo de caja N° ${nroDoc(c.number)} - ${negocio.name}',
                build: () => generarArqueoPdf(c, negocio),
              ),
              if (recienCerrada) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50)),
                  onPressed: () => HomeShell.irAVender(context),
                  icon: const Icon(Icons.point_of_sale_rounded),
                  label: const Text('Volver a Vender'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
