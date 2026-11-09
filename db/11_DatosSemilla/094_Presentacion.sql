/* Presentación de los reportes de tiempo (la interfaz lo lee de los metadatos; ver CatalogoProcedimientos):
   smc:inicial              (parámetro) con qué se llena el campo al abrir aunque sea opcional: inicio_mes | inicio_anio | hoy.
                            Todos los reportes de horas abren con el mes en curso.
   smc:columnasSecundarias  columnas que no se muestran hasta "Más columnas" (siguen en el CSV).
   smc:ayudaColumnas        JSON {"Columna": "qué significa"}: se ve al pasar sobre el encabezado. */

-- Horas por proyecto: mes en curso por omisión (antes abría con todo el historial).
EXEC adm.Descripcion_Establecer 'api.Horas_Arbol', '@Desde', N'smc:inicial', N'inicio_mes';
EXEC adm.Descripcion_Establecer 'api.Horas_Arbol', '@Hasta', N'smc:inicial', N'hoy';
EXEC adm.Descripcion_Establecer 'api.Horas_Arbol', '@Desde', N'MS_Description', N'Fecha del registro de tiempo. Vacío = desde el inicio';
EXEC adm.Descripcion_Establecer 'api.Horas_Arbol', '@Hasta', N'MS_Description', N'Vacío = hasta hoy';

DECLARE @ayudaHoras nvarchar(3750) = N'{
 "HorasRegistradas": "Horas que registraron las personas en este elemento y en todo lo que tiene debajo (subtareas, tareas). No incluye copias.",
 "HorasAutomaticas": "Horas que registró una automatización y que no son copia de otro registro (se cuentan aparte).",
 "HorasCopiadas": "Copias que Automation for Jira hace del registro de una subtarea en su tarea, su épica y la OC. NO se suman: ese trabajo ya cuenta donde se registró.",
 "HorasPropias": "Horas registradas directamente en este elemento, sin contar lo que tiene debajo.",
 "HorasTotales": "Registradas por personas + automáticas (sin copias).",
 "HorasEstimadas": "Estimación original de Jira, sin contar dos veces la de una tarea y la de sus subtareas.",
 "PorcentajeConsumido": "Horas registradas / horas estimadas.",
 "Elementos": "Tickets debajo de este elemento.",
 "Abiertos": "Tickets debajo de este elemento que no están terminados.",
 "IssuesConHoras": "Tickets con horas en el periodo.",
 "UltimoRegistro": "Fecha del registro de tiempo más reciente (sin copias)."
}';
EXEC adm.Descripcion_Establecer 'api.Horas_Arbol', NULL, N'smc:ayudaColumnas', @ayudaHoras;
EXEC adm.Descripcion_Establecer 'api.Horas_Arbol', NULL, N'smc:columnasSecundarias', N'Tipo,Responsable,HorasAutomaticas,HorasCopiadas,HorasPropias,Elementos,Abiertos';
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersonaArbol', NULL, N'smc:ayudaColumnas', @ayudaHoras;
EXEC adm.Descripcion_Establecer 'api.Horas_PorPersonaArbol', NULL, N'smc:columnasSecundarias', N'Tipo,HorasRegistradas,HorasAutomaticas,HorasPropias';
EXEC adm.Descripcion_Establecer 'api.Horas_PorSprintArbol', NULL, N'smc:ayudaColumnas', @ayudaHoras;
EXEC adm.Descripcion_Establecer 'api.Horas_PorSprintArbol', NULL, N'smc:columnasSecundarias', N'Tipo,HorasRegistradas,HorasAutomaticas,HorasPropias';

-- Estimado vs. real
EXEC adm.Descripcion_Establecer 'api.Estimacion_VsReal', NULL, N'smc:ayudaColumnas', N'{
 "HorasEstimadas": "Estimación original de Jira (en una épica, la suma de sus tareas).",
 "HorasRegistradas": "Todo lo que registraron las personas, con subtareas (incluye lo que no tiene estimación).",
 "HorasSinEstimacion": "Parte de lo registrado que está en tareas sin estimación (o en la propia épica): no entra en la desviación.",
 "HorasRestantes": "Estimación restante de Jira de lo que sigue abierto.",
 "HorasProyectadas": "Registrado en lo estimado + restante: en cuánto va a terminar si se cumple lo restante.",
 "DesviacionHoras": "Registrado en lo estimado − estimado. Positivo (+) = se pasó.",
 "PorcentajeConsumo": "Registrado en lo estimado / estimado.",
 "HorasRegistradasEstimados": "Lo registrado solo en lo que tiene estimación (la base de la desviación).",
 "Situacion": "Excedida: registró más de lo estimado. En riesgo: abierta y lo registrado + lo restante ya supera lo estimado.",
 "Tareas": "Tareas e historias debajo.",
 "TareasSinEstimacion": "Tareas e historias debajo que no tienen estimación."
}';
EXEC adm.Descripcion_Establecer 'api.Estimacion_VsReal', NULL, N'smc:columnasSecundarias', N'Tipo,Responsable,HorasRestantes,HorasProyectadas,Tareas';

-- Tiempos invertidos (reporte dinámico con una columna por periodo).
DECLARE @agrupar nvarchar(400) = N'persona=Persona|proyecto=Proyecto|epica=Épica|tarea=Tarea (con sus subtareas)|issue=Ticket|tipo=Tipo de ticket|estado=Estado|ninguna=Ninguna';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', NULL, N'smc:resultados', N'Tiempo por periodo';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Desde', N'smc:inicial', N'inicio_anio';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Hasta', N'smc:inicial', N'hoy';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Desde', N'MS_Description', N'Fecha del registro de tiempo (inclusive)';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Hasta', N'MS_Description', N'Fecha final (inclusive)';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Proyecto', N'smc:origen', N'Proyectos_Listar:Clave:Clave:Nombre';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Proyecto', N'smc:multiple', N'|';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Proyecto', N'MS_Description', N'Uno o varios. Vacío = todos';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Persona', N'smc:origen', N'Personas_Listar(Proyecto=@Proyecto):Nombre:Nombre:Detalle';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Persona', N'smc:multiple', N'|';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Persona', N'MS_Description', N'Una o varias (a quien se atribuye el tiempo). Vacío = todas';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Sprint', N'smc:origen', N'Sprints_Listar(Proyecto=@Proyecto):Valor:Etiqueta:Detalle';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Sprint', N'MS_Description', N'Solo el tiempo de los tickets del sprint registrado mientras estuvo abierto';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Periodo', N'smc:opciones', N'dia=Día|semana=Semana|mes=Mes|trimestre=Trimestre|anio=Año|ninguno=Sin columnas por periodo';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Periodo', N'MS_Description', N'Una columna por cada periodo del rango (máximo 120)';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Categoria', N'smc:opciones', @agrupar;
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Categoria', N'MS_Description', N'Primer nivel de filas';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Grupo', N'smc:opciones', @agrupar;
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Grupo', N'MS_Description', N'Segundo nivel, dentro de cada categoría';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Secundaria', N'smc:opciones', @agrupar;
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Secundaria', N'MS_Description', N'Tercer nivel, dentro de cada grupo';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@Unidad', N'smc:opciones', N'horas=Horas|dias=Días';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', '@HorasPorDia', N'MS_Description', N'Horas de un día cuando la unidad es Días';
EXEC adm.Descripcion_Establecer 'api.Tiempos_Invertidos', NULL, N'smc:ayudaColumnas', N'{
 "Total": "Tiempo de todo el rango de fechas (registrado por personas y automático real; sin las copias de Automation for Jira)."
}';
