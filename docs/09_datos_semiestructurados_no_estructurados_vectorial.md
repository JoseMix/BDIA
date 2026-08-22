# Punto 9 — Datos semiestructurados, no estructurados y búsqueda vectorial

**Corresponde a:** sección 11 de `docs/informe.md` ("Propuesta para datos semiestructurados, no estructurados o vectoriales")

> **Nota de numeración.** El punto 9 de la consigna se corresponde con la **sección 11** del informe, no con la sección 9 ("Datos de ejemplo utilizados"). El propio informe ya remite a esa sección desde 7.2 y 8.1 ("ver punto 11", "el componente vectorial descripto en el punto 11").

---

## 1. Comprensión del caso

### 1.1 Descripción del proyecto

El proyecto es el **diseño de una solución de datos** (no una aplicación) para un sistema de atención al cliente asistido por IA. Una empresa recibe consultas por cinco canales —`chat`, `email`, `whatsapp`, `telefono`, `web`— y necesita: unificar el caso bajo un identificador único, registrar la conversación completa, distinguir qué respuestas generó la IA y cuáles una persona, trazar las derivaciones entre operadores, medir tiempos de resolución y satisfacción, y **reutilizar el conocimiento de casos ya resueltos para sugerir respuestas e identificar consultas frecuentes** (procesos 8 y 9 de la sección 1 del informe).

Lo que existe hoy en el repositorio es exclusivamente **modelo + SQL + documentación**:

| Componente | Estado real verificado |
|---|---|
| Modelo conceptual | `db/conceptual/conceptual_v2.0.png` + `restricciones.md` |
| Modelo lógico | `db/logico/logico_v.2.0.png` + `restricciones.md` (1FN–3FN, políticas de borrado) |
| Implementación física | `db/fisico/01_creacion_tablas.sql` — 8 tablas |
| Índices y vista | `db/fisico/02_indices_vistas.sql` — 9 índices + índice único parcial + `vw_estado_actual_tickets` |
| Datos de prueba | `data/03_datos_ejemplo.sql` — sintéticos |
| Validaciones | `db/fisico/04_validaciones.sql` — 13 pruebas, cierra con `ROLLBACK` |
| Consultas | `db/consultas/05_consultas_representativas.sql` — 8 consultas |
| Componente vectorial | `vectorial/modelo_vectorial.md` — **propuesta en papel, no implementada** |
| Infraestructura | `docker-compose.yml` — imagen `pgvector/pgvector:pg16` + pgAdmin |
| `nosql/`, `anexos/` | **vacíos** (`.gitkeep`, `material_complementario.md` de 0 bytes) |

**No existe código de aplicación**: no hay backend, ni ingesta de canales, ni cliente de un modelo de embeddings, ni proceso de indexación. Esto es relevante para el punto 9 porque significa que **hoy no hay ningún vector generado**: todo el componente semántico es diseño.

### 1.2 Datos identificados

Inventario real de los tipos de dato presentes en el esquema físico:

| Categoría | Qué hay concretamente en el proyecto |
|---|---|
| **Estructurados** | Prácticamente todo el esquema: `roles`, `clientes`, `empleados`, `tickets`, `conversaciones` (`calificacion` SMALLINT 1–5), `ticket_logs` (`estado` de dominio cerrado). Tipos fijos, dominios cerrados por `CHECK`, integridad por FK. |
| **Semiestructurados** | **Ninguno en el esquema actual.** No existe una sola columna `JSON`/`JSONB`, ni `ARRAY`, ni `hstore`, ni XML en `01_creacion_tablas.sql`. Los candidatos existen en el dominio pero están hoy sin representar (sección 2). |
| **No estructurados** | Exactamente **dos columnas**: `consultas.pregunta` (TEXT, `CHECK LENGTH > 0`) y `respuestas.texto_respuesta` (TEXT, `CHECK LENGTH > 0`). Texto libre en lenguaje natural del cliente y del operador/IA. |
| **De auditoría / eventos** | `ticket_logs` (31 filas de ejemplo): log de transiciones de estado con `id_ticket`, `id_empleado`, `fecha` TIMESTAMPTZ y `estado`. Es un log de eventos de negocio, pero **estructurado y de esquema fijo**. |
| **Operacionales** | Estado actual del ticket (vía `vw_estado_actual_tickets`), asignación vigente (`tickets.id_empleado`), cola pendiente por operador. |
| **Analíticos** | Derivados de agregación: tiempos de resolución por canal (consulta 5 del `.sql`), satisfacción por operador (consulta 6), % de respuestas finales IA vs. humanas (consulta 7), distribución canal × estado (consulta 4). |
| **Sensibles** | `clientes.dni`, `clientes.email`, `telefono_1`, `telefono_2`, `direccion`; `empleados.dni`. Y —crítico para este punto— **el contenido de `consultas.pregunta`, que es texto libre donde el cliente puede pegar datos personales** (riesgo R2 del informe). |
| **Derivados / reconstruibles** | El índice semántico propuesto (`consultas_embeddings`): el propio informe lo define como "dato derivado, reconstruible a partir del núcleo transaccional". |
| **Metadatos** | Los que existen hoy son banderas tipadas, no metadatos flexibles: `respuestas.es_humano`, `respuestas.es_respuesta_final`, `tickets.canal_origen`, `activo`. |

Esto completa, con evidencia del código, el cuadro que la sección 3 del informe dejó como plantilla vacía.

### 1.3 Fuentes de datos

| Fuente | Existe hoy | Observación |
|---|---|---|
| Cliente vía 5 canales | Sí, como **valor de `tickets.canal_origen`** | El canal se registra, pero **no se almacena nada propio de cada canal** (ver 2.1) |
| Operador humano | Sí | `respuestas.es_humano = TRUE`, `ticket_logs.id_empleado` |
| Sistema de IA | Sí, como bandera | `respuestas.es_humano = FALSE`. En los datos de ejemplo genera 10 de 17 respuestas |
| Administrador / tablas maestras | Parcial | `roles` con 3 filas; **no existe tabla de parámetros del sistema** aunque el informe atribuye al administrador "parámetros del sistema" |
| Corpus histórico de casos resueltos | Sí | 10 respuestas finales sobre 12 consultas. **Es la única fuente candidata a vectorización** |
| Base de conocimiento / FAQ / manuales | **No existe** | Ni tabla, ni archivos. Sería la fuente vectorizable más natural en un sistema real — lo marco explícitamente como **hipotético** |

### 1.4 Tecnologías y almacenamiento actual

- **PostgreSQL 16**, motor único, base `bdia`, desplegado con Docker Compose.
- La imagen elegida es **`pgvector/pgvector:pg16`**: la infraestructura ya viene preparada para vectores, pero `01_creacion_tablas.sql` **no ejecuta `CREATE EXTENSION vector` ni crea `consultas_embeddings`**. El informe lo reconoce explícitamente en 8.1. No hay contradicción, pero sí una brecha entre infraestructura lista y esquema sin usarla.
- Sin motor NoSQL: la decisión está justificada en la sección 7.2 del informe (MongoDB, Cassandra, Neo4j, Redis y bases vectoriales dedicadas evaluadas y descartadas). El directorio `nosql/` está vacío, coherente con esa decisión.
- Persistencia: volumen Docker `postgres_data`. **No hay almacenamiento de archivos/objetos** de ningún tipo.
- Modelo de acceso: **RLS implementada sobre las 8 tablas del núcleo** (`db/fisico/05_seguridad_permisos.sql`: roles nativos, `CREATE POLICY`, `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`, probado contra Postgres real — sección 13). Falta únicamente sobre `consultas_embeddings`, que no existe físicamente todavía.

---

## 2. Datos semiestructurados

