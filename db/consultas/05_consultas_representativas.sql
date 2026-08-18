-- TP Integrador BDIA - Sistema de atencion al cliente con IA
-- Punto 8: Consultas representativas
-- Archivo: 05_consultas_representativas.sql
-- Requisitos previos:
--   1. db/fisico/01_creacion_tablas.sql
--   2. db/fisico/02_indices_vistas.sql
--   3. data/03_datos_ejemplo.sql


-- -------------------------------------------------------------
-- CONSULTA 1: TICKETS PENDIENTES DE UN OPERADOR
-- Pregunta: ¿Qué tickets activos tiene pendientes el empleado 3?
-- Utilidad: Permite visualizar los tickets de trabajo del empleado.
-- Optimizacion: usa la vista de estado actual y el indice parcial
-- idx_tickets_empleado_activos.
-- -------------------------------------------------------------
SELECT
    id_ticket,
    cliente,
    canal_origen,
    estado_actual,
    fecha_ultimo_estado
FROM vw_estado_actual_tickets
WHERE id_empleado = 3
  AND activo = TRUE
  AND estado_actual IN ('abierto', 'en_proceso', 'reabierto')
ORDER BY fecha_ultimo_estado;

-- -------------------------------------------------------------
-- CONSULTA 2: HISTORIAL DE UN TICKET
-- Pregunta: ¿Por qué estados pasó el ticket 5 y que empleado
-- intervino en cada momento?
-- Utilidad: brinda trazabilidad y permite auditar derivaciones.
-- Optimizacion: usa idx_ticket_logs_ticket_fecha.
-- -------------------------------------------------------------
SELECT
    tl.id_ticket,
    tl.fecha,
    tl.estado,
    tl.id_empleado,
    CONCAT_WS(' ', e.nombre, e.apellido) AS empleado,
    r.descripcion AS rol
FROM ticket_logs AS tl
INNER JOIN empleados AS e
    ON e.id_empleado = tl.id_empleado
INNER JOIN roles AS r
    ON r.id_rol = e.id_rol
WHERE tl.id_ticket = 5
ORDER BY tl.fecha, tl.id_ticket_log;

-- -------------------------------------------------------------
-- CONSULTA 3: CONVERSACIóN COMPLETA CON CONSULTAS Y RESPUESTAS
-- Pregunta: ¿Qué preguntó el cliente en el ticket 9 y que
-- respuestas generó la IA o envio el empleado?
-- Utilidad: reconstruye la interaccion completa para auditoria,
-- control de calidad y reutilizacion futura del conocimiento.
-- Para consultar otro ticket, reemplazar el valor 9.
-- -------------------------------------------------------------
SELECT
    t.id_ticket,
    CONCAT_WS(' ', c.nombre, c.apellido) AS cliente,
    conv.id_conversacion,
    q.id_consulta,
    q.pregunta,
    resp.id_respuesta,
    resp.texto_respuesta,
    CASE
        WHEN resp.es_humano = TRUE THEN 'Humana'
        ELSE 'IA'
    END AS origen_respuesta,
    resp.es_respuesta_final
FROM tickets AS t
INNER JOIN clientes AS c
    ON c.id_cliente = t.id_cliente
INNER JOIN conversaciones AS conv
    ON conv.id_ticket = t.id_ticket
INNER JOIN consultas AS q
    ON q.id_conversacion = conv.id_conversacion
LEFT JOIN respuestas AS resp
    ON resp.id_consulta = q.id_consulta
WHERE t.id_ticket = 9
ORDER BY q.id_consulta, resp.id_respuesta;

-- -------------------------------------------------------------
-- CONSULTA 4: CANTIDAD DE TICKETS POR CANAL Y ESTADO ACTUAL
-- Pregunta: ¿Como se distribuyen los tickets activos por canal
-- de origen y estado actual?
-- Utilidad: identifica los canales con mayor demanda y posibles
-- acumulaciones de casos pendientes.

SELECT
    canal_origen,
    estado_actual,
    COUNT(*) AS cantidad_tickets
FROM vw_estado_actual_tickets
WHERE activo = TRUE
GROUP BY canal_origen, estado_actual
ORDER BY canal_origen, cantidad_tickets DESC;

-- -------------------------------------------------------------
-- CONSULTA 5: TIEMPO PROMEDIO DE RESOLUCION POR CANAL
-- Pregunta: ¿Cuantas horas tarda, en promedio, la primera
-- resolución de un ticket en cada canal?
-- Utilidad: permite comparar eficiencia y detectar canales que
-- requieren mas recursos o mejoras de proceso.
-- Solo considera tickets activos cuyo estado actual es resuelto
-- o cerrado y que tienen fechas de apertura y resolución.

