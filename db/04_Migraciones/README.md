# Migraciones

Los scripts de `03_Tablas` describen la **forma más reciente** de cada tabla y solo crean la tabla si no existe.
Cuando una tabla que ya está en producción cambia (columna nueva, tipo distinto, columna eliminada),
el cambio se escribe aquí como script **numerado y protegido**, por ejemplo:

```
04_Migraciones/0001_ops.Issue_AgregarEquipo.sql
```

```sql
IF COL_LENGTH('ops.Issue', 'EquipoId') IS NULL
    ALTER TABLE ops.Issue ADD EquipoId varchar(50) NULL;
GO
```

Reglas:

1. Se ejecutan **una sola vez** por base de datos (los registra `adm.ScriptEjecutado`).
2. Aun así, cada sentencia va protegida (`IF COL_LENGTH ... IS NULL`), porque en una base nueva la tabla ya se creó con la forma final.
3. Al mismo tiempo se actualiza el `CREATE TABLE` en `03_Tablas`, para que las instalaciones nuevas nazcan con la forma correcta.
4. Nunca se edita una migración ya publicada: se agrega otra con el número siguiente.
