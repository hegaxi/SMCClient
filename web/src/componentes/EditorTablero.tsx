import { useState, type FormEvent } from 'react';
import { api, ErrorApi } from '../api';
import type { Fila } from '../tipos';

interface Props {
  tablero?: Fila;
  onGuardado: (tableroId: number) => void;
  onCancelar: () => void;
}

export function EditorTablero({ tablero, onGuardado, onCancelar }: Props) {
  const [nombre, setNombre] = useState(String(tablero?.Nombre ?? ''));
  const [descripcion, setDescripcion] = useState(String(tablero?.Descripcion ?? ''));
  const [compartir, setCompartir] = useState(String(tablero?.CompartidoCon ?? ''));
  const [error, setError] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const enviar = async (e: FormEvent) => {
    e.preventDefault();
    setOcupado(true);
    setError(null);
    try {
      const r = await api.ejecutar('Tablero_Guardar', {
        ...(tablero ? { TableroId: tablero.TableroId } : {}),
        Nombre: nombre, Descripcion: descripcion || null, CompartirCon: compartir || null,
      });
      onGuardado(Number(r.resultados[0].filas[0].TableroId));
    } catch (err) {
      setError(err instanceof ErrorApi ? err.message : 'No se pudo guardar el tablero.');
    } finally {
      setOcupado(false);
    }
  };

  return (
    <article className="vista">
      <header><h1>{tablero ? 'Editar tablero' : 'Nuevo tablero'}</h1></header>
      <form className="formulario" onSubmit={enviar}>
        <div className="campos">
          <div className="campo">
            <label htmlFor="t-nombre">Nombre <span className="obligatorio" aria-hidden="true">*</span></label>
            <input id="t-nombre" value={nombre} onChange={(e) => setNombre(e.target.value)} required maxLength={150} />
          </div>
          <div className="campo">
            <label htmlFor="t-descripcion">Descripción</label>
            <input id="t-descripcion" value={descripcion} onChange={(e) => setDescripcion(e.target.value)} maxLength={400} />
          </div>
          <div className="campo">
            <label htmlFor="t-compartir">Compartir con</label>
            <input id="t-compartir" value={compartir} onChange={(e) => setCompartir(e.target.value)} aria-describedby="t-compartir-ayuda" />
            <small id="t-compartir-ayuda" className="ayuda">Usuarios o roles separados por coma, p. ej. <code>ana, rol:Consulta</code>. Vacío = solo usted.</small>
          </div>
        </div>
        {error && <p className="alerta" role="alert">{error}</p>}
        <div className="acciones">
          <button type="submit" className="boton" disabled={ocupado}>{ocupado ? 'Guardando…' : 'Guardar'}</button>
          <button type="button" className="boton secundario-btn" onClick={onCancelar}>Cancelar</button>
        </div>
      </form>
    </article>
  );
}
