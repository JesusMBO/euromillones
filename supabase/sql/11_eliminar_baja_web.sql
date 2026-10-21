-- =====================================================================
-- EuromillonesCAIB · Botón "Eliminar definitivamente" en Administrar
-- Ejecutar entero en Supabase → SQL Editor → New query → Run
-- (después de 10_borrar_usuario_baja.sql).
--
-- Permite a un administrador, desde la web, hacer lo mismo que
-- BorrarUsuarioBajaSinJugar: borrar del todo a quien está de baja,
-- nunca ha jugado y tiene saldo 0. Las comprobaciones son las mismas.
-- =====================================================================

create function public.eliminar_baja_sin_jugar(p_perfil uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text;
begin
  perform public.solo_admin();
  if p_perfil = auth.uid() then raise exception 'No puedes eliminar tu propia cuenta'; end if;
  select email into v_email from public.perfiles where id = p_perfil;
  if not found then raise exception 'Ese participante no existe'; end if;
  return public.BorrarUsuarioBajaSinJugar(v_email);
end;
$$;

revoke execute on function public.eliminar_baja_sin_jugar(uuid) from public, anon;
grant execute on function public.eliminar_baja_sin_jugar(uuid) to authenticated;
