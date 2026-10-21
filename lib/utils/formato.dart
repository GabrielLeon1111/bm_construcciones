import 'package:intl/intl.dart';

final _gs = NumberFormat.decimalPattern('es');
final fechaCorta = DateFormat('dd/MM/yyyy', 'es');
final fechaHora = DateFormat('dd/MM/yyyy HH:mm', 'es');
final hora = DateFormat('HH:mm', 'es');
final fechaLarga = DateFormat("EEEE d 'de' MMMM", 'es');
final mesAnio = DateFormat('MMMM yyyy', 'es');
final mesCorto = DateFormat('MMM', 'es');

/// 1355000 -> "1.355.000"
String miles(num valor) => _gs.format(valor.round());

/// 1355000 -> "Gs. 1.355.000"
String gs(num valor) => 'Gs. ${miles(valor)}';

/// Número de comprobante con ceros: 12 -> "000012"
String nroDoc(int n) => n.toString().padLeft(6, '0');

// Tercios incluidos: la arena y la piedra se venden por 1/3 y 2/3 de carga.
final _fracciones = <double, String>{0.25: '1/4', 0.333: '1/3', 0.5: '1/2', 0.667: '2/3', 0.75: '3/4'};

/// Cantidad legible para materiales: 0.5 -> "1/2", 1.5 -> "1 1/2",
/// 2.25 -> "2 1/4", 2.4 -> "2,4", 3000 -> "3.000".
String cantidad(num valor) {
  final v = valor.toDouble();
  final entero = v.truncate();
  final resto = double.parse((v - entero).toStringAsFixed(3));
  if (resto == 0) return miles(entero);
  final frac = _fracciones[resto];
  if (frac != null) return entero == 0 ? frac : '${miles(entero)} $frac';
  return NumberFormat('#,##0.###', 'es').format(v);
}

/// Como [leerCantidad] pero sin redondear las fracciones (1/3 = 0,3333…),
/// para que 1/3 de Gs. 900.000 dé exactamente Gs. 300.000.
double? leerCantidadExacta(String texto) {
  final t = texto.trim().replaceAll(RegExp(r'\s+'), ' ');
  final mixto = RegExp(r'^(\d+) (\d+)/(\d+)$').firstMatch(t);
  if (mixto != null) {
    final den = int.parse(mixto.group(3)!);
    return den == 0 ? null : int.parse(mixto.group(1)!) + int.parse(mixto.group(2)!) / den;
  }
  final frac = RegExp(r'^(\d+)/(\d+)$').firstMatch(t);
  if (frac != null) {
    final den = int.parse(frac.group(2)!);
    return den == 0 ? null : int.parse(frac.group(1)!) / den;
  }
  return leerCantidad(t);
}

/// Interpreta lo que escribe el usuario: "1/2", "1 1/2", "2,5", "2.5", "3000".
/// Devuelve null si no se entiende.
double? leerCantidad(String texto) {
  final t = texto.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return null;
  final mixto = RegExp(r'^(\d+) (\d+)/(\d+)$').firstMatch(t);
  if (mixto != null) {
    final den = int.parse(mixto.group(3)!);
    if (den == 0) return null;
    return int.parse(mixto.group(1)!) + int.parse(mixto.group(2)!) / den;
  }
  final frac = RegExp(r'^(\d+)/(\d+)$').firstMatch(t);
  if (frac != null) {
    final den = int.parse(frac.group(2)!);
    if (den == 0) return null;
    return int.parse(frac.group(1)!) / den;
  }
  // "2,5" → 2.5 · "3.000" (punto de miles) → 3000 · "2.5" → 2.5
  final String normal;
  if (t.contains(',')) {
    normal = t.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(t)) {
    normal = t.replaceAll('.', '');
  } else {
    normal = t;
  }
  final v = double.tryParse(normal);
  if (v == null || v.isNaN || v.isInfinite) return null;
  return double.parse(v.toStringAsFixed(3));
}

/// "1.355.000" o "1355000" -> 1355000
int? leerMonto(String texto) {
  final limpio = texto.replaceAll(RegExp(r'[^0-9]'), '');
  if (limpio.isEmpty) return null;
  return int.tryParse(limpio);
}

/// Etiqueta de la unidad según la cantidad: (2, 'bolsa') -> 'bolsas'.
String unidadPlural(String unidad, num cant) {
  if (cant <= 1) return unidad;
  const especiales = {'unidad': 'unidades', 'kg': 'kg', 'm²': 'm²', 'm³': 'm³', 'lt': 'lt', 'metro': 'metros'};
  return especiales[unidad] ?? (unidad.endsWith('s') ? unidad : '${unidad}s');
}

String metodoPagoTexto(String m) => switch (m) {
      'efectivo' => 'Efectivo',
      'transferencia' => 'Transferencia',
      'qr' => 'QR',
      'mixto' => 'Mixto',
      _ => m,
    };

/// Teléfono paraguayo a formato internacional para WhatsApp: 0981 123456 -> 595981123456
String? telefonoWhatsapp(String? tel) {
  if (tel == null) return null;
  var d = tel.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.isEmpty) return null;
  if (d.startsWith('595')) return d;
  if (d.startsWith('0')) d = d.substring(1);
  return '595$d';
}