**Hallazgo central: hoy el proyecto no tiene ningún dato semiestructurado.** El esquema es enteramente tipado y con dominios cerrados. Lo que sigue son los cuatro lugares donde el dominio *sí* genera datos de forma variable y que hoy quedan sin capturar. Cada uno está marcado como *existe* o *podría incorporarse*.

### 2.1 Metadatos técnicos propios de cada canal — *podría incorporarse*

- **Dato:** identificadores y atributos que solo tienen sentido en un canal: `message_id` y cabeceras en email, `wa_id`/número normalizado en WhatsApp, duración y grabación en teléfono, `session_id`/user-agent/URL de origen en chat web, id de formulario en web.
- **Origen:** la pasarela de cada canal en el momento de la ingesta. Hoy la ingesta no existe; el único rastro es `tickets.canal_origen`.
- **Características:** **el conjunto de atributos cambia según el valor de `canal_origen`**. Un ticket de teléfono tiene `duracion_segundos` y no tiene `message_id`; uno de email al revés. Es el caso de libro de esquema variable — y el enunciado lo pide explícitamente al listar "canales de atención" como dato a administrar.
- **Representación propuesta:** columna `tickets.metadatos_canal JSONB NULL`, con índice GIN solo si se llega a filtrar por su contenido.
- **Justificación:** las alternativas son peores. (a) Cinco columnas nullables por canal → tabla ancha con 80% de NULLs y una anomalía nueva cada canal que se sume; (b) tabla EAV `ticket_atributos(id_ticket, clave, valor)` → pierde el tipado y obliga a pivotar en cada lectura; (c) cinco tablas de extensión `ticket_email`, `ticket_whatsapp`… → correcto en teoría pero cinco LEFT JOIN para un dato que se lee entero y casi nunca se consulta por partes. JSONB conserva la fila única, no obliga a migrar el esquema al habilitar un canal nuevo, y el `CHECK` sobre `canal_origen` sigue garantizando el dominio cerrado de lo que sí importa para las agregaciones. **La flexibilidad se acota deliberadamente a lo accesorio**: nada que alimente un indicador de gestión debe vivir dentro del JSONB.

### 2.2 Trazas de generación de la respuesta automática — *podría incorporarse*

- **Dato:** por cada fila con `respuestas.es_humano = FALSE`: modelo y versión usados, temperatura, tokens consumidos, latencia, score de confianza y —el más importante— **la lista de `id_consulta` históricos que se recuperaron y se usaron como contexto**.
- **Origen:** el subsistema de IA en el momento de generar la sugerencia.
- **Características:** semiestructurado y **versionado en el tiempo**. Cambiar de modelo de embeddings o de LLM cambia el conjunto de campos; guardar eso como columnas obliga a un `ALTER TABLE` por cada cambio de proveedor. El enunciado exige "registrar qué respuestas fueron generadas automáticamente"; hoy eso se cumple con un booleano, que dice *que* fue automática pero no *cómo*.
- **Representación propuesta:** `respuestas.metadatos_generacion JSONB NULL`, obligatorio por `CHECK` cuando `es_humano = FALSE`.
- **Justificación:** es el registro de auditoría que hace *auditable* la sugerencia. Sin la lista de casos recuperados no se puede responder "¿de dónde salió esta respuesta?" cuando la IA sugiere algo incorrecto — que es exactamente el riesgo R4 del informe ("contaminación del corpus"). Y es el único lugar donde se puede detectar **autofagia del corpus**: una sugerencia de IA construida sobre respuestas finales que también eran de IA. En los datos de ejemplo esto ya es material: **3 de las 10 respuestas finales son puramente de IA** (`id_respuesta` 3, 12 y 17) y ninguna pasó por revisión humana registrada.

### 2.3 Detalle del evento de derivación — *podría incorporarse (o resolverse relacionalmente)*

- **Dato:** el motivo por el cual un caso pasa de un operador a otro, y el par (de → a). Hoy `ticket_logs` guarda solo `estado`, `fecha` e `id_empleado`, y la derivación queda **implícita**: en el ticket 5, los logs 14 y 15 son ambos `en_proceso` pero cambia el `id_empleado` (1 → 2). Un lector reconstruye que hubo derivación por comparación de filas consecutivas, no porque el modelo lo diga. El enunciado pide "derivaciones" como dato de primera clase.
- **Origen:** el operador o el supervisor que reasigna.
- **Características:** un texto corto opcional (motivo) más dos referencias. **Aquí el diagnóstico honesto es que NO amerita JSONB**: el conjunto de atributos es fijo y conocido.
- **Representación propuesta:** columnas nuevas en `ticket_logs`: `id_empleado_anterior INTEGER NULL REFERENCES empleados`, `motivo TEXT NULL`. No JSONB.
- **Justificación:** lo incluyo precisamente **como contraejemplo**. Es un dato de baja frecuencia y estructura estable; meterlo en un JSONB solo porque "es texto variable" perdería la FK a `empleados` —y con ella la garantía de trazabilidad que el propio modelo defiende con `ON DELETE RESTRICT`— sin ganar nada. La flexibilidad de esquema se justifica por variabilidad real, no por comodidad.

### 2.4 Parámetros de configuración del sistema — *podría incorporarse*

- **Dato:** los "parámetros del sistema" que la sección 1 del informe atribuye al rol Administrador: umbral de similitud por debajo del cual no se sugiere nada, cantidad de sugerencias a devolver, canales habilitados, reglas de derivación automática, modelo de embeddings vigente.
- **Origen:** el administrador. **No existe ninguna tabla que lo soporte** — inconsistencia entre el informe y el esquema implementado.
- **Características:** claves heterogéneas con valores de tipos distintos (número, booleano, lista), de muy baja cardinalidad y muy baja frecuencia de escritura.
- **Representación propuesta:** tabla `parametros(clave TEXT PK, valor JSONB NOT NULL, descripcion TEXT, fecha_modificacion TIMESTAMPTZ)`.
- **Justificación:** una tabla con una columna por parámetro exigiría un `ALTER TABLE` por cada parámetro nuevo. `valor JSONB` permite tipos mixtos manteniendo la clave tipada e indexada por PK. El volumen es de decenas de filas: la eficiencia es irrelevante, lo que importa es no tocar el esquema para agregar un parámetro.

### 2.5 Lo que *parece* semiestructurado y no lo es

Conviene dejarlo explícito para no sobre-diseñar:

- **`ticket_logs` no es un log semiestructurado.** Es una tabla de eventos con esquema fijo y dominio cerrado (`CHECK estado IN (...)`). No hay payload variable. Sacarla a una colección de documentos o a un motor de logs sería un error: se perdería la FK a `empleados` que sostiene la auditoría y las agregaciones de la consulta 5 (`MIN(fecha) FILTER (WHERE estado = 'abierto')`) se volverían costosas.
- **`conversaciones.calificacion` no es semiestructurada.** Es un `SMALLINT` con `CHECK BETWEEN 1 AND 5`. La reseña *textual* que la acompañaría en un sistema real no existe en este modelo (ver 3.3).
- **Las relaciones del dominio no son "altamente conectadas".** La jerarquía es lineal y de profundidad fija: `cliente → ticket → conversación → consulta → respuesta`, más `empleado → rol`. Cuatro saltos de FK conocidos de antemano, sin recorridos de longitud variable ni preguntas de camino más corto. Coincide con lo que la sección 7.2 del informe argumenta para descartar Neo4j, y lo confirmo con el esquema en mano: **ninguna tabla tiene relación muchos-a-muchos**, no hay una sola tabla intermedia en las 8. Un grafo solo se justificaría ante una necesidad que hoy no existe —por ejemplo detectar clientes vinculados por compartir `telefono_1` o `direccion`, útil en antifraude— y eso es un caso **hipotético**, ajeno al enunciado.

