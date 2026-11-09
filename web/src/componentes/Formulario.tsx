import type { FormEvent, ReactNode } from 'react';
import type { ParametroInfo, ValoresFormulario } from '../tipos';
import { etiqueta, tipoControl } from '../formato';
import { ListaOrigen } from './ListaOrigen';

interface Props {
  parametros: ParametroInfo[];
  valores: ValoresFormulario;
  errores: Record<string, string[]>;
  ocupado: boolean;
  onCambio: (nombre: string, valor: string) => void;
  onEnviar: () => void;
  textoBoton?: string;
  /** Acciones secundarias junto al botón principal (p. ej. "Guardar como filtro"). */
  children?: ReactNode;
}

/** Formulario generado a partir de los metadatos del procedimiento (tipo, longitud, opcional, opciones, descripción). */
export function Formulario({ parametros, valores, errores, ocupado, onCambio, onEnviar, textoBoton = 'Consultar', children }: Props) {
  const visibles = parametros.filter((p) => !p.salida);
  const enviar = (e: FormEvent) => {
    e.preventDefault();
    onEnviar();
  };

  return (
    <form className={visibles.length > 0 ? 'formulario' : 'formulario sin-campos'} onSubmit={enviar} noValidate>
      {visibles.length > 0 && (
        <div className="campos">
          {visibles.map((p) => {
            const id = `p-${p.nombre}`;
            const err = errores[p.nombre] ?? errores[`@${p.nombre}`];
            const ayuda = p.descripcion ? `${id}-ayuda` : undefined;
            const descrito = [ayuda, err ? `${id}-error` : undefined].filter(Boolean).join(' ') || undefined;
            const comunes = {
              id,
              name: p.nombre,
              value: valores[p.nombre] ?? '',
              'aria-invalid': err ? true : undefined,
              'aria-describedby': descrito,
              required: !p.opcional,
              onChange: (ev: { target: { value: string } }) => onCambio(p.nombre, ev.target.value),
            };
            const control = tipoControl(p);
            const entrada = control === 'lista' ? (
                  <select {...comunes}>
                    <option value="">{p.opcional ? 'Todos' : 'Seleccione…'}</option>
                    {p.opciones!.map((o) => (
                      <option key={o.valor} value={o.valor}>{o.etiqueta}</option>
                    ))}
                  </select>
                ) : control === 'siNo' ? (
                  <select {...comunes}>
                    <option value="">{p.opcional ? 'Sin filtro' : 'Seleccione…'}</option>
                    <option value="true">Sí</option>
                    <option value="false">No</option>
                  </select>
                ) : (
                  <input
                    {...comunes}
                    type={control === 'fecha' ? 'date' : control === 'fechaHora' ? 'datetime-local' : control === 'texto' ? 'text' : 'number'}
                    step={control === 'entero' ? 1 : control === 'decimal' ? 'any' : undefined}
                    maxLength={control === 'texto' && p.longitud && p.longitud > 0 ? p.longitud : undefined}
                    inputMode={control === 'entero' ? 'numeric' : control === 'decimal' ? 'decimal' : undefined}
                  />
                );
            const etiquetaId = `${id}-etiqueta`;
            return (
              <div key={p.nombre} className={err ? 'campo con-error' : 'campo'}>
                <label htmlFor={p.origen && p.multiple ? undefined : id} id={etiquetaId}>
                  {etiqueta(p.nombre)}
                  {!p.opcional && <span className="obligatorio" aria-hidden="true"> *</span>}
                </label>
                {p.origen ? (
                  <ListaOrigen id={id} etiquetaId={etiquetaId} origen={p.origen} multiple={p.multiple ?? null}
                               valor={valores[p.nombre] ?? ''} onCambio={(v) => onCambio(p.nombre, v)} opcional={p.opcional}
                               describedBy={descrito} invalido={!!err} respaldo={entrada} />
                ) : entrada}
                {p.descripcion && <small id={ayuda} className="ayuda">{p.descripcion}</small>}
                {err && <small id={`${id}-error`} className="error-campo">{err.join(' ')}</small>}
              </div>
            );
          })}
        </div>
      )}
      <div className="acciones-formulario">
        <button type="submit" className="boton" disabled={ocupado} aria-busy={ocupado || undefined}>
          {ocupado ? 'Consultando…' : textoBoton}
        </button>
        {children}
      </div>
    </form>
  );
}
