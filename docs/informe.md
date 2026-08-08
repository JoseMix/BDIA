
### 1. Descripción del caso de uso
* **Problema a resolver:** [Describir el problema elegido y el contexto de aplicación].
* **Usuarios principales:** [].
* **Procesos y funcionalidades:** [Detallar los procesos principales que debe soportar la solución].

### 2. Relevamiento de datos necesarios
* **Información requerida:** [Enumerar y describir los datos que la solución necesita almacenar o consultar].
[Ver ejemplos en *datos/* o *data/ejemplos*].
* **Riesgos asociados:** [Identificar riesgos potenciales en relación con la gestión de estos datos].

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
* **Estrategia adoptada:** [Explicar los criterios de diseño aplicados].
* **Justificación técnica:** Justificar la elección (evitar redundancias/anomalías en relacionales o analizar los compromisos y ventajas de embeber/referenciar/desnormalizar en NoSQL) en función de los patrones de consulta esperados.

### 7. Justificación de la tecnología seleccionada
Explicación detallada de por qué se eligieron las tecnologías de base de datos para el proyecto, considerando:
* Tipo, estructura, variabilidad y volumen esperado de los datos.
* Patrones de consulta y consistencia requerida.
* Complejidad operativa, seguridad, escalabilidad y comparativa frente a otras alternativas.

### 8. Implementación mínima realizada
* **Alcance de la implementación:** [Resumen de los componentes principales creados].
* **Scripts / Definición de estructuras:** Referencia a los archivos de creación de tablas, colecciones o esquemas ubicados en el repositorio.

### 9. Datos de ejemplo utilizados
* **Estructura de prueba:** Descripción de los datos sintéticos o de muestra generados.
* **Validación:** Coherencia de los datos para validar de forma efectiva las entidades, relaciones y consultas clave del modelo.

### 10. Consultas representativas
Breve explicación de la utilidad de cada una de las 5 consultas mínimas requeridas, adjuntando el código correspondiente:
1. **Consulta 1 (Selección y filtrado):** [Explicación y código].
2. **Consulta 2 (Información relacionada / JOINs):** [Explicación y código].
3. **Consulta 3 (Agregaciones / Indicadores):** [Explicación y código].
4. **Consulta 4 (Toma de decisiones):** [Explicación y código].
5. **Consulta 5 (Optimización mediante Índices/Vistas):** [Explicación y código que justifique el uso de estas estructuras].

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

