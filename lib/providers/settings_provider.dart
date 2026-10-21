import 'package:flutter/foundation.dart';
import '../models/business_settings.dart';
import '../repositories/settings_repository.dart';
import '../security/registro_seguro.dart';

/// Datos del negocio (salen en los comprobantes) y estado de la licencia.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._repo);

  final SettingsRepository _repo;
  BusinessSettings _settings = const BusinessSettings();
  bool _licenseOk = true;

  BusinessSettings get settings => _settings;
  bool get licenseOk => _licenseOk;

  Future<void> cargar() async {
    try {
      _settings = await _repo.get();
      _licenseOk = await _repo.licenseOk();
      notifyListeners();
    } catch (e) {
      registrarError('cargarNegocio', e);
    }
  }

  Future<void> guardar(BusinessSettings s) async {
    _settings = await _repo.update(s);
    notifyListeners();
  }

  Future<void> subirLogo(Uint8List bytes, String extension) async {
    final url = await _repo.uploadLogo(bytes, extension);
    _settings = await _repo.update(_settings.copyWith(logoUrl: url));
    notifyListeners();
  }

  Future<void> quitarLogo() async {
    _settings = await _repo.update(_settings.copyWith(clearLogo: true));
    notifyListeners();
  }
}
