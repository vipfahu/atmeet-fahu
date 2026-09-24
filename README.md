# at meet FAHU

Consultas de disponibilidad por fechas, semanas y días de mes. Incluye comentarios, coincidencias, exportación a calendarios, cierre y notificaciones.

## Instalación en un proyecto Supabase compartido

Ejecutar una sola vez `supabase/shared-project.sql`. Crea exclusivamente el esquema `atmeet_fahu` y sus seis tablas; no modifica las tablas, funciones, perfiles ni usuarios de otras aplicaciones.

Añadir `atmeet_fahu` a los esquemas expuestos de Data API, conservando los existentes. El acceso de tablas y funciones se limita a `service_role`; los roles `anon` y `authenticated` no tienen acceso. RLS está habilitado en todas las tablas. La clave de servicio conserva privilegios de proyecto: el esquema separa los datos pero no limita esa clave a una aplicación.

No ejecutar los scripts anteriores que instalan tablas en `public`; permanecen como referencia de la versión original.

## Publicación

Node.js 22.13 o superior. `npm ci`, `npm run build`. Netlify usa `netlify.toml`, con salida `dist-netlify` y funciones en `netlify/functions`.

Después del instalador base, ejecutar `supabase/admin-recovery.sql` una sola vez.

Remitente FAHU: `at meet FAHU <atmeetfahu@contact.agencements.net>`.

Variables de servidor: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `RESEND_API_KEY`, `RESEND_FROM_EMAIL`. Nunca guardar secretos en GitHub ni añadirles el prefijo VITE_. Los correos requieren un remitente verificado.

## Administración independiente

Las cuentas de at meet FAHU son exclusivas de este sistema y pueden pertenecer a personas sin cuenta VIP. No utilizan Supabase Auth ni las tablas de perfiles del portal. Contraseñas con scrypt y sal aleatoria; sesiones opacas de ocho horas con cookies HttpOnly, Secure y SameSite=Strict. Ocho intentos por correo cada quince minutos. Cada petición comprueba que la cuenta siga activa.

El propietario provisiona la primera invitación guardando solo el SHA-256 de un token aleatorio de 32 bytes en `atmeet_fahu.meeting_admin_invitations`, con el correo concreto y vencimiento. Se entrega privadamente el enlace `/admin#invite=TOKEN`. No incluir el token en el repositorio. Las siguientes invitaciones se generan y envían desde Administración.

La aceptación comprueba destinatario, vencimiento y uso único de forma transaccional. Un cambio de contraseña invalida las sesiones anteriores. Desactivar una cuenta mediante `active=false` revoca su acceso. La recuperación por correo usa enlaces de un solo uso con vencimiento de 30 minutos, respuestas neutrales y límites de solicitud. Cambiar la contraseña invalida enlaces anteriores y sesiones. Las invitaciones se envían por correo; si falla el envío, se conserva el enlace para compartirlo manualmente.

## Comprobaciones

`npx tsc --noEmit`, `npm run build`. Compilar `scripts/test-admin.mjs` con esbuild para Node y ejecutar: verifica aislamiento respecto de Supabase Auth, cabeceras de esquema, cookies, origen, revocación e invitaciones de uso único.
