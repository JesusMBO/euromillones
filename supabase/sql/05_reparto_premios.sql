-- =====================================================================
-- EuromillonesCAIB · Reparto de premios según el reglamento
-- Ejecutar entero en Supabase → SQL Editor → New query → Run
-- (después de 04_correcciones.sql).
--
--   · Premio de menos de 2.000 €: se reparte a partes iguales en el saldo
--     de quienes jugaron ese sorteo. Los céntimos que no se pueden
--     repartir van al bote.
--   · Premio de 2.000 € o más: NO pasa por los saldos. Se cobra en el
--     banco identificándose todos los participantes con el acta.
-- =====================================================================

alter table public.ajustes drop column umbral_reparto;
alter table public.ajustes add column umbral_banco numeric(12,2) not null default 2000.00;

alter table public.sorteos add column cobro_banco boolean not null default false;

create or replace function public.registrar_resultado(p_sorteo bigint, p_premio numeric)
returns public.sorteos
language plpgsql
security definer
set search_path = ''
as $$
declare
  a public.ajustes;
  s public.sorteos;
  v_premio numeric := round(p_premio, 2);
  v_por_persona numeric;
  v_resto numeric;
  v_banco boolean := false;
begin
  perform public.solo_admin();
  select * into s from public.sorteos where id = p_sorteo for update;
  if not found or s.estado <> 'cerrado' then raise exception 'Ese sorteo ya tiene resultado'; end if;
  if v_premio is null or v_premio < 0 then raise exception 'El premio no puede ser negativo'; end if;

  select * into a from public.ajustes where id = 1;
  v_por_persona := floor(v_premio * 100 / s.participantes) / 100;

  if v_premio >= a.umbral_banco then
    -- Se cobra en el banco: solo queda apuntado, los saldos no cambian
    v_banco := true;
  elsif v_premio > 0 then
    if v_por_persona > 0 then
      insert into public.movimientos (perfil_id, tipo, importe, sorteo_id, nota, creado_por)
      select perfil_id, 'premio', v_por_persona, s.id, 'Premio sorteo ' || to_char(s.fecha, 'DD/MM/YYYY'), auth.uid()
      from public.participaciones where sorteo_id = s.id;
    end if;
    v_resto := v_premio - v_por_persona * s.participantes;
    if v_resto > 0 then
      insert into public.bote_movimientos (sorteo_id, concepto, importe) values (s.id, 'Céntimos sobrantes del reparto', v_resto);
    end if;
  end if;

  update public.sorteos
  set estado = 'finalizado', premio = v_premio, cobro_banco = v_banco,
      premio_por_persona = case when v_premio > 0 then v_por_persona end
  where id = s.id
  returning * into s;

  return s;
end;
$$;

create or replace function public.deshacer_resultado(p_sorteo bigint)
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
  if not s.cobro_banco and s.premio_por_persona > 0 and exists (
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
  update public.sorteos set estado = 'cerrado', premio = null, premio_por_persona = null, cobro_banco = false
  where id = p_sorteo;
end;
$$;
