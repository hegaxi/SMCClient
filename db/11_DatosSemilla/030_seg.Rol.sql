/* Roles de sistema. Solo inserta lo que falte: no pisa permisos que el administrador haya cambiado. */
MERGE seg.Rol AS t
USING (VALUES
    (N'Administrador', N'Todo: consultas y administración (usuarios, roles, mapeo de campos, avisos).'),
    (N'Consulta',      N'Todas las consultas de Scrum y mesa de ayuda.')
) AS s (Nombre, Descripcion) ON t.Nombre = s.Nombre
WHEN NOT MATCHED THEN INSERT (Nombre, Descripcion, EsSistema) VALUES (s.Nombre, s.Descripcion, 1);

INSERT seg.RolPermiso (RolId, Permiso)
SELECT r.RolId, p.Permiso
FROM seg.Rol r
JOIN (VALUES (N'Administrador', N'admin'), (N'Administrador', N'lectura'), (N'Consulta', N'lectura')) p (Rol, Permiso) ON p.Rol = r.Nombre
WHERE NOT EXISTS (SELECT 1 FROM seg.RolPermiso x WHERE x.RolId = r.RolId)   -- solo roles recién creados
  AND r.EsSistema = 1;
GO
