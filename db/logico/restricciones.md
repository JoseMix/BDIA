# Restricciones de integridad

A continuación se detallan las restricciones de integridad aplicadas al modelo lógico, organizadas por tabla. Se incluyen restricciones de dominio (NOT NULL, CHECK), de unicidad (UNIQUE), y de integridad referencial (FOREIGN KEY con políticas ON DELETE / ON UPDATE).

## CLIENTES

| Columna | Restricción | Justificación |
|---|---|---|
| `id_cliente` | PRIMARY KEY | Identificador único del cliente |
| `nombre` | NOT NULL | Dato obligatorio para identificar al cliente |
| `apellido` | NOT NULL | Dato obligatorio para identificar al cliente |
| `dni` | UNIQUE, NOT NULL | No puede haber dos clientes con el mismo documento |
| `email` | UNIQUE, NOT NULL | Se usa como canal de contacto y posible identificador de acceso |
| `telefono_1` | NOT NULL | Canal de contacto principal obligatorio |
| `telefono_2` | NULL permitido | Contacto alternativo, opcional |
| `direccion` | NULL permitido | No es indispensable para dar de alta al cliente |
| `activo` | NOT NULL, DEFAULT `true` | Soft delete: permite dar de baja al cliente sin romper la integridad referencial con `tickets` |

## EMPLEADOS

| Columna | Restricción | Justificación |
|---|---|---|
| `id_empleado` | PRIMARY KEY | Identificador único del empleado |
| `id_rol` | FOREIGN KEY → `roles.id_rol`, NOT NULL, ON DELETE RESTRICT, ON UPDATE CASCADE | Todo empleado debe tener un rol asignado; no se permite borrar un rol que tenga empleados activos |
| `nombre` | NOT NULL | Dato obligatorio |
| `apellido` | NOT NULL | Dato obligatorio |
| `dni` | UNIQUE, NOT NULL | No puede haber dos empleados con el mismo documento |
| `departamento` | NOT NULL | Necesario para trazabilidad organizacional |
| `activo` | NOT NULL, DEFAULT `true` | Soft delete: permite dar de baja al empleado sin perder la trazabilidad de tickets y logs asociados |

## ROLES

| Columna | Restricción | Justificación |
|---|---|---|
| `id_rol` | PRIMARY KEY | Identificador único del rol |
| `descripcion` | UNIQUE, NOT NULL | No deben existir roles duplicados con la misma descripción |

## TICKETS

| Columna | Restricción | Justificación |
|---|---|---|
| `id_ticket` | PRIMARY KEY | Identificador único del ticket |
| `id_cliente` | FOREIGN KEY → `clientes.id_cliente`, NOT NULL, ON DELETE RESTRICT, ON UPDATE CASCADE | Todo ticket debe pertenecer a un cliente; no se permite eliminar un cliente con tickets asociados |
| `id_empleado` | FOREIGN KEY → `empleados.id_empleado`, NOT NULL, ON DELETE RESTRICT, ON UPDATE CASCADE | Todo ticket debe tener un empleado asignado actualmente |
| `canal_origen` | NOT NULL, CHECK (`canal_origen` IN ('chat', 'email', 'whatsapp', 'telefono', 'web')) | Restringe los valores posibles a los canales soportados por el sistema |
| `activo` | NOT NULL, DEFAULT `true` | Soft delete: permite "eliminar" un ticket (ej. duplicado, error de carga) sin perder su historial de logs y conversaciones |

## TICKET_LOGS

| Columna | Restricción | Justificación |
|---|---|---|
| `id_ticket_log` | PRIMARY KEY | Identificador único del registro de auditoría |
| `id_ticket` | FOREIGN KEY → `tickets.id_ticket`, NOT NULL, ON DELETE RESTRICT, ON UPDATE CASCADE | Un log siempre pertenece a un ticket; el ticket no se puede borrar, solo se hace soft delete |
| `id_empleado` | FOREIGN KEY → `empleados.id_empleado`, NOT NULL, ON DELETE RESTRICT, ON UPDATE CASCADE | Todo cambio de estado debe quedar trazado a un empleado; no se permite borrar un empleado con logs asociados (preserva auditoría) |
| `fecha` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Todo evento de log debe tener fecha de registro |
| `estado` | NOT NULL, CHECK (`estado` IN ('abierto', 'en_proceso', 'resuelto', 'cerrado', 'reabierto')) | Restringe los valores posibles a los estados definidos del ciclo de vida del ticket |

## CONVERSACIONES

| Columna | Restricción | Justificación |
|---|---|---|
| `id_conversacion` | PRIMARY KEY | Identificador único de la conversación |
| `id_ticket` | FOREIGN KEY → `tickets.id_ticket`, NOT NULL, ON DELETE RESTRICT, ON UPDATE CASCADE | Toda conversación pertenece a un ticket; el ticket no se borra físicamente (se desactiva vía `activo`), por lo que la conversación nunca queda huérfana |
| `calificacion` | NULL permitido, CHECK (`calificacion` BETWEEN 1 AND 5) | La calificación es opcional (se completa al cerrar la conversación) pero si existe debe estar en escala válida |
| `fecha` | NOT NULL, DEFAULT `CURRENT_TIMESTAMP` | Toda conversación debe tener fecha de inicio |

## CONSULTAS

