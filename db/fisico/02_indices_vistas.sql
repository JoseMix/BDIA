BEGIN;

-- -------------------------------------------------------------
-- INDICES PARA CLAVES FORANEAS Y CONSULTAS FRECUENTES
-- PostgreSQL crea indices para PRIMARY KEY y UNIQUE, pero no
-- crea automaticamente indices para las FOREIGN KEY.
-- -------------------------------------------------------------

-- Permite buscar empleados por rol.
CREATE INDEX idx_empleados_id_rol
    ON empleados (id_rol);

-- Permite recuperar rapidamente los tickets de un cliente.
CREATE INDEX idx_tickets_id_cliente
    ON tickets (id_cliente);

-- Optimiza la consulta de tickets activos asignados a un empleado.
CREATE INDEX idx_tickets_empleado_activos
    ON tickets (id_empleado)
    WHERE activo = TRUE;

-- Optimiza agrupaciones y filtros por canal de origen.
CREATE INDEX idx_tickets_canal_origen
    ON tickets (canal_origen);

-- Optimiza la busqueda del ultimo estado de cada ticket.
CREATE INDEX idx_ticket_logs_ticket_fecha
    ON ticket_logs (id_ticket, fecha DESC, id_ticket_log DESC);

-- Permite consultar los cambios realizados por un empleado.
CREATE INDEX idx_ticket_logs_id_empleado
    ON ticket_logs (id_empleado);

-- Optimiza la navegacion ticket -> conversaciones.
CREATE INDEX idx_conversaciones_id_ticket
    ON conversaciones (id_ticket);

-- Optimiza la navegacion conversacion -> consultas.
CREATE INDEX idx_consultas_id_conversacion
    ON consultas (id_conversacion);

-- Optimiza la navegacion consulta -> respuestas.
CREATE INDEX idx_respuestas_id_consulta
    ON respuestas (id_consulta);

-- -------------------------------------------------------------
-- REGLA DE NEGOCIO: UNA SOLA RESPUESTA FINAL POR CONSULTA
-- El indice solo considera las filas con es_respuesta_final = TRUE.
-- Puede haber varias respuestas intermedias, pero una sola final.
-- -------------------------------------------------------------
CREATE UNIQUE INDEX uq_respuestas_final_por_consulta
    ON respuestas (id_consulta)
    WHERE es_respuesta_final = TRUE;

-- -------------------------------------------------------------
-- VISTA: ESTADO ACTUAL DE LOS TICKETS
-- Reune en una sola consulta el cliente, el empleado asignado,
-- el canal y el ultimo estado registrado en ticket_logs.
-- -------------------------------------------------------------
CREATE VIEW vw_estado_actual_tickets AS
SELECT
    t.id_ticket,
    t.id_cliente,
    CONCAT_WS(' ', c.nombre, c.apellido) AS cliente,
    t.id_empleado,
    CONCAT_WS(' ', e.nombre, e.apellido) AS empleado_asignado,
    r.descripcion AS rol_empleado,
    t.canal_origen,
    ultimo_log.estado AS estado_actual,
    ultimo_log.fecha AS fecha_ultimo_estado,
    t.activo
FROM tickets AS t
INNER JOIN clientes AS c
    ON c.id_cliente = t.id_cliente
INNER JOIN empleados AS e
    ON e.id_empleado = t.id_empleado
INNER JOIN roles AS r
    ON r.id_rol = e.id_rol
LEFT JOIN LATERAL (
    SELECT
        tl.estado,
        tl.fecha
    FROM ticket_logs AS tl
    WHERE tl.id_ticket = t.id_ticket
    ORDER BY tl.fecha DESC, tl.id_ticket_log DESC
    LIMIT 1
) AS ultimo_log
    ON TRUE;

COMMIT;

