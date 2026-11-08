IF OBJECT_ID('ops.IssueSprint', 'U') IS NULL
CREATE TABLE ops.IssueSprint (
    IssueSk   bigint NOT NULL,
    FuenteId  int    NOT NULL,
    SprintId  bigint NOT NULL,
    CONSTRAINT PK_ops_IssueSprint PRIMARY KEY (IssueSk, SprintId)
);
GO
