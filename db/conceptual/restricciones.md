# Restricciones del dominio

- La calificación (`calificacion`) de una `Conversación` es otorgada por el cliente y debe estar en el rango de 1 a 5.
- En `Respuesta`, el campo `es_respuesta_final` indica cuál fue la respuesta que efectivamente resolvió la consulta o cerró la conversación. Por cada `Consulta`, solo una `Respuesta` puede tener `es_respuesta_final = true`, aunque existan varias respuestas asociadas (sugeridas por IA, corregidas por un operador, etc.).
- Todo `Ticket` debe abrirse con un `canal_origen` definido (ej. WhatsApp, email, web), tomado de un dominio cerrado de valores válidos (`chat`, `email`, `whatsapp`, `telefono`, `web`).
- Todo `Ticket` debe estar asociado a un `Cliente`; no puede existir un ticket sin cliente asignado.
- El `Cliente` se autentica en la plataforma web o a través de facilitar información privada como DNI, email o número de teléfono, por lo que sus datos (`id_cliente`, entre otros) están disponibles y validados al momento de generar un `Ticket`.
- El `TicketLog` registra el historial de estados por los que atraviesa un `Ticket`. Cada entrada del log está asociada obligatoriamente a una fecha (`fecha`) y a un `Empleado` responsable de la gestión en ese momento.
- El campo `es_humano` de `Respuesta` es un dominio cerrado con dos valores posibles (implementado como `BOOLEAN`: `TRUE` = respuesta humana, `FALSE` = respuesta generada por IA).