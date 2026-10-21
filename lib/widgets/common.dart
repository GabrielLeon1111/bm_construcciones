import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../security/registro_seguro.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';
import '../utils/validacion.dart';

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;

void showSnack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.red : AppColors.ink,
    ));
}

/// Ejecuta una acción mostrando el error de forma segura si falla.
Future<bool> runSafe(BuildContext context, String contexto, Future<void> Function() action, {String? ok}) async {
  try {
    await action();
    if (ok != null && context.mounted) showSnack(context, ok);
    return true;
  } catch (e) {
    registrarError(contexto, e);
    if (context.mounted) showSnack(context, mensajeErrorSeguro(e), error: true);
    return false;
  }
}

Future<bool> confirmar(BuildContext context, {required String titulo, required String mensaje, String si = 'Confirmar', bool peligro = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(
          style: peligro ? FilledButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(si),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Pide un motivo (anulaciones, ajustes). Devuelve null si cancela.
Future<String?> pedirMotivo(BuildContext context, {required String titulo, String? ayuda, String boton = 'Anular'}) {
  final ctrl = TextEditingController();
  final form = GlobalKey<FormState>();
  void enviar(BuildContext c) {
    if (!form.currentState!.validate()) return;
    Navigator.pop(c, limpiarTexto(ctrl.text));
  }

  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ayuda != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(ayuda)),
            TextFormField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: formatoTexto(Largo.motivo),
              decoration: const InputDecoration(labelText: 'Motivo *', hintText: 'Ej: el cliente devolvió el material'),
              validator: validarTexto(campo: 'el motivo', obligatorio: true, min: 3, max: Largo.motivo),
              onFieldSubmitted: (_) => enviar(c),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white),
          onPressed: () => enviar(c),
          child: Text(boton),
        ),
      ],
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(4, 20, 4, 10)});
  final String text;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(
          children: [
            Container(width: 4, height: 16, color: AppColors.yellow),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 1.1, color: AppColors.ink)),
            ),
            ?trailing,
          ],
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: AppColors.yellowSoft, borderRadius: BorderRadius.circular(18)),
                child: Icon(icon, size: 36, color: AppColors.ink),
              ),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
              ],
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      );
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'No se pudo cargar',
        message: message,
        action: OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
      );
}

/// Etiqueta de estado (Anulada, Pendiente, Bajo stock...).
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = AppColors.ink, this.background});
  final String text;
  final Color color;
  final Color? background;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: background ?? color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      );
}

class StockPill extends StatelessWidget {
  const StockPill({super.key, required this.stock, required this.minStock, required this.unit});
  final double stock;
  final double minStock;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final txt = '${cantidad(stock)} ${unidadPlural(unit, stock)}';
    if (stock <= 0) return Pill('Agotado', color: AppColors.red);
    if (stock <= minStock) return Pill(txt, color: AppColors.orange);
    return Pill(txt, color: AppColors.green);
  }
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.bold = false, this.valueColor, this.big = false});
  final String label;
  final String value;
  final bool bold;
  final bool big;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      fontSize: big ? 20 : 15,
      color: valueColor ?? AppColors.ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: bold ? AppColors.ink : AppColors.muted, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontSize: big ? 17 : 15))),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// Formatea montos mientras se escriben: 1355000 -> 1.355.000
class MilesInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    // Nunca más de 999.999.999: lo que sobre no se escribe.
    if (digits.length > montoMaximo.toString().length) return oldValue;
    final n = int.tryParse(digits);
    if (n == null) return oldValue;
    final txt = miles(n);
    return TextEditingValue(text: txt, selection: TextSelection.collapsed(offset: txt.length));
  }
}

/// Campo de monto en guaraníes: solo números, con punto de miles mientras se escribe.
/// Sin [validator] acepta vacío o cualquier monto hasta el máximo.
class MontoField extends StatelessWidget {
  const MontoField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.helper,
    this.hint = 'Ej: 70.000',
  });
  final TextEditingController controller;
  final String label;
  final String? helper;
  final String hint;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: TextInputType.number,
        textInputAction: onSubmitted == null ? null : TextInputAction.done,
        inputFormatters: [MilesInputFormatter()],
        decoration: InputDecoration(labelText: label, hintText: hint, prefixText: 'Gs. ', helperText: helper, helperMaxLines: 2),
        validator: validator ?? validarMonto(obligatorio: false, min: 0),
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
        style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
      );
}

/// Campo de cantidad que acepta 1/2, 1 1/2, 2,5, 3.000 (pone el punto de miles solo).
class CantidadField extends StatelessWidget {
  const CantidadField({
    super.key,
    required this.controller,
    this.label = 'Cantidad',
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.allowZero = false,
    this.obligatorio = true,
    this.focusNode,
    this.enteros = false,
    this.ayuda,
  });
  final TextEditingController controller;
  final String label;
  final String? suffix;

  /// Se vende por unidad: solo números enteros, sin fracciones (1/2) ni decimales.
  final bool enteros;

  /// Texto de ayuda debajo (si no, el de fracciones: "Media: 1/2 · dos y media: 2,5").
  final String? ayuda;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool allowZero;
  final bool obligatorio;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        textInputAction: onSubmitted == null ? null : TextInputAction.done,
        keyboardType: enteros ? TextInputType.number : const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [enteros ? MilesInputFormatter() : CantidadInputFormatter()],
        decoration: InputDecoration(
          labelText: label,
          hintText: enteros ? 'Ej: 10' : 'Ej: 2 · 1/2 · 2,5 · 3.000',
          suffixText: suffix,
          helperText: enteros ? null : (ayuda ?? 'Media: 1/2 · dos y media: 2,5'),
        ),
        validator: validarCantidad(obligatorio: obligatorio, permitirCero: allowZero, soloEnteros: enteros),
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
        style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
      );
}

/// Total resaltado (fondo amarillo, número grande): "TOTAL A PAGAR Gs. 1.355.000".
/// Se usa en el cobro, el presupuesto y el detalle de cada venta.
class TotalDestacado extends StatelessWidget {
  const TotalDestacado({super.key, required this.etiqueta, required this.monto, this.detalle});
  final String etiqueta;
  final int monto;
  final String? detalle;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.yellow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.ink, width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(etiqueta, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.8, color: AppColors.ink)),
                  if (detalle != null) Text(detalle!, style: const TextStyle(fontSize: 12.5, color: AppColors.ink)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  gs(monto),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 28, color: AppColors.ink, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
            ),
          ],
        ),
      );
}

/// Fila de campos de formulario: lado a lado en pantallas anchas y uno debajo
/// del otro en el celular, así ningún campo queda apretado.
/// Los hijos se escriben como en un Row (con Expanded y SizedBox(width: …)).
class FilaCampos extends StatelessWidget {
  const FilaCampos({super.key, required this.children, this.crossAxisAlignment = CrossAxisAlignment.start, this.anchoMinimo = 520});
  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;

  /// Debajo de este ancho los campos se apilan.
  final double anchoMinimo;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (box.maxWidth >= anchoMinimo) return Row(crossAxisAlignment: crossAxisAlignment, children: children);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final w in children)
              if (w is Expanded)
                w.child
              else if (w is SizedBox && w.height == null)
                const SizedBox(height: 12)
              else
                w,
          ],
        );
      });
}

/// Margen lateral según el ancho: más chico en celulares angostos.
double margenLateral(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < 360) return 12;
  if (w < 600) return 16;
  return 24;
}
