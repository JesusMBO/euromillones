# EuromillonesCAIB · Guía para Claude

Web para gestionar la peña de Euromillones sin ánimo de lucro de unos 30 compañeros de trabajo de la CAIB (puede crecer a cientos). Cada uno tiene un saldo prepagado; cada semana se cobra 1 € a quien tiene saldo, se juegan apuestas y se reparten los premios. El [README.md](README.md) explica el funcionamiento y la puesta en marcha; este archivo recoge cómo trabajar en el proyecto.

## Con quién trabajas

- El usuario habla **español** y está **empezando en desarrollo web**. Responde siempre en español, sin jerga, paso a paso.
- Prefiere **entender antes de construir**: cuando pide «explícame» o «solo contesta», no toques nada.
- En cambios grandes quiere ir **paso a paso**: propón los pasos y espera a que diga «lanzamos» antes de cada uno.
- Él ejecuta los SQL en Supabase y prueba en la web real. Al acabar cada cambio, dile exactamente qué archivo ejecutar y qué probar.

## Tecnología

- **Web estática** sin compilación: HTML + JS + CSS. Supabase JS desde CDN (`@supabase/supabase-js@2.57.4`, versión fija).
- **Supabase** (proyecto `stockjrwbrqcaspnuvvd`): login por enlace/código al email, base de datos Postgres, Storage (resguardos) y pg_cron (cierre semanal).
- **GitHub Pages**: repositorio público `JesusMBO/euromillones`, rama `main`. Publicar = hacer push a `main`; tarda 1–2 minutos.
- Correo de acceso por SMTP de Gmail (`eurocomissio@gmail.com`, contraseña de aplicación que pone el usuario en Supabase; nunca se la pidas).

## Archivos

| Archivo | Qué es |
|---|---|
| `index.html` | Entrar con email (enlace o código) |
| `inicio.html` | Saldo, bote, saldos de todos, sorteos, extracto; alta con DNI y normas |
| `admin.html` | Bizums, sorteo de la semana, correcciones, movimientos, participantes |
| `acta.html` | Acta imprimible de cada sorteo |
| `normas.html` | Normas de la peña (texto legal para los participantes) |
| `app.js` | Funciones comunes: `$`, `euro`, `fecha`, `fechaHora`, `rpc`, `aviso`, `cargarPerfil`, `pintarTopbar`, resguardos, DNI |
| `config.js` | URL y clave **publishable** de Supabase (es pública) |
| `styles.css` | Estilos; colores como variables en `:root`, con modo oscuro |
| `supabase/sql/NN_*.sql` | Cambios de base de datos, numerados y en orden |

## Reglas de la peña (vienen del reglamento del grupo)

- Cuota: **1 € por sorteo**. Se juega el **sorteo del viernes**.
- **Cierre automático cada jueves a las 00:00 (hora de Madrid)**: juegan los activos con saldo ≥ 1 €, DNI y normas aceptadas. Sin saldo no juegas y no generas deuda. Si no llega para ninguna apuesta, no se cobra a nadie. El administrador puede cerrar a mano si el automático falla.
- Apuestas automáticas a 2,50 € en Loterías y Apuestas (online). Lo que sobra va al **bote**, que paga apuestas extra.
- **Premios < 2.000 €**: se suman a partes iguales al saldo de quienes jugaron ese sorteo; los céntimos sobrantes, al bote.
- **Premios ≥ 2.000 €**: no pasan por los saldos. Todos los participantes se identifican en el banco con el acta (evita que Hacienda lo trate como donación).
- **DNI/NIE**: solo el número, nunca copia del documento. Completo solo lo ven el propio participante y los administradores; en el acta sale parcial (`***4567**`, `****4567*`).
- **Transparencia**: todos los miembros ven saldos, movimientos, sorteos, participantes y resguardos de todos.
- Recargas por Bizum o transferencia: el participante avisa en la web y un administrador lo confirma al ver el dinero.
- Los importes (1 €, 2,50 €, 2.000 €) y la versión de las normas están en la tabla `ajustes`.

## Base de datos: principios que no se rompen

