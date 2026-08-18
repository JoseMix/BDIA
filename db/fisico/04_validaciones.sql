-- Todas las pruebas se ejecutan dentro de una transaccion que
-- finaliza con ROLLBACK. La base queda sin modificaciones.


BEGIN;

-- -------------------------------------------------------------
-- VALIDACION 1: EXISTENCIA DE LAS OCHO TABLAS
-- -------------------------------------------------------------
DO $validacion$
DECLARE
    cantidad_tablas INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO cantidad_tablas
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name IN (
          'roles',
          'clientes',
          'empleados',
          'tickets',
          'ticket_logs',
          'conversaciones',
          'consultas',
          'respuestas'
      );

    IF cantidad_tablas <> 8 THEN
        RAISE EXCEPTION
            'VALIDACION FALLIDA: se encontraron % de las 8 tablas esperadas.',
            cantidad_tablas;
    END IF;

    RAISE NOTICE 'OK 1: existen las 8 tablas del modelo.';
END
$validacion$;

-- -------------------------------------------------------------
-- VALIDACION 2: CANTIDADES DE LOS DATOS DE EJEMPLO
-- -------------------------------------------------------------
DO $validacion$
DECLARE
    cantidad_tickets INTEGER;
    cantidad_logs INTEGER;
    cantidad_consultas INTEGER;
    cantidad_respuestas INTEGER;
BEGIN
    SELECT COUNT(*) INTO cantidad_tickets FROM tickets;
    SELECT COUNT(*) INTO cantidad_logs FROM ticket_logs;
    SELECT COUNT(*) INTO cantidad_consultas FROM consultas;
    SELECT COUNT(*) INTO cantidad_respuestas FROM respuestas;

    IF cantidad_tickets <> 10
       OR cantidad_logs <> 31
       OR cantidad_consultas <> 12
       OR cantidad_respuestas <> 17 THEN
        RAISE EXCEPTION
            'VALIDACION FALLIDA: cantidades inesperadas. tickets=%, logs=%, consultas=%, respuestas=%.',
            cantidad_tickets,
            cantidad_logs,
            cantidad_consultas,
            cantidad_respuestas;
    END IF;

    RAISE NOTICE
        'OK 2: datos cargados (10 tickets, 31 logs, 12 consultas y 17 respuestas).';
END
$validacion$;

-- -------------------------------------------------------------
-- VALIDACION 3: RESTRICCION UNIQUE SOBRE CLIENTES.DNI
-- Se intenta insertar un cliente con el DNI del cliente 1.
-- -------------------------------------------------------------
DO $validacion$
BEGIN
    BEGIN
        INSERT INTO clientes (
            id_cliente,
            nombre,
            apellido,
            dni,
            email,
            telefono_1
        ) VALUES (
            9001,
            'Cliente',
            'Duplicado',
            '30111222',
            'duplicado@example.com',
            '1100009001'
        );

        RAISE EXCEPTION
            'VALIDACION FALLIDA: se permitio insertar un DNI duplicado.';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'OK 3: UNIQUE rechazo correctamente el DNI duplicado.';
    END;
END
$validacion$;

-- -------------------------------------------------------------
-- VALIDACION 4: RESTRICCION NOT NULL SOBRE CLIENTES.EMAIL
-- -------------------------------------------------------------
DO $validacion$
BEGIN
    BEGIN
        INSERT INTO clientes (
            id_cliente,
            nombre,
            apellido,
            dni,
            email,
            telefono_1
        ) VALUES (
            9002,
            'Cliente',
            'Sin correo',
            '39999002',
            NULL,
            '1100009002'
        );

        RAISE EXCEPTION
            'VALIDACION FALLIDA: se permitio insertar un email nulo.';
    EXCEPTION
        WHEN not_null_violation THEN
            RAISE NOTICE 'OK 4: NOT NULL rechazo correctamente el email nulo.';
    END;
END
$validacion$;

-- -------------------------------------------------------------
-- VALIDACION 5: INTEGRIDAD REFERENCIAL DE TICKETS.ID_CLIENTE
-- -------------------------------------------------------------
DO $validacion$
BEGIN
    BEGIN
        INSERT INTO tickets (
            id_ticket,
            id_cliente,
            id_empleado,
            canal_origen
        ) VALUES (
            9003,
            999999,
            1,
            'web'
        );

        RAISE EXCEPTION
            'VALIDACION FALLIDA: se permitio un ticket con cliente inexistente.';
    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE NOTICE
                'OK 5: FOREIGN KEY rechazo correctamente el cliente inexistente.';
    END;
END
$validacion$;

-- -------------------------------------------------------------
-- VALIDACION 6: DOMINIO CERRADO DE TICKETS.CANAL_ORIGEN
-- -------------------------------------------------------------
DO $validacion$
BEGIN
    BEGIN
        INSERT INTO tickets (
            id_ticket,
            id_cliente,
            id_empleado,
            canal_origen
        ) VALUES (
            9004,
            1,
            1,
            'instagram'
        );

        RAISE EXCEPTION
            'VALIDACION FALLIDA: se permitio un canal no admitido.';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE
                'OK 6: CHECK rechazo correctamente el canal no admitido.';
    END;
END
$validacion$;

