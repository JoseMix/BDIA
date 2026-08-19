
### 1. Descripción del caso de uso
* **Problema a resolver:** una empresa recibe consultas de sus clientes por múltiples canales (chat web, correo electrónico, WhatsApp, teléfono y formulario web) y hoy los atiende de manera dispersa: cada canal deja su propio registro, no existe un identificador único de caso que atraviese la interacción completa y el conocimiento generado al resolver una consulta se pierde una vez finalizada la atención.

Esto presenta las siguientes limitaciones:

1. No hay reutilización del conocimiento: consultas equivalentes se responden desde cero una y otra vez, porque el histórico no es consultable por contenido sino, en el mejor de los casos, por fecha o por cliente.
2. No hay medición confiable de la calidad del servicio: Sin un registro estructurado de los cambios de estado de cada caso, no es posible calcular tiempos de resolución, volumen por canal, carga por operador ni satisfacción del cliente.
3. No hay trazabilidad: no queda registrado quién intervino en cada momento de la atención.

La empresa desea incorporar asistencia basada en IA para **sugerir respuestas a partir de casos históricos ya resueltos**, **identificar las consultas más frecuentes** y **derivar a un operador humano los casos complejos**, conservando en todo momento el histórico de interacciones para mejorar la atención futura y auditar la calidad del servicio.

* **Usuarios principales:** 

| Usuario | Qué hace en el sistema | Qué necesita del modelo de datos |
|---|---|---|
| **Cliente** | Inicia una consulta por alguno de los canales habilitados, recibe una respuesta y califica la atención al cierre | Identidad validada (DNI, email o teléfono), acceso al historial de sus propios casos únicamente |
| **Operador** | Atiende los tickets asignados, revisa las respuestas sugeridas por la IA, las corrige o redacta las propias, cambia el estado del caso | Ver la conversación completa de sus casos, las sugerencias disponibles y su cola de trabajo |
| **Supervisor** | Controla la calidad de la atención, redistribuye carga entre operadores y audita casos puntuales | Indicadores agregados (tiempos de resolución, satisfacción por operador y por canal, tickets pendientes) y acceso de lectura al detalle de cualquier caso del equipo |
| **Administrador** | Gestiona altas y bajas de empleados, roles, canales habilitados y parámetros del sistema | Acceso a las tablas maestras y al esquema |
| **Sistema de IA** | Lee casos históricos resueltos para sugerir respuestas y detectar consultas frecuentes; escribe respuestas sugeridas | Un subconjunto de datos acotado, **sólo de casos ya resueltos y validados**, con el texto anonimizado y con las mismas restricciones de acceso que aplican al usuario que dispara la consulta |

La distinción del sistema de IA como un usuario más (con sus propios permisos de lectura y escritura) es deliberada ya que si el modelo puede recuperar por similitud semántica un caso al que el operador no tendría acceso por la vía relacional habitual, el control de accesos queda vulnerado por una puerta lateral. 

* **Procesos y funcionalidades:** la solución de datos debe soportar los siguientes procesos:

1. **Identificación del cliente.** El cliente se autentica en la plataforma web o se identifica aportando datos privados (DNI, email o teléfono) al contactar por otro canal. Sus datos están validados al momento de generar el caso.
2. **Apertura de un ticket.** Todo contacto genera un ticket asociado obligatoriamente a un cliente, a un canal de origen tomado de un dominio predefinido y a un empleado responsable.
3. **Registro de la conversación.** Cada ticket agrupa una o más conversaciones, y cada conversación contiene una o más consultas concretas del cliente. Esta separación permite que un mismo caso incluya varias preguntas ("¿qué medios de pago aceptan?" y, a continuación, "¿puedo pagar en cuotas?") sin abrir un ticket nuevo por cada una.
4. **Generación de respuestas.** Una consulta puede acumular varias respuestas: la sugerencia automática de la IA, la corrección del operador y la versión efectivamente enviada al cliente. El modelo debe distinguir el **origen** de cada respuesta (automática o humana) y marcar **cuál fue la que resolvió** la consulta, con la regla de que sólo puede existir una respuesta final por consulta.
5. **Derivación y cambio de estado.** El caso atraviesa un flujo de estados (abierto → en proceso → resuelto → cerrado, con posibilidad de reapertura) y puede pasar de un operador a otro. Cada transición queda registrada con fecha y empleado responsable, de modo que el historial sea reconstruible y no sobrescribible.
6. **Cierre y evaluación de satisfacción.** Al finalizar, el cliente puede calificar la atención en una escala acotada. La calificación es opcional.
7. **Cálculo de indicadores de servicio.** A partir del historial de estados y de las calificaciones, el sistema debe permitir calcular tiempos de resolución por canal, carga pendiente por operador, distribución de casos por canal y estado, y proporción de respuestas resueltas automáticamente frente a las resueltas por una persona.
8. **Identificación de consultas frecuentes y sugerencia de respuestas.** Sobre el corpus de consultas ya resueltas y sus respuestas validadas, el sistema debe permitir búsquedas por similitud semántica para agrupar temas recurrentes y proponer respuestas a casos nuevos.
9. **Control de accesos por rol y preservación del historial.** Cada rol accede únicamente al subconjunto de datos que le corresponde, y ninguna baja de cliente, empleado o ticket puede destruir el historial de auditoría asociado.

