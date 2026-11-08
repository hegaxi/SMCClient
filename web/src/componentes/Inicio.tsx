import type { ProcedimientoInfo } from '../tipos';

interface Props {
  consultas: ProcedimientoInfo[];
  onAbrir: (nombre: string) => void;
}

export function Inicio({ consultas, onAbrir }: Props) {
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
      </ul>
    </article>
  );
}
