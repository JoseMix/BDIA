-- =============================================================
-- TP Integrador BDIA - Sistema de atencion al cliente con IA
-- Punto 7: Datos de ejemplo para la implementacion minima
-- Motor: PostgreSQL 16
-- Base de datos: bdia
-- Archivo: 03_datos_ejemplo.sql
-- Requisitos previos:
--   1. db/fisico/01_creacion_tablas.sql
--   2. db/fisico/02_indices_vistas.sql
-- Este archivo debe ejecutarse una sola vez sobre tablas vacias.
-- =============================================================

BEGIN;

-- -------------------------------------------------------------
-- ROLES
-- -------------------------------------------------------------
INSERT INTO roles (id_rol, descripcion) VALUES
    (1, 'Operador'),
    (2, 'Supervisor'),
    (3, 'Administrador');

-- -------------------------------------------------------------
-- EMPLEADOS
-- Incluye operadores de distintas areas, un supervisor y un
-- administrador para representar los roles del sistema.
-- -------------------------------------------------------------
INSERT INTO empleados (
    id_empleado,
    id_rol,
    nombre,
    apellido,
    dni,
    departamento,
    activo
) VALUES
    (1, 1, 'Lucia',     'Fernandez', '32111222', 'Atencion general', TRUE),
    (2, 1, 'Martin',    'Lopez',     '33222333', 'Facturacion',      TRUE),
    (3, 1, 'Sofia',     'Ramirez',   '34333444', 'Soporte tecnico', TRUE),
    (4, 2, 'Diego',     'Moreno',    '35444555', 'Calidad',         TRUE),
    (5, 3, 'Valentina', 'Castro',    '36555666', 'Sistemas',        TRUE);

-- -------------------------------------------------------------
-- CLIENTES
-- Se utilizan datos completamente sinteticos.
-- -------------------------------------------------------------
INSERT INTO clientes (
    id_cliente,
    nombre,
    apellido,
    dni,
    email,
    telefono_1,
    telefono_2,
    direccion,
    activo
) VALUES
    (1, 'Juan',   'Perez',     '30111222', 'juan.perez@example.com',      '1120010001', NULL,         'Av. Rivadavia 1200', TRUE),
    (2, 'Maria',  'Gonzalez',  '30222333', 'maria.gonzalez@example.com',  '1120010002', '1120090002', 'Av. Cabildo 2450',   TRUE),
    (3, 'Carlos', 'Rodriguez', '30333444', 'carlos.rodriguez@example.com','1120010003', NULL,         'Av. La Plata 850',   TRUE),
    (4, 'Ana',    'Martinez',  '30444555', 'ana.martinez@example.com',    '1120010004', NULL,         'Paraguay 3100',      TRUE),
    (5, 'Pedro',  'Sanchez',   '30555666', 'pedro.sanchez@example.com',   '1120010005', '1120090005', 'San Juan 1750',      TRUE),
    (6, 'Laura',  'Fernandez', '30666777', 'laura.fernandez@example.com', '1120010006', NULL,         NULL,                 TRUE);

-- -------------------------------------------------------------
-- TICKETS
-- Se incluyen todos los canales admitidos y un ticket marcado
-- como inactivo para probar el borrado logico.
-- -------------------------------------------------------------
INSERT INTO tickets (
    id_ticket,
    id_cliente,
    id_empleado,
    canal_origen,
    activo
) VALUES
    (1,  1, 1, 'whatsapp', TRUE),
    (2,  2, 2, 'email',    TRUE),
    (3,  3, 1, 'web',      TRUE),
    (4,  4, 3, 'chat',     TRUE),
    (5,  1, 2, 'telefono', TRUE),
    (6,  5, 3, 'whatsapp', TRUE),
    (7,  6, 2, 'email',    FALSE),
    (8,  2, 3, 'web',      TRUE),
    (9,  3, 2, 'chat',     TRUE),
    (10, 4, 1, 'whatsapp', TRUE);