### 2. Relevamiento de datos necesarios
* **Información requerida:** el relevamiento se organizó por entidad del dominio. 

| Entidad | Datos a almacenar | Por qué se necesita |
|---|---|---|
| **Cliente** | Nombre, apellido, DNI, email, teléfono principal y alternativo, dirección, estado de actividad | Identificar y validar al cliente al abrir un caso y contactarlo por el canal correspondiente. El DNI y el email son identificadores únicos del cliente en el sistema |
| **Empleado** | Nombre, apellido, DNI, departamento, rol asignado, estado de actividad | Asignar responsables a los casos, trazar quién intervino en cada cambio de estado y calcular indicadores por operador |
| **Rol** | Descripción del rol (operador, supervisor, administrador) | Definir el nivel de acceso y las funciones habilitadas para cada empleado. (Se modela como entidad propia para poder incorporar roles nuevos sin modificar el esquema) |
| **Ticket** | Cliente asociado, empleado responsable actual, canal de origen, estado de actividad | Es la unidad de caso que atraviesa todos los canales y da un identificador único a la atención completa |
| **Historial de estados (ticket log)** | Ticket, empleado que ejecuta el cambio, fecha y hora, estado alcanzado | Reconstruir el ciclo de vida del caso, auditar derivaciones entre operadores y calcular tiempos de resolución |
| **Conversación** | Ticket al que pertenece, fecha de inicio, calificación de satisfacción | Agrupar el intercambio dentro de un caso y capturar la evaluación del cliente al cierre |
| **Consulta** | Conversación a la que pertenece, texto de la pregunta del cliente | Es el texto en lenguaje natural que dispara la atención y la unidad mínima sobre la que la IA busca casos similares |
| **Respuesta** | Consulta a la que responde, texto de la respuesta, indicador de origen (humano o automático), indicador de respuesta final | Distinguir sugerencia de IA, corrección humana y respuesta efectivamente enviada |
| **Índice semántico** | Texto de la pregunta y de la respuesta final, canal de origen, vector de embedding, modelo utilizado, fecha de indexación, referencia a la consulta y respuesta de origen | Habilitar la búsqueda por similitud sin recalcular el embedding en cada consulta y sin bloquear las tablas operativas. Es un dato derivado, reconstruible a partir del núcleo transaccional |

