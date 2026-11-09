/* Pantallas de administración como catálogos: el listado con los registros actuales, un botón "Nuevo" y acciones en
   cada fila (Editar, Eliminar, Marcar atendido…) que abren el formulario ya lleno o ejecutan tras confirmar.
   smc:acciones (en el procedimiento del listado) = arreglo JSON; cada acción:
     etiqueta   texto del botón
     proc       procedimiento del esquema api que ejecuta (solo se muestra si el usuario lo tiene permitido), o
     vista      pantalla a la que lleva (otro procedimiento o una vista propia como _restablecer)
     fila       true = botón en cada fila; false = botón arriba del listado ("Nuevo …")
     valores    parámetros del formulario: "{Columna}" toma el valor de la fila; otro texto es fijo
     bloquear   parámetros que no se pueden cambiar al editar (la llave)
     directo    true = no abre formulario: pide confirmación y ejecuta
     confirmar  pregunta antes de ejecutar ("{Columna}" se reemplaza)
     exito      mensaje al terminar ("{Parametro}" se reemplaza)
     peligro    true = botón de color de alerta (eliminar)
     ocultarSi  {"Columna": valor}: no se muestra en las filas que lo cumplen (p. ej. roles del sistema)
   Las acciones dejan de estar en el menú (smc:oculto): se usan desde su listado. El permiso no cambia. */
DECLARE @a TABLE (Objeto nvarchar(300), Acciones nvarchar(3750));
INSERT @a VALUES
 ('api.Usuarios_Listar', N'[
   {"etiqueta":"Nuevo usuario","proc":"Usuario_Guardar","fila":false,"exito":"Usuario {Login} creado. Asígnele una contraseña temporal."},
   {"etiqueta":"Editar","proc":"Usuario_Guardar","fila":true,"valores":{"Login":"{Login}","Nombre":"{Nombre}","Activo":"{Activo}","Roles":"{Roles}"},"bloquear":["Login"],"exito":"Usuario {Login} guardado."},
   {"etiqueta":"Contraseña temporal","vista":"_restablecer","fila":true,"valores":{"usuario":"{Login}"}}
 ]'),
 ('api.Roles_Listar', N'[
   {"etiqueta":"Nuevo rol","proc":"Rol_Guardar","fila":false,"exito":"Rol {Nombre} creado. Concédale opciones en Permisos por opción."},
   {"etiqueta":"Permisos por opción","vista":"Permisos_Matriz","fila":false},
   {"etiqueta":"Editar","proc":"Rol_Guardar","fila":true,"valores":{"Nombre":"{Nombre}","Descripcion":"{Descripcion}"},"bloquear":["Nombre"],"exito":"Rol {Nombre} guardado."},
   {"etiqueta":"Eliminar","proc":"Rol_Eliminar","fila":true,"valores":{"Nombre":"{Nombre}"},"directo":true,"peligro":true,
    "confirmar":"¿Eliminar el rol {Nombre}? No se puede deshacer.","exito":"Rol {Nombre} eliminado.","ocultarSi":{"EsSistema":true}}
 ]'),
 ('api.Usuarios_Externos_Listar', N'[
   {"etiqueta":"Nuevo cliente","proc":"Usuario_Guardar","fila":false,"valores":{"Roles":"Cliente"},"exito":"Cliente {Login} creado. Asígnele sus organizaciones."},
   {"etiqueta":"Organizaciones","proc":"Usuario_Organizaciones_Guardar","fila":true,"valores":{"Login":"{Login}","Organizaciones":"{Organizaciones}"},"bloquear":["Login"],"exito":"Organizaciones de {Login} guardadas."},
   {"etiqueta":"Editar","proc":"Usuario_Guardar","fila":true,"valores":{"Login":"{Login}","Nombre":"{Nombre}","Activo":"{Activo}","Roles":"{Roles}"},"bloquear":["Login"],"exito":"Usuario {Login} guardado."},
   {"etiqueta":"Contraseña temporal","vista":"_restablecer","fila":true,"valores":{"usuario":"{Login}"}}
 ]'),
 ('api.Avisos_Listar', N'[
   {"etiqueta":"Marcar atendido","proc":"Aviso_Atender","fila":true,"valores":{"EventoId":"{EventoId}"},"directo":true,
    "confirmar":"¿Marcar como atendido el aviso del {Fecha}?","exito":"Aviso marcado como atendido.","ocultarSi":{"Atendido":true}}
 ]'),
 ('api.Sync_Frecuencias_Listar', N'[
   {"etiqueta":"Cambiar frecuencia","proc":"Sync_Frecuencia_Guardar","fila":true,"valores":{"Fuente":"{Fuente}","Entidad":"{Entidad}","FrecuenciaMin":"{FrecuenciaMin}"},"bloquear":["Fuente","Entidad"],"exito":"Frecuencia de {Entidad} guardada: cada {FrecuenciaMin} minutos."},
   {"etiqueta":"Cambiar margen de atraso","proc":"Sync_Antiguedad_Guardar","fila":true,"valores":{"Fuente":"{Fuente}","MaxAntiguedadMin":"{MaxAntiguedadMin}"},"bloquear":["Fuente"],"exito":"Margen guardado: {MaxAntiguedadMin} minutos."}
 ]'),
 ('api.Mapeos_Listar', N'[
   {"etiqueta":"Asignar campo","proc":"Mapeo_Establecer","fila":true,"valores":{"Fuente":"{Fuente}","Rol":"{Rol}","CampoId":"{CampoId}"},"bloquear":["Fuente","Rol"],"exito":"Campo asignado a {Rol}."}
 ]'),
 ('api.Proyectos_Listar', N'[
   {"etiqueta":"Ver horas","vista":"Horas_Arbol","fila":true,"valores":{"Proyecto":"{Clave}"}},
   {"etiqueta":"Buscar sus issues","vista":"Issues_Buscar","fila":true,"valores":{"Proyecto":"{Clave}"}}
 ]');