-- -------------------------------------------------------------
-- TICKET_LOGS
-- Los registros permiten reconstruir el ciclo de vida, calcular
-- tiempos de resolucion y observar derivaciones entre empleados.
-- -------------------------------------------------------------
INSERT INTO ticket_logs (
    id_ticket_log,
    id_ticket,
    id_empleado,
    fecha,
    estado
) VALUES
    (1,  1, 1, TIMESTAMPTZ '2026-08-01 09:00:00-03', 'abierto'),
    (2,  1, 1, TIMESTAMPTZ '2026-08-01 09:15:00-03', 'en_proceso'),
    (3,  1, 1, TIMESTAMPTZ '2026-08-01 10:20:00-03', 'resuelto'),

    (4,  2, 2, TIMESTAMPTZ '2026-08-03 14:00:00-03', 'abierto'),
    (5,  2, 2, TIMESTAMPTZ '2026-08-04 09:30:00-03', 'en_proceso'),
    (6,  2, 2, TIMESTAMPTZ '2026-08-05 11:00:00-03', 'resuelto'),
    (7,  2, 2, TIMESTAMPTZ '2026-08-06 08:00:00-03', 'cerrado'),

    (8,  3, 1, TIMESTAMPTZ '2026-08-08 10:00:00-03', 'abierto'),
    (9,  3, 1, TIMESTAMPTZ '2026-08-09 08:30:00-03', 'en_proceso'),

    (10, 4, 3, TIMESTAMPTZ '2026-08-05 16:00:00-03', 'abierto'),
    (11, 4, 3, TIMESTAMPTZ '2026-08-05 16:10:00-03', 'en_proceso'),
    (12, 4, 3, TIMESTAMPTZ '2026-08-05 17:00:00-03', 'resuelto'),

    (13, 5, 1, TIMESTAMPTZ '2026-08-02 11:00:00-03', 'abierto'),
    (14, 5, 1, TIMESTAMPTZ '2026-08-02 11:20:00-03', 'en_proceso'),
    (15, 5, 2, TIMESTAMPTZ '2026-08-03 09:00:00-03', 'en_proceso'),
    (16, 5, 2, TIMESTAMPTZ '2026-08-04 12:00:00-03', 'resuelto'),

    (17, 6, 3, TIMESTAMPTZ '2026-08-06 13:00:00-03', 'abierto'),
    (18, 6, 3, TIMESTAMPTZ '2026-08-06 13:30:00-03', 'en_proceso'),
    (19, 6, 3, TIMESTAMPTZ '2026-08-07 10:00:00-03', 'resuelto'),

    (20, 7, 2, TIMESTAMPTZ '2026-08-07 09:00:00-03', 'abierto'),
    (21, 7, 2, TIMESTAMPTZ '2026-08-07 09:10:00-03', 'cerrado'),

    (22, 8, 3, TIMESTAMPTZ '2026-08-01 12:00:00-03', 'abierto'),
    (23, 8, 3, TIMESTAMPTZ '2026-08-02 10:00:00-03', 'resuelto'),
    (24, 8, 3, TIMESTAMPTZ '2026-08-10 15:00:00-03', 'reabierto'),
    (25, 8, 3, TIMESTAMPTZ '2026-08-11 08:00:00-03', 'en_proceso'),

    (26, 9, 2, TIMESTAMPTZ '2026-08-09 10:00:00-03', 'abierto'),
    (27, 9, 2, TIMESTAMPTZ '2026-08-09 10:45:00-03', 'resuelto'),

    (28, 10, 3, TIMESTAMPTZ '2026-08-10 09:00:00-03', 'abierto'),
    (29, 10, 1, TIMESTAMPTZ '2026-08-10 09:20:00-03', 'en_proceso'),
    (30, 10, 1, TIMESTAMPTZ '2026-08-10 11:30:00-03', 'resuelto'),
    (31, 10, 1, TIMESTAMPTZ '2026-08-11 09:00:00-03', 'cerrado');

-- -------------------------------------------------------------
-- CONVERSACIONES
-- Las conversaciones abiertas o reabiertas aun no tienen nota.
-- -------------------------------------------------------------
INSERT INTO conversaciones (
    id_conversacion,
    id_ticket,
    calificacion,
    fecha
) VALUES
    (1,  1,  5,    TIMESTAMPTZ '2026-08-01 09:01:00-03'),
    (2,  2,  4,    TIMESTAMPTZ '2026-08-03 14:01:00-03'),
    (3,  3,  NULL, TIMESTAMPTZ '2026-08-08 10:01:00-03'),
    (4,  4,  3,    TIMESTAMPTZ '2026-08-05 16:01:00-03'),
    (5,  5,  5,    TIMESTAMPTZ '2026-08-02 11:01:00-03'),
    (6,  6,  2,    TIMESTAMPTZ '2026-08-06 13:01:00-03'),
    (7,  7,  NULL, TIMESTAMPTZ '2026-08-07 09:01:00-03'),
    (8,  8,  NULL, TIMESTAMPTZ '2026-08-01 12:01:00-03'),
    (9,  9,  4,    TIMESTAMPTZ '2026-08-09 10:01:00-03'),
    (10, 10, 5,    TIMESTAMPTZ '2026-08-10 09:01:00-03');

