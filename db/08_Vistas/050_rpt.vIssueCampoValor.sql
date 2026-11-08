/* Valores de campos personalizados con el nombre ACTUAL del campo (si lo renombran, el reporte se actualiza solo). */
CREATE OR ALTER VIEW rpt.vIssueCampoValor
AS
SELECT
    v.IssueSk, i.FuenteId, i.Clave, v.CampoId, c.Nombre AS Campo, c.TipoSchema, c.Activo AS CampoActivo,
    v.Orden, v.ValorId, v.ValorTexto, v.ValorNumero, v.ValorFecha, v.ValorJson
FROM ops.IssueCampoValor v
JOIN ops.Issue i ON i.IssueSk = v.IssueSk
LEFT JOIN meta.CampoJira c ON c.FuenteId = i.FuenteId AND c.CampoId = v.CampoId;
GO