* **Riesgos asociados:** 
| # | Riesgo | Descripción | Mitigación prevista en el diseño |
|---|---|---|---|
| R1 | **Exposición de datos personales** | El modelo almacena DNI, email, teléfono y dirección de personas físicas. Una consulta mal filtrada expone información sensible | Control de accesos por rol nativo del motor y *Row Level Security*, de modo que el filtro no dependa de que la aplicación lo recuerde aplicar |
| R2 | **Fuga de datos sensibles por vía semántica** | El cliente puede pegar su DNI, su email o datos de su tarjeta dentro del texto libre de la consulta. Ese texto se vectoriza e indexa, y luego puede reaparecer como "respuesta sugerida" ante un caso de otro cliente | Anonimizar/enmascarar el texto antes de generar el embedding |
| R3 | **Sugerencia de información incorrecta o desactualizada** | Si una respuesta final se corrige después de haber sido indexada, el índice semántico sigue sugiriendo la versión anterior. El sistema propaga entonces una respuesta que la empresa ya invalidó | Reindexación asíncrona ante cualquier modificación del texto de una respuesta final; indexar únicamente respuestas marcadas como finales de casos ya resueltos, nunca sugerencias intermedias o descartadas |
| R4 | **Contaminación del corpus de conocimiento** | La respuesta marcada como final es la que alimenta las sugerencias futuras | Restricción de unicidad de respuesta final por consulta, marca explícita de origen humano o automático y trazabilidad hacia el empleado responsable, para poder auditar |
| R5 | **Pérdida de trazabilidad por borrado físico** | Eliminar un cliente, un empleado o un ticket destruiría el historial de auditoría asociado y falsearía retroactivamente los indicadores de servicio | Borrado lógico mediante el campo `activo` y políticas `ON DELETE RESTRICT` en todas las claves foráneas: ninguna baja puede arrastrar historial |
| R6 | **Inconsistencia de dominio en campos categóricos** | Canales y estados cargados como texto libre derivan en valores equivalentes escritos de distinta forma ("WhatsApp", "whatsapp", "wsp"), que rompen silenciosamente toda agregación por canal o por estado | Dominios cerrados verificados por restricciones `CHECK` a nivel de motor |
| R7 | **Transferencia de datos a un proveedor externo de embeddings** | El texto de las consultas sale de la infraestructura de la empresa | Anonimización previa y, como alternativa evaluable, uso de un modelo de embeddings autoalojado si el volumen o la sensibilidad lo justifican |
| R8 | **Sesgo en los indicadores de desempeño** | Los indicadores por operador (satisfacción promedio, carga pendiente) pueden usarse para evaluar personas sin considerar la complejidad diferencial de los casos ni el volumen de calificaciones recibidas | Exponer siempre el indicador junto a su denominador (cantidad de conversaciones calificadas) y documentar que se trata de una señal de proceso, no de una calificación individual concluyente |

### 3. Clasificación de los datos según su tipo
Clasificación detallada de los datos del dominio según las siguientes categorías:
* **Estructurados:** [Ej. tablas relacionales].
* **Semiestructurados:** [Ej. documentos JSON, configuraciones].
* **No estructurados:** [Ej. texto libre, archivos, imágenes].
* **Operacionales:** [Datos del día a día de la aplicación].
* **Analíticos:** [Datos orientados al análisis y soporte de IA].
* **Sensibles:** [Datos que requieren protección especial].
* **De auditoría o trazabilidad:** [Logs y registros de eventos].

### 4. Modelo conceptual
* **Diagrama conceptual:** [Insertar o hacer referencia al diagrama conceptual (DER/UML)].
* **Descripción del dominio:** Justificación de las entidades principales, sus atributos relevantes, relaciones, cardinalidades y restricciones de negocio identificadas.

### 5. Modelo de implementación según la tecnología elegida
* **Detalle del modelo:** [Presentar el modelo correspondiente a la tecnología seleccionada (Tablas relacionales, Colecciones documentales, Familias de columnas, Nodos/Relaciones de Grafos, o Colecciones Vectoriales)].
* **Estructuras específicas:** Definición de claves primarias, foráneas, tipos de campos, restricciones de integridad e índices según aplique.

### 6. Decisiones de normalización, embebido, referencia o desnormalización

#### 6.1 Estrategia general

El núcleo transaccional de la solución (`clientes`, `empleados`, `roles`, `tickets`, `ticket_logs`, `conversaciones`, `consultas`, `respuestas`) se diseñó como un modelo **relacional normalizado hasta 3FN** en PostgreSQL. Sobre ese núcleo se propone una extensión híbrida con **pgvector** para indexar semánticamente las consultas históricas y sus respuestas finales, con el objetivo de identificar consultas frecuentes y sugerir respuestas (detalle en `vectorial/modelo_vectorial.md`). Esta combinación permite aplicar, dentro del mismo motor de base de datos, los dos enfoques que pide la consigna: normalización clásica para el registro operativo del caso, y decisiones de embebido/referencia/desnormalización propias del mundo NoSQL para el componente de recuperación semántica.

#### 6.2 Normalización del núcleo relacional

El detalle tabla por tabla está documentado en `db/logico/restricciones.md`. Que en resumen se detalla:

