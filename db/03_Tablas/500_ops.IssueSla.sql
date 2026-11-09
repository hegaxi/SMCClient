/* SLA de Jira Service Management, uno por SLA y ciclo (un ticket reabierto tiene varios ciclos).
   Ciclo 0 = ciclo en curso; 1..n = ciclos completados. Los SLA nuevos aparecen solos (SlaId + Nombre). */
IF OBJECT_ID('ops.IssueSla', 'U') IS NULL
CREATE TABLE ops.IssueSla (
    IssueSk           bigint         NOT NULL,
    SlaId             varchar(30)    NOT NULL,
    Ciclo             smallint       NOT NULL,
    Nombre            nvarchar(255)  NOT NULL,   -- 'Time to resolution', 'Time to first response'
    EnCurso           bit            NOT NULL,
    Inicio            datetimeoffset(3) NULL,
    Fin               datetimeoffset(3) NULL,
    Vencimiento       datetimeoffset(3) NULL,    -- breachTime
    ObjetivoMs        bigint         NULL,
    TranscurridoMs    bigint         NULL,
    RestanteMs        bigint         NULL,
    Incumplido        bit            NULL,
    Pausado           bit            NULL,
    EnHorarioLaboral  bit            NULL,
    CONSTRAINT PK_ops_IssueSla PRIMARY KEY (IssueSk, SlaId, Ciclo)
);
GO
