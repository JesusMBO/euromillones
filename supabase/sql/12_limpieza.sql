-- =====================================================================
-- EuromillonesCAIB · Limpieza
-- Ejecutar entero en Supabase → SQL Editor → New query → Run
-- (después de 11_eliminar_baja_web.sql).
--
-- Borra guardar_nombre: era el alta antigua (solo pedía el nombre).
-- Desde 06_dni_normas.sql el alta la hace completar_registro y ya nada
-- la usa.
-- =====================================================================

drop function if exists public.guardar_nombre(text);
