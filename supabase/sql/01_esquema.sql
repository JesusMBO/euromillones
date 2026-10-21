-- =====================================================================
-- EuromillonesCAIB · Base de datos
-- Ejecutar entero en Supabase → SQL Editor → New query → Run.
--
-- Idea principal: el saldo NO se guarda como un número que se cambia.
-- Cada euro que entra o sale es una línea en "movimientos" (como un
-- extracto del banco) y el saldo es la suma. Lo mismo para el bote.
--
-- Nadie escribe directamente en las tablas: todo pasa por funciones
-- que comprueban quién eres (miembro o administrador).
-- =====================================================================


-- ---------- Ajustes (una sola fila) ----------

create table public.ajustes (
  id int primary key default 1 check (id = 1),
  cuota_semanal numeric(10,2) not null default 1.00,
  precio_apuesta numeric(10,2) not null default 2.50,
  umbral_reparto numeric(10,2) not null default 50.00  -- € por persona para repartir un premio
);
insert into public.ajustes default values;


-- ---------- Participantes ----------

create table public.perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  nombre text,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'activo', 'baja')),
  es_admin boolean not null default false,
  creado timestamptz not null default now()
);

-- Cada usuario nuevo de Supabase Auth crea su perfil "pendiente"
create function public.crear_perfil()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.perfiles (id, email) values (new.id, new.email);
  return new;
end;
$$;

create trigger al_crear_usuario
  after insert on auth.users
  for each row execute function public.crear_perfil();


-- ---------- Sorteos (uno por semana) ----------

create table public.sorteos (
  id bigint generated always as identity primary key,
  fecha date not null unique,
  estado text not null default 'cerrado' check (estado in ('cerrado', 'finalizado')),
  participantes int not null default 0,
  recaudado numeric(10,2) not null default 0,
  bote_antes numeric(10,2) not null default 0,
  apuestas int not null default 0,
  coste numeric(10,2) not null default 0,
  premio numeric(12,2),
  premio_por_persona numeric(12,2),  -- solo si se repartió
  creado timestamptz not null default now()
);

-- Quién jugaba en cada sorteo (la prueba de que el boleto era compartido)
create table public.participaciones (
  sorteo_id bigint not null references public.sorteos(id) on delete cascade,
  perfil_id uuid not null references public.perfiles(id),
  importe numeric(10,2) not null,
  primary key (sorteo_id, perfil_id)
);


-- ---------- Movimientos (el extracto de cada persona) ----------

create table public.movimientos (
  id bigint generated always as identity primary key,
  perfil_id uuid not null references public.perfiles(id),
  tipo text not null check (tipo in ('ingreso', 'apuesta', 'premio', 'retirada', 'ajuste')),
  importe numeric(12,2) not null check (importe <> 0),
  sorteo_id bigint references public.sorteos(id),
  nota text,
  creado_por uuid references public.perfiles(id),
  creado timestamptz not null default now()
);
create index movimientos_perfil_idx on public.movimientos (perfil_id);
create index movimientos_sorteo_idx on public.movimientos (sorteo_id);


-- ---------- Bote común (sobrantes y premios pequeños) ----------

create table public.bote_movimientos (
  id bigint generated always as identity primary key,
  sorteo_id bigint references public.sorteos(id),
  concepto text not null,
  importe numeric(12,2) not null check (importe <> 0),
  creado timestamptz not null default now()
);


-- ---------- Avisos de pago ("He hecho un Bizum") ----------

create table public.avisos_pago (
  id bigint generated always as identity primary key,
  perfil_id uuid not null references public.perfiles(id),
  importe numeric(10,2) not null check (importe > 0),
  nota text,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'confirmado', 'rechazado')),
  creado timestamptz not null default now(),
  revisado_por uuid references public.perfiles(id),
  revisado timestamptz
);


-- =====================================================================
-- Seguridad
-- =====================================================================

create function public.es_miembro()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.perfiles where id = auth.uid() and estado = 'activo');
$$;

create function public.es_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.perfiles where id = auth.uid() and estado = 'activo' and es_admin);
$$;

alter table public.ajustes enable row level security;
alter table public.perfiles enable row level security;
alter table public.sorteos enable row level security;
alter table public.participaciones enable row level security;
alter table public.movimientos enable row level security;
alter table public.bote_movimientos enable row level security;
alter table public.avisos_pago enable row level security;

