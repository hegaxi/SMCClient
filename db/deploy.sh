#!/usr/bin/env bash
# Despliega la base de datos de SMCClient ejecutando los scripts EN ORDEN:
#   carpetas NN_* en orden numérico y, dentro de cada una, archivos en orden de nombre.
# Todos los scripts son idempotentes (se pueden correr N veces), salvo 04_Migraciones,
# que se ejecuta una sola vez por base (bitácora en adm.ScriptEjecutado).
#
# Uso:
#   ./deploy.sh -S servidor -d SMCClient [-U usuario] [-C] [--crear-bd] [--listar] [--permitir-migracion-editada]
#   La contraseña se toma de la variable SQLCMDPASSWORD (no se pasa por línea de comandos).
#   Sin -U usa autenticación integrada (-E).
#   SQLCMD=/ruta/a/sqlcmd para usar otro ejecutable.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SQLCMD="${SQLCMD:-sqlcmd}"
SERVER="" ; DB="" ; USER_SQL="" ; TRUST="" ; CREAR=0 ; LISTAR=0 ; PERMITIR=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -S) SERVER="$2"; shift 2 ;;
    -d) DB="$2"; shift 2 ;;
    -U) USER_SQL="$2"; shift 2 ;;
    -C) TRUST="-C"; shift ;;
    --crear-bd) CREAR=1; shift ;;
    --listar) LISTAR=1; shift ;;
    --permitir-migracion-editada) PERMITIR=1; shift ;;
    *) echo "Parámetro desconocido: $1" >&2; exit 2 ;;
  esac
done

mapfile -t SCRIPTS < <(cd "$DIR" && find . -mindepth 2 -maxdepth 2 -path './[0-9][0-9]_*/*.sql' | sed 's|^\./||' | LC_ALL=C sort)

if [[ $LISTAR -eq 1 ]]; then
  printf '%s\n' "${SCRIPTS[@]}"
  exit 0
fi

[[ -n "$SERVER" && -n "$DB" ]] || { echo "Faltan -S y -d" >&2; exit 2; }
AUTH=(-E); [[ -n "$USER_SQL" ]] && AUTH=(-U "$USER_SQL")
BASE=("$SQLCMD" -S "$SERVER" "${AUTH[@]}" $TRUST -b -I -x -f 65001)   # scripts en UTF-8

if [[ $CREAR -eq 1 ]]; then
  # Creada por una cuenta de Windows (DOMINIO\usuario): el dueño pasa a sa (EXECUTE AS OWNER no consulta al dominio).
  "${BASE[@]}" -d master -Q "IF DB_ID(N'${DB//\'/\'\'}') IS NULL BEGIN CREATE DATABASE [${DB//]/]]}]; IF SUSER_SNAME() LIKE N'%\\%' ALTER AUTHORIZATION ON DATABASE::[${DB//]/]]}] TO sa; END;"
fi

consulta() { "${BASE[@]}" -d "$DB" -h -1 -W -Q "SET NOCOUNT ON; $1"; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

for rel in "${SCRIPTS[@]}"; do
  # Hash sin retornos de carro: el mismo con CRLF o LF (igual que deploy.ps1).
  hash=$(tr -d '\r' < "$DIR/$rel" | sha256sum | cut -d' ' -f1)
  crudo=$(sha256sum "$DIR/$rel" | cut -d' ' -f1)
  ruta=${rel//\'/\'\'}
  registro="SET NOCOUNT ON;
IF OBJECT_ID('adm.ScriptEjecutado') IS NOT NULL
MERGE adm.ScriptEjecutado AS t USING (SELECT N'$ruta' AS Ruta, '$hash' AS Hash) AS s ON t.Ruta = s.Ruta
WHEN MATCHED THEN UPDATE SET Hash = s.Hash, Ejecuciones = t.Ejecuciones + 1, Ultima = SYSDATETIMEOFFSET()
WHEN NOT MATCHED THEN INSERT (Ruta, Hash) VALUES (s.Ruta, s.Hash);"
  if [[ "$rel" == 04_Migraciones/* ]]; then
    previo=$(consulta "SELECT ISNULL((SELECT Hash FROM adm.ScriptEjecutado WHERE Ruta = N'$ruta'), '-');" | tr -d '[:space:]')
    if [[ "$previo" != "-" ]]; then
      # Una migración aplicada no se edita (04_Migraciones/README.md, regla 4).
      if [[ ! "$previo" =~ ^[0-9a-f]{64}$ ]]; then
        echo "Aviso: la migración $rel está registrada sin hash ($previo); no se puede verificar si cambió." >&2
      elif [[ "$previo" != "$hash" && "$previo" != "$crudo" && $PERMITIR -eq 0 ]]; then
        echo "La migración $rel cambió después de aplicarse (hash $previo). Escribe una migración nueva o usa --permitir-migracion-editada." >&2
        exit 1
      fi
      echo "  (omitido, ya aplicado) $rel"; continue
    fi
    # Migración y registro en una sola transacción (misma conexión): si falla, sqlcmd sale y SQL Server deshace todo.
    printf 'SET XACT_ABORT ON;\nBEGIN TRANSACTION;\nGO\n' > "$TMP/ini.sql"
    printf '%s\nCOMMIT TRANSACTION;\nGO\n' "$registro" > "$TMP/fin.sql"
    echo "  -> $rel (migración, en transacción)"
    "${BASE[@]}" -d "$DB" -i "$TMP/ini.sql,$DIR/$rel,$TMP/fin.sql"
    continue
  fi
  echo "  -> $rel"
  "${BASE[@]}" -d "$DB" -i "$DIR/$rel"
  consulta "$registro" > /dev/null
done
echo "Despliegue terminado: ${#SCRIPTS[@]} scripts."
