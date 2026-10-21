// Configuración de Supabase.
// La clave "anon / publishable" es PÚBLICA: puede ir en la web y en GitHub.
// NUNCA pongas aquí la clave "service_role" / "secret".
const SUPABASE_URL = "https://TU-PROYECTO.supabase.co";
const SUPABASE_ANON_KEY = "TU-CLAVE-PUBLISHABLE";

const sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