- **1FN — valores atómicos, sin grupos repetidos.** Se cumple en las 8 tablas: no existen columnas que almacenen listas (`clientes` separa `telefono_1` y `telefono_2` en vez de un campo concatenado), y toda fila se identifica por una PK simple autonumérica.
- **2FN — dependencia funcional completa de la clave.** Se cumple trivialmente porque ninguna tabla usa clave primaria compuesta: no hay relaciones muchos-a-muchos en el dominio (cada `ticket` tiene un único `cliente` y, en un momento dado, un único `empleado` asignado; cada `respuesta` pertenece a una única `consulta`), por lo que no existen tablas intermedias con dependencias parciales que resolver.
- **3FN — sin dependencias transitivas.** Se revisó cada tabla buscando atributos no clave que dependieran de otro atributo no clave. El caso límite analizado fue `empleados.departamento`: se descartó como dependencia transitiva de `id_rol` porque un mismo rol puede existir en más de un departamento, por lo que `departamento` es un atributo propio del empleado y no un dato derivable del rol.

**Problemas que esta normalización evita, con ejemplos concretos del dominio:**

| Problema | Qué pasaría sin normalizar | Cómo lo evita el diseño |
|---|---|---|
| Redundancia | Repetir `nombre`/`apellido` del empleado en cada fila de `ticket_logs` (una por cada cambio de estado de cada ticket) | `ticket_logs.id_empleado` referencia a `empleados`; el nombre se guarda una sola vez |
| Anomalía de inserción | No poder dar de alta un `rol` nuevo hasta que exista un empleado con ese rol, si el rol viviera como texto suelto dentro de `empleados` | `roles` es una entidad propia; se puede crear un rol sin empleados asignados todavía |
| Anomalía de actualización | Si la descripción de un rol se repitiera en cada empleado, cambiar el nombre de un rol obligaría a actualizar N filas, con riesgo de dejar alguna desactualizada | `empleados.id_rol` es FK a `roles`; la descripción se actualiza en un único lugar |
| Anomalía de eliminación | Si `consultas`/`respuestas` fueran columnas embebidas en `tickets`, cerrar o depurar un ticket podría arrastrar la pérdida de toda la conversación | Cada entidad tiene su propio ciclo de vida y PK; además se usa *soft delete* (`activo = false`) en vez de `DELETE` físico |
| Inconsistencia de dominio | `canal_origen` como texto libre permitiría valores como "WhatsApp"/"whatsapp"/"wsp" | `CHECK (canal_origen IN (...))` fija un dominio cerrado de valores válidos |

#### 6.3 Desnormalización controlada

Se identificaron dos desnormalizaciones **intencionales**, documentadas y justificadas por patrón de consulta, no por descuido de diseño:

**a) `tickets.id_empleado` (asignación actual) frente al histórico de `ticket_logs`.** El empleado asignado actualmente a un ticket se refleja tanto en `tickets.id_empleado` como, implícitamente, en la última fila de `ticket_logs` de ese ticket.
- *Ventaja:* la consulta más frecuente del sistema —"¿qué tickets tiene asignados cada operador ahora mismo?"— se resuelve con un filtro directo sobre `tickets`, sin calcular por cada ticket cuál es su log más reciente.
- *Compromiso:* ambos valores deben mantenerse sincronizados (toda reasignación debe escribirse en ambas tablas, idealmente en la misma transacción). Se acepta este costo de escritura porque un ticket se reasigna pocas veces pero se consulta su estado actual constantemente.

**b) Índice vectorial de consultas/respuestas frecuentes (extensión pgvector).** Para identificar consultas frecuentes y sugerir respuestas, se decidió mantener una tabla desnormalizada de solo lectura (`consultas_embeddings`) que **referencia** la fila de origen (`id_consulta`/`id_respuesta`, para trazabilidad) pero **duplica (embebe)** una copia normalizada del texto de la pregunta y de la respuesta final junto a su vector, en lugar de resolver esto con un `JOIN` en caliente contra `consultas`/`respuestas`.
- *Ventaja:* las búsquedas de similitud —potencialmente muy frecuentes si se ejecutan por cada consulta entrante— no compiten por bloqueos ni I/O con las tablas operativas, y se benefician de un índice `HNSW` dedicado.
- *Compromiso:* si el texto original se corrige después de indexado, el contenido embebido queda desactualizado hasta la próxima reindexación (proceso batch o disparado por evento). Se acepta **consistencia eventual** en este componente puntual, mientras el núcleo transaccional (estado del ticket, quién respondió, calificación) mantiene consistencia fuerte en todo momento. Esta es la misma lógica de "desnormalización controlada" propia de NoSQL, aplicada dentro del motor relacional gracias a pgvector.

#### 6.4 Cómo la estructura responde a los patrones de consulta esperados

