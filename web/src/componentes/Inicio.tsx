import type { SubgrupoMenu } from '../menu';
import type { Fila } from '../tipos';

interface Props {
  /** Consultas del menú, agrupadas igual que en él (Historias y tickets, Tiempo y estimación…). */
  grupos: SubgrupoMenu[];
  onAbrir: (nombre: string) => void;
  /** Consultas personalizadas que puede ver (los clientes solo tienen éstas). */
  personalizadas?: Fila[];
  onAbrirPersonalizada?: (consultaId: number) => void;
}

export function Inicio({ grupos, onAbrir, personalizadas = [], onAbrirPersonalizada }: Props) {
  const consultas = grupos.flatMap((g) => g.procs);
  return (
    <article className="vista">
      <header>
        <h1>Scrum y mesa de ayuda</h1>
        <p className="secundario">Tickets, historias, tiempo invertido, SLA y avance de sprints, sincronizados desde Jira.</p>
      </header>
      {personalizadas.length > 0 && (
        <section className="seccion-inicio" aria-labelledby="inicio-personalizadas">
          <h2 id="inicio-personalizadas">Consultas compartidas con usted</h2>
          <ul className="tarjetas">
            {personalizadas.map((c) => (
              <li key={`c${String(c.ConsultaId)}`}>
                <button type="button" className="tarjeta-consulta" onClick={() => onAbrirPersonalizada?.(Number(c.ConsultaId))}>
                  <strong>{String(c.Nombre)}</strong>
                  {c.Descripcion ? <span>{String(c.Descripcion)}</span> : null}
                </button>
              </li>
            ))}
          </ul>
        </section>
      )}
      {grupos.filter((g) => g.procs.length > 0).map((g, i) => (
        <section key={g.titulo ?? i} className="seccion-inicio" aria-labelledby={`inicio-g${i}`}>
          <h2 id={`inicio-g${i}`}>{g.titulo ?? 'Consultas'}</h2>
          <ul className="tarjetas">
            {g.procs.map((p) => (
              <li key={p.nombre}>
                <button type="button" className="tarjeta-consulta" onClick={() => onAbrir(p.nombre)}>
                  <strong>{p.titulo}</strong>
                  {p.descripcion && <span>{p.descripcion}</span>}
                </button>
              </li>
            ))}
          </ul>
        </section>
      ))}
      {consultas.length === 0 && personalizadas.length === 0 && (
        <p className="vacio">Todavía no tiene consultas asignadas. Pida acceso a un administrador.</p>
      )}
    </article>
  );
}
