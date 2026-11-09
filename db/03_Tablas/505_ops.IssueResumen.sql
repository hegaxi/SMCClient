/* Datos derivados por issue, calculados al integrar (sync.Resumen_Recalcular) para no recalcularlos en cada consulta:
   horas propias y de todo su árbol (épica → tareas → subtareas), separadas en registradas por personas y automáticas,
   estimación del árbol, último registro y épica a la que pertenece. La prueba de carga (db/tests/carga) mostró que
   calcularlos al consultar tomaba de 6 a 30 s con 500 000 worklogs. */
IF OBJECT_ID('ops.IssueResumen', 'U') IS NULL
CREATE TABLE ops.IssueResumen (
    IssueSk              bigint         NOT NULL CONSTRAINT PK_ops_IssueResumen PRIMARY KEY,
    FuenteId             int            NOT NULL,
    IssueId              varchar(30)    NOT NULL,
    SegRegPropios        bigint         NULL,     -- NULL = sin worklogs de ese origen
    SegAutPropios        bigint         NULL,     -- automáticas que NO son copia de otro worklog
    SegCopiaPropios      bigint         NULL,     -- copias automáticas de worklogs de otros issues (no se suman)
    UltimoRegistroPropio datetimeoffset(3) NULL,
    SegRegArbol          bigint         NULL,
    SegAutArbol          bigint         NULL,
    SegCopiaArbol        bigint         NULL,
    EstimacionArbolSeg   bigint         NULL,
    UltimoRegistroArbol  datetimeoffset(3) NULL,
    EpicaIssueId         varchar(30)    NULL,     -- id de Jira de su épica (él mismo si es épica)
    Actualizado          datetimeoffset(3) NOT NULL CONSTRAINT DF_ops_IssueResumen_Actualizado DEFAULT SYSDATETIMEOFFSET()
);
GO
