/* Solo inserta los parámetros que falten: no pisa valores que el administrador haya cambiado. */
MERGE cfg.Parametro AS t
USING (VALUES
    ('TraslapeMin',           N'5',   N'Minutos que se restan a la marca de agua al pedir cambios a Jira.'),
    ('DiasCargaInicial',      N'730', N'Días hacia atrás en la primera carga de una entidad incremental.'),
    ('TamanoLoteProceso',     N'200', N'Documentos por transacción al integrar raw -> ops.'),
    ('MaxIntentosDocumento',  N'3',   N'Fallos antes de dejar un documento en cuarentena.'),
    ('UmbralBajaCatalogoPct', N'50',  N'Porcentaje mínimo del catálogo que debe llegar para dar de baja campos, proyectos o issues.'),
    ('ContrasenaLongitudMinima', N'10', N'Caracteres mínimos de una contraseña.'),
    ('IntentosFallidosMaximos',  N'5',  N'Intentos fallidos seguidos antes de bloquear la cuenta.'),
    ('MinutosBloqueo',           N'15', N'Minutos que la cuenta queda bloqueada tras los intentos fallidos.')
) AS s (Clave, Valor, Descripcion) ON t.Clave = s.Clave
WHEN NOT MATCHED THEN INSERT (Clave, Valor, Descripcion) VALUES (s.Clave, s.Valor, s.Descripcion);
GO