- *Selección y filtrado operativo* (tickets abiertos de un cliente, por canal o por operador) → índices sobre `tickets.id_cliente`, `tickets.id_empleado`, `tickets.canal_origen`.
- *Reconstrucción de una conversación completa* → cadena de JOINs `clientes → tickets → conversaciones → consultas → respuestas`, con integridad referencial garantizada.
- *Indicadores de calidad de servicio* (tiempos de resolución, satisfacción promedio por canal/operador) → agregaciones (`GROUP BY`, `AVG`) sobre `ticket_logs.fecha` y `conversaciones.calificacion`.
- *Auditoría de respuestas automáticas vs. humanas* → `respuestas.es_humano` y `respuestas.es_respuesta_final`, con la regla de unicidad de respuesta final por consulta.
- *Identificación de consultas frecuentes / sugerencia de respuestas* → `ORDER BY embedding <-> query_vector LIMIT N` sobre `consultas_embeddings`, combinable con filtros SQL convencionales en la misma sentencia.

### 7. Justificación de la tecnología seleccionada

#### 7.1 Tecnología elegida

**PostgreSQL** como motor único, con la **extensión `pgvector`** habilitada sobre el mismo motor para el componente de búsqueda semántica. No se incorpora ningún motor NoSQL adicional (documental, clave-valor, columnar o de grafos) como parte del sistema de registro.

#### 7.2 Justificación según los criterios de la consigna

- **Tipo de datos a almacenar.** El dominio combina datos estructurados con reglas de negocio estrictas (clientes, empleados, tickets, estados) con una porción de texto libre en lenguaje natural (`consultas.pregunta`, `respuestas.texto_respuesta`). Esta última porción es la única candidata a tratamiento vectorial (ver punto 11); el resto del dominio es naturalmente tabular.

- **Estructura y variabilidad de los datos.** El esquema es estable, los canales de atención, los estados de ticket y los roles son un conjunto cerrado y conocido de antemano (reforzado con `CHECK`), no datos que cambien de forma en cada registro. Esto favorece un esquema fijo y tipado por sobre un esquema flexible tipo documento.

- **Volumen esperado.** Es un sistema de atención al cliente pensado para empresas con un volumen de consultas bajo a mediano, no una plataforma de escala masiva (redes sociales, IoT). El volumen de tickets/consultas/respuestas es alto pero manejable por PostgreSQL.

- **Patrones de consulta.** Conviven tres patrones: transaccional (OLTP) sobre un ticket puntual, analítico/agregado para reportes de calidad de servicio (JOINs, `GROUP BY`, funciones de ventana), y búsqueda por similitud para sugerencia de respuestas. PostgreSQL + pgvector resuelve los tres dentro de un mismo motor y una misma transacción, evitando construir y sincronizar sistemas separados.

- **Relaciones entre entidades.** Son numerosas, jerárquicas y bien definidas (`cliente → ticket → conversación → consulta → respuesta`, `empleado → rol`), con reglas de integridad estrictas (una respuesta no puede existir sin una consulta; una consulta sólo puede tener una respuesta marcada como final). Este tipo de reglas se expresa de forma nativa con `FOREIGN KEY`, `CHECK` y transacciones; en un modelo documental habría que reimplementarlas a nivel aplicación, con mayor riesgo de inconsistencia.

- **Consistencia requerida.** El estado de un ticket, quién lo atendió y la calificación de satisfacción alimentan reportes de gestión: requieren consistencia fuerte y transacciones ACID. El único componente donde se acepta consistencia eventual es el índice vectorial de sugerencias, que no es fuente de verdad sino una ayuda de recuperación.

- **Seguridad y control de acceso.** El caso exige aislar lo que puede ver cada rol (cliente, operador, supervisor, administrador). PostgreSQL permite resolver esto con **roles nativos + Row Level Security (RLS)**, aplicando el control a nivel de motor en lugar de depender exclusivamente de que la aplicación recuerde aplicar el filtro correcto.

- **Necesidades de escalabilidad.** Moderadas en el estado actual, con margen de crecimiento vía escalabilidad vertical inmediata y, si es necesario, horizontal (réplicas de lectura, particionamiento). No se justifica, a esta escala, la complejidad de un sistema distribuido tipo Cassandra.

