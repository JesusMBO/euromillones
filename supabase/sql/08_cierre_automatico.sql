-- =====================================================================
-- EuromillonesCAIB · Cierre automático de la semana
-- Ejecutar entero en Supabase → SQL Editor → New query → Run
-- (después de 07_acta.sql).
--
-- Cada jueves a las 00:00 (hora de Madrid) se cierra la lista del
-- sorteo del viernes: se cobra 1 € a cada participante con saldo, DNI
-- y normas aceptadas, y se calcula cuántas apuestas comprar.
--   · Si no llega para ninguna apuesta, no se cobra a nadie.
--   · Si falla (por ejemplo, falta apuntar el resultado del sorteo
--     anterior), queda anotado y el administrador lo ve en Administrar,
--     donde puede cerrar a mano.
-- =====================================================================

-- Registro de cada cierre (automático o manual)
create table public.cierres (
  id bigint generated always as identity primary key,
  ejecutado timestamptz not null default now(),
  fecha_sorteo date,
  automatico boolean not null,
  ok boolean not null,
  mensaje text not null
);
alter table public.cierres enable row level security;
create policy "admins leen cierres" on public.cierres for select to authenticated using (public.es_admin());
revoke insert, update, delete, truncate on public.cierres from anon, authenticated;
revoke all on public.cierres from anon;


-- El cierre en sí, sin comprobar quién lo pide (solo lo usan las funciones de abajo)
create function public.cerrar_semana_interna(p_fecha date)
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

  -- Juega quien está activo, tiene DNI, aceptó las normas y tiene saldo
  insert into public.participaciones (sorteo_id, perfil_id, importe)
  select s.id, p.id, a.cuota_semanal
  from public.perfiles p
  left join public.movimientos m on m.perfil_id = p.id
  where p.estado = 'activo' and p.dni is not null and p.acepta_normas is not null
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

-- Cierre a mano desde Administrar (por si falla el automático)
create or replace function public.cerrar_semana(p_fecha date)
returns public.sorteos
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.sorteos;
begin
  perform public.solo_admin();
  s := public.cerrar_semana_interna(p_fecha);
  insert into public.cierres (fecha_sorteo, automatico, ok, mensaje)
  values (p_fecha, false, true, format('Cierre manual: %s participantes, %s apuestas', s.participantes, s.apuestas));
  return s;
end;
$$;

-- Lo lanza pg_cron. Como pg_cron va en hora UTC, se programa a las 22:00 y
-- a las 23:00 UTC del miércoles y solo actúa la vez que en Madrid son las
-- 00:xx del jueves (así funciona igual en horario de verano y de invierno).
create function public.cierre_automatico(p_ahora timestamptz default now())
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_local timestamp := p_ahora at time zone 'Europe/Madrid';
  v_fecha date := (p_ahora at time zone 'Europe/Madrid')::date + 1;  -- el viernes
  s public.sorteos;
begin
  if extract(isodow from v_local) <> 4 or extract(hour from v_local) <> 0 then return; end if;
  if exists (select 1 from public.sorteos where fecha = v_fecha) then return; end if;

  begin
    s := public.cerrar_semana_interna(v_fecha);
    insert into public.cierres (fecha_sorteo, automatico, ok, mensaje)
    values (v_fecha, true, true, format('Cierre automático: %s participantes, %s apuestas', s.participantes, s.apuestas));
  exception when others then
    insert into public.cierres (fecha_sorteo, automatico, ok, mensaje) values (v_fecha, true, false, sqlerrm);
  end;
end;
$$;

revoke execute on function public.cerrar_semana_interna(date), public.cierre_automatico(timestamptz) from public, anon, authenticated;


-- ---------- Programar el cierre (pg_cron) ----------
create extension if not exists pg_cron;
select cron.schedule('cierre-semanal', '0 22,23 * * 3', 'select public.cierre_automatico()');
