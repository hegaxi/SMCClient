/* La frecuencia por omisión pasa a 2 horas para todos los tipos de dato (antes: 15 min los datos y 60 min los
   catálogos). Solo cambia las que siguen con el valor original: no pisa una frecuencia que el administrador ajustó.
   "Sincronizar ahora" sigue disponible para traer los cambios en el momento. */
UPDATE cfg.EntidadSync
SET FrecuenciaMin = 120
WHERE (Modo = 'catalogo' AND FrecuenciaMin = 60) OR (Modo <> 'catalogo' AND FrecuenciaMin = 15);
GO