- **Complejidad operativa.** Un único motor para lo transaccional, lo analítico básico y lo vectorial reduce la cantidad de piezas de infraestructura a desplegar, respaldar, monitorear y asegurar, frente a combinar PostgreSQL + MongoDB + una base vectorial dedicada. Se optó por la combinación mínima que cubre los requerimientos reales del caso.

**Ventajas y limitaciones frente a otras alternativas:**

| Alternativa | Por qué no se adoptó como base para este caso |
|---|---|
| MongoDB (documental) | El dominio tiene relaciones estables y reglas de integridad estrictas. Modelarlo como documentos obligaría a duplicar datos de cliente/empleado en cada documento relacionado, reproduciendo los problemas de redundancia y actualización que la normalización busca evitar. |
| Cassandra (columnar) | Pensada para volúmenes de escritura muy altos con consultas conocidas de antemano por clave de partición (streams de eventos/sensores). Este caso no tiene ese perfil de escritura y prioriza consistencia fuerte sobre disponibilidad extrema, lo opuesto al compromiso CAP típico de Cassandra. |
| Neo4j (grafos) | Las relaciones del dominio tienen profundidad conocida y acotada (pocos saltos de FK), no recorridos de longitud variable ni preguntas tipo "camino más corto". Un grafo agregaría complejidad de modelado sin resolver mejor los patrones de acceso reales. |
| Redis (clave-valor) | Útil como complemento futuro (caché de respuestas frecuentes, estado temporal de una conversación en curso, *rate limiting*) pero no como sistema de registro: no ofrece integridad referencial ni consultas relacionales. Se deja como posible mejora de escalabilidad, no como parte del núcleo. |
| Base vectorial dedicada (Pinecone, Weaviate, Milvus, etc.) | Sumaría un segundo sistema a operar, sincronizar y asegurar por separado, con riesgo de que los metadatos de permisos queden desacoplados de la base transaccional. Con el volumen esperado, `pgvector` dentro de PostgreSQL cubre la necesidad sin ese costo operativo y sin duplicar el modelo de permisos. |
| **PostgreSQL + pgvector (adoptada)** | Cubre en un solo motor, integridad referencial y transacciones ACID para el núcleo operativo, consultas analíticas complejas para reportes de calidad de servicio, y búsqueda por similitud para consultas frecuentes/respuestas sugeridas — con un único modelo de seguridad (roles + RLS) aplicado de forma consistente a todos los datos, incluidos los vectores. |

#### 7.3 Límites reconocidos de la elección

Se reconoce que, si el volumen de búsquedas semánticas creciera órdenes de magnitud (por ejemplo, si la solución se ofreciera como plataforma multi-tenant a muchas empresas), podría justificarse migrar el componente vectorial a un motor dedicado. A la escala del caso propuesto (una empresa gestionando su propia atención al cliente), esa complejidad adicional no se justifica hoy.

### 8. Implementación mínima realizada

#### 8.1 Alcance de la implementación

La implementación mínima se realizó en **PostgreSQL 16** sobre una base de datos denominada `bdia`. Se construyó el núcleo relacional completo definido en el modelo lógico, compuesto por las tablas `roles`, `clientes`, `empleados`, `tickets`, `ticket_logs`, `conversaciones`, `consultas` y `respuestas`.

La estructura física incluye:

- Identificadores autonuméricos mediante columnas `IDENTITY`;
- Claves primarias y foráneas para garantizar la integridad referencial;
- Restricciones `NOT NULL`, `UNIQUE` y `CHECK` para controlar los dominios;
- Políticas `ON DELETE RESTRICT` y `ON UPDATE CASCADE` en las relaciones;
- Borrado lógico mediante el campo `activo` en clientes, empleados y tickets;
- Nueve índices para claves foráneas y patrones de consulta frecuentes;
- Un índice único parcial que garantiza una sola respuesta final por consulta;
- Una vista que presenta el cliente, empleado asignado y último estado de cada ticket.

La extensión `pgvector` y la tabla `consultas_embeddings` se mantienen como propuesta del componente vectorial descripto en el punto 11; no forman parte del núcleo transaccional mínimo implementado en esta etapa.

#### 8.2 Scripts desarrollados

Los archivos deben ejecutarse respetando el siguiente orden:

1. `db/fisico/01_creacion_tablas.sql`: Crea las ocho tablas, sus tipos de datos, claves y restricciones de integridad.
2. `db/fisico/02_indices_vistas.sql`: Crea los índices de rendimiento, la restricción de respuesta final única y la vista `vw_estado_actual_tickets`.
3. `data/03_datos_ejemplo.sql`: Carga el conjunto sintético utilizado para comprobar las relaciones y consultas.
4. `db/fisico/04_validaciones.sql`: Ejecuta trece pruebas automáticas sobre las estructuras creadas.

