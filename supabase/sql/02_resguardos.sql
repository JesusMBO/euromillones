-- =====================================================================
-- EuromillonesCAIB · Resguardos de las apuestas
-- Ejecutar entero en Supabase → SQL Editor → New query → Run
-- (después de 01_esquema.sql).
--
-- Los resguardos (foto, captura o PDF) se guardan en Storage, en la
-- carpeta "resguardos/<id del sorteo>/". Los ven todos los miembros;
-- solo los administradores pueden subirlos o borrarlos.
-- =====================================================================

alter table public.sorteos add column jugado timestamptz;

-- Carpeta privada: máx. 5 MB por archivo, solo imágenes y PDF
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('resguardos', 'resguardos', false, 5242880,
        array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']);

create policy "miembros ven resguardos" on storage.objects
  for select to authenticated using (bucket_id = 'resguardos' and public.es_miembro());
create policy "admins suben resguardos" on storage.objects
  for insert to authenticated with check (bucket_id = 'resguardos' and public.es_admin());
create policy "admins borran resguardos" on storage.objects
  for delete to authenticated using (bucket_id = 'resguardos' and public.es_admin());


-- Marca el sorteo como jugado (hace falta haber subido al menos un resguardo)
create function public.marcar_jugado(p_sorteo bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.solo_admin();
  if not exists (select 1 from public.sorteos where id = p_sorteo and estado = 'cerrado' and jugado is null) then
    raise exception 'Ese sorteo ya está marcado como jugado o ya tiene resultado';
  end if;
  if not exists (select 1 from storage.objects where bucket_id = 'resguardos' and name like p_sorteo || '/%') then
    raise exception 'Sube primero el resguardo de las apuestas';
  end if;
  update public.sorteos set jugado = now() where id = p_sorteo;
end;
$$;

-- Ya no se puede anular un sorteo con apuestas compradas
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
  if exists (select 1 from public.sorteos where id = p_sorteo and jugado is not null)
     or exists (select 1 from storage.objects where bucket_id = 'resguardos' and name like p_sorteo || '/%') then
    raise exception 'Este sorteo ya tiene resguardo: las apuestas están compradas y no se puede anular';
  end if;
  delete from public.movimientos where sorteo_id = p_sorteo;
  delete from public.bote_movimientos where sorteo_id = p_sorteo;
  delete from public.sorteos where id = p_sorteo;  -- borra también sus participaciones
end;
$$;

revoke execute on function public.marcar_jugado(bigint) from public, anon;
grant execute on function public.marcar_jugado(bigint) to authenticated;
