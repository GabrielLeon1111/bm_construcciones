import 'package:bm_construcciones/repositories/empleado_repository.dart';
import 'package:bm_construcciones/screens/empleados/empleados_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el usuario se sugiere sin tildes ni espacios', () {
    expect(sugerirUsuario('Juan', 'Pérez'), 'juan.perez');
    expect(sugerirUsuario('María José', 'Núñez Benítez'), 'maria.nunez');
    expect(sugerirUsuario('Ñandú', ''), 'nandu');
  });

  test('entrar con usuario o con email', () {
    expect(emailDeUsuario('juan.perez'), 'juan.perez@$dominioEmpleados');
    expect(emailDeUsuario('  Juan.Perez '), 'juan.perez@$dominioEmpleados');
    expect(emailDeUsuario('admin@ejemplo.com'), 'admin@ejemplo.com');
  });
}
