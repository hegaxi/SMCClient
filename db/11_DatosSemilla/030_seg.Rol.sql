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
JOIN (VALUES (N'Administrador', N'admin'), (N'Administrador', N'lectura'), (N'Administrador', N'usuario'),
            (N'Consulta', N'lectura'), (N'Consulta', N'usuario')) p (Rol, Permiso) ON p.Rol = r.Nombre
WHERE NOT EXISTS (SELECT 1 FROM seg.RolPermiso x WHERE x.RolId = r.RolId)   -- solo roles recién creados
  AND r.EsSistema = 1;

-- Rol externo para clientes: solo la opción "Consultas personalizadas" (las compartidas con ellos o con el rol), limitadas
-- a los tickets de sus organizaciones. El administrador puede renombrarlo, darle tableros o filtros, o crear otros.
IF NOT EXISTS (SELECT 1 FROM seg.Rol WHERE EsExterno = 1) AND NOT EXISTS (SELECT 1 FROM seg.Rol WHERE Nombre = N'Cliente')
BEGIN
    INSERT seg.Rol (Nombre, Descripcion, EsSistema, EsExterno)
    VALUES (N'Cliente', N'Clientes externos: solo las consultas personalizadas compartidas, con los tickets de su organización.', 0, 1);
    INSERT seg.RolPermiso (RolId, Permiso) SELECT RolId, N'consultas_personalizadas' FROM seg.Rol WHERE Nombre = N'Cliente';
END;
GO
