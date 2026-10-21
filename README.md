# EuromillonesCAIB

Web para gestionar la peña de Euromillones de los compañeros: cada uno ve su saldo, el de todos, el bote y los sorteos.

## Cómo funciona

- Cada participante recarga saldo con **Bizum** y lo avisa en la web («He hecho un Bizum»). Un administrador lo confirma al verlo en el banco.
- **Cada jueves a las 00:00** (hora de Madrid) la lista del sorteo del viernes se cierra sola: se descuenta **1 €** a quien tenga saldo, DNI y normas aceptadas, y la web dice cuántas apuestas automáticas comprar (a 2,50 €). Quien no tiene saldo no juega. Si no llega para ninguna apuesta no se cobra a nadie. Si el cierre falla (por ejemplo, falta apuntar el resultado anterior), el administrador lo ve en Administrar y puede **cerrar a mano**.
- El administrador compra las apuestas en Loterías y Apuestas (botón **Jugar**), **sube el resguardo** (captura, foto o PDF) y marca el sorteo como **jugado**. Todos pueden ver el resguardo.
- Cada sorteo tiene su **acta**: fecha y hora del cierre, importe jugado, resguardo y lista de participantes con su DNI parcial (`***4567**`) y su porcentaje. Se puede imprimir o guardar en PDF; los administradores pueden sacarla con los DNI completos para llevarla al banco.
- Si algo se apunta mal, **Corregir este sorteo** permite cambiar la fecha, deshacer «jugado» para cambiar el resguardo o anular el cierre. El resultado del último sorteo también se puede deshacer y volver a apuntar.
- Lo que sobra va al **bote**, que paga apuestas extra otras semanas.
- Al apuntar el premio: si es de **menos de 2.000 €** se suma a partes iguales al saldo de quienes jugaron (los céntimos que no se pueden repartir van al bote). Si es de **2.000 € o más** no pasa por los saldos: cada participante lo cobra en el banco identificándose con el acta del sorteo.
- Todos los miembros ven los saldos y movimientos de todos (transparencia). El email de cada uno solo lo ven los administradores.
- Se entra sin contraseña: un enlace o código al correo. Al darse de alta cada participante pone su nombre, su **número de DNI/NIE** (sin copia del documento) y acepta las [normas](normas.html). Las cuentas nuevas quedan **pendientes** hasta que un administrador las aprueba, y no se pueden aprobar sin DNI.
- El DNI completo solo lo ven el propio participante y los administradores. Si cambian las normas, se sube `normas_version` en la tabla `ajustes` y todos tendrán que aceptarlas de nuevo al entrar.

Los importes (1 €, 2,50 € y 2.000 €) están en la tabla `ajustes` de Supabase y se pueden cambiar.

## Archivos

| Archivo | Qué es |
|---|---|
| `index.html` | Entrar con email |
| `inicio.html` | Saldo, bote, saldos de todos, sorteos y extracto |
| `admin.html` | Confirmar Bizums, cerrar semana, resultados, participantes |
| `app.js` | Funciones comunes |
| `config.js` | Dirección y clave pública de Supabase |
| `supabase/sql/01_esquema.sql` | Base de datos, reglas de seguridad y toda la lógica del dinero |
| `supabase/sql/02_resguardos.sql` | Carpeta de resguardos y marcar sorteos como jugados |
| `supabase/sql/03_eliminar_pendientes.sql` | Eliminar cuentas pendientes creadas por error |
| `supabase/sql/04_correcciones.sql` | Corregir sorteos apuntados mal |
| `supabase/sql/05_reparto_premios.sql` | Reparto según el reglamento: saldos o cobro en el banco |
| `supabase/sql/06_dni_normas.sql` | DNI/NIE y aceptación de las normas |
| `supabase/sql/07_acta.sql` | Datos del acta de cada sorteo (DNI parcial y porcentajes) |
| `supabase/sql/08_cierre_automatico.sql` | Cierre automático de los jueves (pg_cron) y registro de cierres |
| `normas.html` | Normas de la peña |
| `acta.html` | Acta imprimible de cada sorteo |

## Puesta en marcha (una sola vez)

### 1. Supabase
1. Crea un proyecto nuevo en [supabase.com](https://supabase.com) (región Europa).
2. **SQL Editor → New query**: pega todo `supabase/sql/01_esquema.sql` y pulsa **Run**. Después haz lo mismo, cada uno en una consulta nueva y en orden, con `02_resguardos.sql`, `03_eliminar_pendientes.sql`, `04_correcciones.sql`, `05_reparto_premios.sql`, `06_dni_normas.sql`, `07_acta.sql` y `08_cierre_automatico.sql`.
3. **Project Settings → API**: copia la *Project URL* y la clave *publishable / anon* en `config.js`. **Nunca** la clave `service_role` / `secret`.

### 2. Login por email
En **Authentication → URL Configuration**:
- *Site URL*: `https://jesusmbo.github.io/euromillones/`
- *Redirect URLs*: `https://jesusmbo.github.io/euromillones/inicio.html` y, para probar en local, `http://localhost:5500/inicio.html`

En **Authentication → Emails → Magic Link**, añade el código al texto del correo para poder entrar desde otro dispositivo:
```html
<p>O escribe este código en la web: <b>{{ .Token }}</b></p>
```

### 3. Enviar los correos desde Gmail
El correo de pruebas de Supabase solo envía unos pocos emails por hora. Para usar `eurocomissio@gmail.com`:
1. En esa cuenta de Google activa la **verificación en dos pasos** y crea una **contraseña de aplicación** (myaccount.google.com → Seguridad → Contraseñas de aplicaciones).
2. En Supabase, **Authentication → Emails → SMTP Settings**: activa *Custom SMTP* con
   - Host `smtp.gmail.com`, puerto `465`
   - Usuario `eurocomissio@gmail.com` y la contraseña de aplicación
   - Remitente `eurocomissio@gmail.com`, nombre `EuromillonesCAIB`

### 4. Publicar en GitHub Pages
En GitHub → repositorio → **Settings → Pages**: *Deploy from a branch*, rama `main`, carpeta `/ (root)`. La web quedará en `https://jesusmbo.github.io/euromillones/`.

### 5. Primer administrador
Entra en la web con tu email y pon tu nombre. Después, en el **SQL Editor** de Supabase:
```sql
update public.perfiles set estado = 'activo', es_admin = true where email = 'TU-EMAIL';
```
A partir de ahí, el resto de administradores y aprobaciones se hacen desde la propia web.

## Probar en local
Abre la carpeta con un servidor (por ejemplo, la extensión *Live Server* de VS Code en el puerto 5500) y entra en `http://localhost:5500`. No funciona abriendo el archivo directamente (`file://`).