Todos los scripts utilizan transacciones. Los tres primeros finalizan con `COMMIT` para evitar una implementación parcialmente cargada ante un error. El script de validaciones finaliza con `ROLLBACK`, ya que realiza inserciones y actualizaciones intencionalmente inválidas para comprobar las restricciones sin alterar los datos de ejemplo.

### 9. Datos de ejemplo utilizados

#### 9.1 Estructura de prueba

Se generó un conjunto de datos completamente **sintético**, sin información personal real, con el siguiente volumen:

| Tabla | Registros | Casos representados |
|---|---:|---|
| `roles` | 3 | Operador, supervisor y administrador |
| `empleados` | 5 | Operadores de distintas áreas, un supervisor y un administrador |
| `clientes` | 6 | Clientes con datos de contacto obligatorios y opcionales |
| `tickets` | 10 | Todos los canales admitidos y un caso de borrado lógico |
| `ticket_logs` | 31 | Estados abiertos, en proceso, resueltos, cerrados y reabiertos |
| `conversaciones` | 10 | Casos con y sin calificación de satisfacción |
| `consultas` | 12 | Conversaciones con una o varias preguntas |
| `respuestas` | 17 | Respuestas de IA, humanas, intermedias y finales |

Los datos permiten representar tickets en distintas etapas del ciclo de vida, derivaciones entre operadores, diferentes canales de atención, conversaciones pendientes y finalizadas, calificaciones entre 1 y 5 y consultas con múltiples respuestas. Los identificadores se establecieron explícitamente para facilitar la lectura de las relaciones y, al finalizar la carga, se sincronizaron las secuencias autonuméricas para permitir nuevas inserciones.

#### 9.2 Validación de coherencia

El archivo `db/fisico/04_validaciones.sql` comprueba automáticamente:

- La existencia de las ocho tablas y las cantidades esperadas de datos;
- La unicidad del DNI de los clientes;
- La obligatoriedad del correo electrónico;
- El rechazo de claves foráneas inexistentes;
- Los dominios cerrados de canales y calificaciones;
- El rechazo de consultas vacías;
- La regla de una sola respuesta final por consulta;
- La aplicación de valores predeterminados;
- La conservación del historial mediante borrado lógico;
- El cálculo correcto del último estado a través de la vista;
- La existencia del índice único parcial y de la vista implementada.

Cada prueba informa un mensaje `OK` cuando PostgreSQL rechaza o procesa el caso de la forma esperada. Como el script completo finaliza con `ROLLBACK`, los registros temporales utilizados en las pruebas no permanecen almacenados.

### 10. Consultas representativas
Breve explicación de la utilidad de cada una de las 5 consultas mínimas requeridas, adjuntando el código correspondiente:
1. **Consulta 1 (Selección y filtrado):** ¿Qué tickets tiene pendiente cierto operador? Muestra los trabajos que todavía tiene por terminar el operador.

```sql
SELECT id_ticket, cliente, canal_origen, estado_actual, fecha_ultimo_estado 
FROM vw_estado_actual_tickets 
WHERE id_empleado = 3 AND activo = TRUE AND estado_actual IN ('abierto', 'en_proceso', 'reabierto') 
ORDER BY fecha_ultimo_estado;
```


2. **Consulta 2 (Información relacionada / JOINs):** Esta consulta responde a la pregunta: ¿Qué consultas realizó un cliente y qué respuestas fueron generadas por IA o enviadas por una persona?

```sql
SELECT t.id_ticket, CONCAT_WS(' ', c.nombre, c.apellido) AS cliente, conv.id_conversacion, q.id_consulta, q.pregunta, resp.id_respuesta, resp.texto_respuesta,
       CASE
           WHEN resp.es_humano = TRUE THEN 'Humana' 
           ELSE 'IA'
       END AS origen_respuesta, resp.es_respuesta_final 
FROM tickets AS t 
INNER JOIN clientes AS c ON c.id_cliente = t.id_cliente 
INNER JOIN conversaciones AS conv ON conv.id_ticket = t.id_ticket
INNER JOIN consultas AS q ON q.id_conversacion = conv.id_conversacion 
LEFT JOIN respuestas AS resp ON resp.id_consulta = q.id_consulta 
WHERE t.id_ticket = 9 
ORDER BY q.id_consulta, resp.id_respuesta;
```

