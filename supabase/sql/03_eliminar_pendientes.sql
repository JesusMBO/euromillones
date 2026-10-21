-- =====================================================================
-- EuromillonesCAIB · Eliminar cuentas pendientes
-- Ejecutar entero en Supabase → SQL Editor → New query → Run
-- (después de 02_resguardos.sql).
--
-- Para cuentas creadas por error (un email mal escrito, alguien que no
-- es de la peña...). Solo se pueden eliminar cuentas PENDIENTES: no
-- tienen dinero ni historial. A quien ya ha jugado se le da de baja.
-- =====================================================================

create function public.eliminar_pendiente(p_perfil uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.solo_admin();
  if not exists (select 1 from public.perfiles where id = p_perfil and estado = 'pendiente') then
    raise exception 'Solo se pueden eliminar cuentas pendientes de aprobar';
  end if;
  -- Borra el usuario del login; su perfil se borra con él
  delete from auth.users where id = p_perfil;
end;
$$;

revoke execute on function public.eliminar_pendiente(uuid) from public, anon;
grant execute on function public.eliminar_pendiente(uuid) to authenticated;
