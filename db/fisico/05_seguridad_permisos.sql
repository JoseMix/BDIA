-- -------------------------------------------------------------
-- SEGURIDAD, PERMISOS Y AISLAMIENTO
-- Implementacion practica de docs/informe.md, seccion 13.
--
-- Aditivo: no modifica 01_creacion_tablas.sql, 02_indices_vistas.sql
-- ni 04_validaciones.sql. Debe ejecutarse despues de 01 y 02 (y,
-- opcionalmente, despues de cargar data/03_datos_ejemplo.sql para
-- poder probarlo con datos reales).
--
-- Convencion de sesion que asumen las politicas de abajo: el backend
-- autentica al usuario final y, en la misma conexion/transaccion,
-- hace SET ROLE al rol de Postgres que corresponda (rol_app_cliente,
-- rol_operador, rol_supervisor o rol_administrador) y fija una de
-- estas dos variables de sesion segun el caso:
--   SET app.current_cliente_id  = '<id_cliente>';
--   SET app.current_empleado_id = '<id_empleado>';
-- Todas las politicas leen esas variables con current_setting(..., true)
-- (segundo argumento = missing_ok): si no esta seteada, devuelve NULL
-- en vez de lanzar error, y la comparacion "columna = NULL" es NULL,
-- que RLS trata como "no coincide" -> deniega en vez de romper la
-- consulta. Esto corrige el ::int sin missing_ok que tenia el
-- fragmento original de la seccion 13 del informe.
-- -------------------------------------------------------------

BEGIN;

-- =================================================================
-- 0. CORRECCION SOBRE UN OBJETO YA EXISTENTE
-- =================================================================
-- Por defecto, una vista corre con los privilegios de quien la creo,
-- no de quien la consulta. Sin esto, ni la RLS de tickets/clientes ni
-- los GRANT por columna de mas abajo aplican cuando se lee a traves
-- de vw_estado_actual_tickets -- que es el camino que usan varias de
-- las 5 consultas representativas del punto 10. Disponible desde
-- PostgreSQL 15 (el proyecto usa la 16). No se toca 02_indices_vistas.sql:
-- esto es un ALTER sobre el objeto ya creado, no una edicion de ese
-- archivo.
ALTER VIEW vw_estado_actual_tickets SET (security_invoker = true);

-- =================================================================
-- 1. ROLES DE POSTGRES
-- =================================================================
-- Todos NOLOGIN: no son usuarios de conexion directa (los clientes
-- serian miles; no tiene sentido un login de Postgres por cliente).
-- El backend se conecta con un unico rol de aplicacion (fuera del
-- alcance de este script) y hace SET ROLE al que corresponda.
CREATE ROLE rol_app_cliente NOLOGIN;
CREATE ROLE rol_operador NOLOGIN;
CREATE ROLE rol_supervisor NOLOGIN;
CREATE ROLE rol_administrador NOLOGIN;

-- Rol de servicio para el actor "Sistema de IA" del punto 1 del
-- informe. No representa a una persona: solo puede insertar
-- respuestas automaticas (es_humano = false). Su lectura para
-- generar una sugerencia NO pasa por este rol -- corre dentro de la
-- sesion (y por lo tanto de la RLS) del usuario humano que disparo
-- la consulta, que es la mitigacion a la "puerta lateral" descripta
-- en el punto 1 y al riesgo R2 del punto 2. Este rol de servicio
-- existe unicamente para el camino de escritura, que ningun rol
-- humano tiene permitido.
CREATE ROLE rol_sistema_ia NOLOGIN;

-- security_invoker (seccion 0) hace que la vista respete los
-- privilegios de quien consulta sobre las tablas base, pero eso no
-- alcanza: tambien hace falta el GRANT sobre la vista como objeto.
-- Sin esta linea, cualquier rol recibe "permission denied for view"
-- aunque tenga acceso a las tablas subyacentes (asi fallo en la
-- primera prueba manual contra un Postgres real -- ver notas al pie
-- de este archivo).
GRANT SELECT ON vw_estado_actual_tickets
    TO rol_app_cliente, rol_operador, rol_supervisor, rol_administrador;

