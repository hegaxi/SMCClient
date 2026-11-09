import { useState, type FormEvent } from 'react';
import { api, ErrorApi } from '../api';
import { construirCuerpo, etiqueta, formatear } from '../formato';
import type { ProcedimientoInfo, ValoresFormulario } from '../tipos';

/** Fechas relativas que entiende la base (dash.fn_FechaRelativa). */
export const FECHAS_RELATIVAS = [
  { valor: '{hoy}', etiqueta: 'Hoy' },
  { valor: '{hoy-7}', etiqueta: 'Hace 7 días' },
  { valor: '{hoy-30}', etiqueta: 'Hace 30 días' },
  { valor: '{inicio_semana}', etiqueta: 'Inicio de la semana' },
  { valor: '{inicio_mes}', etiqueta: 'Inicio del mes' },
  { valor: '{inicio_mes_anterior}', etiqueta: 'Inicio del mes anterior' },
  { valor: '{fin_mes_anterior}', etiqueta: 'Fin del mes anterior' },
  { valor: '{inicio_anio}', etiqueta: 'Inicio del año' },
];

interface Props {
  proc: ProcedimientoInfo;
  valores: ValoresFormulario;
  onGuardado: (nombre: string) => void;
  onCancelar: () => void;
}

/** Guarda la consulta actual con sus valores. Las fechas pueden guardarse fijas o relativas. */
export function GuardarFiltro({ proc, valores, onGuardado, onCancelar }: Props) {
  const fechas = proc.parametros.filter((p) => p.tipo === 'date' && (valores[p.nombre] ?? '') !== '');
  const [nombre, setNombre] = useState('');
  const [compartido, setCompartido] = useState(false);
  const [relativas, setRelativas] = useState<Record<string, string>>({});
  const [error, setError] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const enviar = async (e: FormEvent) => {
    e.preventDefault();
    setOcupado(true);
    setError(null);
    const { Pagina: _, ...cuerpo } = construirCuerpo(proc.parametros, valores);
    for (const [p, token] of Object.entries(relativas)) if (token) cuerpo[p] = token;
    try {
      await api.ejecutar('Filtro_Guardar', { Nombre: nombre, Procedimiento: proc.nombre, Parametros: JSON.stringify(cuerpo), Compartido: compartido });
      onGuardado(nombre);
    } catch (err) {
      setError(err instanceof ErrorApi ? err.message : 'No se pudo guardar el filtro.');
    } finally {
      setOcupado(false);
    }
  };

  return (
    <form className="formulario guardar-filtro" onSubmit={enviar} aria-label="Guardar como filtro">
      <h3>Guardar como filtro</h3>
      <div className="campos">
        <div className="campo">
          <label htmlFor="gf-nombre">Nombre del filtro <span className="obligatorio" aria-hidden="true">*</span></label>
          <input id="gf-nombre" value={nombre} onChange={(e) => setNombre(e.target.value)} required maxLength={150} autoFocus />
        </div>
        {fechas.map((p) => (
          <div className="campo" key={p.nombre}>
            <label htmlFor={`gf-${p.nombre}`}>{etiqueta(p.nombre)}</label>
            <select id={`gf-${p.nombre}`} value={relativas[p.nombre] ?? ''} onChange={(e) => setRelativas((r) => ({ ...r, [p.nombre]: e.target.value }))}>
              <option value="">Fija: {formatear(valores[p.nombre], 'date')}</option>
              {FECHAS_RELATIVAS.map((f) => <option key={f.valor} value={f.valor}>{f.etiqueta}</option>)}
            </select>
            <small className="ayuda">Relativa = el tablero siempre muestra datos actuales.</small>
          </div>
        ))}
      </div>
      <label className="casilla">
        <input type="checkbox" checked={compartido} onChange={(e) => setCompartido(e.target.checked)} />
        Compartir con quienes pueden usar esta consulta
      </label>
      {error && <p className="alerta" role="alert">{error}</p>}
      <div className="acciones">
        <button type="submit" className="boton" disabled={ocupado || !nombre.trim()}>{ocupado ? 'Guardando…' : 'Guardar filtro'}</button>
        <button type="button" className="boton secundario-btn" onClick={onCancelar}>Cancelar</button>
      </div>
    </form>
  );
}