---

## 3. Datos no estructurados

### 3.1 Texto de la consulta del cliente — *existe*

- **Dato:** `consultas.pregunta`. Ejemplos reales del proyecto: *"Como puedo restablecer mi contrasena?"*, *"El producto llego danado. Como solicito el cambio?"*, *"Mi caso fue cerrado pero el problema continua."*
- **Origen:** el cliente, por cualquiera de los cinco canales.
- **Características:** lenguaje natural, longitud variable, sin esquema interno, con faltas de ortografía y sin tildes en el corpus actual, y **con riesgo de contener datos personales** que el cliente pega por iniciativa propia (R2 del informe). Es no estructurado en sentido estricto: su significado no es accesible por ninguna operación relacional.
- **Representación propuesta:** **se queda donde está**, en `consultas.pregunta TEXT` dentro de PostgreSQL. Es la fuente de verdad. Sobre ella se construyen dos derivados: un índice léxico (`tsvector` + GIN) y, en el diseño propuesto, un embedding en tabla aparte.
- **Justificación:** el texto es corto (una o dos oraciones), pertenece inseparablemente a una fila con integridad referencial, y debe leerse siempre junto a su ticket y su cliente. Sacarlo a un almacenamiento documental externo rompería la transacción que crea consulta y respuesta juntas y duplicaría el modelo de permisos, que es justo lo que la sección 7.2 evita. `TEXT` en PostgreSQL usa TOAST de forma transparente: no hay ganancia de rendimiento en externalizarlo.

### 3.2 Texto de la respuesta — *existe*

- **Dato:** `respuestas.texto_respuesta`, con dos subpoblaciones que el modelo distingue por `es_humano`: sugerencias de IA (*"La IA sugiere iniciar un reclamo por producto danado."*) y respuestas humanas (*"Se genero el reclamo y se coordino el reemplazo sin costo."*).
- **Origen:** el subsistema de IA o el operador.
- **Características:** igual que 3.1, con dos diferencias decisivas para este punto: **está clasificado por origen** (`es_humano`) y **por validez** (`es_respuesta_final`, con índice único parcial `uq_respuestas_final_por_consulta` que garantiza una sola final por consulta). Esas dos banderas son las que hacen que el corpus sea *curable* — sin ellas no habría forma de separar conocimiento validado de ruido.
- **Representación propuesta:** `TEXT` en `respuestas`, sin cambios. Es el candidato principal a vectorización, siempre y solo en la partición `es_respuesta_final = TRUE`.
- **Justificación:** ídem 3.1. El valor está en el par pregunta–respuesta final, y el modelo ya lo puede reconstruir con un JOIN por `id_consulta`.

### 3.3 Reseña textual de satisfacción — *no existe; podría incorporarse*

- **Dato:** el comentario libre del cliente al calificar. `conversaciones.calificacion` guarda el número (1–5) pero **no hay ninguna columna para el "por qué"**. Con los datos de ejemplo, la conversación 6 tiene calificación 2 y no hay forma de saber qué falló.
- **Características:** texto libre, corto, opcional, con carga subjetiva. El enunciado lista "evaluaciones de satisfacción" entre los datos posibles; el modelo capturó la métrica y descartó el contenido.
- **Representación propuesta:** `conversaciones.comentario TEXT NULL`, relacional. **No lo vectorizaría** en una primera etapa (ver 4.4).
- **Justificación:** una columna nullable en una tabla que ya se lee completa; no hay ninguna razón para complicarlo.

### 3.4 Adjuntos, imágenes y audio — *no existen; el caso los implica*

- **Dato:** el modelo **no tiene ninguna tabla de archivos**, pero el dominio los produce inevitablemente: el canal `email` trae adjuntos (comprobantes, capturas); la consulta 6 —*"El producto llego danado"*— implica en la práctica una foto; y el canal **`telefono`**, que está en el `CHECK` y en los datos (ticket 5), implica una llamada de voz. Hoy el ticket 5 tiene su consulta como texto en `consultas.pregunta`: es decir **el modelo asume una transcripción previa que no está modelada en ninguna parte**, y no queda registro de que el original fuera audio ni de la confiabilidad de esa transcripción.
- **Características:** binarios de tamaño grande y variable, sin contenido consultable por SQL.
- **Representación propuesta:** **almacenamiento de objetos externo** (sistema de archivos o S3-compatible) + tabla relacional de metadatos: `adjuntos(id_adjunto, id_consulta FK, uri, tipo_mime, tamano_bytes, hash_sha256, fecha_carga)`. Para el audio, además, `transcripciones(id_adjunto FK, texto, motor, confianza)` — la transcripción sí es texto y sí entra al circuito semántico; el audio no.
- **Justificación:** guardar binarios en `BYTEA` infla la tabla, castiga los backups y el TOAST y no aporta nada: nunca se consultan por contenido desde SQL. El patrón correcto es puntero + metadatos en la base, bytes afuera. **Y el `hash_sha256` no es decorativo**: es lo que permite detectar el mismo adjunto reenviado y, sobre todo, saber si el binario cambió sin que cambiara la fila.

---

## 4. Datos potencialmente vectorizables

Aplico un filtro estricto: solo entra lo que tiene texto en lenguaje natural **y** una consulta real que la búsqueda exacta no resuelve.

### 4.1 Par `pregunta` + `respuesta final` de casos cerrados — **candidato principal**

- **Contenido:** la concatenación del texto de `consultas.pregunta` con el de su `respuestas.texto_respuesta` marcada como final, restringida a casos efectivamente terminados. Con los datos de ejemplo serían **10 pares** (las consultas 3 y 8 quedan fuera: no tienen respuesta final).
- **Por qué podría vectorizarse:** porque la pregunta que llega es siempre nueva *en su redacción* y casi nunca nueva *en su significado*. Dos clientes preguntan lo mismo con palabras que no comparten ningún término. El proyecto ya tiene el ejemplo dentro de sus propios datos: la consulta 1 dice *"Como puedo restablecer mi contrasena?"* y la consulta 11 dice *"No puedo ingresar a la aplicacion movil."* — su respuesta (id 15) es *"actualizar la aplicacion y restablecer la contraseña"*. Son el mismo problema subyacente y **no comparten ni una palabra de contenido**. Ninguna búsqueda por igualdad, `LIKE` o `tsvector` las relaciona.
- **Qué representa el embedding:** la **intención del cliente resuelta**, no el texto. Un punto en el espacio semántico que dice "este es un caso de recuperación de acceso", con la resolución validada colgada de él.
- **Qué consulta permitiría:** dada una consulta entrante, recuperar los *k* casos históricos semánticamente más cercanos, con su resolución, para que la IA proponga una respuesta y el operador la valide o la corrija.
- **Qué problema resolvería:** exactamente la limitación 1 de la sección 1 del informe —"el histórico no es consultable por contenido"— y los procesos 8 del enunciado ("sugerir respuestas", "identificar consultas frecuentes").

### 4.2 Solo la `pregunta`, sin la respuesta — **candidato secundario, para otra tarea**