3. **Consulta 3 (Agregaciones / Indicadores):** Esta consulta responde el porcentaje de respuestas finales de IA y humanas.

```sql
SELECT 
    CASE 
        WHEN es_humano = TRUE THEN 'Humana' 
        ELSE 'IA' END AS origen_respuesta, 
        COUNT(*) AS cantidad_respuestas_finales, 
        ROUND( 100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2 ) AS porcentaje 
FROM respuestas 
WHERE es_respuesta_final = TRUE
GROUP BY es_humano 
ORDER BY cantidad_respuestas_finales DESC;
```

4. **Consulta 4 (Toma de decisiones):** Esta consulta responde la carga de trabajo pendiente por cada operador. Para que el supervisor pueda ver cuanto
trabajo tiene cada operador y asignar tareas en base a ello.

```sql
SELECT 
    e.id_empleado, 
    CONCAT_WS(' ', e.nombre, e.apellido) AS operador, 
    COUNT(actual.id_ticket) AS tickets_pendientes 
FROM empleados AS e 
INNER JOIN roles AS r ON r.id_rol = e.id_rol 
LEFT JOIN vw_estado_actual_tickets AS actual ON actual.id_empleado = e.id_empleado AND actual.activo = TRUE AND actual.estado_actual IN ('abierto', 'en_proceso', 'reabierto') 
WHERE r.descripcion = 'Operador' AND e.activo = TRUE 
GROUP BY e.id_empleado, e.nombre, e.apellido 
ORDER BY tickets_pendientes DESC, operador;
```

5. **Consulta 5 (Optimización mediante Índices/Vistas):** La vista vw_estado_actual_tickets evita repetir en cada consulta los JOIN necesarios para relacionar tickets, clientes, empleados, roles y el último registro de ticket_logs. Esto simplifica las consultas operativas y centraliza la lógica utilizada para determinar el estado actual de cada ticket. Además, la búsqueda del último registro se optimiza mediante el índice compuesto idx_ticket_logs_ticket_fecha, que busca por ticket y el orden descendiente de la fecha.

```sql
SELECT canal_origen, estado_actual, COUNT(*) AS cantidad_tickets 
FROM vw_estado_actual_tickets 
WHERE activo = TRUE 
GROUP BY canal_origen, estado_actual0
ORDER BY canal_origen, cantidad_tickets DESC;
```

### 11. Propuesta para datos semiestructurados, no estructurados o vectoriales
* **Manejo de datos complejos:** [Analizar la conveniencia de usar formatos JSON/JSONB, colecciones NoSQL u otras estrategias en la solución principal].
* **Enfoque vectorial y búsquedas semánticas:** Justificación del uso (o no) de una base vectorial, indicando qué datos se vectorizarían, metadatos asociados, consultas por similitud deseadas y mitigación de riesgos de información incorrecta o no autorizada.

### 12. Propuesta de arquitectura de datos
* **Diagrama de arquitectura:** [Insertar o hacer referencia al diagrama de arquitectura general].
* **Flujo y componentes:** Justificación del ciclo de vida de los datos desde la ingesta hasta el consumo por la IA, argumentando la elección de un enfoque simple o estructurado (Data Warehouse, Data Lake, Lakehouse, etc.).

### 13. Estrategia de seguridad, permisos y aislamiento
* **Control de accesos:** Matriz o definición de roles, usuarios y permisos.
* **Mecanismos de aislamiento:** Explicación técnica de cómo garantizar el aislamiento entre tenants, empresas o usuarios según el caso.
* **Mitigación de riesgos en IA:** Estrategia para evitar la exposición indebida de datos sensibles a través de interfaces de lenguaje natural o asistentes inteligentes.

### 14. Consideraciones de escalabilidad y rendimiento
* **Puntos críticos de crecimiento:** Identificación de las estructuras que experimentarán mayor incremento de volumen de datos o consultas.
* **Estrategia de optimización:** Propuesta de índices necesarios, particionamiento de datos, precalculados o separación de componentes operacionales/analíticos.

### 15. Conclusiones
* **Balance del diseño:** Resumen de los principales hallazgos, lecciones aprendidas y compromisos asumidos entre rendimiento, consistencia, simplicidad y costo dentro de la solución de datos planteada.