-- Solo lectura. Las escrituras se hacen con las funciones de abajo.
create policy "leer ajustes" on public.ajustes for select to authenticated using (true);
-- Tu propio perfil (con email) o todos si eres admin. Los nombres y saldos de todos salen de ver_saldos().
create policy "leer perfil" on public.perfiles for select to authenticated using (id = auth.uid() or public.es_admin());
-- Transparencia: cualquier miembro activo ve sorteos, participantes y movimientos de todos
create policy "leer sorteos" on public.sorteos for select to authenticated using (public.es_miembro());
create policy "leer participaciones" on public.participaciones for select to authenticated using (public.es_miembro());
create policy "leer movimientos" on public.movimientos for select to authenticated using (public.es_miembro());
create policy "leer bote" on public.bote_movimientos for select to authenticated using (public.es_miembro());
create policy "leer avisos" on public.avisos_pago for select to authenticated using (perfil_id = auth.uid() or public.es_admin());

revoke insert, update, delete, truncate on all tables in schema public from anon, authenticated;
revoke all on all tables in schema public from anon;


-- =====================================================================
-- Funciones de consulta
-- =====================================================================

-- Saldo de todos los participantes (activos y de baja)
create function public.ver_saldos()
returns table (id uuid, nombre text, estado text, saldo numeric)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.nombre, p.estado, coalesce(sum(m.importe), 0)::numeric(12,2)
  from public.perfiles p
  left join public.movimientos m on m.perfil_id = p.id
  where public.es_miembro() and p.estado <> 'pendiente'
  group by p.id
  order by p.nombre;
$$;

create function public.ver_bote()
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select case when public.es_miembro()
    then coalesce((select sum(importe) from public.bote_movimientos), 0)::numeric(12,2)
  end;
$$;


-- =====================================================================
-- Funciones para cualquier participante
-- =====================================================================

