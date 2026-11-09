/* Valores de TODOS los campos (incluidos los que se creen mañana) sin cambiar la estructura.
   Un campo de varios valores (multiselect, etiquetas, sprints) genera una fila por valor (Orden). */
IF OBJECT_ID('ops.IssueCampoValor', 'U') IS NULL
CREATE TABLE ops.IssueCampoValor (
    IssueSk      bigint          NOT NULL,
    CampoId      varchar(100)    NOT NULL,
    Orden        smallint        NOT NULL,
    ValorTexto   nvarchar(4000)  NULL,
    ValorNumero  decimal(19,4)   NULL,
    ValorFecha   datetimeoffset(3) NULL,
    ValorId      varchar(200)    NULL,         -- id de opción, accountId, key...
    ValorJson    nvarchar(max)   NULL,         -- estructuras que no se reconocen (nunca se pierden)
    CONSTRAINT PK_ops_IssueCampoValor PRIMARY KEY (IssueSk, CampoId, Orden)
);
GO
