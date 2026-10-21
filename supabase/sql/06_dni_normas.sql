-- =====================================================================
-- EuromillonesCAIB · DNI/NIE y aceptación de las normas
-- Ejecutar entero en Supabase → SQL Editor → New query → Run
-- (después de 05_reparto_premios.sql).
--
-- Cada participante guarda su número de DNI/NIE (sin copia del
-- documento) y acepta las normas. El DNI completo solo lo ven el propio
-- participante y los administradores.
-- Si algún día cambian las normas, se sube "normas_version" en ajustes
-- y todos tendrán que aceptarlas de nuevo al entrar.
-- =====================================================================

alter table public.ajustes add column normas_version text not null default '1';

alter table public.perfiles add column dni text unique;
alter table public.perfiles add column acepta_normas timestamptz;
alter table public.perfiles add column normas_version text;

-- Comprueba la letra de un DNI (12345678Z) o NIE (X1234567L)
create function public.dni_valido(p_dni text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text := upper(regexp_replace(coalesce(p_dni, ''), '[\s.-]', '', 'g'));
  n text;
begin
  if v ~ '^[XYZ][0-9]{7}[A-Z]$' then
    n := translate(substr(v, 1, 1), 'XYZ', '012') || substr(v, 2, 7);
  elsif v ~ '^[0-9]{8}[A-Z]$' then
    n := substr(v, 1, 8);
  else
    return false;
  end if;
  return substr('TRWAGMYFPDXBNJZSQVHLCKE', (n::int % 23) + 1, 1) = right(v, 1);
end;
$$;

-- Alta (o actualización) de los datos del propio participante
create function public.completar_registro(p_nombre text, p_dni text, p_acepta boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dni text := upper(regexp_replace(coalesce(p_dni, ''), '[\s.-]', '', 'g'));
  v_actual text;
begin
  if auth.uid() is null then raise exception 'Tienes que iniciar sesión'; end if;
  p_nombre := btrim(p_nombre);
  if length(p_nombre) not between 2 and 60 then raise exception 'El nombre debe tener entre 2 y 60 caracteres'; end if;
  if not public.dni_valido(v_dni) then raise exception 'El DNI/NIE no es válido. Revisa los números y la letra'; end if;
  if not coalesce(p_acepta, false) then raise exception 'Tienes que aceptar las normas de la peña'; end if;

  select dni into v_actual from public.perfiles where id = auth.uid();
  if v_actual is not null and v_actual <> v_dni then
    raise exception 'Para cambiar tu DNI habla con un administrador';
  end if;
  if exists (select 1 from public.perfiles where dni = v_dni and id <> auth.uid()) then
    raise exception 'Ese DNI/NIE ya está registrado con otra cuenta';
  end if;

  update public.perfiles
  set nombre = p_nombre, dni = v_dni, acepta_normas = now(),
      normas_version = (select normas_version from public.ajustes where id = 1)
  where id = auth.uid();
end;
$$;

-- Corregir el DNI de alguien (por ejemplo, si se equivocó al escribirlo)
create function public.cambiar_dni(p_perfil uuid, p_dni text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dni text := upper(regexp_replace(coalesce(p_dni, ''), '[\s.-]', '', 'g'));
begin
  perform public.solo_admin();
  if not public.dni_valido(v_dni) then raise exception 'El DNI/NIE no es válido. Revisa los números y la letra'; end if;
  if exists (select 1 from public.perfiles where dni = v_dni and id <> p_perfil) then
    raise exception 'Ese DNI/NIE ya está registrado con otra cuenta';
  end if;
  update public.perfiles set dni = v_dni where id = p_perfil;
  if not found then raise exception 'Ese participante no existe'; end if;
end;
$$;

-- No se puede aprobar (ni reactivar) a quien no ha dado su DNI y aceptado las normas
create or replace function public.cambiar_estado(p_perfil uuid, p_estado text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.solo_admin();
  if p_estado not in ('activo', 'baja') then raise exception 'Estado no válido'; end if;
  if p_perfil = auth.uid() then raise exception 'No puedes cambiar tu propio estado'; end if;
  if p_estado = 'activo' and exists (
    select 1 from public.perfiles where id = p_perfil and (dni is null or acepta_normas is null)
  ) then
    raise exception 'Este participante aún no ha puesto su DNI ni aceptado las normas';
  end if;
  update public.perfiles set estado = p_estado where id = p_perfil;
end;
$$;

revoke execute on function public.completar_registro(text, text, boolean), public.cambiar_dni(uuid, text), public.dni_valido(text) from public, anon;
grant execute on function public.completar_registro(text, text, boolean), public.cambiar_dni(uuid, text), public.dni_valido(text) to authenticated;
