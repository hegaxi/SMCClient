/* Configuración de la instancia smco.atlassian.net. NO forma parte del despliegue ordenado
   (es propia de este ambiente); se ejecuta una vez después de deploy y se puede repetir. */
EXEC sync.Fuente_Registrar @Codigo = 'smco', @Tipo = 'jira-cloud', @UrlBase = N'https://smco.atlassian.net',
     @CloudId = '68e377d9-bfb6-47f8-b84b-8136cc23876b';

-- Proyectos de pruebas: no se sincronizan ni aparecen en reportes.
EXEC sync.Proyecto_Excluir @Fuente = 'smco', @Clave = 'TS25',   @Motivo = N'Pruebas-SIAMCO25';
EXEC sync.Proyecto_Excluir @Fuente = 'smco', @Clave = 'TSM26',  @Motivo = N'PRUEBAS-SIAMCO26';
EXEC sync.Proyecto_Excluir @Fuente = 'smco', @Clave = 'TSSM26', @Motivo = N'SCRUM PRUEBAS SIAMCO 26';
GO