WITH tiempos_por_ticket AS (
    SELECT
        t.id_ticket,
        t.canal_origen,
        MIN(tl.fecha) FILTER (
            WHERE tl.estado = 'abierto'
        ) AS fecha_apertura,
        MIN(tl.fecha) FILTER (
            WHERE tl.estado = 'resuelto'
        ) AS fecha_resolucion
    FROM tickets AS t
    INNER JOIN ticket_logs AS tl
        ON tl.id_ticket = t.id_ticket
    GROUP BY t.id_ticket, t.canal_origen
)
SELECT
    tiempos.canal_origen,
    COUNT(*) AS tickets_resueltos,
    ROUND(
        AVG(
            EXTRACT(
                EPOCH FROM (tiempos.fecha_resolucion - tiempos.fecha_apertura)
            ) / 3600
        ),
        2
    ) AS horas_promedio_resolucion
FROM tiempos_por_ticket AS tiempos
INNER JOIN vw_estado_actual_tickets AS actual
    ON actual.id_ticket = tiempos.id_ticket
WHERE actual.activo = TRUE
  AND actual.estado_actual IN ('resuelto', 'cerrado')
  AND tiempos.fecha_apertura IS NOT NULL
  AND tiempos.fecha_resolucion IS NOT NULL
GROUP BY tiempos.canal_origen
ORDER BY horas_promedio_resolucion;

-- -------------------------------------------------------------
-- CONSULTA 6: SATISFACCIÓN PROMEDIO POR OPERADOR
-- Pregunta: ¿Que calificación promedio reciben las conversaciones
-- atendidas por cada operador?
-- Utilidad: Da un indicador de calidad para supervisores.
-- -------------------------------------------------------------
SELECT
    e.id_empleado,
    CONCAT_WS(' ', e.nombre, e.apellido) AS operador,
    COUNT(conv.calificacion) AS conversaciones_calificadas,
    ROUND(AVG(conv.calificacion), 2) AS satisfaccion_promedio
FROM empleados AS e
INNER JOIN roles AS r
    ON r.id_rol = e.id_rol
INNER JOIN tickets AS t
    ON t.id_empleado = e.id_empleado
INNER JOIN conversaciones AS conv
    ON conv.id_ticket = t.id_ticket
WHERE r.descripcion = 'Operador'
  AND e.activo = TRUE
  AND t.activo = TRUE
GROUP BY e.id_empleado, e.nombre, e.apellido
HAVING COUNT(conv.calificacion) > 0
ORDER BY satisfaccion_promedio DESC, operador;

-- -------------------------------------------------------------
-- CONSULTA 7: RESPUESTAS FINALES DE IA Y HUMANAS
-- Pregunta: ¿Que porcentaje de las respuestas finales fue
-- generado por IA y que porcentaje fue enviado por humanos?
-- Utilidad: mide el nivel de automatizacion efectivo del sistema.
-- -------------------------------------------------------------
SELECT
    CASE
        WHEN es_humano = TRUE THEN 'Humana'
        ELSE 'IA'
    END AS origen_respuesta,
    COUNT(*) AS cantidad_respuestas_finales,
    ROUND(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),
        2
    ) AS porcentaje
FROM respuestas
WHERE es_respuesta_final = TRUE
GROUP BY es_humano
ORDER BY cantidad_respuestas_finales DESC;

-- -------------------------------------------------------------
-- CONSULTA 8: CARGA DE TRABAJO PENDIENTE POR OPERADOR
-- Pregunta: ¿Cuántos tickets pendientes tiene actualmente cada
-- operador, incluidos aquellos cuya carga es cero?
-- Utilidad: ayuda al supervisor a distribuir o reasignar casos.
-- Optimizacion: reutiliza vw_estado_actual_tickets para evitar
-- calcular nuevamente el ultimo log de cada ticket.
-- -------------------------------------------------------------
SELECT
    e.id_empleado,
    CONCAT_WS(' ', e.nombre, e.apellido) AS operador,
    COUNT(actual.id_ticket) AS tickets_pendientes
FROM empleados AS e
INNER JOIN roles AS r
    ON r.id_rol = e.id_rol
LEFT JOIN vw_estado_actual_tickets AS actual
    ON actual.id_empleado = e.id_empleado
   AND actual.activo = TRUE
   AND actual.estado_actual IN ('abierto', 'en_proceso', 'reabierto')
WHERE r.descripcion = 'Operador'
  AND e.activo = TRUE
GROUP BY e.id_empleado, e.nombre, e.apellido
ORDER BY tickets_pendientes DESC, operador;

