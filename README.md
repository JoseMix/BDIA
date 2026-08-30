# TP Integrador — Sistema de Atención al Cliente con IA

**Asignatura:** Bases de Datos para IA

## Integrantes

- Putrino, Daniela
- Lastra, Nicolás
- Silva, José Miguel
- Curcho, Franco
- Valle, Alejandro
- Castro, José Roberto

## Caso de uso

Enunciado 5 — Sistema de atención al cliente con IA.

> Una empresa recibe consultas de clientes por distintos canales y desea mejorar su proceso de atención utilizando asistencia basada en IA. El sistema debe registrar conversaciones, identificar consultas frecuentes, sugerir respuestas y derivar casos complejos a operadores humanos.
>
> Se desea diseñar una solución de datos que permita administrar clientes, consultas, tickets, estados de atención, operadores, respuestas sugeridas, derivaciones y tiempos de resolución. También deberá conservar el historial de interacciones para mejorar la atención futura y analizar la calidad del servicio.
>
> El sistema deberá contemplar distintos roles, como clientes, operadores, supervisores y administradores. También deberá registrar qué respuestas fueron generadas automáticamente, cuáles fueron enviadas por operadores y qué cambios ocurrieron durante la atención de cada caso.
>
> Algunos datos posibles: clientes, consultas, tickets, conversaciones, operadores, estados de atención, respuestas sugeridas, derivaciones, historial de casos, tiempos de resolución, canales de atención y evaluaciones de satisfacción.

## Descripción breve de la solución

Un núcleo relacional (`clientes`, `empleados`, `roles`, `tickets`, `ticket_logs`, `conversaciones`, `consultas`, `respuestas`) registra la atención de principio a fin: un ticket agrupa una o más conversaciones, cada conversación una o más consultas, y cada consulta puede acumular varias respuestas (sugerencia de IA, corrección humana, versión final), distinguiendo siempre origen automático u humano y marcando cuál fue la que efectivamente resolvió el caso. El historial de estados queda en `ticket_logs`, de solo inserción, así que el ciclo de vida completo de cada ticket es reconstruible y auditable. Sobre ese núcleo se propone un componente de búsqueda semántica con `pgvector` para identificar consultas frecuentes y sugerir respuestas a partir de casos ya resueltos, con el mismo modelo de permisos que protege el resto de los datos — de modo que la IA nunca pueda recuperar por similitud algo que el usuario que pregunta no podría ver por la vía relacional normal.

## Datos principales identificados

| Entidad                                              | Contenido                                                         | Para qué se usa                                        |
| ---------------------------------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------ |
| Cliente                                              | Identidad y contacto (DNI, email, teléfonos, dirección)           | Abrir y validar un ticket                              |
| Empleado / Rol                                       | Datos del empleado y su rol (operador, supervisor, administrador) | Asignación, permisos, indicadores por operador         |
| Ticket                                               | Cliente, empleado asignado, canal de origen, actividad            | Unidad de caso que atraviesa todos los canales         |
| Historial de estados (`ticket_logs`)                 | Ticket, empleado, fecha, estado alcanzado                         | Auditoría y cálculo de tiempos de resolución           |
| Conversación                                         | Ticket, fecha, calificación de satisfacción                       | Agrupa el intercambio y la evaluación del cliente      |
| Consulta                                             | Conversación, texto de la pregunta                                | Unidad mínima sobre la que la IA busca casos similares |
| Respuesta                                            | Consulta, texto, origen (humano/IA), si es la final               | Trazabilidad de qué se respondió y quién lo generó     |
| Índice semántico (`consultas_embeddings`, propuesto) | Pregunta y respuesta final vectorizadas, con metadatos            | Búsqueda por similitud sin recalcular en cada consulta |

Detalle completo del relevamiento y de los riesgos identificados (R1-R8) en `docs/informe.md`, puntos 1 y 2.

## Tecnología propuesta

**PostgreSQL 16** (imagen `pgvector/pgvector:pg16` en `docker-compose.yml`) con la extensión **pgvector** habilitada sobre el mismo motor para la búsqueda semántica. No se incorpora ningún motor NoSQL adicional: el dominio es mayormente tabular, con relaciones estables y reglas de integridad estrictas, y el único componente que se beneficia de un enfoque no relacional (el texto libre de preguntas y respuestas) se resuelve con pgvector dentro del propio PostgreSQL. Justificación completa frente a MongoDB, Cassandra, Neo4j, Redis y una base vectorial dedicada en `docs/informe.md`, punto 7. La capa de seguridad (`db/fisico/05_seguridad_permisos.sql`) se verificó además contra una instancia de PostgreSQL 18 durante el desarrollo — el motor de despliegue del proyecto sigue siendo la versión 16 declarada arriba; detalle en el punto 13 del informe.

## Estructura del repositorio

```
BDIA/
├── README.md
├── CLAUDE.md
├── docker-compose.yml
├── docs/
│   ├── informe.md                                        # entregable central, 15 secciones
│   ├── 09_datos_semiestructurados_no_estructurados_vectorial.md   # desarrollo completo del punto 9
│   └── 10_arquitectura_de_datos.md                        # desarrollo completo del punto 10
├── data/
│   └── 03_datos_ejemplo.sql                                # carga de datos sintéticos
├── db/
│   ├── conceptual/          # diagrama ER y restricciones de dominio
│   ├── logico/               # diagrama lógico y restricciones de integridad tabla por tabla
│   ├── fisico/                # scripts ejecutables: tablas, índices, validaciones, seguridad
│   └── consultas/            # consultas SQL representativas
├── vectorial/
│   └── modelo_vectorial.md   # propuesta del componente pgvector (consultas_embeddings)
├── nosql/                    # vacío — no se incorpora ningún motor NoSQL (ver punto 7)
└── anexos/                   # material complementario
```

