# Modelo de datos vectorial (extensión pgvector)

## 1. ¿Qué se vectoriza?

Se vectoriza el texto de una consulta junto con el de su respuesta final (`respuestas.es_respuesta_final = true`), pero solo cuando el ticket al que pertenece está efectivamente cerrado: `estado = 'cerrado'` en el último `ticket_log` —no alcanza con `resuelto`, que no es un estado terminal en este modelo: un ticket puede volver a `reabierto`— y `tickets.activo = TRUE` —un ticket dado de baja, aunque tenga respuesta final, no debe sugerirse—. No se vectorizan consultas todavía abiertas, respuestas intermedias o descartadas, ni casos que llegaron a cerrarse pero después se dieron de baja.

## 2. Tabla propuesta

```sql

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE consultas_embeddings (
    id_embedding         SERIAL PRIMARY KEY,
    id_consulta          INTEGER NOT NULL REFERENCES consultas(id_consulta),
    id_respuesta         INTEGER NOT NULL REFERENCES respuestas(id_respuesta),
    id_cliente            INTEGER NOT NULL REFERENCES clientes(id_cliente),
    id_ticket             INTEGER NOT NULL REFERENCES tickets(id_ticket),
    contenido_pregunta   TEXT NOT NULL,
    contenido_respuesta  TEXT NOT NULL,
    es_humano            BOOLEAN NOT NULL,
    canal_origen         VARCHAR(20) NOT NULL,
    fecha_resolucion     TIMESTAMPTZ NOT NULL,
    hash_contenido       TEXT NOT NULL,
    vigente              BOOLEAN NOT NULL DEFAULT TRUE,
    embedding            VECTOR(1536) NOT NULL, -- Tamaño sujeto a modelo de embedding utilizado (openAI en este caso)
    modelo_embedding     TEXT NOT NULL,         -- Ejemplo: 'text-embedding-3-small'
    fecha_indexacion     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_consultas_embeddings_id_consulta UNIQUE (id_consulta)
);

-- Indice HNSW diferido a proposito: con un corpus de pocas decenas de
-- filas, un scan secuencial es mas rapido y ademas mas exacto (HNSW es
-- un indice aproximado, puede no devolver el vecino verdadero). Crear
-- recien cuando el volumen del corpus lo justifique, midiendo el recall
-- perdido en ese momento.
-- CREATE INDEX idx_consultas_embeddings_hnsw
--     ON consultas_embeddings USING hnsw (embedding vector_cosine_ops);
```

`id_consulta` tiene una restricción `UNIQUE`: sin ella, reindexar el mismo caso duplicaría la fila, e inflaría tanto el conteo de "consultas frecuentes" como los resultados de una búsqueda por similitud con el mismo caso repetido.

## 3. Decisión de modelado: referencia + duplicación parcial

| Dato | Estrategia | Motivo |
|---|---|---|
| `id_consulta`, `id_respuesta` | Referencia (FK) | Permite trazar cada sugerencia hasta el caso real y auditar el origen de una respuesta sugerida |
| `id_cliente`, `id_ticket` | Duplicación (columnas propias, no derivadas por JOIN) | La Row Level Security por cliente/operador necesita ser una comparación de igualdad indexada sobre esta misma tabla. Resolverla con un `JOIN` contra `consultas → conversaciones → tickets` reintroduciría justo lo que esta desnormalización existe para evitar |
| `contenido_pregunta`, `contenido_respuesta` | Duplicación (desnormalización controlada) | Evita un `JOIN` contra las tablas transaccionales en el camino caliente de cada búsqueda por similitud |
| `es_humano` | Duplicación | Distingue conocimiento validado por una persona del generado por la propia IA. Sin esta marca, una sugerencia de IA nunca revisada podría terminar alimentando futuras sugerencias de IA |
| `canal_origen` | Duplicación | Señal de contexto para *re-ranking* blando (no para filtro duro — ver punto 4) |
| `fecha_resolucion` | Duplicación | La recencia es el filtro más relevante para decidir si una resolución vieja sigue siendo válida hoy |
| `hash_contenido` | Derivado | Permite reindexar de forma idempotente sin duplicar filas cuando el proceso de indexación se reintenta o se dispara dos veces sobre el mismo caso |
| `vigente` | Propio de esta tabla | Retira una fila de la búsqueda sin `DELETE` físico, consistente con el criterio de borrado lógico del resto del modelo |
| `embedding` | Propio de esta tabla | Es un dato derivado, de uso exclusivo del subsistema de recuperación; no tiene sentido guardarlo en `consultas`/`respuestas` |

