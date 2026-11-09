/* Calcula los datos derivados (atribución de worklogs y ops.IssueResumen) donde falten: la primera vez después de la
   migración 0005, o si alguien cargó datos por fuera de la integración. Si ya están, no hace nada. */
DECLARE @f int, @vacio sync.IdTipo;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT f.FuenteId FROM cfg.Fuente f
    WHERE EXISTS (SELECT 1 FROM ops.Worklog w WHERE w.FuenteId = f.FuenteId AND w.MetodoAtribucion IS NULL)
       OR EXISTS (SELECT 1 FROM ops.Issue i WHERE i.FuenteId = f.FuenteId AND NOT EXISTS (SELECT 1 FROM ops.IssueResumen r WHERE r.IssueSk = i.IssueSk));
OPEN c; FETCH c INTO @f;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sync.Worklog_Atribuir @FuenteId = @f, @Issues = @vacio, @Todo = 1;
    EXEC sync.Resumen_Recalcular @FuenteId = @f, @Issues = @vacio, @Todo = 1;
    FETCH c INTO @f;
END;
CLOSE c; DEALLOCATE c;
GO
