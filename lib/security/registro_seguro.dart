// =================================================================
//  ERRORES SEGUROS
//  Dos funciones para manejar errores sin filtrar datos personales:
//    - registrarError: deja un rastro en la consola de desarrollo.
//    - mensajeErrorSeguro: decide qué texto ve el usuario en pantalla.
//  Regla de oro: NUNCA mostrar ni imprimir la respuesta cruda del servidor.
// =================================================================
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// REGISTRAR UN ERROR (solo para el programador). Imprime dónde pasó y de qué
// TIPO fue, pero nunca el mensaje completo. En release no registra nada.
void registrarError(String contexto, Object error) {
  if (kReleaseMode) return;
  final codigo = error is PostgrestException ? ' code=${error.code}' : '';
  debugPrint('$contexto [${error.runtimeType}$codigo]');
}

// OPERACIÓN YA REGISTRADA. La base devuelve este código cuando llega de nuevo
// la clave de una operación que ya se guardó, pero con otros datos (por ejemplo,
// se cortó internet, la venta sí entró y después se cambió el carrito).
const codigoYaRegistrada = 'BM409';

bool esYaRegistrada(Object error) => error is PostgrestException && error.code == codigoYaRegistrada;

/// Email o contraseña incorrectos (cuenta para el bloqueo por intentos).
bool esCredencialIncorrecta(Object error) =>
    error is AuthException && (error.code == 'invalid_credentials' || error.message.toLowerCase().contains('invalid login'));

/// El servidor contestó con un error (stock, datos, permisos...): la operación seguro NO se hizo.
/// Un 5xx sin código de la base (502, 504: se cayó la conexión en el medio) no cuenta:
/// la operación pudo haber entrado.
bool esRechazoDelServidor(Object error) {
  if (error is! PostgrestException) return false;
  final code = error.code ?? '';
  return code.isNotEmpty && !RegExp(r'^5\d\d$').hasMatch(code);
}

// ELEGIR EL TEXTO PARA EL USUARIO. Recibe el error y un mensaje genérico.
String mensajeErrorSeguro(Object error, [String generico = 'No se pudo completar la operación. Intentá de nuevo.']) {
  if (error is PostgrestException) {
    switch (error.code) {
      // Mensajes escritos por nosotros en las funciones de la base (raise exception).
      case 'P0001':
      case codigoYaRegistrada:
        return error.message;
      case '23505':
        if (error.message.contains('products_name_unique')) return 'Ya existe un producto con ese nombre. Buscalo en la lista.';
        if (error.message.contains('cash_sessions_una_abierta')) return 'Ya tenés tu caja abierta. Cerrala antes de abrir otra.';
        return 'Ya existe un registro con ese mismo dato.';
      case '23503':
        return 'No se puede borrar porque tiene ventas, compras o movimientos registrados. Podés desactivarlo.';
      case '23514':
        return 'Hay un dato que no es válido. Revisá los campos.';
      case '42501':
        return 'Tu usuario no tiene permiso para hacer esto.';
      case 'PGRST301':
      case 'PGRST303':
        return 'Tu sesión venció. Volvé a iniciar sesión.';
    }
    return generico;
  }
  if (error is AuthException) {
    final m = error.message.toLowerCase();
    if (m.contains('invalid login') || error.code == 'invalid_credentials') {
      return 'Usuario o contraseña incorrectos. Revisá bien los datos.';
    }
    if (error.code == 'user_banned' || m.contains('banned')) {
      return 'Tu usuario está desactivado. Hablá con el administrador.';
    }
    if (m.contains('rate limit') || error.statusCode == '429') {
      return 'Demasiados intentos seguidos. Esperá un minuto y volvé a intentar.';
    }
    if (m.contains('not confirmed')) return 'Ese email todavía no fue confirmado.';
    return 'No se pudo iniciar sesión. Revisá tu conexión e intentá de nuevo.';
  }
  if (error is SocketException || error is TimeoutException || error is HttpException) {
    return 'No hay conexión a internet. Revisá el wifi o los datos móviles.';
  }
  final tipo = error.runtimeType.toString();
  if (tipo.contains('ClientException') || tipo.contains('Socket')) {
    return 'No hay conexión a internet. Revisá el wifi o los datos móviles.';
  }
  return generico;
}
