import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre el menú de compartir del sistema (WhatsApp, correo, etc.) con el archivo.
Future<void> compartirArchivo(Uint8List bytes, String nombre, {String? texto, String mime = 'application/pdf'}) async {
  if (kIsWeb) {
    await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, name: nombre, mimeType: mime)], text: texto));
    return;
  }
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$nombre');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: mime)], text: texto, subject: nombre));
}

/// Guarda el archivo en el equipo.
/// - Computadora: en la carpeta Descargas, y la abre.
/// - Celular (PDF): abre la vista de impresión, donde se elige "Guardar como PDF".
/// Devuelve la ruta guardada (solo en computadora) para avisar al usuario.
Future<String?> guardarArchivo(Uint8List bytes, String nombre, {bool esPdf = true}) async {
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    var file = File('${dir.path}${Platform.pathSeparator}$nombre');
    var n = 1;
    while (await file.exists()) {
      final punto = nombre.lastIndexOf('.');
      file = File('${dir.path}${Platform.pathSeparator}${nombre.substring(0, punto)} ($n)${nombre.substring(punto)}');
      n++;
    }
    await file.writeAsBytes(bytes, flush: true);
    await launchUrl(Uri.file(file.path));
    return file.path;
  }
  if (esPdf) {
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: nombre);
  } else {
    await compartirArchivo(bytes, nombre,
        mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  }
  return null;
}

Future<void> imprimirPdf(Uint8List bytes, String nombre) => Printing.layoutPdf(onLayout: (_) async => bytes, name: nombre);

/// Abre un chat de WhatsApp con ese número (formato 595...).
Future<bool> abrirWhatsapp(String numero, {String texto = ''}) =>
    launchUrl(Uri.parse('https://wa.me/$numero?text=${Uri.encodeComponent(texto)}'), mode: LaunchMode.externalApplication);