## Instrucciones para ejecutar o revisar la implementación mínima

Levantar la base (PostgreSQL 16 + pgvector en `:5432`, pgAdmin en `:8080`; credenciales `postgres`/`postgres`, base `bdia`):

```bash
docker compose up -d
```

Ejecutar los scripts en este orden — es el orden de dependencia, no solo de numeración:

```bash
docker exec -i bdia_postgres psql -U postgres -d bdia < db/fisico/01_creacion_tablas.sql
docker exec -i bdia_postgres psql -U postgres -d bdia < db/fisico/02_indices_vistas.sql
docker exec -i bdia_postgres psql -U postgres -d bdia < data/03_datos_ejemplo.sql
docker exec -i bdia_postgres psql -U postgres -d bdia < db/fisico/04_validaciones.sql
docker exec -i bdia_postgres psql -U postgres -d bdia < db/fisico/05_seguridad_permisos.sql
```

`04_validaciones.sql` corre trece pruebas automáticas y termina en `ROLLBACK`, así que puede ejecutarse repetidamente sin alterar los datos de ejemplo. `05_seguridad_permisos.sql` es aditivo (no modifica 01/02/04): crea los roles de PostgreSQL, las políticas de Row Level Security y los `GRANT` descriptos en el punto 13 del informe.

Hay un segundo archivo con prefijo `05` en una carpeta distinta, `db/consultas/05_consultas_representativas.sql` — no forma parte de la secuencia de creación, son las consultas de ejemplo (8 en total) y puede ejecutarse en cualquier momento después de cargar los datos:

```bash
docker exec -i bdia_postgres psql -U postgres -d bdia < db/consultas/05_consultas_representativas.sql
```

## Principales decisiones de diseño

- **Núcleo relacional normalizado hasta 3FN**, con dos desnormalizaciones intencionales y documentadas: `tickets.id_empleado` (evita recalcular la asignación vigente desde `ticket_logs` en la consulta más frecuente del sistema) y la tabla vectorial `consultas_embeddings` (evita un `JOIN` en caliente contra el núcleo en cada búsqueda por similitud). Detalle en el punto 6.
- **Motor único** — PostgreSQL + pgvector — en vez de un stack políglota, para no duplicar el modelo de permisos entre varios sistemas. Punto 7.
- **Nunca borrado físico**: baja lógica vía columna `activo` y `ON DELETE RESTRICT` en todas las claves foráneas; `ticket_logs` es además append-only (sin `UPDATE`/`DELETE` habilitado para ningún rol). Mitigación central del riesgo de pérdida de trazabilidad (R5).
- **Seguridad a nivel de motor, no de aplicación**: roles nativos de PostgreSQL + Row Level Security + `GRANT` a nivel de columna, implementados y probados contra una instancia real (`db/fisico/05_seguridad_permisos.sql`). El sistema de IA es un actor con permisos propios que opera con las restricciones del usuario que dispara la consulta, para no abrir una vía de acceso semántica que esquive el control relacional. Punto 13.
- **Arquitectura por capas dentro de un único PostgreSQL** (crudo, operacional, IA, analítico como esquemas separados) en lugar de un Data Warehouse, Data Lake o Lakehouse, evaluados y descartados por resolver problemas que este caso no tiene a su volumen. Punto 12.

## Consultas incluidas

`db/consultas/05_consultas_representativas.sql` tiene 8 consultas; el punto 10 del informe documenta 5 (la 1, 3, 7, 8 y 4 de ese archivo, en ese orden) cubriendo las categorías pedidas:

1. Selección y filtrado — tickets pendientes de un operador.
2. Información relacionada (JOINs) — conversación completa de un ticket con sus consultas y respuestas.
3. Agregación / indicadores — proporción de respuestas finales de IA vs. humanas.
4. Toma de decisiones — carga de trabajo pendiente por operador.
5. Uso de índices/vistas — cantidad de tickets por canal y estado, sobre `vw_estado_actual_tickets`.

Las 3 restantes del archivo (historial completo de un ticket, tiempo promedio de resolución por canal, satisfacción promedio por operador) no están documentadas en el informe pero son igual de ejecutables.

## Limitaciones y posibles mejoras

- **El componente vectorial está completamente diseñado (`vectorial/modelo_vectorial.md`) pero no construido — y no por falta de tiempo, sino por una razón concreta.** La columna `embedding VECTOR(1536)` necesita vectores generados por un modelo de embeddings real (ej. OpenAI), no datos que se puedan escribir a mano. Sin acceso a ese modelo, las únicas alternativas eran dejar la tabla vacía (no demuestra nada que el diseño ya escrito no muestre) o completarla con vectores inventados (una búsqueda semántica "funcionando" sobre números al azar, engañosa en un trabajo evaluado por la solidez de la solución de datos) — se descartaron las dos. El diseño en sí ya resuelve RLS (columnas propias `id_cliente`/`id_ticket`, puntos 6.3b y 13), trazabilidad IA/humano, vigencia sin `DELETE` físico y reindexación idempotente. Aunque se generaran vectores reales, además, con el criterio de indexación correcto el corpus de casos elegibles hoy es de 2 sobre 10 tickets: no hay volumen para que aporte valor todavía. Falta, además, una regla de **auto-cierre** de tickets (`resuelto` sin reapertura durante N días → `cerrado`) sin la cual el corpus no tiene forma de crecer.