- **Contenido:** únicamente `consultas.pregunta`, incluidas las consultas **sin resolver** (3 y 8 en los datos de ejemplo).
- **Por qué podría vectorizarse:** porque agrupar por tema es una tarea distinta de sugerir una respuesta. Para detectar "los temas más consultados este mes" hay que poder agrupar consultas *aunque todavía no tengan respuesta*, y mezclar el texto de la respuesta en el vector contamina esa agrupación: dos preguntas distintas con respuestas parecidas quedarían artificialmente cerca.
- **Qué representa el embedding:** el **tema consultado**, con independencia de si se resolvió.
- **Qué consulta permitiría:** clustering sobre los vectores para producir el panel de temas frecuentes del supervisor; y detección de picos ("apareció un grupo nuevo de 40 consultas en 3 días" → probable incidente en producción).
- **Qué problema resolvería:** "identificar consultas frecuentes" de forma no supervisada, sin que nadie tenga que etiquetar cada consulta a mano.
- **Advertencia sobre la implementación propuesta:** la segunda consulta de `vectorial/modelo_vectorial.md` **no logra esto**. Hace `GROUP BY contenido_pregunta` con `COUNT(*)`: eso agrupa por **texto literal idéntico**, de modo que dos preguntas semánticamente iguales pero escritas distinto cuentan 1 cada una — justo lo que la búsqueda vectorial venía a resolver. Cuenta duplicados exactos, no similares. La agrupación por cercanía requiere clustering (k-means / HDBSCAN sobre los vectores) o, como aproximación en SQL, contar vecinos dentro de un radio por cada consulta, no un `GROUP BY` sobre el texto.

### 4.3 Artículos de una base de conocimiento — **el mejor candidato, pero no existe** *(hipotético)*

- **Contenido:** artículos de FAQ, políticas de devolución, manuales de producto, instructivos.
- **Por qué sería el mejor candidato:** son documentos largos, escritos una vez, **estables**, curados por la empresa y sin datos personales. Es decir, invierten todos los riesgos del corpus de casos: no hay que anonimizarlos, no se desactualizan cada día, y no hay problema de autorización por cliente.
- **Estado:** **no existen** en el repositorio — ni tabla, ni archivos, ni mención. Lo declaro explícitamente hipotético. Si se incorporaran, el diseño requeriría *chunking* (partir cada documento en fragmentos de unos cientos de tokens con solapamiento) porque un vector por documento largo promedia demasiados temas y pierde precisión. El corpus de casos, en cambio, **no necesita chunking**: cada par pregunta–respuesta ya es una unidad breve y autocontenida, lo cual es una ventaja concreta de este caso.

### 4.4 Reseñas de satisfacción — **no lo vectorizaría**

Si se incorporara `conversaciones.comentario` (3.3), el uso natural sería clasificar sentimiento y extraer motivos de queja recurrentes. Pero: es un texto que **nadie va a buscar por similitud** ("tráeme comentarios parecidos a este" no es una pregunta que ningún rol del informe necesite hacer), el volumen es bajo, y el valor analítico se obtiene con clasificación, no con recuperación. Vectorizarlo sería agregar un índice que nadie consulta.

### 4.5 Lo que explícitamente **no** vectorizaría

`clientes`, `empleados`, `roles`, `tickets`, `ticket_logs`, `conversaciones.calificacion` y las respuestas **no finales**. Son datos tipados con dominios cerrados, o ruido descartado. Un embedding de un DNI o de un `estado` es un sinsentido: la operación que se necesita sobre ellos es igualdad, rango o agregación, y para eso el B-tree es exacto, más rápido y auditable. Sobre las **respuestas intermedias y descartadas** el criterio de `modelo_vectorial.md` es correcto y lo suscribo: indexarlas contaminaría el corpus con precisamente el material que un humano ya rechazó.

En números: de las **8 tablas y ~40 columnas** del esquema, las candidatas a vectorización son **2 columnas**. Ese ratio es, en sí mismo, la respuesta a la pregunta de cuánto peso debe tener el componente vectorial en la arquitectura.

---

## 5. Búsqueda semántica y recuperación de información

### 5.1 ¿Existe una necesidad real? Sí — y es verificable contra las alternativas

La necesidad no es una suposición: el enunciado la pide ("sugerir respuestas", "identificar consultas frecuentes") y la sección 1 del informe la formaliza como proceso 8. La pregunta útil es si algo más barato la resuelve. Comparo las tres alternativas honestamente:

| Alternativa | Qué resuelve | Dónde falla en *este* caso |
|---|---|---|
| **`LIKE` / `ILIKE`** | Coincidencia de subcadena | Falla ante cualquier variación. `ILIKE '%contraseña%'` no encuentra *"contrasena"* (los datos de ejemplo están sin tildes) ni *"clave"* ni *"password"* |
| **FTS nativo: `tsvector` + GIN, config `spanish`, con `unaccent`** | Resuelve tildes y flexión (*"restablecer"* ≈ *"restablecí"*), es exacto, barato, transaccional y sin dependencias externas. **Es el punto de partida correcto** | No resuelve **sinonimia ni paráfrasis**, que es el 100% del problema. *"clave"* / *"contraseña"* / *"password"*, *"factura"* / *"comprobante"*, *"pedido"* / *"envío"* no comparten lexema. Se puede mitigar con un diccionario `thesaurus`, pero eso es **un glosario de sinónimos del dominio que alguien mantiene a mano para siempre**, y que nunca cubre la redacción que no se anticipó |
| **`pg_trgm` (trigramas)** | Tolera errores de tipeo y variantes morfológicas | Opera sobre la forma de la palabra, no sobre el significado. *"contrasena"* vs *"contraseña"* sí; *"clave"* vs *"contraseña"* no |
| **Clasificación por categorías** (tabla `categorias` + `consultas.id_categoria`) | Resuelve "consultas frecuentes" con un `GROUP BY`, sin ningún vector. **Alternativa seria y más barata para ese requisito puntual** | (a) Requiere que alguien etiquete cada consulta; (b) la taxonomía queda corta ante temas nuevos justo cuando más importa detectarlos; (c) **no resuelve el otro requisito**: da el tema, no la respuesta concreta a sugerir |
| **Embeddings + pgvector** | Recupera por significado sin glosario ni etiquetado manual | Es aproximado, no auditable línea por línea, requiere reindexación y depende de un modelo externo (riesgo R7 del informe) |

**Conclusión de la comparación:** el FTS y los trigramas cubren el caso fácil (el cliente usa la palabra que está en el corpus) y son insuficientes para el caso que da valor (el cliente describe su problema con sus propias palabras). El límite del FTS no es de rendimiento sino **de expresividad**, y no se cierra con más índices. Por eso el componente vectorial se justifica — y solo para esas 2 columnas.

### 5.2 Consultas que los usuarios podrían realizar

Las escribo por rol, porque de eso depende el filtrado (5.5):

| Rol | Consulta en lenguaje natural | Traducción operativa |
|---|---|---|
| Operador | "¿Cómo resolvimos antes casos como este?" | top-5 vecinos del vector de la consulta entrante, entre casos cerrados |
| Sistema de IA | "Dame contexto validado para redactar una sugerencia" | top-3 vecinos con `distancia < umbral`; **si nada baja del umbral, no sugerir nada** |
| Supervisor | "¿Cuáles fueron los 10 temas más consultados este mes?" | clustering sobre los vectores de preguntas del período |
| Supervisor | "¿Hay un tema nuevo creciendo esta semana?" | detección de un cluster denso y reciente sin histórico previo |
| Supervisor | "De los casos parecidos a este, ¿cuáles se resolvieron peor?" | vecinos + JOIN a `conversaciones.calificacion` |
| Supervisor / Calidad | "¿Este caso es duplicado de uno existente?" | vecino más cercano con distancia casi nula — el caso del ticket 7 de los datos de ejemplo, hoy detectado a mano |
| Cliente | "¿Ya me respondieron algo así?" | vecinos **restringidos a sus propios casos** |

### 5.3 Cómo funcionaría conceptualmente la recuperación

Flujo de **indexación** (asíncrono, disparado por evento):

