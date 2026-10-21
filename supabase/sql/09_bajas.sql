-- =====================================================================
-- EuromillonesCAIB · Pedir la baja
-- Ejecutar entero en Supabase → SQL Editor → New query → Run
-- (después de 08_cierre_automatico.sql).
--
-- Un participante pide la baja desde la web. Desde ese momento ya no
-- entra en los cierres semanales. Un administrador le devuelve el saldo
-- (Bizum o transferencia) y tramita la baja: se apunta la devolución y
-- la cuenta pasa a "baja".
-- =====================================================================

create table public.solicitudes_baja (
  id bigint generated always as identity primary key,
  perfil_id uuid not null references public.perfiles(id),
  nota text,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'tramitada', 'cancelada', 'rechazada')),
  creado timestamptz not null default now(),
  revisado_por uuid references public.perfiles(id),
  revisado timestamptz
);
-- Como mucho una solicitud pendiente por persona
create unique index solicitudes_baja_pendiente on public.solicitudes_baja (perfil_id) where estado = 'pendiente';

alter table public.solicitudes_baja enable row level security;
create policy "leer solicitudes de baja" on public.solicitudes_baja
  for select to authenticated using (perfil_id = auth.uid() or public.es_admin());
revoke insert, update, delete, truncate on public.solicitudes_baja from anon, authenticated;
revoke all on public.solicitudes_baja from anon;


-- ---------- Participante ----------

create function public.pedir_baja(p_nota text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.es_miembro() then raise exception 'Tu cuenta no está activa'; end if;
  if exists (select 1 from public.solicitudes_baja where perfil_id = auth.uid() and estado = 'pendiente') then
    raise exception 'Ya has pedido la baja. Un administrador la está tramitando';
  end if;
  insert into public.solicitudes_baja (perfil_id, nota) values (auth.uid(), nullif(btrim(p_nota), ''));
end;
$$;

create function public.cancelar_baja()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.solicitudes_baja set estado = 'cancelada', revisado = now()
  where perfil_id = auth.uid() and estado = 'pendiente';
  if not found then raise exception 'No tienes ninguna solicitud de baja pendiente'; end if;
end;
$$;


-- ---------- Administrador ----------

-- Apunta la devolución de todo el saldo y da de baja la cuenta
create function public.tramitar_baja(p_solicitud bigint)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.solicitudes_baja;
  v_saldo numeric;
begin
  perform public.solo_admin();
  select * into v from public.solicitudes_baja where id = p_solicitud for update;
  if not found or v.estado <> 'pendiente' then raise exception 'Esa solicitud ya no está pendiente'; end if;
  if v.perfil_id = auth.uid() then raise exception 'Tu propia baja la tiene que tramitar otro administrador'; end if;

  select coalesce(sum(importe), 0) into v_saldo from public.movimientos where perfil_id = v.perfil_id;
  if v_saldo > 0 then
    insert into public.movimientos (perfil_id, tipo, importe, nota, creado_por)
    values (v.perfil_id, 'retirada', -v_saldo, 'Devolución del saldo por baja', auth.uid());
  end if;

  update public.perfiles set estado = 'baja', es_admin = false where id = v.perfil_id;
  update public.solicitudes_baja set estado = 'tramitada', revisado_por = auth.uid(), revisado = now() where id = p_solicitud;
  return greatest(v_saldo, 0);
end;
$$;

create function public.rechazar_baja(p_solicitud bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.solo_admin();
  update public.solicitudes_baja set estado = 'rechazada', revisado_por = auth.uid(), revisado = now()
  where id = p_solicitud and estado = 'pendiente';
  if not found then raise exception 'Esa solicitud ya no está pendiente'; end if;
end;
$$;


-- ---------- Quien ha pedido la baja ya no entra en los cierres ----------

create or replace function public.cerrar_semana_interna(p_fecha date)
returns public.sorteos
language plpgsql
security definer
set search_path = ''
as $$
declare
  a public.ajustes;
  s public.sorteos;
  v_n int;
  v_bote numeric;
  v_recaudado numeric;
  v_apuestas int;
  v_sobrante numeric;
begin
  -- Evita que dos cierres se ejecuten a la vez
  lock table public.sorteos in share row exclusive mode;

  if exists (select 1 from public.sorteos where estado = 'cerrado') then
    raise exception 'Hay un sorteo sin resultado. Apunta su resultado antes de cerrar otra semana';
  end if;
  if exists (select 1 from public.sorteos where fecha = p_fecha) then
    raise exception 'Ya existe un sorteo con esa fecha';
  end if;

  select * into a from public.ajustes where id = 1;
  insert into public.sorteos (fecha) values (p_fecha) returning * into s;

  -- Juega quien está activo, tiene DNI, aceptó las normas, tiene saldo y no ha pedido la baja
  insert into public.participaciones (sorteo_id, perfil_id, importe)
  select s.id, p.id, a.cuota_semanal
  from public.perfiles p
  left join public.movimientos m on m.perfil_id = p.id
  where p.estado = 'activo' and p.dni is not null and p.acepta_normas is not null
    and not exists (select 1 from public.solicitudes_baja b where b.perfil_id = p.id and b.estado = 'pendiente')
  group by p.id
  having coalesce(sum(m.importe), 0) >= a.cuota_semanal;
  get diagnostics v_n = row_count;

  if v_n = 0 then raise exception 'Nadie tiene saldo suficiente para jugar'; end if;

  v_recaudado := v_n * a.cuota_semanal;
  select coalesce(sum(importe), 0) into v_bote from public.bote_movimientos;
  v_apuestas := floor((v_recaudado + v_bote) / a.precio_apuesta);
  v_sobrante := v_recaudado - v_apuestas * a.precio_apuesta;

  -- Sin ninguna apuesta no se cobra a nadie (el error deshace todo lo anterior)
  if v_apuestas = 0 then
    raise exception 'Con % € (% participantes y % € de bote) no llega para una apuesta de % €. No se ha cobrado a nadie',
      replace(to_char(v_recaudado, 'FM999990.00'), '.', ','), v_n,
      replace(to_char(v_bote, 'FM999990.00'), '.', ','), replace(to_char(a.precio_apuesta, 'FM999990.00'), '.', ',');
  end if;

  insert into public.movimientos (perfil_id, tipo, importe, sorteo_id, nota, creado_por)
  select perfil_id, 'apuesta', -importe, s.id, 'Sorteo ' || to_char(p_fecha, 'DD/MM/YYYY'), auth.uid()
  from public.participaciones where sorteo_id = s.id;

  if v_sobrante > 0 then
    insert into public.bote_movimientos (sorteo_id, concepto, importe) values (s.id, 'Sobrante de la semana', v_sobrante);
  elsif v_sobrante < 0 then
    insert into public.bote_movimientos (sorteo_id, concepto, importe) values (s.id, 'Apuestas extra pagadas con el bote', v_sobrante);
  end if;

  update public.sorteos
  set participantes = v_n, recaudado = v_recaudado, bote_antes = v_bote,
      apuestas = v_apuestas, coste = v_apuestas * a.precio_apuesta
  where id = s.id
  returning * into s;

  return s;
end;
$$;

revoke execute on function public.cerrar_semana_interna(date) from public, anon, authenticated;
revoke execute on function public.pedir_baja(text), public.cancelar_baja(), public.tramitar_baja(bigint), public.rechazar_baja(bigint) from public, anon;
grant execute on function public.pedir_baja(text), public.cancelar_baja(), public.tramitar_baja(bigint), public.rechazar_baja(bigint) to authenticated;
