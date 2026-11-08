# SMCClient

Consulta de proyectos Scrum (Jira Software) y de mesa de ayuda (Jira Service Management):
tickets, historias, tiempo invertido, SLA y avance de sprints.

- **Base de datos:** SQL Server 2017+ (recomendado 2019+). Ver [`db/README.md`](db/README.md).
- **API:** C# (.NET 8) con un solo controlador que descubre y ejecuta los procedimientos del esquema `api`. *(pendiente)*
- **Interfaz:** React. *(pendiente)*

La arquitectura, cómo resiste cambios en Jira y cómo funciona la sincronización están en
[`docs/arquitectura.md`](docs/arquitectura.md).

## Estado

| Parte | Estado |
|---|---|
| Base de datos (esquemas, tablas, integración `raw → ops`, API en SQL, despliegue ordenado, pruebas) | Lista |
| Worker de sincronización (C#) | Pendiente |
| Controlador único (C#) | Pendiente |
| Interfaz (React) | Pendiente |