1. Un ticket alcanza estado terminal y su consulta tiene respuesta final.
2. Se **anonimiza** el texto: enmascarado de DNI, email, teléfono, tarjeta, direcciones por patrón. Sobre el texto enmascarado, nunca sobre el original.
3. Se calcula el `hash` del texto anonimizado. Si coincide con el ya indexado, no se hace nada (evita reindexar por cambios irrelevantes).
4. Se genera el embedding del texto anonimizado y se hace `UPSERT` sobre la clave `id_consulta`.

Flujo de **consulta** (sincrónico):

1. Llega una consulta nueva → se anonimiza → se embebe con **el mismo modelo** con que se indexó el corpus (mezclar modelos produce distancias sin sentido).
2. Búsqueda ANN con **filtros de metadatos aplicados en la misma sentencia**, más un umbral de distancia máxima.
3. Los resultados se devuelven **con su procedencia** (`id_consulta`, `id_ticket`, fecha, origen humano/IA, distancia) — nunca como texto anónimo sin trazabilidad.
4. Si el mejor resultado no baja del umbral: **no se sugiere nada y se deriva a un humano**. Es la derivación de "casos complejos" que pide el enunciado, y es preferible a sugerir el mejor de los malos.

### 5.4 Qué información acompañaría a cada vector

Aquí el diseño existente en `vectorial/modelo_vectorial.md` **necesita corregirse**. La tabla propuesta allí tiene `id_consulta`, `id_respuesta`, los dos textos, `canal_origen`, el vector, el modelo y la fecha de indexación. Le faltan metadatos sin los cuales el propio diseño se contradice:

| Metadato | ¿Está en la propuesta actual? | Por qué es imprescindible |
|---|---|---|
| `id_consulta`, `id_respuesta` | Sí | Trazabilidad hasta el caso real |
| `contenido_pregunta`, `contenido_respuesta` | Sí | Evitan el JOIN en el camino caliente |
| `canal_origen` | Sí, pero mal usado como filtro duro (5.5) | Contexto de formato y tono |
| `embedding`, `modelo_embedding` | Sí | El modelo es obligatorio: sin él no se sabe qué vectores son comparables entre sí |
| `fecha_indexacion` | Sí | Detectar vectores viejos respecto del texto |
| **`id_cliente`** | **No — y sin esto la RLS declarada es inaplicable** | La sección 5 de `modelo_vectorial.md` afirma que la tabla "debe respetar la misma política de aislamiento… (RLS)". Pero **no hay ninguna columna por la cual escribir esa política**: para saber de qué cliente es una fila hay que hacer JOIN a `consultas → conversaciones → tickets`, es decir el JOIN que la desnormalización existía para evitar. La consecuencia es concreta: **o se agrega `id_cliente`/`id_ticket`, o la RLS no se puede implementar sin anular el motivo de la tabla** |
| **`id_ticket`** | **No** | Ancla de permisos y de vigencia; además permite filtrar por `tickets.activo` |
| **`es_humano`** de la respuesta final | **No** | Sin este metadato no se puede distinguir conocimiento validado por una persona del texto que la propia IA produjo. En los datos de ejemplo **3 de 10 respuestas finales son de IA** (`id` 3, 12, 17): indexarlas sin marca hace que el sistema se alimente de sí mismo, que es el riesgo R4 del informe sin mitigación efectiva |
| **`fecha_resolucion` del caso** | **No, y no es derivable de forma barata** | Es el metadato de **recencia**, el filtro más importante de todos: una respuesta sobre medios de pago de hace tres años es probablemente falsa hoy. Y aquí aparece un vacío del modelo: **ni `consultas` ni `respuestas` tienen columna de fecha**. La única fecha cercana es `conversaciones.fecha` (inicio) y las de `ticket_logs`. Habría que derivarla del log de `resuelto`/`cerrado` o —mejor— **agregar `respuestas.fecha TIMESTAMPTZ`**, que hoy falta y hace imposible ordenar respuestas por tiempo dentro de una consulta |
| **`hash_contenido`** | **No** | Permite saber si el texto cambió desde la indexación y evita reindexaciones inútiles |
| **`vigente BOOLEAN`** | **No** | Permite retirar un vector del índice sin borrarlo, preservando la auditoría — coherente con el criterio de *soft delete* del resto del modelo |
| **`calificacion`** de la conversación | **No** | Permite no sugerir resoluciones de casos que el cliente calificó con 1 o 2 |

Y dos correcciones estructurales:

- **Falta `UNIQUE (id_consulta)`.** Sin esa restricción, cada reindexación **inserta** en lugar de actualizar, y el índice acumula duplicados. Consecuencia doble: el top-3 devuelve tres veces la misma sugerencia, y cualquier conteo de "consultas frecuentes" queda inflado por versiones del mismo caso.
- **El índice HNSW es prematuro al volumen actual.** Con 10 filas, un scan secuencial es más rápido y —sobre todo— **exacto**. HNSW es un índice *aproximado*: puede no devolver el vecino verdadero. Crearlo desde el primer día introduce inexactitud sin ninguna ganancia. El criterio correcto es partir sin índice y crearlo cuando la latencia lo exija, midiendo el *recall* perdido.

### 5.5 Filtros por metadatos necesarios

| Filtro | Cómo aplicarlo | Justificación |
|---|---|---|
| **Permisos (RLS por rol)** | Duro, no negociable. Cliente: solo `id_cliente` propio. Operador: los casos de su alcance. Supervisor: su equipo | Es el punto que la sección 1 del informe señala como "puerta lateral": si la búsqueda semántica recupera un caso al que el usuario no llegaría por SQL, el control de accesos quedó vulnerado. Requiere las columnas de 5.4 |
| **Caso terminado** | Duro: solo casos cuyo estado actual sea `cerrado` | **Corrijo aquí el criterio de `modelo_vectorial.md`, que indexa por `es_respuesta_final = true` sin mirar el estado del ticket.** En este modelo `resuelto` **no es terminal**: existe `reabierto`, y los datos de ejemplo lo demuestran — el ticket 8 pasó `abierto → resuelto → reabierto → en_proceso`. Indexar al llegar a `resuelto` habría cargado al corpus el conocimiento de un caso que después se probó no resuelto |
| **Ticket vigente** | Duro: `tickets.activo = TRUE` | **Segunda corrección al criterio actual, con evidencia en los datos.** El **ticket 7 tiene `activo = FALSE`** (borrado lógico por duplicado) y su consulta 7 **sí tiene respuesta final** (`id_respuesta` 10, `es_respuesta_final = TRUE`). Con el criterio de `modelo_vectorial.md`, **ese caso dado de baja entraría al índice y sería sugerible**. Es el riesgo de "documentos eliminados pero presentes en el índice" ya materializado en el conjunto de prueba, no una hipótesis |
| **Recencia** | Duro con ventana amplia (p. ej. últimos 24 meses) + preferencia por lo reciente en el desempate | Una resolución vieja puede ser hoy incorrecta aunque siga siendo la más parecida |
| **Umbral de distancia** | Duro | Sin umbral, la búsqueda **siempre** devuelve *k* resultados, incluso si el más cercano no tiene nada que ver. Es la causa directa de los falsos positivos de 6.4 |
| **Origen validado** | Preferencia, no exclusión | Priorizar `es_humano = TRUE`; permitir las de IA solo si están revisadas. Frena la autofagia del corpus |
| **Calificación** | Preferencia | Descartar resoluciones de casos calificados 1–2 |
| **Canal** | **Blando (re-ranking), no filtro duro** | **Tercera corrección.** El ejemplo de `modelo_vectorial.md` filtra `WHERE canal_origen = 'whatsapp'`. Pero la respuesta a *"¿cómo restablezco mi contraseña?"* es la misma por WhatsApp que por email: el canal condiciona el **formato y el tono**, no el contenido. Como filtro duro parte el corpus en cinco y descarta buenas resoluciones por una razón irrelevante — con los 10 pares actuales, filtrar por canal deja **1 o 2 candidatos**. Debe influir en el orden, no en la elegibilidad |