-- =================================================================
-- 2. ROLES (tabla de catalogo: descripciones de rol de empleado)
-- =================================================================
-- Tabla chica y no sensible (3 filas: Operador/Supervisor/
-- Administrador). No se habilita RLS: cualquier rol interno puede
-- ver el catalogo completo.
GRANT SELECT ON roles TO rol_operador, rol_supervisor, rol_administrador;
GRANT INSERT, UPDATE ON roles TO rol_administrador;
-- Sin DELETE para nadie: ver criterio de "nunca borrado fisico" al
-- final de este archivo (seccion 9).

-- =================================================================
-- 3. EMPLEADOS
-- =================================================================
ALTER TABLE empleados ENABLE ROW LEVEL SECURITY;

CREATE POLICY operador_ve_su_propio_registro ON empleados
    FOR SELECT
    TO rol_operador
    USING (id_empleado = current_setting('app.current_empleado_id', true)::int);

-- Simplificacion respecto de la matriz original del informe: el
-- modelo fisico no tiene un concepto de "equipo" (no hay relacion
-- supervisor-operador, solo id_rol). Se implementa "supervisor ve
-- toda la nomina" en vez de un recorte por equipo que el esquema no
-- puede resolver hoy; queda anotado como simplificacion deliberada.
CREATE POLICY supervisor_admin_ven_todo_empleados ON empleados
    FOR SELECT
    TO rol_supervisor, rol_administrador
    USING (true);

CREATE POLICY administrador_inserta_empleados ON empleados
    FOR INSERT
    TO rol_administrador
    WITH CHECK (true);

CREATE POLICY administrador_actualiza_empleados ON empleados
    FOR UPDATE
    TO rol_administrador
    USING (true)
    WITH CHECK (true);

GRANT SELECT ON empleados TO rol_operador, rol_supervisor, rol_administrador;
GRANT INSERT, UPDATE ON empleados TO rol_administrador;

-- =================================================================
-- 4. CLIENTES
-- =================================================================
ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;

CREATE POLICY cliente_ve_su_propio_registro ON clientes
    FOR SELECT
    TO rol_app_cliente
    USING (id_cliente = current_setting('app.current_cliente_id', true)::int);

CREATE POLICY cliente_actualiza_su_propio_registro ON clientes
    FOR UPDATE
    TO rol_app_cliente
    USING (id_cliente = current_setting('app.current_cliente_id', true)::int)
    WITH CHECK (id_cliente = current_setting('app.current_cliente_id', true)::int);

-- El operador solo ve clientes con los que tiene contacto por tener
-- al menos un ticket asignado.
CREATE POLICY operador_ve_clientes_de_sus_tickets ON clientes
    FOR SELECT
    TO rol_operador
    USING (
        id_cliente IN (
            SELECT id_cliente FROM tickets
            WHERE id_empleado = current_setting('app.current_empleado_id', true)::int
        )
    );

CREATE POLICY supervisor_admin_ven_todo_clientes ON clientes
    FOR SELECT
    TO rol_supervisor, rol_administrador
    USING (true);

CREATE POLICY administrador_inserta_clientes ON clientes
    FOR INSERT
    TO rol_administrador
    WITH CHECK (true);

CREATE POLICY administrador_actualiza_clientes ON clientes
    FOR UPDATE
    TO rol_administrador
    USING (true)
    WITH CHECK (true);

-- El cliente solo puede tocar sus datos de contacto, nunca su
-- identidad (dni/email) ni el flag activo (baja logica).
GRANT SELECT ON clientes TO rol_app_cliente;
GRANT UPDATE (nombre, apellido, telefono_1, telefono_2, direccion)
    ON clientes TO rol_app_cliente;

-- El operador nunca necesita dni/direccion/telefono_2 para resolver
-- un caso: alcanza con nombre, apellido, email y telefono principal.
GRANT SELECT (id_cliente, nombre, apellido, email, telefono_1)
    ON clientes TO rol_operador;

GRANT SELECT ON clientes TO rol_supervisor;
GRANT SELECT, INSERT, UPDATE ON clientes TO rol_administrador;

