-- =====================================================================
-- EuromillonesCAIB · Acta digital de cada sorteo
-- Ejecutar entero en Supabase → SQL Editor → New query → Run
-- (después de 06_dni_normas.sql).
--
-- Lista de participantes de un sorteo con su DNI/NIE parcial y su
-- porcentaje. Los administradores pueden pedirla con el DNI completo
-- (para llevarla al banco si toca un premio grande).
-- =====================================================================

-- DNI parcial según el criterio de la Agencia de Protección de Datos:
-- 12345678Z → ***4567**   ·   X1234567L → ****4567*
create function public.dni_parcial(p_dni text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_dni ~ '^[0-9]{8}[A-Z]$' then '***' || substr(p_dni, 4, 4) || '**'
    when p_dni ~ '^[XYZ][0-9]{7}[A-Z]$' then '****' || substr(p_dni, 5, 4) || '*'
  end;
$$;

-- Vacía si quien la pide no es miembro activo, o pide DNI completos sin ser admin
create function public.acta_participantes(p_sorteo bigint, p_completo boolean default false)
returns table (nombre text, dni text, importe numeric, porcentaje numeric)
language sql
stable
security definer
set search_path = ''
as $$
  select p.nombre,
         case when p_completo then p.dni else public.dni_parcial(p.dni) end,
         pa.importe,
         round(pa.importe * 100 / nullif(s.recaudado, 0), 4)
  from public.participaciones pa
  join public.perfiles p on p.id = pa.perfil_id
  join public.sorteos s on s.id = pa.sorteo_id
  where pa.sorteo_id = p_sorteo
    and public.es_miembro()
    and (not p_completo or public.es_admin())
  order by p.nombre;
$$;

revoke execute on function public.dni_parcial(text), public.acta_participantes(bigint, boolean) from public, anon;
grant execute on function public.dni_parcial(text), public.acta_participantes(bigint, boolean) to authenticated;