create function public.guardar_nombre(p_nombre text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Tienes que iniciar sesión'; end if;
  p_nombre := btrim(p_nombre);
  if length(p_nombre) not between 2 and 60 then raise exception 'El nombre debe tener entre 2 y 60 caracteres'; end if;
  update public.perfiles set nombre = p_nombre where id = auth.uid();
end;
$$;

create function public.avisar_pago(p_importe numeric, p_nota text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.es_miembro() then raise exception 'Tu cuenta no está activa'; end if;
  if p_importe is null or p_importe < 1 or p_importe > 500 then raise exception 'El importe debe estar entre 1 y 500 €'; end if;
  if (select count(*) from public.avisos_pago where perfil_id = auth.uid() and estado = 'pendiente') >= 3 then
    raise exception 'Ya tienes 3 avisos pendientes de confirmar';
  end if;
  insert into public.avisos_pago (perfil_id, importe, nota)
  values (auth.uid(), round(p_importe, 2), nullif(btrim(p_nota), ''));
end;
$$;


-- =====================================================================
-- Funciones de administrador
-- =====================================================================

create function public.solo_admin()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.es_admin() then raise exception 'Solo los administradores pueden hacer esto'; end if;
end;
$$;

create function public.confirmar_aviso(p_aviso bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.avisos_pago;
begin
  perform public.solo_admin();
  select * into v from public.avisos_pago where id = p_aviso for update;
  if not found or v.estado <> 'pendiente' then raise exception 'Ese aviso ya no está pendiente'; end if;

  insert into public.movimientos (perfil_id, tipo, importe, nota, creado_por)
  values (v.perfil_id, 'ingreso', v.importe, coalesce(v.nota, 'Bizum'), auth.uid());

  update public.avisos_pago set estado = 'confirmado', revisado_por = auth.uid(), revisado = now() where id = p_aviso;
end;
$$;

create function public.rechazar_aviso(p_aviso bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.solo_admin();
  update public.avisos_pago set estado = 'rechazado', revisado_por = auth.uid(), revisado = now()
  where id = p_aviso and estado = 'pendiente';
  if not found then raise exception 'Ese aviso ya no está pendiente'; end if;
end;
$$;

-- Ingreso (+), retirada (devolver dinero, −) o ajuste (corrección, + o −)
create function public.registrar_movimiento(p_perfil uuid, p_tipo text, p_importe numeric, p_nota text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_importe numeric := round(p_importe, 2);
  v_saldo numeric;
begin
  perform public.solo_admin();
  if p_tipo not in ('ingreso', 'retirada', 'ajuste') then raise exception 'Tipo de movimiento no válido'; end if;
  if v_importe is null or v_importe = 0 then raise exception 'El importe no puede ser 0'; end if;
  if not exists (select 1 from public.perfiles where id = p_perfil and estado <> 'pendiente') then
    raise exception 'Ese participante no existe o no está aprobado';
  end if;

  if p_tipo = 'ingreso' then v_importe := abs(v_importe); end if;
  if p_tipo = 'retirada' then
    v_importe := -abs(v_importe);
    select coalesce(sum(importe), 0) into v_saldo from public.movimientos where perfil_id = p_perfil;
    if v_saldo + v_importe < 0 then raise exception 'No tiene saldo suficiente para retirar esa cantidad'; end if;
  end if;
  if p_tipo = 'ajuste' and nullif(btrim(p_nota), '') is null then raise exception 'Explica el motivo del ajuste en la nota'; end if;

  insert into public.movimientos (perfil_id, tipo, importe, nota, creado_por)
  values (p_perfil, p_tipo, v_importe, nullif(btrim(p_nota), ''), auth.uid());
end;
$$;

create function public.cambiar_estado(p_perfil uuid, p_estado text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.solo_admin();
  if p_estado not in ('activo', 'baja') then raise exception 'Estado no válido'; end if;
  if p_perfil = auth.uid() then raise exception 'No puedes cambiar tu propio estado'; end if;
  update public.perfiles set estado = p_estado where id = p_perfil;
end;
$$;

create function public.cambiar_admin(p_perfil uuid, p_admin boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.solo_admin();
  if p_perfil = auth.uid() then raise exception 'No puedes quitarte a ti mismo de administrador'; end if;
  update public.perfiles set es_admin = p_admin where id = p_perfil and estado = 'activo';
  if not found then raise exception 'Solo puede ser administrador un participante activo'; end if;
end;
$$;

-- Cierra la semana: cobra la cuota a quien tenga saldo y calcula las apuestas
create function public.cerrar_semana(p_fecha date)
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
  perform public.solo_admin();
  -- Evita que dos administradores cierren a la vez
  lock table public.sorteos in share row exclusive mode;

  if exists (select 1 from public.sorteos where estado = 'cerrado') then
    raise exception 'Hay un sorteo sin resultado. Apunta su resultado antes de cerrar otra semana';
  end if;
  if exists (select 1 from public.sorteos where fecha = p_fecha) then
    raise exception 'Ya existe un sorteo con esa fecha';
  end if;

  select * into a from public.ajustes where id = 1;
  insert into public.sorteos (fecha) values (p_fecha) returning * into s;

  insert into public.participaciones (sorteo_id, perfil_id, importe)
  select s.id, p.id, a.cuota_semanal
  from public.perfiles p
  left join public.movimientos m on m.perfil_id = p.id
  where p.estado = 'activo'
  group by p.id
  having coalesce(sum(m.importe), 0) >= a.cuota_semanal;
  get diagnostics v_n = row_count;

  if v_n = 0 then raise exception 'Nadie tiene saldo suficiente para jugar'; end if;

  insert into public.movimientos (perfil_id, tipo, importe, sorteo_id, nota, creado_por)
  select perfil_id, 'apuesta', -importe, s.id, 'Sorteo ' || to_char(p_fecha, 'DD/MM/YYYY'), auth.uid()
  from public.participaciones where sorteo_id = s.id;

  v_recaudado := v_n * a.cuota_semanal;
  select coalesce(sum(importe), 0) into v_bote from public.bote_movimientos;
  v_apuestas := floor((v_recaudado + v_bote) / a.precio_apuesta);
  v_sobrante := v_recaudado - v_apuestas * a.precio_apuesta;

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

-- Deshace un cierre de semana por error (solo el último y sin resultado)
create function public.anular_sorteo(p_sorteo bigint)
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

-- Apunta el premio. Si sale a umbral_reparto € o más por persona se reparte; si no, va al bote.
create function public.registrar_resultado(p_sorteo bigint, p_premio numeric)
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
begin
  perform public.solo_admin();
  select * into s from public.sorteos where id = p_sorteo for update;
  if not found or s.estado <> 'cerrado' then raise exception 'Ese sorteo ya tiene resultado'; end if;
  if v_premio is null or v_premio < 0 then raise exception 'El premio no puede ser negativo'; end if;

  select * into a from public.ajustes where id = 1;
  v_por_persona := floor(v_premio * 100 / s.participantes) / 100;

  if v_premio > 0 and v_por_persona >= a.umbral_reparto then
    insert into public.movimientos (perfil_id, tipo, importe, sorteo_id, nota, creado_por)
    select perfil_id, 'premio', v_por_persona, s.id, 'Premio sorteo ' || to_char(s.fecha, 'DD/MM/YYYY'), auth.uid()
    from public.participaciones where sorteo_id = s.id;

    v_resto := v_premio - v_por_persona * s.participantes;
    if v_resto > 0 then
      insert into public.bote_movimientos (sorteo_id, concepto, importe) values (s.id, 'Céntimos sobrantes del reparto', v_resto);
    end if;
  else
    v_por_persona := null;
    if v_premio > 0 then
      insert into public.bote_movimientos (sorteo_id, concepto, importe) values (s.id, 'Premio pequeño', v_premio);
    end if;
  end if;

  update public.sorteos set estado = 'finalizado', premio = v_premio, premio_por_persona = v_por_persona
  where id = s.id
  returning * into s;

  return s;
end;
$$;


-- Las funciones solo las pueden llamar usuarios con sesión iniciada
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
revoke execute on function public.crear_perfil() from authenticated;