-- Nota de alcance: el alta de un cliente nuevo (autorregistro) queda
-- fuera de este script -- requeriria un camino propio (ej. una
-- funcion SECURITY DEFINER) porque al momento del alta todavia no
-- existe la sesion "app.current_cliente_id" del propio cliente.

-- =================================================================
-- 5. TICKETS
-- =================================================================
ALTER TABLE tickets ENABLE ROW LEVEL SECURITY;

CREATE POLICY cliente_ve_sus_tickets ON tickets
    FOR SELECT
    TO rol_app_cliente
    USING (id_cliente = current_setting('app.current_cliente_id', true)::int);

CREATE POLICY cliente_crea_tickets ON tickets
    FOR INSERT
    TO rol_app_cliente
    WITH CHECK (id_cliente = current_setting('app.current_cliente_id', true)::int);
-- Nota de alcance: no se restringe aqui que id_empleado sea un
-- operador con menor carga -- la asignacion inicial (a que operador
-- se deriva un ticket nuevo) es logica de la aplicacion, no una regla
-- expresable como WITH CHECK de fila individual.

CREATE POLICY operador_ve_asignados ON tickets
    FOR SELECT
    TO rol_operador
    USING (id_empleado = current_setting('app.current_empleado_id', true)::int);

-- USING limita que filas puede tocar (solo las suyas); WITH CHECK
-- (true) permite que el nuevo valor de id_empleado sea OTRO empleado,
-- para no bloquear la derivacion/reasignacion a otro operador.
CREATE POLICY operador_actualiza_asignados ON tickets
    FOR UPDATE
    TO rol_operador
    USING (id_empleado = current_setting('app.current_empleado_id', true)::int)
    WITH CHECK (true);

CREATE POLICY supervisor_admin_ven_todo_tickets ON tickets
    FOR SELECT
    TO rol_supervisor, rol_administrador
    USING (true);

-- El supervisor reasigna cualquier ticket (no solo los propios).
CREATE POLICY supervisor_actualiza_todo_tickets ON tickets
    FOR UPDATE
    TO rol_supervisor
    USING (true)
    WITH CHECK (true);

CREATE POLICY administrador_inserta_tickets ON tickets
    FOR INSERT
    TO rol_administrador
    WITH CHECK (true);

CREATE POLICY administrador_actualiza_tickets ON tickets
    FOR UPDATE
    TO rol_administrador
    USING (true)
    WITH CHECK (true);

GRANT SELECT, INSERT ON tickets TO rol_app_cliente;
GRANT SELECT, UPDATE ON tickets TO rol_operador;
GRANT SELECT, UPDATE ON tickets TO rol_supervisor;
GRANT SELECT, INSERT, UPDATE ON tickets TO rol_administrador;

-- =================================================================
-- 6. TICKET_LOGS -- append-only por diseno (ver restricciones.md)
-- =================================================================
ALTER TABLE ticket_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY cliente_ve_logs_de_sus_tickets ON ticket_logs
    FOR SELECT
    TO rol_app_cliente
    USING (
        id_ticket IN (
            SELECT id_ticket FROM tickets
            WHERE id_cliente = current_setting('app.current_cliente_id', true)::int
        )
    );

CREATE POLICY operador_ve_logs_de_sus_tickets ON ticket_logs
    FOR SELECT
    TO rol_operador
    USING (
        id_ticket IN (
            SELECT id_ticket FROM tickets
            WHERE id_empleado = current_setting('app.current_empleado_id', true)::int
        )
    );

CREATE POLICY operador_inserta_logs_de_sus_tickets ON ticket_logs
    FOR INSERT
    TO rol_operador
    WITH CHECK (
        id_empleado = current_setting('app.current_empleado_id', true)::int
        AND id_ticket IN (
            SELECT id_ticket FROM tickets
            WHERE id_empleado = current_setting('app.current_empleado_id', true)::int
        )
    );

CREATE POLICY supervisor_ve_todo_logs ON ticket_logs
    FOR SELECT
    TO rol_supervisor, rol_administrador
    USING (true);

