// Utilidades compartidas por todas las páginas

const CONFIGURADO = !SUPABASE_URL.includes("TU-PROYECTO");

const $ = (sel, root = document) => root.querySelector(sel);

function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = text ?? "";
  return div.innerHTML;
}

const formatoEuro = new Intl.NumberFormat("es-ES", { style: "currency", currency: "EUR" });
function euro(n) {
  return formatoEuro.format(Number(n) || 0);
}

function fecha(d) {
  if (!d) return "";
  // Las fechas "2026-10-21" se leen como hora local para que no cambie el día
  const date = d.length === 10 ? new Date(d + "T00:00:00") : new Date(d);
  return date.toLocaleDateString("es-ES", { day: "2-digit", month: "2-digit", year: "numeric" });
}

function hoyISO() {
  const d = new Date();
  d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
  return d.toISOString().slice(0, 10);
}

// Mensaje flotante breve
function aviso(texto, tipo = "ok") {
  let el = $("#toast");
  if (!el) {
    el = document.createElement("div");
    el.id = "toast";
    el.setAttribute("role", "status");
    document.body.appendChild(el);
  }
  el.textContent = texto;
  el.className = "toast " + tipo;
  clearTimeout(el._t);
  el._t = setTimeout(() => (el.className = "toast hidden"), 4000);
}

// Los errores de las funciones SQL ya vienen en español ("raise exception")
function textoError(error) {
  const m = error?.message || "";
  if (/failed to fetch|network/i.test(m)) return "Error de conexión. Inténtalo de nuevo.";
  return m || "Algo ha fallado. Inténtalo de nuevo.";
}

// Llama a una función de la base de datos y lanza un Error legible si falla
async function rpc(nombre, params) {
  const { data, error } = await sb.rpc(nombre, params);
  if (error) throw new Error(textoError(error));
  return data;
}

// Devuelve el perfil del usuario con sesión, o redirige al login
async function cargarPerfil() {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) {
    location.replace("index.html");
    return null;
  }
  const { data, error } = await sb.from("perfiles").select("*").eq("id", session.user.id).single();
  if (error) throw new Error(textoError(error));
  return data;
}

async function salir() {
  await sb.auth.signOut();
  location.replace("index.html");
}

// Semáforo del saldo según cuántas semanas cubre
function colorSaldo(saldo, cuota) {
  if (saldo < cuota) return "rojo";
  if (saldo < cuota * 3) return "amarillo";
  return "verde";
}

function iniciales(nombre) {
  return (nombre || "?").split(/\s+/).slice(0, 2).map(p => p[0]).join("").toUpperCase();
}

// Barra superior común
function pintarTopbar(perfil, paginaActual) {
  const enlaceAdmin = perfil?.es_admin && perfil.estado === "activo"
    ? (paginaActual === "admin"
        ? `<a class="btn-ghost" href="inicio.html">Inicio</a>`
        : `<a class="btn-ghost" href="admin.html">Administrar</a>`)
    : "";
  $("#topbar").innerHTML = `
    <a class="logo" href="inicio.html">
      <span class="logo-mark">★</span>
      <span>Euromillones<b>CAIB</b></span>
    </a>
    <div class="user-chip">
      ${enlaceAdmin}
      <span class="avatar" title="${escapeHtml(perfil?.nombre || perfil?.email)}">${escapeHtml(iniciales(perfil?.nombre || perfil?.email))}</span>
      <button class="btn-ghost" id="salir" type="button">Salir</button>
    </div>`;
  $("#salir").addEventListener("click", salir);
}

function avisoSinConfigurar() {
  document.body.insertAdjacentHTML("afterbegin",
    `<div class="banner">Falta configurar Supabase en <code>config.js</code>. Mira el README.</div>`);
}