-- -------------------------------------------------------------
-- CONSULTAS
-- Algunas conversaciones contienen mas de una consulta.
-- -------------------------------------------------------------
INSERT INTO consultas (
    id_consulta,
    id_conversacion,
    pregunta
) VALUES
    (1,  1,  'Como puedo restablecer mi contrasena?'),
    (2,  2,  'No recibi la factura de mi ultima compra.'),
    (3,  3,  'Quiero cambiar el domicilio registrado.'),
    (4,  4,  'Donde se encuentra mi pedido?'),
    (5,  5,  'Quiero cancelar el servicio contratado.'),
    (6,  6,  'El producto llego danado. Como solicito el cambio?'),
    (7,  7,  'Duplique una consulta anterior por error.'),
    (8,  8,  'Mi caso fue cerrado pero el problema continua.'),
    (9,  9,  'Que medios de pago aceptan?'),
    (10, 9,  'Puedo pagar la compra en cuotas?'),
    (11, 10, 'No puedo ingresar a la aplicacion movil.'),
    (12, 1,  'Cuanto tiempo dura el enlace para cambiar la contrasena?');

-- -------------------------------------------------------------
-- RESPUESTAS
-- Se combinan sugerencias de IA, respuestas humanas, respuestas
-- intermedias y finales. Las consultas 3 y 8 siguen sin finalizar.
-- -------------------------------------------------------------
INSERT INTO respuestas (
    id_respuesta,
    id_consulta,
    texto_respuesta,
    es_humano,
    es_respuesta_final
) VALUES
    (1,  1,  'La IA sugiere enviar un enlace de recuperacion al correo registrado.', FALSE, FALSE),
    (2,  1,  'Se envio el enlace de recuperacion y se verifico el acceso del cliente.', TRUE,  TRUE),
    (3,  2,  'Puede descargar la factura desde la seccion Mis compras.', FALSE, TRUE),
    (4,  3,  'La IA sugiere solicitar la validacion de identidad antes del cambio.', FALSE, FALSE),
    (5,  4,  'La IA informa que el pedido se encuentra en distribucion.', FALSE, FALSE),
    (6,  4,  'El pedido sera entregado durante el dia de hoy.', TRUE, TRUE),
    (7,  5,  'La cancelacion fue registrada y se envio el comprobante por correo.', TRUE, TRUE),
    (8,  6,  'La IA sugiere iniciar un reclamo por producto danado.', FALSE, FALSE),
    (9,  6,  'Se genero el reclamo y se coordino el reemplazo sin costo.', TRUE, TRUE),
    (10, 7,  'El ticket fue identificado como duplicado y se cerro sin eliminar el historial.', TRUE, TRUE),
    (11, 8,  'La IA sugiere reabrir el caso para una nueva revision tecnica.', FALSE, FALSE),
    (12, 9,  'Se aceptan tarjetas de credito, debito y transferencia bancaria.', FALSE, TRUE),
    (13, 10, 'La IA sugiere consultar las promociones bancarias vigentes.', FALSE, FALSE),
    (14, 10, 'La compra puede abonarse en tres cuotas sin interes con bancos adheridos.', TRUE, TRUE),
    (15, 11, 'La IA sugiere actualizar la aplicacion y restablecer la contrasena.', FALSE, FALSE),
    (16, 11, 'Se restablecio el acceso y el cliente pudo ingresar a la aplicacion.', TRUE, TRUE),
    (17, 12, 'El enlace de recuperacion permanece vigente durante treinta minutos.', FALSE, TRUE);

-- -------------------------------------------------------------
-- SINCRONIZACION DE SECUENCIAS
-- Como los identificadores se cargaron manualmente para que las
-- relaciones sean faciles de leer, se actualiza cada secuencia.
-- -------------------------------------------------------------
SELECT SETVAL(PG_GET_SERIAL_SEQUENCE('roles', 'id_rol'),
              (SELECT MAX(id_rol) FROM roles), TRUE);

SELECT SETVAL(PG_GET_SERIAL_SEQUENCE('empleados', 'id_empleado'),
              (SELECT MAX(id_empleado) FROM empleados), TRUE);

SELECT SETVAL(PG_GET_SERIAL_SEQUENCE('clientes', 'id_cliente'),
              (SELECT MAX(id_cliente) FROM clientes), TRUE);

SELECT SETVAL(PG_GET_SERIAL_SEQUENCE('tickets', 'id_ticket'),
              (SELECT MAX(id_ticket) FROM tickets), TRUE);

SELECT SETVAL(PG_GET_SERIAL_SEQUENCE('ticket_logs', 'id_ticket_log'),
              (SELECT MAX(id_ticket_log) FROM ticket_logs), TRUE);

SELECT SETVAL(PG_GET_SERIAL_SEQUENCE('conversaciones', 'id_conversacion'),
              (SELECT MAX(id_conversacion) FROM conversaciones), TRUE);

SELECT SETVAL(PG_GET_SERIAL_SEQUENCE('consultas', 'id_consulta'),
              (SELECT MAX(id_consulta) FROM consultas), TRUE);

SELECT SETVAL(PG_GET_SERIAL_SEQUENCE('respuestas', 'id_respuesta'),
              (SELECT MAX(id_respuesta) FROM respuestas), TRUE);

COMMIT;