-- El supervisor puede loguear una accion (ej. una reasignacion) sobre
-- cualquier ticket, no solo los propios; se autoatribuye vía
-- id_empleado.
CREATE POLICY supervisor_inserta_logs ON ticket_logs
    FOR INSERT
    TO rol_supervisor
    WITH CHECK (id_empleado = current_setting('app.current_empleado_id', true)::int);

GRANT SELECT ON ticket_logs TO rol_app_cliente, rol_operador, rol_supervisor, rol_administrador;
GRANT INSERT ON ticket_logs TO rol_operador, rol_supervisor;
-- No hay UPDATE ni DELETE otorgado a NINGUN rol, ni siquiera
-- administrador: asi se aplica "append-only" a nivel de privilegios
-- de motor, no solo como convencion documentada. Es el mismo
-- criterio que restricciones.md ya describe en prosa, ahora tambien
-- imposible de violar por accidente desde la aplicacion.

-- =================================================================
-- 7. CONVERSACIONES Y CONSULTAS
-- =================================================================
ALTER TABLE conversaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE consultas ENABLE ROW LEVEL SECURITY;

CREATE POLICY cliente_ve_sus_conversaciones ON conversaciones
    FOR SELECT
    TO rol_app_cliente
    USING (
        id_ticket IN (
            SELECT id_ticket FROM tickets
            WHERE id_cliente = current_setting('app.current_cliente_id', true)::int
        )
    );

CREATE POLICY cliente_crea_conversaciones ON conversaciones
    FOR INSERT
    TO rol_app_cliente
    WITH CHECK (
        id_ticket IN (
            SELECT id_ticket FROM tickets
            WHERE id_cliente = current_setting('app.current_cliente_id', true)::int
        )
    );

-- Calificar es la unica escritura de un cliente sobre una conversacion
-- ya existente (columna acotada mas abajo con GRANT UPDATE (calificacion)).
CREATE POLICY cliente_califica_conversacion ON conversaciones
    FOR UPDATE
    TO rol_app_cliente
    USING (
        id_ticket IN (
            SELECT id_ticket FROM tickets
            WHERE id_cliente = current_setting('app.current_cliente_id', true)::int
        )
    )
    WITH CHECK (
        id_ticket IN (
            SELECT id_ticket FROM tickets
            WHERE id_cliente = current_setting('app.current_cliente_id', true)::int
        )
    );

CREATE POLICY operador_ve_conversaciones_de_sus_tickets ON conversaciones
    FOR SELECT
    TO rol_operador
    USING (
        id_ticket IN (
            SELECT id_ticket FROM tickets
            WHERE id_empleado = current_setting('app.current_empleado_id', true)::int
        )
    );

CREATE POLICY supervisor_admin_ven_todo_conversaciones ON conversaciones
    FOR SELECT
    TO rol_supervisor, rol_administrador
    USING (true);

CREATE POLICY administrador_escribe_conversaciones ON conversaciones
    FOR ALL
    TO rol_administrador
    USING (true)
    WITH CHECK (true);

GRANT SELECT, INSERT ON conversaciones TO rol_app_cliente;
GRANT UPDATE (calificacion) ON conversaciones TO rol_app_cliente;
GRANT SELECT ON conversaciones TO rol_operador, rol_supervisor;
GRANT SELECT, INSERT, UPDATE ON conversaciones TO rol_administrador;

-- CONSULTAS: mismo criterio de aislamiento, un nivel mas profundo
-- (via conversaciones -> tickets).
CREATE POLICY cliente_ve_sus_consultas ON consultas
    FOR SELECT
    TO rol_app_cliente
    USING (
        id_conversacion IN (
            SELECT c.id_conversacion FROM conversaciones AS c
            INNER JOIN tickets AS t ON t.id_ticket = c.id_ticket
            WHERE t.id_cliente = current_setting('app.current_cliente_id', true)::int
        )
    );

CREATE POLICY cliente_crea_consultas ON consultas
    FOR INSERT
    TO rol_app_cliente
    WITH CHECK (
        id_conversacion IN (
            SELECT c.id_conversacion FROM conversaciones AS c
            INNER JOIN tickets AS t ON t.id_ticket = c.id_ticket
            WHERE t.id_cliente = current_setting('app.current_cliente_id', true)::int
        )
    );