## 4. Consultas por similitud esperadas

```sql
-- Sugerir hasta 3 respuestas historicas mas parecidas a una consulta nueva.
-- El canal YA NO es un filtro duro (WHERE): es una senal de re-ranking
-- blando, para no descartar una buena respuesta solo por haber ocurrido
-- en otro canal. El umbral de distancia es obligatorio -- sin el, esta
-- consulta siempre devuelve 3 filas aunque ninguna se parezca de verdad.
-- La comparacion 0.02 es ilustrativa, a calibrar con datos reales.
-- RLS (via id_cliente/id_ticket) se asume aplicada por policy de la
-- sesion, no repetida aqui a mano.
SELECT
    contenido_pregunta,
    contenido_respuesta,
    embedding <=> '[vector de consulta buscada]'::vector AS distancia
FROM consultas_embeddings
WHERE vigente = TRUE
  AND embedding <=> '[vector de consulta buscada]'::vector < 0.35
ORDER BY
    (embedding <=> '[vector de consulta buscada]'::vector)
    - (CASE WHEN canal_origen = '[canal de origen de la consulta nueva]' THEN 0.02 ELSE 0 END)
LIMIT 3;
```

```sql
-- Detectar consultas frecuentes: para una pregunta de interes (o el
-- centroide de un cluster obtenido por fuera de esta consulta), contar
-- cuantos casos historicos caen dentro del radio de similitud.
-- NO se agrupa por contenido_pregunta: dos redacciones distintas del
-- mismo problema no comparten una palabra, y agrupar por texto literal
-- cuenta duplicados exactos, no consultas parecidas -- contradice el
-- proposito mismo de la busqueda semantica. Para un panel completo de
-- "temas mas consultados" conviene correr esta cuenta por cada centroide
-- de un clustering periodico sobre `embedding`, no por texto agrupado.
SELECT
    COUNT(*) AS ocurrencias_similares
FROM consultas_embeddings
WHERE vigente = TRUE
  AND embedding <=> '[pregunta de interes]'::vector < 0.2;
```

## 5. Restricciones de acceso y riesgos

- `consultas_embeddings` debe tener Row Level Security habilitada, con políticas que comparan directamente sus columnas propias `id_cliente`/`id_ticket` contra la sesión —por ejemplo `id_cliente = current_setting('app.current_cliente_id', true)::int` para el cliente, y equivalente por `id_ticket` para el operador vía los tickets que tiene asignados—, no un `JOIN` contra `consultas`/`respuestas`, que es exactamente lo que estas columnas duplicadas existen para evitar. Un operador o un cliente no deben poder recuperar, vía búsqueda semántica, el contenido de un caso al que no tendrían acceso por la vía relacional normal. Detalle de la implementación de roles y políticas del núcleo en `db/fisico/05_seguridad_permisos.sql`.

- **Riesgo principal:** sugerir una respuesta desactualizada o incorrecta si el contenido original fue corregido después de indexado.
**Mitigación propuesta:** reindexar de forma asíncrona ante cualquier `UPDATE` sobre `respuestas.texto_respuesta` cuando `es_respuesta_final = true`, usando `hash_contenido` para detectar si el contenido cambió de verdad antes de reescribir la fila, y marcando `vigente = false` (en vez de `DELETE`) cuando un caso deja de calificar — por ejemplo, si el ticket se reabre después de haber sido indexado.

- **Riesgo secundario:** filtrar datos sensibles del cliente si el texto de la consulta los contiene (ej. un DNI o email pegado en la pregunta).
**Mitigación propuesta:** anonimizar/enmascarar el texto antes de generar el embedding, no sólo antes de mostrarlo en pantalla.
