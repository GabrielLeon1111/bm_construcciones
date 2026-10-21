// =================================================================
//  VALIDACIÓN DE CAMPOS
//  Reglas únicas para toda la app (las mismas que controla la base de datos),
//  pensadas para que alguien sin experiencia no pueda cargar un dato mal:
//    - límites de largo y de valor en cada campo,
//    - formatos de Paraguay (celular, CI, RUC),
//    - limpieza de caracteres invisibles o de control.
//  La base vuelve a validar todo: esto es para avisar antes y con claridad.
// =================================================================
import 'package:flutter/services.dart';
import 'formato.dart';

/// Largos máximos (iguales a los CHECK de la base).
abstract final class Largo {
  static const nombre = 80;
  static const categoria = 40;
  static const marca = 40;
  static const descripcion = 120;
  static const notas = 300;
  static const telefono = 20;
  static const documento = 15;
  static const direccion = 150;
  static const ciudad = 60;
  static const email = 100;
  static const motivo = 150;
  static const proveedor = 80;
  static const factura = 30;
  static const titulo = 60;
}

/// Máximo de un monto en guaraníes (999.999.999).
const montoMaximo = 999999999;

/// Máxima cantidad por línea (100.000 unidades, kg, metros...).
const cantidadMaxima = 100000.0;

// Control (menos tab y salto de línea), espacios de ancho cero y marcas de dirección de texto.
final _control = RegExp(
  '[${_rango(0x00, 0x08)}${_rango(0x0B, 0x0C)}${_rango(0x0E, 0x1F)}${_rango(0x7F, 0x7F)}'
  '${_rango(0x200B, 0x200F)}${_rango(0x2028, 0x202E)}${_rango(0x2060, 0x206F)}${_rango(0xFEFF, 0xFEFF)}]',
);

String _rango(int desde, int hasta) {
  String u(int c) => '\\u${c.toRadixString(16).padLeft(4, '0')}';
  return desde == hasta ? u(desde) : '${u(desde)}-${u(hasta)}';
}

/// Quita caracteres invisibles o de control, espacios dobles y espacios en los bordes.
/// Con [multilinea] se conservan los saltos de línea (máximo uno seguido).
String limpiarTexto(String texto, {bool multilinea = false}) {
  var t = texto.replaceAll(_control, '');
  if (multilinea) {
    t = t.replaceAll('\r', '').replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r'\n{3,}'), '\n\n');
  } else {
    t = t.replaceAll(RegExp(r'\s+'), ' ');
  }
  return t.trim();
}

/// Bloquea mientras se escribe los caracteres invisibles o de control.
class SinCaracteresRaros extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (!_control.hasMatch(newValue.text)) return newValue;
    final t = newValue.text.replaceAll(_control, '');
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

/// Formateadores para un campo de texto de largo [max].
List<TextInputFormatter> formatoTexto(int max) => [SinCaracteresRaros(), LengthLimitingTextInputFormatter(max)];

// ---------------- Validadores ----------------

/// Texto libre: obligatorio o no, con largo mínimo y máximo.
String? Function(String?) validarTexto({
  required String campo,
  bool obligatorio = false,
  int min = 2,
  required int max,
  bool multilinea = false,
}) =>
    (v) {
      final t = limpiarTexto(v ?? '', multilinea: multilinea);
      if (t.isEmpty) return obligatorio ? 'Escribí $campo' : null;
      if (t.length < min) return 'Muy corto: escribí al menos $min letras';
      if (t.length > max) return 'Muy largo: máximo $max caracteres';
      if (!RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9]').hasMatch(t)) return 'Escribí letras o números';
      return null;
    };

/// Celular o teléfono de Paraguay: 0981 123456, 021 123456, +595 981 123456.
String? validarTelefono(String? v, {bool obligatorio = false}) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return obligatorio ? 'Escribí el número' : null;
  if (!RegExp(r'^\+?[0-9 ()-]+$').hasMatch(t)) return 'Solo números (ej: 0981 123456)';
  final d = t.replaceAll(RegExp(r'[^0-9]'), '');
  final local = d.startsWith('595') ? '0${d.substring(3)}' : d;
  if (!local.startsWith('0')) return 'Empezá con 0 (ej: 0981 123456)';
  if (local.length < 9 || local.length > 11) return 'Número incompleto (ej: 0981 123456)';
  return null;
}

