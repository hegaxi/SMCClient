import type { Fila, ProcedimientoInfo } from '../tipos';

interface Props {
  consultas: ProcedimientoInfo[];
  onAbrir: (nombre: string) => void;
  /** Consultas personalizadas que puede ver (los clientes solo tienen éstas). */
  personalizadas?: Fila[];
  onAbrirPersonalizada?: (consultaId: number) => void;
}

export function Inicio({ consultas, onAbrir, personalizadas = [], onAbrirPersonalizada }: Props) {
  return (
    <article className="vista">
      <header>
        <h1>Scrum y mesa de ayuda</h1>
        <p className="secundario">Tickets, historias, tiempo invertido, SLA y avance de sprints, sincronizados desde Jira.</p>
      </header>
      <ul className="tarjetas">
        {consultas.map((p) => (
          <li key={p.nombre}>
            <button type="button" className="tarjeta-consulta" onClick={() => onAbrir(p.nombre)}>
              <strong>{p.titulo}</strong>
              {p.descripcion && <span>{p.descripcion}</span>}
            </button>
          </li>
        ))}
        {personalizadas.map((c) => (
          <li key={`c${String(c.ConsultaId)}`}>
            <button type="button" className="tarjeta-consulta" onClick={() => onAbrirPersonalizada?.(Number(c.ConsultaId))}>
              <strong>{String(c.Nombre)}</strong>
              {c.Descripcion ? <span>{String(c.Descripcion)}</span> : null}
            </button>
          </li>
        ))}
      </ul>
      {consultas.length === 0 && personalizadas.length === 0 && (
        <p className="vacio">Todavía no tiene consultas asignadas. Pida acceso a un administrador.</p>
      )}
    </article>
  );
}