Una nota de eficiencia sobre estos filtros: en pgvector, filtrar y hacer ANN a la vez tiene un problema conocido — si el `WHERE` es muy selectivo, el índice HNSW recorre vecinos que después se descartan y puede devolver menos de *k* resultados. Con filtros duros muy restrictivos (RLS por cliente, por ejemplo) suele ser mejor **filtrar primero y hacer distancia exacta sobre el subconjunto**. Otra razón para no dar por sentado el HNSW.

---

## 6. Riesgos y consideraciones

Los riesgos R1–R8 de la sección 2 del informe cubren bien el terreno general. Detallo los específicos del componente semántico, marcando cuáles están mitigados y cuáles quedan abiertos.

### 6.1 Información incorrecta

El corpus se alimenta de `es_respuesta_final = TRUE`, pero **"final" significa "la que se envió", no "la que era correcta"**. Un operador puede haber cerrado un caso con una respuesta equivocada que el cliente nunca objetó. Esa respuesta entra al índice con el mismo peso que una correcta y se propaga a todos los casos parecidos: un error individual se vuelve sistemático.

*Mitigación:* usar `conversaciones.calificacion` como señal de calidad (excluir 1–2); permitir a supervisores marcar un vector como no vigente; y revisión periódica de las sugerencias más recuperadas — las que más se reutilizan son las que más conviene auditar. **Riesgo abierto:** el modelo no tiene ningún campo de "validación por calidad" independiente del envío.

### 6.2 Información desactualizada

Es el riesgo R3 del informe y el más probable en la práctica. Tres variantes distintas:

1. **El texto cambió tras indexarse.** Mitigado por la reindexación asíncrona que ya propone `modelo_vectorial.md`, más el `hash_contenido` de 5.4.
2. **El texto no cambió pero el mundo sí.** *"Se aceptan tarjetas de credito, debito y transferencia bancaria"* (respuesta 12, generada por IA y marcada como final) sigue siendo idéntica cuando la empresa deja de aceptar transferencias. **Ningún trigger detecta esto**, porque no hubo `UPDATE`. Solo lo mitigan la ventana de recencia y la revisión periódica. **Riesgo abierto y estructural.**
3. **El modelo de embeddings cambió.** Si se cambia de modelo, los vectores viejos **no son comparables** con los nuevos: las distancias entre espacios distintos no significan nada. Obliga a reindexar el corpus completo. Por eso `modelo_embedding` es obligatorio, y por eso conviene poder convivir con dos modelos durante la migración.

### 6.3 Autorización y filtrado por permisos

Dos aspectos separados, con alcance distinto:

- **Identidades y RLS del núcleo.** `db/fisico/05_seguridad_permisos.sql` (sección 13 del informe) define los cinco roles de la sección 1 —incluido `rol_sistema_ia`, que solo puede insertar sugerencias (`es_humano = false`) y no tiene lectura propia amplia— y RLS sobre las 8 tablas del núcleo, probado contra Postgres real. La IA opera "con las mismas restricciones de acceso que aplican al usuario que dispara la consulta", tal como pide la sección 1, en vez de con credenciales de aplicación con acceso a todo el corpus.
- **La tabla vectorial es lo que queda por cerrar.** `consultas_embeddings` no existe físicamente, y la propuesta de `modelo_vectorial.md` no tiene columnas por las que escribir una política de RLS (5.4). Sin `id_cliente`/`id_ticket` propios, no hay sobre qué aplicarle a esa tabla el mismo mecanismo que ya protege al resto del núcleo.

### 6.4 Falsos positivos y resultados semánticamente similares pero incorrectos

Es el modo de falla propio de esta técnica, y el más engañoso porque el resultado *se ve* razonable. Con los datos del proyecto:

- Las consultas 9 (*"Que medios de pago aceptan?"*) y 10 (*"Puedo pagar la compra en cuotas?"*) son vecinas muy cercanas en el espacio semántico y tienen **respuestas distintas y no intercambiables**. Sugerir *"Se aceptan tarjetas de credito, debito y transferencia"* a quien pregunta por cuotas es una respuesta plausible, cercana y **equivocada**.
- La negación es un caso clásico: *"puedo cancelar el servicio"* y *"no puedo cancelar el servicio"* son casi idénticos como vectores y opuestos como intención.

*Mitigación:* umbral de distancia estricto; presentar siempre **varias** sugerencias con su distancia visible en lugar de una sola como si fuera la verdad; y —lo más importante— mantener la sugerencia como **borrador para el operador**, no como respuesta automática al cliente. El modelo ya soporta esto: la sugerencia de IA se guarda como respuesta no final y el humano crea la final (patrón visible en las respuestas 1→2, 5→6, 13→14).

### 6.5 Pérdida de contexto

El vector aplana el par pregunta–respuesta y descarta todo lo demás: qué producto, qué cliente, qué había pasado antes en la conversación. La consulta 12 (*"Cuanto tiempo dura el enlace para cambiar la contrasena?"*) **solo se entiende leída después de la consulta 1** de la misma conversación. Indexada suelta, es un fragmento huérfano; recuperada como sugerencia para una consulta aislada, puede resultar incomprensible. *Mitigación:* conservar `id_conversacion` y presentar siempre la sugerencia con un enlace al caso completo, para que el operador lea el contexto antes de reutilizarla.

### 6.6 Privacidad e información sensible

Riesgos R2 y R7 del informe, bien identificados. Dos precisiones:

- **La anonimización debe ocurrir antes de generar el embedding, no antes de mostrarlo.** El informe ya lo dice, y es correcto: **el embedding es una transformación con fuga**. Aunque no se guarde el texto, un vector generado sobre un texto que contenía un DNI conserva parte de esa información, y existen ataques de inversión que reconstruyen texto aproximado desde el vector. Si además se guarda `contenido_pregunta` en claro —como hace la propuesta actual— el problema es directo: el dato sensible está en la tabla.
- **`modelo_vectorial.md` propone `VECTOR(1536)` con `text-embedding-3-small` de OpenAI**, lo que materializa el riesgo R7: el texto de las consultas sale de la infraestructura. El informe ya ofrece la alternativa (modelo autoalojado). Dado que el resto del despliegue es local (`docker-compose`), **elegir un proveedor externo por defecto es la única decisión del diseño que rompe con esa autocontención**, y conviene explicitarla como decisión consciente o revisarla.
- Hay además una tensión no resuelta: `clientes.activo = FALSE` se documenta en `db/logico/restricciones.md` como "anonimización de datos personales", pero **nada anonimiza el texto de sus consultas ya indexadas**. Un cliente dado de baja —o que ejerce su derecho a la supresión de datos— deja su texto en el índice.

### 6.7 Documentos eliminados pero presentes en el índice / sincronización

Ya documentado con evidencia en 5.5: el **ticket 7 (`activo = FALSE`) es indexable con el criterio actual**. Y como el modelo no hace borrado físico, el problema no es "el documento desapareció" sino "el documento sigue ahí pero dejó de ser válido", que es más silencioso.

*Mitigación:* condicionar la indexación a `tickets.activo = TRUE` **y** estado `cerrado`; usar `vigente = FALSE` en lugar de `DELETE` para retirar vectores, coherente con el criterio de *soft delete* del modelo; y una **reconciliación periódica** que compare el índice contra el estado transaccional y detecte huérfanos, porque los triggers fallan y las colas pierden mensajes.

### 6.8 Calidad de los embeddings

Tres consideraciones concretas de este corpus:

