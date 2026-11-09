# Prueba de carga

Mide las consultas de la aplicación con un volumen realista. Los datos imitan la forma del Jira real de smco:
Automation for Jira registra 8 h por día hábil en cada tarea o épica abierta, y las personas registran en las subtareas.

| Datos sintéticos (`010_generar_datos.sql`, fuente `carga`) | Cantidad |
|---|---|
| Issues Scrum: épicas / tareas / subtareas | 300 / 2 700 / 2 000 |
| Tickets de mesa de ayuda (2 SLA cada uno) | 3 000 |
| Worklogs (automáticos / de personas) | 515 000 (450 000 / 65 000) |
| Cambios de historial (responsable y estado) | 25 000 |
| Sprints de 2 semanas | 26 |

```bash
# Sobre una base recién desplegada (no se ejecuta con las pruebas normales):
sqlcmd -d SMCClient -b -I -i tests/carga/010_generar_datos.sql
sqlcmd -d SMCClient -I -i tests/carga/020_medir.sql -o medir.txt
grep '^MEDICION' medir.txt     # caso | primera vez (con compilación) ms | mediana ms | presupuesto ms | resultado
```

Presupuesto: 1,5 s para consultas interactivas (búsqueda, detalle, estado) y 3 s para reportes. Cada caso corre 4 veces;
la mediana es de las 3 últimas.

## Resultados (SQL Server 2022 en contenedor, 4 núcleos)

| Caso | Antes | Después |
|---|---|---|
| Búsqueda: columnas épica y horas, orden por horas | 17 568 ms | 100 ms |
| Búsqueda: horas registradas > 50 | 6 119 ms | 54 ms |
| Widget: horas registradas por épica | 31 534 ms | 295 ms |
| Horas por persona: último año | 25 645 ms | 259 ms |
| Horas por sprint (todos) | 16 069 ms | 538 ms |
| Avance de sprints | más de 10 min | 133 ms |
| Detalle de una épica | 145 ms | 50 ms |
| Resto de los casos (búsquedas, valores, conteos, épicas, estado) | 0 – 2 000 ms | 4 – 294 ms |

Qué cambió: la atribución de horas (a quién se le cuentan las automáticas), las horas de cada issue con todo su árbol y
su épica se calculaban **en cada consulta**, fila por fila. Ahora se calculan **al integrar** y se guardan
(`ops.Worklog.EsAutomatico / AtribuidoAId / MetodoAtribucion` con `sync.Worklog_Atribuir`, y `ops.IssueResumen` con
`sync.Resumen_Recalcular`), solo para los issues tocados en cada corrida (`sync.Derivados_Actualizar`). Los reportes de
sprint usan tablas temporales indexadas y los worklogs se unen por la llave que tiene índice (`FuenteId, IssueId`).

Costo de mantenerlo, medido en la misma carga:

| Recálculo | Tiempo |
|---|---|
| Por corrida del worker (50 issues tocados) | ~1 s |
| Completo de la fuente: resumen por issue | 0,6 s |
| Completo de la fuente: atribución de 515 000 worklogs (solo tras una migración o un reproceso) | ~31 s |