CREATE POLICY operador_ve_consultas_de_sus_tickets ON consultas
    FOR SELECT
    TO rol_operador
    USING (
        id_conversacion IN (
            SELECT c.id_conversacion FROM conversaciones AS c
            INNER JOIN tickets AS t ON t.id_ticket = c.id_ticket
            WHERE t.id_empleado = current_setting('app.current_empleado_id', true)::int
        )
    );

CREATE POLICY supervisor_admin_ven_todo_consultas ON consultas
    FOR SELECT
    TO rol_supervisor, rol_administrador
    USING (true);

CREATE POLICY administrador_escribe_consultas ON consultas
    FOR ALL
    TO rol_administrador
    USING (true)
    WITH CHECK (true);

GRANT SELECT, INSERT ON consultas TO rol_app_cliente;
GRANT SELECT ON consultas TO rol_operador, rol_supervisor;
GRANT SELECT, INSERT, UPDATE ON consultas TO rol_administrador;

-- =================================================================
-- 8. RESPUESTAS
-- =================================================================
ALTER TABLE respuestas ENABLE ROW LEVEL SECURITY;

CREATE POLICY cliente_ve_respuestas_de_sus_consultas ON respuestas
    FOR SELECT
    TO rol_app_cliente
    USING (
        id_consulta IN (
            SELECT q.id_consulta FROM consultas AS q
            INNER JOIN conversaciones AS c ON c.id_conversacion = q.id_conversacion
            INNER JOIN tickets AS t ON t.id_ticket = c.id_ticket
            WHERE t.id_cliente = current_setting('app.current_cliente_id', true)::int
        )
    );

CREATE POLICY operador_ve_respuestas_de_sus_tickets ON respuestas
    FOR SELECT
    TO rol_operador
    USING (
        id_consulta IN (
            SELECT q.id_consulta FROM consultas AS q
            INNER JOIN conversaciones AS c ON c.id_conversacion = q.id_conversacion
            INNER JOIN tickets AS t ON t.id_ticket = c.id_ticket
            WHERE t.id_empleado = current_setting('app.current_empleado_id', true)::int
        )
    );

-- El operador solo escribe respuestas humanas (es_humano = true) y
-- solo sobre sus propios tickets. Nunca inserta/edita una fila con
-- es_humano = false: eso es exclusivo del rol_sistema_ia de abajo.
CREATE POLICY operador_inserta_respuestas_humanas ON respuestas
    FOR INSERT
    TO rol_operador
    WITH CHECK (
        es_humano = TRUE
        AND id_consulta IN (
            SELECT q.id_consulta FROM consultas AS q
            INNER JOIN conversaciones AS c ON c.id_conversacion = q.id_conversacion
            INNER JOIN tickets AS t ON t.id_ticket = c.id_ticket
            WHERE t.id_empleado = current_setting('app.current_empleado_id', true)::int
        )
    );

-- Unica escritura permitida sobre una fila ya existente: marcar/
-- desmarcar es_respuesta_final (columna acotada con GRANT mas abajo),
-- nunca el texto ya enviado.
CREATE POLICY operador_actualiza_finalidad_propia ON respuestas
    FOR UPDATE
    TO rol_operador
    USING (
        es_humano = TRUE
        AND id_consulta IN (
            SELECT q.id_consulta FROM consultas AS q
            INNER JOIN conversaciones AS c ON c.id_conversacion = q.id_conversacion
            INNER JOIN tickets AS t ON t.id_ticket = c.id_ticket
            WHERE t.id_empleado = current_setting('app.current_empleado_id', true)::int
        )
    )
    WITH CHECK (es_humano = TRUE);

-- Rol de servicio de la IA: solo puede insertar sugerencias
-- (es_humano = false). Puede llegar a marcar es_respuesta_final = true
-- porque el caso "resuelto 100% por IA sin intervencion humana" es
-- parte del diseno (ver datos de ejemplo: respuesta id 3).
CREATE POLICY ia_inserta_sugerencias ON respuestas
    FOR INSERT
    TO rol_sistema_ia
    WITH CHECK (es_humano = FALSE);

