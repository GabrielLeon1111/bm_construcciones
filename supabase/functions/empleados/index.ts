// =================================================================
//  EMPLEADOS: el administrador crea vendedores, los activa/desactiva y
//  les cambia la contraseña. Necesita la clave de servicio (solo existe
//  en el servidor), por eso no se hace desde la app.
//  Cada pedido verifica que quien llama sea un administrador activo.
// =================================================================
import { createClient } from "npm:@supabase/supabase-js@2";

// Los vendedores entran con un usuario (ej: "juan.perez"). Por dentro se usa
// un email con un dominio reservado que nunca recibe correos (.invalid).
const DOMINIO = "empleados.bm-construcciones.invalid";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const responder = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const error = (status: number, mensaje: string) => responder(status, { error: mensaje });

const limpiar = (v: unknown) => (typeof v === "string" ? v.replace(/\s+/g, " ").trim() : "");
const nombreOk = (v: string) => v.length >= 2 && v.length <= 40 && /^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ' -]+$/.test(v);
const usuarioOk = (v: string) => /^[a-z0-9._-]{3,30}$/.test(v);
const claveOk = (v: unknown): v is string => typeof v === "string" && v.length >= 8 && v.length <= 72;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return error(405, "Método no permitido.");

  const url = Deno.env.get("SUPABASE_URL")!;
  const servicio = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(url, servicio, { auth: { persistSession: false, autoRefreshToken: false } });

  // 1) ¿Quién llama? Tiene que ser un administrador activo.
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: quien } = await admin.auth.getUser(token);
  if (!quien?.user) return error(401, "Tu sesión venció. Volvé a iniciar sesión.");
  const { data: yo } = await admin.from("app_members").select("role, active").eq("user_id", quien.user.id).maybeSingle();
  if (!yo || !yo.active || yo.role !== "admin") return error(403, "Solo el administrador puede manejar empleados.");

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return error(400, "Pedido inválido.");
  }

  // Solo se tocan vendedores (nunca un administrador ni uno mismo).
  const vendedor = async (id: unknown) => {
    if (typeof id !== "string" || id === quien.user.id) return null;
    const { data } = await admin.from("app_members").select("user_id, role, full_name").eq("user_id", id).maybeSingle();
    return data && data.role === "vendedor" ? data : null;
  };

  switch (body.accion) {
    case "crear": {
      const nombre = limpiar(body.nombre);
      const apellido = limpiar(body.apellido);
      const usuario = limpiar(body.usuario).toLowerCase();
      if (!nombreOk(nombre)) return error(400, "Revisá el nombre (solo letras, 2 a 40).");
      if (!nombreOk(apellido)) return error(400, "Revisá el apellido (solo letras, 2 a 40).");
      if (!usuarioOk(usuario)) return error(400, "El usuario va en minúsculas, sin espacios (ej: juan.perez).");
      if (!claveOk(body.clave)) return error(400, "La contraseña tiene que tener al menos 8 caracteres.");

      const { data: existe } = await admin.from("app_members").select("user_id").ilike("username", usuario).maybeSingle();
      if (existe) return error(409, `Ya existe un empleado con el usuario "${usuario}".`);

      const completo = `${nombre} ${apellido}`;
      const { data: creado, error: e1 } = await admin.auth.admin.createUser({
        email: `${usuario}@${DOMINIO}`,
        password: body.clave,
        email_confirm: true,
        user_metadata: { full_name: completo },
        app_metadata: { role: "vendedor" },
      });
      if (e1 || !creado.user) {
        const ya = (e1?.message ?? "").toLowerCase().includes("already");
        return error(ya ? 409 : 400, ya ? `Ya existe un empleado con el usuario "${usuario}".` : "No se pudo crear el usuario.");
      }
      const { error: e2 } = await admin.from("app_members").insert({
        user_id: creado.user.id,
        role: "vendedor",
        full_name: completo,
        username: usuario,
        active: true,
      });
      if (e2) {
        // No dejar un usuario a medias.
        await admin.auth.admin.deleteUser(creado.user.id);
        return error(400, "No se pudo registrar al empleado. Intentá de nuevo.");
      }
      return responder(200, { ok: true, user_id: creado.user.id, usuario, nombre: completo });
    }

    case "activar": {
      const v = await vendedor(body.user_id);
      if (!v) return error(404, "No se encontró ese empleado.");
      const activo = body.activo === true;
      // Desactivado: no puede entrar (y si tenía la sesión abierta, el servidor ya no lo deja operar).
      const { error: e } = await admin.auth.admin.updateUserById(v.user_id, { ban_duration: activo ? "none" : "876000h" });
      if (e) return error(400, "No se pudo cambiar el estado.");
      await admin.from("app_members").update({ active: activo }).eq("user_id", v.user_id);
      return responder(200, { ok: true });
    }

    case "clave": {
      const v = await vendedor(body.user_id);
      if (!v) return error(404, "No se encontró ese empleado.");
      if (!claveOk(body.clave)) return error(400, "La contraseña tiene que tener al menos 8 caracteres.");
      const { error: e } = await admin.auth.admin.updateUserById(v.user_id, { password: body.clave });
      if (e) return error(400, "No se pudo cambiar la contraseña.");
      return responder(200, { ok: true });
    }

    case "eliminar": {
      // Solo si nunca vendió ni presupuestó (ej: se creó por error). Si ya tiene historial, se desactiva.
      const v = await vendedor(body.user_id);
      if (!v) return error(404, "No se encontró ese empleado.");
      const [{ count: ventas }, { count: presupuestos }] = await Promise.all([
        admin.from("sales").select("id", { count: "exact", head: true }).eq("created_by", v.user_id),
        admin.from("quotes").select("id", { count: "exact", head: true }).eq("created_by", v.user_id),
      ]);
      if ((ventas ?? 0) > 0 || (presupuestos ?? 0) > 0) {
        return error(409, "Este empleado ya tiene ventas o presupuestos: desactivalo en lugar de eliminarlo.");
      }
      const { error: e } = await admin.auth.admin.deleteUser(v.user_id);
      if (e) return error(400, "No se pudo eliminar.");
      return responder(200, { ok: true });
    }
  }
  return error(400, "Acción desconocida.");
});