- **El corpus actual es demasiado chico.** 10 pares indexables. Con ese volumen, el vecino más cercano a cualquier consulta nueva está lejísimo y las sugerencias son ruido. El componente **no aporta valor hasta unos cientos de casos resueltos** y conviene decirlo antes de construirlo.
- **Idioma y normalización.** El corpus está en español y **sin tildes** (*"contrasena"*, *"danado"*). Es un artefacto de los datos sintéticos, pero si el corpus real mezcla textos con y sin tildes, un modelo multilingüe lo tolera razonablemente mientras el FTS necesitaría `unaccent` obligatorio. Conviene normalizar en la indexación de todos modos.
- **Asimetría pregunta/respuesta.** Se busca *una pregunta nueva* contra *pares pregunta+respuesta*. Los textos no son del mismo tipo y eso degrada las distancias. Es una razón concreta para preferir **indexar la pregunta** y traer la respuesta por referencia (4.2), o usar un modelo entrenado para recuperación asimétrica, en lugar de concatenar todo en un solo vector como propone el diseño actual.

---

## 7. Decisión arquitectónica

### 7.1 Tabla de decisión

| Tipo de dato | Ejemplo en el proyecto | Representación propuesta | Motivo |
|---|---|---|---|
| Estructurado, dominio cerrado | `tickets.canal_origen`, `ticket_logs.estado`, `roles.descripcion` | **Relacional + `CHECK`** (como está) | Dominios finitos y conocidos; las agregaciones por canal/estado son el corazón de los indicadores. Texto libre acá rompe todo reporte (R6) |
| Estructurado sensible | `clientes.dni`, `email`, `telefono_1`, `direccion` | **Relacional + RLS**, nunca en el índice vectorial | Identidad y unicidad requieren `UNIQUE` e igualdad exacta; no tienen semántica que buscar |
| Log de eventos de negocio | `ticket_logs` (31 filas de ejemplo) | **Relacional, esquema fijo** (como está) | Es un log tipado, no un log semiestructurado. La FK a `empleados` sostiene la auditoría; sacarlo a documentos la destruiría |
| Métrica acotada | `conversaciones.calificacion` (1–5) | **Relacional `SMALLINT` + `CHECK`** (como está) | `AVG`/`GROUP BY` sobre un entero; sin ambigüedad |
| Semiestructurado por canal | `message_id` de email, `wa_id`, duración de llamada | **`tickets.metadatos_canal JSONB`** *(no existe hoy)* | Los atributos **cambian según el canal**; columnas nullables o EAV son peores. Se acota a lo accesorio: nada que alimente un indicador |
| Semiestructurado versionado | modelo, tokens, confianza y casos recuperados de una sugerencia de IA | **`respuestas.metadatos_generacion JSONB`** *(no existe hoy)* | Cambia con cada versión del modelo; hace auditable la sugerencia (R4) sin un `ALTER TABLE` por proveedor |
| Semiestructurado de configuración | umbral de similitud, `k` de sugerencias, canales habilitados | **tabla `parametros(clave, valor JSONB)`** *(no existe hoy)* | Claves heterogéneas, volumen mínimo; evita migrar el esquema por cada parámetro |
| Estructura fija que *parece* flexible | motivo y par de empleados de una derivación | **columnas nuevas en `ticket_logs`**, no JSONB | Estructura estable y necesita FK a `empleados`; JSONB perdería la integridad sin ganar nada |
| No estructurado, texto corto | `consultas.pregunta`, `respuestas.texto_respuesta` | **`TEXT` en PostgreSQL** (como está) + FTS `tsvector`/GIN + **embedding derivado en tabla aparte** | Es la fuente de verdad, transaccional con su fila. FTS para lo léxico; vector para lo semántico. Ninguno reemplaza al `TEXT` |
| No estructurado, texto opcional | comentario de satisfacción *(no existe hoy)* | **`conversaciones.comentario TEXT`**, sin vectorizar | Nadie necesita buscarlo por similitud; su valor es clasificatorio |
| No estructurado binario | adjuntos de email, foto de producto dañado, audio de llamada *(no existen hoy)* | **objeto externo + tabla de metadatos**; audio → tabla de transcripción | `BYTEA` castiga backups y TOAST sin beneficio: nunca se consultan por contenido desde SQL |
| Derivado semántico | vector del par pregunta + respuesta final de casos cerrados | **`consultas_embeddings` con pgvector**, con los metadatos de 5.4 y sin índice HNSW hasta que el volumen lo exija | Único subconjunto donde la búsqueda léxica es estructuralmente insuficiente (sinonimia). Es reconstruible: se acepta consistencia eventual |
| Relaciones jerárquicas | `cliente → ticket → conversación → consulta → respuesta` | **FK relacionales** (como está) | Profundidad fija de 4 saltos, sin recorridos variables. **Ninguna relación muchos-a-muchos en las 8 tablas** |
| Relaciones "altamente conectadas" | clientes vinculados por teléfono/dirección compartidos | **no aplica** *(hipotético, antifraude)* | No está en el enunciado. Un grafo agregaría un motor entero para una pregunta que nadie hizo |

### 7.2 Estrategia recomendada

**PostgreSQL único, con tres mecanismos de acceso sobre el mismo motor y un orden de incorporación deliberado.** Confirma la elección de la sección 7 del informe, y agrega el orden:

1. **Núcleo relacional normalizado** (ya implementado) — la fuente de verdad, con consistencia fuerte, FK, `CHECK` y *soft delete*. No se toca.
2. **JSONB acotado a tres lugares** (`tickets.metadatos_canal`, `respuestas.metadatos_generacion`, `parametros.valor`) — donde la variabilidad es real. **Regla explícita: ningún dato que alimente un indicador de gestión, una FK o una restricción de negocio vive dentro de un JSONB.** El JSONB documenta lo accesorio; el esquema tipado garantiza lo que se mide. Esto responde la pregunta de la sección 11 del informe sobre "conveniencia de JSON/JSONB": **sí, pero en tres columnas, no como estrategia general** — el resto del dominio tiene esquema estable y `CHECK` cerrados, y ahí JSONB solo quitaría garantías.
3. **FTS nativo primero** (`tsvector` + GIN, config `spanish`, con `unaccent`) — cuesta un índice, es exacto y transaccional, y resuelve el caso en que el cliente usa las palabras del corpus. **Debería existir antes que el componente vectorial**, y hoy tampoco existe.
4. **pgvector sobre 2 columnas y ~10 filas de corpus** — con los metadatos de 5.4, los filtros de 5.5, y **sin índice HNSW hasta que la latencia lo pida**.

**Sin motor adicional.** Un almacenamiento de objetos aparecería solo si se incorporan adjuntos (3.4), y es almacenamiento de archivos, no una base de datos nueva.

### 7.3 Cambios concretos que este punto propone sobre el diseño existente

Sobre `vectorial/modelo_vectorial.md` (autoría de N. Lastra), cuya estructura general suscribo. Nueve deltas:

