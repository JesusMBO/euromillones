-- =====================================================================
-- EuromillonesCAIB · Corregir sorteos
-- Ejecutar entero en Supabase → SQL Editor → New query → Run
-- (después de 03_eliminar_pendientes.sql).
--
-- Permite arreglar errores al apuntar un sorteo:
--   · cambiar la fecha
--   · deshacer "jugado" para cambiar los resguardos
--   · anular el cierre aunque tenga resguardo (la web borra los archivos)
--   · deshacer el resultado si el premio se apuntó mal
-- =====================================================================

create function public.cambiar_fecha_sorteo(p_sorteo bigint, p_fecha date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.solo_admin();
  if p_fecha is null then raise exception 'Indica la nueva fecha'; end if;
  if exists (select 1 from public.sorteos where fecha = p_fecha and id <> p_sorteo) then
    raise exception 'Ya existe otro sorteo con esa fecha';
  end if;
  update public.sorteos set fecha = p_fecha where id = p_sorteo;
  if not found then raise exception 'Ese sorteo no existe'; end if;
  update public.movimientos
  set nota = case tipo when 'premio' then 'Premio sorteo ' else 'Sorteo ' end || to_char(p_fecha, 'DD/MM/YYYY')
  where sorteo_id = p_sorteo and tipo in ('apuesta', 'premio');
end;
$$;

create function public.desmarcar_jugado(p_sorteo bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.solo_admin();
  update public.sorteos set jugado = null where id = p_sorteo and estado = 'cerrado' and jugado is not null;
  if not found then raise exception 'Ese sorteo no está marcado como jugado o ya tiene resultado'; end if;
end;
$$;

-- Anular ya no se bloquea por los resguardos: la web pide confirmación y los borra
create or replace function public.anular_sorteo(p_sorteo bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.solo_admin();
  if not exists (select 1 from public.sorteos where id = p_sorteo and estado = 'cerrado') then
    raise exception 'Solo se puede anular un sorteo que aún no tiene resultado';
  end if;
  delete from public.movimientos where sorteo_id = p_sorteo;
  delete from public.bote_movimientos where sorteo_id = p_sorteo;
  delete from public.sorteos where id = p_sorteo;  -- borra también sus participaciones
end;
$$;

-- Vuelve a dejar el último sorteo sin resultado para apuntarlo bien
create function public.deshacer_resultado(p_sorteo bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.sorteos;
begin
  perform public.solo_admin();
  select * into s from public.sorteos where id = p_sorteo for update;
  if not found or s.estado <> 'finalizado' then raise exception 'Ese sorteo no tiene resultado'; end if;
  -- Si hay un sorteo posterior, puede haber gastado el bote de este premio
  if exists (select 1 from public.sorteos where id > p_sorteo) then
    raise exception 'Solo se puede corregir el resultado del último sorteo';
  end if;

  -- Si alguien ya retiró el premio, quitárselo dejaría su saldo en negativo
  if s.premio_por_persona is not null and exists (
    select 1
    from public.participaciones pa
    where pa.sorteo_id = p_sorteo
      and (select coalesce(sum(importe), 0) from public.movimientos where perfil_id = pa.perfil_id) < s.premio_por_persona
  ) then
    raise exception 'Algún participante ya ha retirado el premio. Corrígelo con un ajuste';
  end if;

  delete from public.movimientos where sorteo_id = p_sorteo and tipo = 'premio';
  delete from public.bote_movimientos
  where sorteo_id = p_sorteo and concepto in ('Premio pequeño', 'Céntimos sobrantes del reparto');
  update public.sorteos set estado = 'cerrado', premio = null, premio_por_persona = null where id = p_sorteo;
end;
$$;

revoke execute on function public.cambiar_fecha_sorteo(bigint, date), public.desmarcar_jugado(bigint), public.deshacer_resultado(bigint) from public, anon;
grant execute on function public.cambiar_fecha_sorteo(bigint, date), public.desmarcar_jugado(bigint), public.deshacer_resultado(bigint) to authenticated;