-- -------------------------------------------------------------
-- VALIDACION 7: CALIFICACION ENTRE 1 Y 5
-- -------------------------------------------------------------
DO $validacion$
BEGIN
    BEGIN
        INSERT INTO conversaciones (
            id_conversacion,
            id_ticket,
            calificacion
        ) VALUES (
            9005,
            1,
            6
        );

        RAISE EXCEPTION
            'VALIDACION FALLIDA: se permitio una calificacion fuera de rango.';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE
                'OK 7: CHECK rechazo correctamente la calificacion fuera de rango.';
    END;
END
$validacion$;

-- -------------------------------------------------------------
-- VALIDACION 8: TEXTO DE CONSULTA NO VACIO
-- -------------------------------------------------------------
DO $validacion$
BEGIN
    BEGIN
        INSERT INTO consultas (
            id_consulta,
            id_conversacion,
            pregunta
        ) VALUES (
            9006,
            1,
            ''
        );

        RAISE EXCEPTION
            'VALIDACION FALLIDA: se permitio una consulta vacia.';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE
                'OK 8: CHECK rechazo correctamente la consulta vacia.';
    END;
END
$validacion$;

-- -------------------------------------------------------------
-- VALIDACION 9: UNA SOLA RESPUESTA FINAL POR CONSULTA
-- La consulta 1 ya tiene una respuesta final (id_respuesta = 2).
-- -------------------------------------------------------------
DO $validacion$
BEGIN
    BEGIN
        INSERT INTO respuestas (
            id_respuesta,
            id_consulta,
            texto_respuesta,
            es_humano,
            es_respuesta_final
        ) VALUES (
            9007,
            1,
            'Segunda respuesta final que no deberia permitirse.',
            TRUE,
            TRUE
        );

        RAISE EXCEPTION
            'VALIDACION FALLIDA: se permitieron dos respuestas finales.';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE
                'OK 9: el indice unico rechazo una segunda respuesta final.';
    END;
END
$validacion$;

-- -------------------------------------------------------------
-- VALIDACION 10: VALOR DEFAULT DEL CAMPO CLIENTES.ACTIVO
-- -------------------------------------------------------------
DO $validacion$
DECLARE
    valor_activo BOOLEAN;
BEGIN
    INSERT INTO clientes (
        id_cliente,
        nombre,
        apellido,
        dni,
        email,
        telefono_1
    ) VALUES (
        9008,
        'Cliente',
        'Temporal',
        '39999008',
        'temporal@example.com',
        '1100009008'
    );

    SELECT activo
    INTO valor_activo
    FROM clientes
    WHERE id_cliente = 9008;

    IF valor_activo IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION
            'VALIDACION FALLIDA: el valor DEFAULT de activo no es TRUE.';
    END IF;

    RAISE NOTICE 'OK 10: el valor DEFAULT de clientes.activo es TRUE.';
END
$validacion$;

-- -------------------------------------------------------------
-- VALIDACION 11: BORRADO LOGICO
-- Se desactiva temporalmente un cliente y se verifica que su
-- ticket relacionado siga existiendo.
-- -------------------------------------------------------------
UPDATE clientes
SET activo = FALSE
WHERE id_cliente = 6;

DO $validacion$
DECLARE
    cliente_activo BOOLEAN;
    cantidad_tickets INTEGER;
BEGIN
    SELECT activo
    INTO cliente_activo
    FROM clientes
    WHERE id_cliente = 6;

    SELECT COUNT(*)
    INTO cantidad_tickets
    FROM tickets
    WHERE id_cliente = 6;

    IF cliente_activo IS DISTINCT FROM FALSE OR cantidad_tickets <> 1 THEN
        RAISE EXCEPTION
            'VALIDACION FALLIDA: el borrado logico no preservo el historial.';
    END IF;

    RAISE NOTICE
        'OK 11: el cliente se desactivo y su ticket relacionado se conservo.';
END
$validacion$;

-- -------------------------------------------------------------
-- VALIDACION 12: VISTA DEL ESTADO ACTUAL
-- El ultimo estado del ticket 8 debe ser en_proceso.
-- -------------------------------------------------------------
DO $validacion$
DECLARE
    estado_ticket VARCHAR(20);
BEGIN
    SELECT estado_actual
    INTO estado_ticket
    FROM vw_estado_actual_tickets
    WHERE id_ticket = 8;

    IF estado_ticket IS DISTINCT FROM 'en_proceso' THEN
        RAISE EXCEPTION
            'VALIDACION FALLIDA: estado actual inesperado para ticket 8: %.',
            estado_ticket;
    END IF;

    RAISE NOTICE
        'OK 12: la vista devuelve correctamente el ultimo estado del ticket.';
END
$validacion$;

-- -------------------------------------------------------------
-- VALIDACION 13: EXISTENCIA DEL INDICE UNICO Y DE LA VISTA
-- -------------------------------------------------------------
DO $validacion$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_indexes
        WHERE schemaname = 'public'
          AND indexname = 'uq_respuestas_final_por_consulta'
    ) THEN
        RAISE EXCEPTION
            'VALIDACION FALLIDA: no existe el indice de respuesta final.';
    END IF;

    IF TO_REGCLASS('public.vw_estado_actual_tickets') IS NULL THEN
        RAISE EXCEPTION
            'VALIDACION FALLIDA: no existe la vista de estado actual.';
    END IF;

    RAISE NOTICE 'OK 13: existen el indice unico y la vista esperados.';
END
$validacion$;

-- Se revierten el cliente temporal y el cambio de activo realizado
-- durante las pruebas. Ningun dato de ejemplo queda modificado.
ROLLBACK;