CREATE POLICY supervisor_admin_ven_todo_respuestas ON respuestas
    FOR SELECT
    TO rol_supervisor, rol_administrador
    USING (true);

CREATE POLICY administrador_escribe_respuestas ON respuestas
    FOR ALL
    TO rol_administrador
    USING (true)
    WITH CHECK (true);

GRANT SELECT ON respuestas TO rol_app_cliente;
GRANT SELECT, INSERT ON respuestas TO rol_operador;
GRANT UPDATE (es_respuesta_final) ON respuestas TO rol_operador;
GRANT INSERT ON respuestas TO rol_sistema_ia;
GRANT SELECT ON respuestas TO rol_supervisor;
GRANT SELECT, INSERT, UPDATE ON respuestas TO rol_administrador;

-- =================================================================
-- 9. CRITERIO GENERAL DE BORRADO
-- =================================================================
-- En ninguna tabla del nucleo se otorga DELETE a ningun rol de
-- aplicacion (ni siquiera administrador). El unico mecanismo de baja
-- es logico, vía UPDATE de la columna `activo` en clientes/empleados/
-- tickets -- ya cubierto por los GRANT de UPDATE de administrador
-- (y, para su propio registro, del cliente, que no puede tocar
-- `activo` porque esa columna no esta en su GRANT de UPDATE).
-- Refuerza a nivel de motor lo que restricciones.md ya documenta
-- como criterio de diseno (mitigacion del riesgo R5).

-- =================================================================
-- 10. PENDIENTE (fuera de alcance de este script)
-- =================================================================
-- - consultas_embeddings (extension pgvector, ver
--   vectorial/modelo_vectorial.md) todavia no esta creada en
--   db/fisico/: cuando exista, debe llevar columnas propias
--   id_cliente/id_ticket (no solo id_consulta/id_respuesta) para que
--   su policy de RLS sea una comparacion de igualdad indexada y no un
--   JOIN contra el nucleo -- ese JOIN es justo lo que la tabla
--   desnormalizada existe para evitar (informe, seccion 6.3b y 13).
--   Con esas columnas, la policy es igual a la de tickets:
--     USING (id_cliente = current_setting('app.current_cliente_id', true)::int)
--   tal como pide el punto 5 de vectorial/modelo_vectorial.md.
-- - Alta de clientes por autorregistro (ver nota de la seccion 4).
-- - Password/autenticacion de las conexiones reales de la aplicacion:
--   fuera del alcance de este TP, que modela la capa de datos.

COMMIT;

-- =================================================================
-- NOTA DE USO EN PRODUCCION: SET vs SET LOCAL (verificado empiricamente)
-- =================================================================
-- Probado contra un Postgres real: current_setting(..., true) SI
-- devuelve NULL cuando la variable nunca fue seteada en la sesion
-- (una conexion nueva que jamas se autentico deniega correctamente,
-- en vez de romper). Pero un simple RESET no vuelve a dejarla en
-- "nunca seteada": la deja en '' (string vacio), y ''::int rompe con
-- error, no con deny.
--
-- Esto importa en un backend con connection pooling (pgbouncer o
-- similar), donde la misma conexion fisica de Postgres se reutiliza
-- entre pedidos de usuarios distintos: si el pedido siguiente olvida
-- volver a hacer el SET, el peor escenario no es un error -- es que
-- ese pedido quede corriendo con el app.current_empleado_id de OTRO
-- usuario todavia pegado a la sesion. Un error molesta; una fuga
-- entre usuarios es el riesgo real que esta seccion 13 del informe
-- busca evitar.
--
-- Recomendacion para la capa de aplicacion (fuera del alcance SQL de
-- este script): usar `SET LOCAL app.current_empleado_id = ...` (no
-- `SET`) dentro de la misma transaccion de cada pedido, nunca a nivel
-- de conexion. SET LOCAL revierte solo al terminar la transaccion
-- (COMMIT o ROLLBACK), sin depender de que el backend se acuerde de
-- resetearla -- si el proximo pedido reusa la conexion y olvida
-- setearla, current_setting(..., true) vuelve a ver "nunca seteada"
-- (NULL) y deniega, en vez de heredar el valor del pedido anterior.