/// CI (1.234.567) o RUC (1234567-8 / 80012345-6).
String? validarDocumento(String? v) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return null;
  final sinPuntos = t.replaceAll('.', '').replaceAll(' ', '');
  if (RegExp(r'^\d{5,8}$').hasMatch(sinPuntos)) return null; // CI
  if (RegExp(r'^\d{5,8}-\d$').hasMatch(sinPuntos)) return null; // RUC con dígito verificador
  return 'Escribí la CI (ej: 1.234.567) o el RUC (ej: 1234567-8)';
}

/// RUC del negocio (obligatorio el dígito verificador).
String? validarRuc(String? v) {
  final t = (v ?? '').trim().replaceAll('.', '').replaceAll(' ', '');
  if (t.isEmpty) return null;
  return RegExp(r'^\d{5,8}-\d$').hasMatch(t) ? null : 'Escribí el RUC con guion (ej: 80012345-6)';
}

String? validarEmail(String? v, {bool obligatorio = false}) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return obligatorio ? 'Escribí el email' : null;
  if (t.length > Largo.email) return 'Muy largo';
  if (!RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$').hasMatch(t)) return 'Ese email no es válido (ej: nombre@gmail.com)';
  return null;
}

/// Monto en guaraníes. [min] es el mínimo permitido (por defecto mayor a cero).
String? Function(String?) validarMonto({String campo = 'el monto', bool obligatorio = true, int min = 1, int max = montoMaximo}) => (v) {
      final t = (v ?? '').trim();
      if (t.isEmpty) return obligatorio ? 'Poné $campo' : null;
      final n = leerMonto(t);
      if (n == null) return 'Solo números (ej: 70.000)';
      if (n < min) return min <= 1 ? 'Tiene que ser mayor a cero' : 'Mínimo ${gs(min)}';
      if (n > max) return 'Máximo ${gs(max)}. Revisá si sobra algún cero';
      return null;
    };

/// Cantidad de material (acepta 1/2, 1 1/2, 2,5, 3.000).
String? Function(String?) validarCantidad({bool obligatorio = true, bool permitirCero = false, double max = cantidadMaxima, bool soloEnteros = false}) =>
    (v) {
      final t = (v ?? '').trim();
      if (t.isEmpty) return obligatorio ? 'Escribí la cantidad' : null;
      final q = leerCantidad(t);
      if (q == null) return soloEnteros ? 'Escribí un número (ej: 10)' : 'No se entiende. Ej: 2 · 1/2 · 2,5 · 3.000';
      if (soloEnteros && q != q.roundToDouble()) return 'Se vende por unidad: solo números enteros (ej: 10)';
      if (q < 0) return 'No puede ser negativa';
      if (q == 0 && !permitirCero) return 'Tiene que ser mayor a cero';
      if (q > max) return 'Máximo ${cantidad(max)}. Revisá si sobra algún cero';
      return null;
    };

/// Mientras se escribe una cantidad: separador de miles y coma decimal.
/// "3000" → "3.000" · "2." → "2," · "1/2" y "1 1/2" quedan como están.
class CantidadInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var t = newValue.text.replaceAll(RegExp(r'[^0-9.,/ ]'), '');
    if (t.contains('/') || RegExp(r'^\d+ ').hasMatch(t)) {
      // Fracciones: "n/d" o "e n/d" (un espacio después del entero anuncia la fracción).
      t = t.replaceAll(RegExp(r' {2,}'), ' ').replaceAll('.', '').replaceAll(',', '');
      if (t.length > 9) return oldValue;
      return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
    }
    t = t.replaceAll(' ', '');
    // Un punto recién escrito al final es la coma decimal (en el teclado numérico es lo que hay).
    final agregoPunto = t.length > oldValue.text.replaceAll(' ', '').length && t.endsWith('.');
    if (agregoPunto) t = '${t.substring(0, t.length - 1)},';
    t = t.replaceAll('.', '');
    final partes = t.split(',');
    final entero = partes.first.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (entero.length > 6) return oldValue;
    final decimales = partes.length > 1 ? partes.sublist(1).join() : null;
    if (decimales != null && decimales.length > 3) return oldValue;
    var res = entero.isEmpty ? (decimales != null ? '0' : '') : miles(int.parse(entero));
    if (decimales != null) res = '$res,$decimales';
    return TextEditingValue(text: res, selection: TextSelection.collapsed(offset: res.length));
  }
}