| Columna | Restricción | Justificación |
|---|---|---|
| `id_consulta` | PRIMARY KEY | Identificador único de la consulta |
| `id_conversacion` | FOREIGN KEY → `conversaciones.id_conversacion`, NOT NULL, ON DELETE RESTRICT, ON UPDATE CASCADE | Toda consulta pertenece a una conversación; la conversación no tiene borrado físico ni lógico propio, por lo que la consulta nunca queda huérfana |
| `pregunta` | NOT NULL, CHECK (`LENGTH(pregunta) > 0`) | El texto de la consulta no puede estar vacío |

## RESPUESTAS

| Columna | Restricción | Justificación |
|---|---|---|
| `id_respuesta` | PRIMARY KEY | Identificador único de la respuesta |
| `id_consulta` | FOREIGN KEY → `consultas.id_consulta`, NOT NULL, ON DELETE RESTRICT, ON UPDATE CASCADE | Toda respuesta pertenece a una consulta; la consulta no tiene borrado físico ni lógico propio, por lo que la respuesta nunca queda huérfana |
| `texto_respuesta` | NOT NULL, CHECK (`LENGTH(texto_respuesta) > 0`) | El texto de la respuesta no puede estar vacío |
| `es_humano` | NOT NULL, DEFAULT `false` | Debe quedar explícito si la respuesta la generó un agente humano o el sistema de IA |
| `es_respuesta_final` | NOT NULL, DEFAULT `false` | Debe quedar explícito si es la respuesta definitiva de la consulta o un intento intermedio |

## Resumen de políticas de borrado (ON DELETE)

| Relación | Política | Justificación |
|---|---|---|
| `empleados.id_rol → roles.id_rol` | RESTRICT | No se elimina un rol en uso |
| `tickets.id_cliente → clientes.id_cliente` | RESTRICT | No se elimina un cliente con historial de tickets |
| `tickets.id_empleado → empleados.id_empleado` | RESTRICT | No se elimina un empleado con tickets asignados activos |
| `ticket_logs.id_ticket → tickets.id_ticket` | RESTRICT | No se elimina el historial de un ticket si se borra un ticket, se debe hacer soft delete del ticket |
| `ticket_logs.id_empleado → empleados.id_empleado` | RESTRICT | Se preserva la trazabilidad/auditoría aunque el empleado sea dado de baja |
| `conversaciones.id_ticket → tickets.id_ticket` | RESTRICT | El ticket nunca se borra físicamente (se desactiva vía `activo`), por lo que la conversación siempre conserva su ticket asociado |
| `consultas.id_conversacion → conversaciones.id_conversacion` | RESTRICT | La conversación nunca se borra físicamente, por lo que la consulta siempre conserva su conversación asociada |
| `respuestas.id_consulta → consultas.id_consulta` | RESTRICT | La consulta nunca se borra físicamente, por lo que la respuesta siempre conserva su consulta asociada |

## Criterio de soft delete

En este modelo **no se realiza borrado físico (`DELETE`)** sobre entidades de negocio que tengan historial asociado. En su lugar:

| Tabla | Mecanismo | Motivo |
|---|---|---|
| `CLIENTES` | `activo = false` | Anonimización de datos personales sin perder integridad referencial con `tickets` |
| `EMPLEADOS` | `activo = false` | Preserva la trazabilidad/auditoría de tickets y logs asociados a un empleado dado de baja |
| `TICKETS` | `activo = false` | Permite "cerrar"/ocultar un ticket operativamente sin perder su historial de logs, conversaciones, consultas y respuestas |

Las tablas `ROLES`, `TICKET_LOGS`, `CONVERSACIONES`, `CONSULTAS` y `RESPUESTAS` no requieren su propio flag `activo`: son registros históricos inmutables o dependen directamente del estado de su tabla padre (`tickets`), por lo que heredan su condición de "inactivo" sin necesidad de duplicar el campo.


# Criterios de normalización

El modelo lógico cumple hasta la Tercera Forma Normal (3FN) en todas sus tablas.

## 1FN — Valores atómicos, sin grupos repetitivos

**Criterio:** cada atributo contiene un único valor indivisible; no hay listas ni campos multivaluados; cada fila se identifica por una PK.

**En el diseño:** no hay campos que almacenen varios valores juntos (ej. `clientes` usa `telefono_1` y `telefono_2` como columnas separadas, no un campo con teléfonos concatenados). Todas las tablas tienen PK simple. Se cumple en las 8 tablas.

## 2FN — Dependencia funcional completa de la PK

**Criterio:** todo atributo no-clave depende de la PK completa. Solo aplica cuando hay PK compuesta.

**En el diseño:** no hay ninguna PK compuesta (todas son autonuméricas simples), por lo que 2FN se cumple automáticamente en todo el modelo — no hay dependencias parciales posibles.

## 3FN — Sin dependencias transitivas

**Criterio:** ningún atributo no-clave depende de otro atributo no-clave, solo de la PK.

**En el diseño:** se revisó cada tabla y no se encontraron dependencias transitivas. El caso más cercano a una violación sería `empleados.departamento` dependiendo de `empleados.id_rol` (si cada rol perteneciera siempre a un único departamento) — se descarta porque un mismo rol puede existir en varios departamentos, así que `departamento` es atributo propio del empleado, no derivado del rol. Se cumple en las 8 tablas.

## Conclusión

El modelo evita redundancia, anomalías de inserción/actualización/borrado. La única desnormalización intencional es `tickets.id_empleado` (asignación actual) frente al histórico en `ticket_logs`, ya documentada como desnormalización controlada por rendimiento, no como violación de forma normal.