DECLARE @o nvarchar(300), @j nvarchar(3750);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT Objeto, Acciones FROM @a WHERE OBJECT_ID(Objeto) IS NOT NULL;
OPEN c; FETCH c INTO @o, @j;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF ISJSON(@j) = 0 BEGIN DECLARE @m nvarchar(400) = N'smc:acciones inválido en ' + @o; THROW 50000, @m, 1; END;
    EXEC adm.Descripcion_Establecer @Objeto = @o, @Nombre = N'smc:acciones', @Valor = @j;
    FETCH c INTO @o, @j;
END;
CLOSE c; DEALLOCATE c;

-- Las acciones se usan desde su listado: fuera del menú.
DECLARE @ocultar TABLE (Objeto nvarchar(300));
INSERT @ocultar VALUES ('api.Usuario_Guardar'), ('api.Rol_Guardar'), ('api.Rol_Eliminar'), ('api.Usuario_Organizaciones_Guardar'),
                       ('api.Aviso_Atender'), ('api.Sync_Frecuencia_Guardar'), ('api.Sync_Antiguedad_Guardar'), ('api.Mapeo_Establecer');
DECLARE co CURSOR LOCAL FAST_FORWARD FOR SELECT Objeto FROM @ocultar WHERE OBJECT_ID(Objeto) IS NOT NULL;
OPEN co; FETCH co INTO @o;
WHILE @@FETCH_STATUS = 0 BEGIN EXEC adm.Descripcion_Establecer @Objeto = @o, @Nombre = N'smc:oculto', @Valor = N'1'; FETCH co INTO @o; END;
CLOSE co; DEALLOCATE co;

-- Listas para elegir sprints, épicas y personas, dependientes del proyecto elegido en el mismo formulario.
DECLARE @l TABLE (Objeto nvarchar(300), Parametro sysname, Origen nvarchar(400), Ayuda nvarchar(300));
INSERT @l VALUES
 ('api.Horas_PorSprint',   '@Sprint',        N'Sprints_Listar(Proyecto=@Proyecto):Valor:Etiqueta:Detalle', N'Elija el sprint (elija antes el proyecto para ver solo los suyos)'),
 ('api.Horas_PorSprintArbol', '@Sprint',   N'Sprints_Listar(Proyecto=@Proyecto):Valor:Etiqueta:Detalle', N'Elija el sprint (elija antes el proyecto para ver solo los suyos)'),
 ('api.Horas_PorSprintArbol', '@Persona',  N'Personas_Listar(Proyecto=@Proyecto):Nombre:Nombre:Detalle',  N'Una persona (vacío = todas)'),
 ('api.Estimacion_VsReal', '@Sprint',        N'Sprints_Listar(Proyecto=@Proyecto):Valor:Etiqueta:Detalle', N'Elija el sprint (elija antes el proyecto para ver solo los suyos)'),
 ('api.Estimacion_VsReal', '@Epica',         N'Epicas_Listar(Proyecto=@Proyecto):Valor:Etiqueta:Detalle',  N'Elija la épica (elija antes el proyecto para ver solo las suyas)'),
 ('api.Horas_PorPersonaArbol', '@Epica',    N'Epicas_Listar(Proyecto=@Proyecto):Valor:Etiqueta:Detalle',  N'Elija la épica (elija antes el proyecto para ver solo las suyas)'),
 ('api.Horas_PorPersonaArbol', '@Persona',  N'Personas_Listar(Proyecto=@Proyecto):Nombre:Nombre:Detalle',  N'Una persona (vacío = todas)'),
 ('api.Horas_PorPersona',  '@Epica',         N'Epicas_Listar(Proyecto=@Proyecto):Valor:Etiqueta:Detalle',  N'Elija la épica (elija antes el proyecto para ver solo las suyas)'),
 ('api.Estimacion_VsReal', '@Responsable',   N'Personas_Listar(Proyecto=@Proyecto):Nombre:Nombre:Detalle',  N'Responsable de la tarea'),
 ('api.Horas_Arbol',       '@Persona',       N'Personas_Listar(Proyecto=@Proyecto):Nombre:Nombre:Detalle',  N'Quien registró (o a quien se atribuyen las automáticas)'),
 ('api.Issues_Buscar',     '@ResponsableId', N'Personas_Listar(Proyecto=@Proyecto):AccountId:Nombre:Detalle', N'Responsable actual');
DECLARE @p sysname, @origen nvarchar(400), @ayuda nvarchar(300);
DECLARE cl CURSOR LOCAL FAST_FORWARD FOR
    SELECT Objeto, Parametro, Origen, Ayuda FROM @l
    WHERE EXISTS (SELECT 1 FROM sys.parameters x WHERE x.object_id = OBJECT_ID(Objeto) AND x.name = Parametro);
OPEN cl; FETCH cl INTO @o, @p, @origen, @ayuda;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC adm.Descripcion_Establecer @Objeto = @o, @Parametro = @p, @Nombre = N'smc:origen', @Valor = @origen;
    EXEC adm.Descripcion_Establecer @Objeto = @o, @Parametro = @p, @Nombre = N'MS_Description', @Valor = @ayuda;
    FETCH cl INTO @o, @p, @origen, @ayuda;
END;
CLOSE cl; DEALLOCATE cl;
GO
