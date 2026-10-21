import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Los vendedores entran con un usuario (ej: "juan.perez"); por dentro es este email
/// con un dominio reservado que nunca recibe correos.
const dominioEmpleados = 'empleados.bm-construcciones.invalid';

/// "juan.perez" → email interno; un email se deja como está.
String emailDeUsuario(String entrada) {
  final t = entrada.trim().toLowerCase();
  return t.contains('@') ? t : '$t@$dominioEmpleados';
}

class Empleado {
  final String userId;
  final String rol;
  final String nombre;
  final String? usuario;
  final bool activo;
  final DateTime creado;

  const Empleado({required this.userId, required this.rol, required this.nombre, this.usuario, required this.activo, required this.creado});

  bool get esAdmin => rol == 'admin';

  factory Empleado.fromMap(Map<String, dynamic> m) => Empleado(
        userId: m['user_id'] as String,
        rol: m['role'] as String,
        nombre: (m['full_name'] as String?) ?? 'Sin nombre',
        usuario: m['username'] as String?,
        activo: (m['active'] as bool?) ?? true,
        creado: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}

/// Error con un mensaje para mostrar tal cual (escrito por nosotros en la función).
class EmpleadoException implements Exception {
  EmpleadoException(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}

class EmpleadoRepository {
  Future<List<Empleado>> list() async {
    final rows = await supa.from('app_members').select('user_id, role, full_name, username, active, created_at').order('role').order('full_name');
    return rows.map(Empleado.fromMap).toList();
  }

  // Edge Function "empleados": crea usuarios con la clave de servicio (solo en el servidor)
  // y verifica que quien la llama sea un administrador.
  Future<Map<String, dynamic>> _llamar(Map<String, dynamic> body) async {
    try {
      final r = await supa.functions.invoke('empleados', body: body);
      return Map<String, dynamic>.from((r.data as Map?) ?? const {});
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['error'] is String) throw EmpleadoException(d['error'] as String);
      rethrow;
    }
  }

  Future<void> crear({required String nombre, required String apellido, required String usuario, required String clave}) =>
      _llamar({'accion': 'crear', 'nombre': nombre, 'apellido': apellido, 'usuario': usuario, 'clave': clave});

  Future<void> activar(String userId, bool activo) => _llamar({'accion': 'activar', 'user_id': userId, 'activo': activo});

  Future<void> cambiarClave(String userId, String clave) => _llamar({'accion': 'clave', 'user_id': userId, 'clave': clave});

  Future<void> eliminar(String userId) => _llamar({'accion': 'eliminar', 'user_id': userId});
}
