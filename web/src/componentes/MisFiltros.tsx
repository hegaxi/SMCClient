import { useEffect, useState } from 'react';
import { api, ErrorApi } from '../api';
import type { Fila, ValoresFormulario } from '../tipos';

interface Props {
  onAbrir: (nombre: string, valores: ValoresFormulario) => void;
}

/** Filtros guardados propios y compartidos: abrirlos (con las fechas relativas ya resueltas) o eliminarlos. */
export function MisFiltros({ onAbrir }: Props) {
  const [filtros, setFiltros] = useState<Fila[] | null>(null);
  const [mensaje, setMensaje] = useState<string | null>(null);

  const cargar = () => api.ejecutar('Filtros_Listar').then((r) => setFiltros(r.resultados[0]?.filas ?? [])).catch(() => setFiltros([]));
  useEffect(() => { void cargar(); }, []);

  const abrir = (f: Fila) => {
    let valores: Record<string, unknown> = {};
    try { valores = JSON.parse(String(f.ParametrosResueltos ?? '{}')); } catch { /* sin valores */ }
    onAbrir(String(f.Procedimiento), Object.fromEntries(Object.entries(valores).map(([k, v]) => [k, String(v)])));
  };

  const eliminar = async (f: Fila) => {
    if (!window.confirm(`¿Eliminar el filtro "${String(f.Nombre)}"?`)) return;
    try {
      await api.ejecutar('Filtro_Eliminar', { FiltroId: f.FiltroId });
      setMensaje(null);
      await cargar();
    } catch (e) {
      setMensaje(e instanceof ErrorApi ? e.message : 'No se pudo eliminar.');
    }
  };

  return (
    <article className="vista">
      <header>
        <h1>Mis filtros</h1>
        <p className="secundario">Para guardar uno, abra una consulta, elija sus valores y use <strong>Guardar como filtro</strong>.</p>
      </header>
      {mensaje && <p className="alerta" role="alert">{mensaje}</p>}
      {filtros === null ? <div className="cargando" aria-label="Cargando" /> : filtros.length === 0 ? (
        <p className="vacio">Aún no hay filtros guardados.</p>
      ) : (
        <div className="resultado">
          <div className="contenedor-tabla">
            <table>
              <thead><tr><th scope="col">Filtro</th><th scope="col">Consulta</th><th scope="col">De</th><th scope="col">Compartido</th><th scope="col" className="num">Widgets</th><th scope="col"><span className="solo-lectores">Acciones</span></th></tr></thead>
              <tbody>
                {filtros.map((f) => (
                  <tr key={String(f.FiltroId)}>
                    <td>{f.PuedoUsar === true ? <button type="button" className="enlace" onClick={() => abrir(f)}>{String(f.Nombre)}</button> : String(f.Nombre)}</td>
                    <td>{String(f.Consulta)}</td>
                    <td>{f.EsMio ? 'Usted' : String(f.Propietario)}</td>
                    <td>{f.Compartido ? 'Sí' : 'No'}</td>
                    <td className="num">{String(f.Widgets)}</td>
                    <td>{f.EsMio === true && <button type="button" className="enlace peligro" onClick={() => eliminar(f)}>Eliminar</button>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </article>
  );
}
