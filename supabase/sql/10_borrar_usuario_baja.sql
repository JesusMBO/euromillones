-- =====================================================================
-- EuromillonesCAIB · BorrarUsuarioBajaSinJugar
-- Ejecutar entero en Supabase → SQL Editor → New query → Run
-- (después de 09_bajas.sql). Solo hay que hacerlo una vez.
--
-- Deja en Supabase una función para borrar del todo a un usuario que
-- está DE BAJA y que NUNCA HA JUGADO ningún sorteo. Se usa desde el
-- SQL Editor (la web no puede llamarla):
--
--     select BorrarUsuarioBajaSinJugar('email@ejemplo.com');
--
-- Para ver a quién se puede borrar:
--
--     select p.email, p.nombre
--     from perfiles p
--     where p.estado = 'baja'
--       and not exists (select 1 from participaciones pa where pa.perfil_id = p.id);
--
-- Quien ha jugado algún sorteo no se puede borrar: figura en las actas
-- como cotitular y borrarlo descuadraría esos sorteos.
-- =====================================================================

create function public.BorrarUsuarioBajaSinJugar(p_email text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.perfiles;
  v_saldo numeric;
begin
  select * into p from public.perfiles where lower(email) = lower(btrim(p_email));
  if not found then raise exception 'No hay ningún usuario con el email %', p_email; end if;

  if p.estado <> 'baja' then
    raise exception '% no está de baja (está "%"). Dale de baja primero', p.email, p.estado;
  end if;
  if exists (select 1 from public.participaciones where perfil_id = p.id) then
    raise exception '% ha jugado algún sorteo: figura en las actas y no se puede borrar', p.email;
  end if;

  select coalesce(sum(importe), 0) into v_saldo from public.movimientos where perfil_id = p.id;
  if v_saldo <> 0 then
    raise exception '% tiene % € de saldo. Devuélveselo (retirada) antes de borrarlo',
      p.email, replace(to_char(v_saldo, 'FM999990.00'), '.', ',');
  end if;

  -- Si fue administrador y dejó acciones a nombre suyo en cuentas de otros, no se borra
  if exists (select 1 from public.movimientos where creado_por = p.id and perfil_id <> p.id)
     or exists (select 1 from public.avisos_pago where revisado_por = p.id and perfil_id <> p.id)
     or exists (select 1 from public.solicitudes_baja where revisado_por = p.id and perfil_id <> p.id) then
    raise exception '% fue administrador y tiene acciones registradas en cuentas de otros: no se puede borrar', p.email;
  end if;

  -- Sus ingresos y devoluciones (suman 0), avisos de Bizum y solicitudes de baja
  delete from public.movimientos where perfil_id = p.id;
  delete from public.avisos_pago where perfil_id = p.id;
  delete from public.solicitudes_baja where perfil_id = p.id;

  -- El usuario del login; su perfil se borra con él
  delete from auth.users where id = p.id;

  return format('Borrado: %s (%s)', coalesce(p.nombre, 'sin nombre'), p.email);
end;
$$;

-- Solo desde el SQL Editor de Supabase, nunca desde la web
revoke execute on function public.BorrarUsuarioBajaSinJugar(text) from public, anon, authenticated;
