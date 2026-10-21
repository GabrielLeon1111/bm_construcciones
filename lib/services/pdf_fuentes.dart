import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../security/registro_seguro.dart';

/// Tipografías y logo para los PDF (se cargan una sola vez).
class PdfRecursos {
  PdfRecursos._(this.regular, this.medium, this.bold, this.black, this.serif);

  final pw.Font regular;
  final pw.Font medium;
  final pw.Font bold;
  final pw.Font black;
  final pw.Font serif;

  static PdfRecursos? _cache;
  static final Map<String, pw.ImageProvider?> _logos = {};

  static Future<PdfRecursos> cargar() async {
    if (_cache != null) return _cache!;
    Future<pw.Font> f(String name) async => pw.Font.ttf(await rootBundle.load('assets/fonts/$name'));
    _cache = PdfRecursos._(
      await f('Barlow-Regular.ttf'),
      await f('Barlow-Medium.ttf'),
      await f('Barlow-SemiBold.ttf'),
      await f('Barlow-Bold.ttf'),
      await f('DMSerifDisplay-Regular.ttf'),
    );
    return _cache!;
  }

  pw.ThemeData get theme => pw.ThemeData.withFont(base: regular, bold: bold, italic: regular, boldItalic: bold);

  /// Imagen del lado derecho del comprobante (como en el talonario).
  /// 1) El logo cargado en "Datos del negocio". 2) Si no hay (o no hay internet),
  /// la imagen de la app: assets/images/mascota.jpg. 3) Si tampoco está, sale sin imagen.
  static Future<pw.ImageProvider?> logo(String? url) async {
    if (url != null && url.isNotEmpty) {
      if (_logos.containsKey(url)) return _logos[url] ?? await _mascota();
      try {
        final img = await networkImage(url);
        _logos[url] = img;
        return img;
      } catch (e) {
        registrarError('logoPdf', e);
        _logos[url] = null;
      }
    }
    return _mascota();
  }

  static pw.ImageProvider? _mascotaCache;
  static bool _mascotaBuscada = false;

  static Future<pw.ImageProvider?> _mascota() async {
    if (_mascotaBuscada) return _mascotaCache;
    _mascotaBuscada = true;
    try {
      final data = await rootBundle.load('assets/images/mascota.jpg');
      _mascotaCache = pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      _mascotaCache = null; // todavía no se agregó la imagen
    }
    return _mascotaCache;
  }
}