- **El saldo no se guarda: es la suma de `movimientos`.** Igual el bote con `bote_movimientos`. Nunca se borra ni se edita un movimiento para corregir algo: se añade un **ajuste** con su nota.
- **Nadie escribe directamente en las tablas.** RLS solo permite leer; todas las escrituras van por funciones `security definer` con `set search_path = ''`, que empiezan con `perform public.solo_admin();` o comprueban `public.es_miembro()`.
- Los mensajes de `raise exception` están **en español** y la web los enseña tal cual al usuario: escríbelos para él.
- `participaciones` es la **prueba legal** de quién jugaba cada sorteo: no se modifica una vez cerrado (salvo anular el cierre antes del resultado).
- Correcciones posibles: cambiar fecha, deshacer «jugado», anular cierre, deshacer el resultado del **último** sorteo si nadie ha retirado el premio.

## Cómo hacer cambios en la base de datos

1. Crea un archivo **nuevo** `supabase/sql/NN_descripcion.sql` con el número siguiente. **Nunca edites un SQL ya ejecutado**: el usuario ya lo ha pasado en Supabase.
2. Cabecera explicando qué hace y «Ejecutar … después de NN-1». Usa `create or replace function` para cambiar funciones existentes.
3. Para funciones nuevas: `revoke execute … from public, anon;` y `grant execute … to authenticated;` (o sin grant si solo las usa el sistema).
4. Actualiza el README: la tabla de archivos y la lista de la puesta en marcha.
5. Dile al usuario que lo ejecute en **SQL Editor → New query → Run**, antes de que la web nueva se publique.

## Web: convenciones

- Interfaz en español, pensada primero para **móvil**.
- Todo dato que venga de la base de datos se pinta con `escapeHtml`.
- Llamadas a funciones con `rpc(nombre, params)`, que lanza un `Error` con el mensaje en español. En `admin.html`, `accion(boton, fn, textoOk)` muestra el resultado y recarga.
- Los importes con `euro()` (lleva punto de miles) y las fechas con `fecha()` / `fechaHora()`.
- Las acciones que mueven dinero o no se pueden deshacer piden `confirm()` y explican qué va a pasar.

## Seguridad

- **Nunca** pongas la clave `service_role` / `sb_secret_…` en ningún archivo. La publishable de `config.js` es pública por diseño.
- No pidas contraseñas al usuario (Gmail, Supabase, Loterías): las pone él.
- No escribas en la base de datos real para probar. Si hay que mirar algo en el panel de Supabase, el usuario inicia sesión y tú solo lees.

## Cómo probar

- **SQL**: con PGlite (`@electric-sql/pglite@0.2.17`, Postgres en memoria) en el scratchpad. Hace falta simular lo de Supabase antes de cargar los SQL en orden: esquema `auth` con `auth.users` y `auth.uid()` leyendo `current_setting('test.uid', true)`, roles `anon` y `authenticated`, y esquema `storage` con `buckets` y `objects`. Para probar RLS: `set role authenticated`. pg_cron no existe en PGlite: quita la parte de `cron.schedule` al cargar. Ojo: `select (funcion()).*` ejecuta la función una vez por columna; usa `select * from funcion()`.
- **Pantallas**: copia la web al scratchpad con un `config.js` falso (un objeto `sb` con datos de ejemplo), sírvela con un servidor estático local y revísala con el navegador integrado, en móvil (375 px) y escritorio, sin scroll horizontal y sin errores de consola.
- Di siempre qué se ha probado y qué falta por probar en el Supabase real.

## Git

- Mensajes de commit en español. Push directo a `main` (es lo que publica la web).
- El usuario a veces edita archivos desde la web de GitHub: haz `git fetch` y, si hay cambios, mira qué son y haz `rebase` antes del push.

## Pendiente

- Ajustar el documento Word del reglamento (`OneDrive\01 - CAIB\EUROMILLONES\Estatutos_Reglamento_Pena_Loteria.docx`) para que coincida con la web: hueco de 2.000–40.000 €, sin copia del DNI, sin Primitiva, cierre del jueves.
- El primer cierre automático real es el jueves 29/10/2026: comprobar en Administrar que se registró bien.