| # | Cambio | Motivo |
|---|---|---|
| 1 | Agregar `id_cliente` e `id_ticket` | Sin ellos **la RLS que el propio documento declara no es implementable** sin el JOIN que la tabla existe para evitar |
| 2 | Agregar `es_humano` de la respuesta final | Distinguir conocimiento validado por una persona del que la IA produjo (3 de 10 finales son de IA) |
| 3 | Agregar `fecha_resolucion` y, en el núcleo, `respuestas.fecha` | La recencia es el filtro más importante y hoy **no hay ninguna fecha en `consultas` ni en `respuestas`** |
| 4 | Agregar `hash_contenido` y `vigente BOOLEAN` | Reindexación idempotente y retiro de vectores sin `DELETE`, coherente con el *soft delete* del modelo |
| 5 | Agregar `UNIQUE (id_consulta)` | Sin esto la reindexación duplica filas: top-*k* repetido y conteos inflados |
| 6 | Condicionar la indexación a estado `cerrado` **y** `tickets.activo = TRUE` | `resuelto` no es terminal (ticket 8: `resuelto → reabierto`) y hay finales en tickets inactivos (**ticket 7, `activo = FALSE`, respuesta 10 final**) |
| 7 | Convertir el filtro por `canal_origen` en re-ranking blando | Como filtro duro parte el corpus en cinco y descarta buenas resoluciones por una razón irrelevante al contenido |
| 8 | Reemplazar el `GROUP BY contenido_pregunta` por clustering o conteo de vecinos por radio | Ese `GROUP BY` cuenta **duplicados literales**, no similares: contradice el propósito de la búsqueda semántica |
| 9 | Diferir el índice HNSW; agregar umbral de distancia obligatorio en toda consulta | HNSW es aproximado y con 10 filas el scan exacto es mejor; sin umbral la búsqueda **siempre** devuelve *k* resultados aunque ninguno sirva |

---

## 8. Conclusión

### Decisión: **Opción A — sí requiere una solución vectorial, acotada a dos columnas y condicionada al volumen.**

**Qué problema resuelve.** El enunciado exige sugerir respuestas a partir de casos históricos e identificar consultas frecuentes; la sección 1 del informe lo formaliza como proceso 8 y como la limitación 1 del estado actual ("el histórico no es consultable por contenido"). El obstáculo es que el cliente describe su problema con **sus** palabras y el corpus está escrito con **otras**.

**Por qué la búsqueda tradicional no alcanza.** No es un problema de rendimiento, es de expresividad, y por eso no se cierra agregando índices. `LIKE` falla ante cualquier variación. El FTS con diccionario español y `unaccent` resuelve tildes y flexión, y es exacto y barato —debería implementarse igual, antes que los vectores— pero **no resuelve sinonimia ni paráfrasis**, que es el 100% del problema real: *"clave"* y *"contraseña"* no comparten lexema. Se puede paliar con un tesauro de sinónimos del dominio, pero eso es un glosario que alguien mantiene a mano para siempre y que nunca cubre la redacción no anticipada. La prueba está en los datos del propio proyecto: la consulta 1 (*"Como puedo restablecer mi contrasena?"*) y la consulta 11 (*"No puedo ingresar a la aplicacion movil"*, respondida con *"actualizar la aplicacion y restablecer la contraseña"*) son el mismo problema y **no comparten una sola palabra de contenido**. Ninguna técnica léxica las vincula; un embedding sí.

**Qué se vectoriza y qué no.** Solo el par pregunta + respuesta final de casos **cerrados y vigentes**: **2 columnas de las ~40 del esquema**, sobre 10 pares en el conjunto actual. Los otros datos del enunciado —clientes, tickets, estados, logs, calificaciones— no se vectorizan: sobre ellos la operación necesaria es igualdad, rango o agregación, y para eso el índice B-tree es exacto, más rápido y auditable.

**Qué NO concluyo.** No concluyo que el proyecto necesite una base vectorial dedicada: `pgvector` dentro del mismo PostgreSQL cubre la necesidad con un solo modelo de permisos, tal como argumenta la sección 7.2. No concluyo que el diseño vectorial existente esté listo: le faltan cinco metadatos, una restricción de unicidad y una corrección del criterio de indexación (7.3), y sin `id_cliente` **la RLS que el propio diseño declara es inaplicable**. Y no concluyo que convenga construirlo ya: con 10 pares indexables el componente es **demostrativo, no útil**; su valor aparece a partir de algunos cientos de casos cerrados. Lo correcto es implementar primero el FTS —que hoy tampoco existe— y activar el componente vectorial cuando el corpus lo justifique.

**Matiz sobre el segundo requisito.** Para "identificar consultas frecuentes" existe una alternativa más barata y honesta: una tabla `categorias` con `consultas.id_categoria` y un `GROUP BY`. Es menos ambiciosa, requiere etiquetado manual y se queda corta ante temas nuevos —justo cuando detectarlos más importa—, pero **es suficiente para ese requisito puntual**. Lo que esa alternativa no resuelve es el otro requisito: da el tema, no la respuesta concreta a sugerir. Es ahí, en la sugerencia de respuesta, donde la solución vectorial es indispensable y no meramente conveniente.

**Condición de aceptación.** La solución vectorial se justifica **siempre que se cumplan tres condiciones**, porque sin ellas hace más daño que bien: (1) anonimización previa al cálculo del embedding, no previa a mostrarlo — el vector conserva información del texto original; (2) RLS efectiva sobre la tabla de vectores, lo que exige `id_cliente`/`id_ticket` y una identidad de base de datos para el sistema de IA, que hoy no existe (`roles` solo tiene Operador, Supervisor y Administrador); (3) la sugerencia se entrega **al operador como borrador**, nunca automáticamente al cliente. El modelo relacional ya soporta esa tercera condición y es su mejor decisión de diseño para este punto: la sugerencia de IA vive como respuesta no final y un humano crea la final, patrón visible en las cadenas 1→2, 5→6 y 13→14 de los datos de ejemplo.

---

## Anexo — Inconsistencias encontradas entre documentación e implementación

Detectadas durante la inspección. No afectan la conclusión del punto 9, pero conviene corregirlas antes de la entrega.

| # | Ubicación | Inconsistencia |
|---|---|---|
| 1 | `db/conceptual/restricciones.md` vs. `01_creacion_tablas.sql` | Calificación **"rango de 0 a 5"** en el conceptual; `CHECK (calificacion BETWEEN 1 AND 5)` en el físico. Los datos de ejemplo usan 2–5 |
| 2 | `db/conceptual/restricciones.md` | Nombres divergentes: `nota_satisfaccion` → `calificacion`; `es_final` → `es_respuesta_final`; `texto_pregunta` → `pregunta` |
| 3 | `db/conceptual/restricciones.md` | Menciona **Instagram** como canal; el `CHECK` admite solo `chat`, `email`, `whatsapp`, `telefono`, `web` |
| 4 | `db/conceptual/restricciones.md` | Dice que `es_humano` es "dominio cerrado con dos valores: `IA` o `HUMAN`"; el físico lo implementa como `BOOLEAN` |
| 5 | `docs/informe.md`, consulta 5 de la sección 10 | Error de tipeo: `GROUP BY canal_origen, estado_actual0` — sobra el `0`. El `.sql` está correcto |
| 6 | `docs/informe.md` sección 10 vs. `05_consultas_representativas.sql` | El informe documenta 5 consultas y las numera distinto que el `.sql`, que tiene 8. La "Consulta 5" del informe es la "CONSULTA 4" del `.sql` |
| 7 | `docs/informe.md` sección 1 vs. esquema | Atribuye al Administrador la gestión de "parámetros del sistema"; **no existe tabla de parámetros** |
| 8 | Esquema físico | `consultas` y `respuestas` **no tienen columna de fecha**. Impide ordenar respuestas en el tiempo y obliga a derivar la recencia de `conversaciones.fecha` o de `ticket_logs` |
| 9 | `db/fisico/01_creacion_tablas.sql` vs. `docker-compose.yml` | La imagen es `pgvector/pgvector:pg16` pero no se ejecuta `CREATE EXTENSION vector`. Coherente con lo declarado en 8.1, pero deja la infraestructura sin usar |
| 10 | `nosql/`, `anexos/` | Vacíos. El primero es coherente con la decisión de 7.2 (ningún motor NoSQL); el segundo (`material_complementario.md`, 0 bytes) queda pendiente |
| 11 | Numeración general | El punto 9 de la consigna es la **sección 11** del informe. Las secciones 3, 4, 5, 14 y 15 siguen como plantilla |
