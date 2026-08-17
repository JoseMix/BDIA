# Modelo de datos vectorial (extensión pgvector)

## 1. ¿Qué se vectoriza?

Se vectoriza el texto de **consultas de clientes ya resueltas**, junto con el texto de su **respuesta final** (`respuestas.es_respuesta_final = true`). No se vectorizan consultas todavía abiertas ni respuestas intermedias/descartadas; sólo interesa el conocimiento ya validado como resolución correcta de un caso, que es el que tiene sentido reutilizar como sugerencia para casos futuros.

## 2. Tabla propuesta

```sql

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE consultas_embeddings (
    id_embedding         SERIAL PRIMARY KEY,
    id_consulta          INTEGER NOT NULL REFERENCES consultas(id_consulta),
    id_respuesta         INTEGER NOT NULL REFERENCES respuestas(id_respuesta),
    contenido_pregunta   TEXT NOT NULL,         
    contenido_respuesta  TEXT NOT NULL,         
    canal_origen         VARCHAR(20) NOT NULL,
    embedding            VECTOR(1536) NOT NULL, -- Tamaño sujeto a modelo de embedding utilizado (openAI en este caso)
    modelo_embedding     TEXT NOT NULL,         -- Ejemplo: 'text-embedding-3-small'
    fecha_indexacion     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_consultas_embeddings_hnsw
    ON consultas_embeddings USING hnsw (embedding vector_cosine_ops); --Indice HNSW basado en grafos de proximidad y distancia coseno
```

## 3. Decisión de modelado: referencia + duplicación parcial

| Dato | Estrategia | Motivo |
|---|---|---|
| `id_consulta`, `id_respuesta` | Referencia (FK) | Permite trazar cada sugerencia hasta el caso real y auditar el origen de una respuesta sugerida |
| `contenido_pregunta`, `contenido_respuesta` | Duplicación (desnormalización controlada) | Evita un `JOIN` contra las tablas transaccionales en el camino caliente de cada búsqueda por similitud |
| `canal_origen` | Duplicación | Permite filtrar sugerencias por canal sin JOIN adicional (ej. priorizar respuestas ya usadas antes por WhatsApp) |
| `embedding` | Propio de esta tabla | Es un dato derivado, de uso exclusivo del subsistema de recuperación; no tiene sentido guardarlo en `consultas`/`respuestas` |

## 4. Consultas por similitud esperadas

```sql
-- Sugerir hasta 3 respuestas históricas más parecidas a una consulta nueva del canal WhatsApp
SELECT contenido_pregunta, contenido_respuesta,
       embedding <=> '[vector de consulta buscada]'::vector AS distancia
FROM consultas_embeddings
WHERE canal_origen = 'whatsapp'
ORDER BY embedding <=> '[vector de consulta buscada]'::vector
LIMIT 3;
```

```sql
-- Detectar consultas frecuentes: agrupar por cercanía a un conjunto de preguntas de interes
-- (uso típico: alimentar un panel de "temas más consultados" para supervisores)
SELECT contenido_pregunta, COUNT(*) AS ocurrencias_similares
FROM consultas_embeddings
WHERE embedding <=> '[pregunta de interes]'::vector < 0.2
GROUP BY contenido_pregunta
ORDER BY ocurrencias_similares DESC;
```

## 5. Restricciones de acceso y riesgos

- `consultas_embeddings` debe respetar la misma política de aislamiento que `consultas`/`respuestas` (Row Level Security): un operador o un cliente no deben poder recuperar, vía búsqueda semántica, el contenido de un caso al que no tendrían acceso por la vía relacional normal.

- **Riesgo principal:** sugerir una respuesta desactualizada o incorrecta si el contenido original fue corregido después de indexado. 
**Mitigación propuesta:** reindexar de forma asíncrona ante cualquier `UPDATE` sobre `respuestas.texto_respuesta` cuando `es_respuesta_final = true`.

- **Riesgo secundario:** filtrar datos sensibles del cliente si el texto de la consulta los contiene (ej. un DNI o email pegado en la pregunta). 
**Mitigación propuesta:** anonimizar/enmascarar el texto antes de generar el embedding, no sólo antes de mostrarlo en pantalla.
