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

// ---------- Resguardos (Storage: resguardos/<id del sorteo>/) ----------

const URL_JUGAR = "https://www.loteriasyapuestas.es/es/euromillones";

async function listarResguardos(sorteoId) {
  const carpeta = sb.storage.from("resguardos");
  const { data, error } = await carpeta.list(String(sorteoId), { sortBy: { column: "name", order: "asc" } });
  if (error) throw new Error(textoError(error));
  const archivos = data.filter(f => f.id);  // descarta marcadores de carpeta
  if (!archivos.length) return [];
  const rutas = archivos.map(f => `${sorteoId}/${f.name}`);
  const { data: firmadas, error: e2 } = await carpeta.createSignedUrls(rutas, 3600);
  if (e2) throw new Error(textoError(e2));
  return rutas.map((ruta, i) => ({ ruta, url: firmadas[i].signedUrl, esPdf: ruta.endsWith(".pdf") }));
}

function htmlResguardos(lista, conBorrar = false) {
  if (!lista.length) return `<p class="muted small">Todavía no hay resguardo.</p>`;
  return `<div class="resguardos">${lista.map(r => `
    <div class="resguardo">
      <a href="${r.url}" target="_blank" rel="noopener">
        ${r.esPdf ? `<span class="pdf">📄 PDF</span>` : `<img src="${r.url}" alt="Resguardo" loading="lazy">`}
      </a>
      ${conBorrar ? `<button class="quitar" type="button" data-ruta="${escapeHtml(r.ruta)}" aria-label="Quitar">✕</button>` : ""}
    </div>`).join("")}</div>`;
}

// Reduce las fotos del móvil a un tamaño razonable antes de subirlas
async function comprimirImagen(file, lado = 1600) {
  const img = await createImageBitmap(file);
  const escala = Math.min(1, lado / Math.max(img.width, img.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(img.width * escala);
  canvas.height = Math.round(img.height * escala);
  canvas.getContext("2d").drawImage(img, 0, 0, canvas.width, canvas.height);
  return new Promise(res => canvas.toBlob(res, "image/jpeg", 0.85));
}

async function subirResguardos(sorteoId, files) {
  for (const [i, file] of [...files].entries()) {
    const esPdf = file.type === "application/pdf";
    if (!esPdf && !file.type.startsWith("image/")) throw new Error("Solo se pueden subir fotos o PDF.");
    const cuerpo = esPdf ? file : await comprimirImagen(file);
    if (cuerpo.size > 5 * 1024 * 1024) throw new Error("El archivo pesa más de 5 MB.");
    const ruta = `${sorteoId}/${Date.now()}-${i}.${esPdf ? "pdf" : "jpg"}`;
    const { error } = await sb.storage.from("resguardos").upload(ruta, cuerpo, { contentType: esPdf ? "application/pdf" : "image/jpeg" });
    if (error) throw new Error(textoError(error));
  }
}

function avisoSinConfigurar() {
  document.body.insertAdjacentHTML("afterbegin",
    `<div class="banner">Falta configurar Supabase en <code>config.js</code>. Mira el README.</div>`);
}
