import { useEffect, useState, type FormEvent } from 'react';
import { api, ErrorApi } from '../api';
import { DESTINATARIOS, ListaOrigen } from './ListaOrigen';

interface Props {
  /** Parámetros de la búsqueda (los mismos de api.Issues_Consultar). */
  parametros: Record<string, string>;
  /** Si se está editando una consulta ya publicada. */
  consultaId?: number;
  onPublicada: (consultaId: number, nombre: string) => void;
  onCancelar: () => void;
}

/** Publica la búsqueda actual como consulta personalizada y la comparte con usuarios, roles o clientes
 * (quien tiene la opción "Publicar consulta personalizada"). */
export function PublicarConsulta({ parametros, consultaId, onPublicada, onCancelar }: Props) {
  const [nombre, setNombre] = useState('');
  const [descripcion, setDescripcion] = useState('');
  const [compartir, setCompartir] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  useEffect(() => {
    if (!consultaId) return;
    api.ejecutar('ConsultaPersonalizada_Obtener', { ConsultaId: consultaId })
      .then((r) => {
        const d = r.resultados[0]?.filas[0];
        if (!d) return;
        setNombre(String(d.Nombre ?? ''));
        setDescripcion(String(d.Descripcion ?? ''));
        setCompartir(String(d.CompartidaCon ?? ''));
      })
      .catch(() => {});
  }, [consultaId]);

  const enviar = async (e: FormEvent) => {
    e.preventDefault();
    setOcupado(true);
    setError(null);
    try {
      const r = await api.ejecutar('ConsultaPersonalizada_Guardar', {
        ...(consultaId ? { ConsultaId: consultaId } : {}),
        Nombre: nombre, Descripcion: descripcion, CompartirCon: compartir,
        Criterios: parametros.Criterios ?? '[]',
        ...(parametros.Columnas ? { Columnas: parametros.Columnas } : {}),
        ...(parametros.OrdenarPor ? { OrdenarPor: parametros.OrdenarPor } : {}),
        Descendente: parametros.Descendente !== 'false',
      });
      onPublicada(Number(r.resultados[0]?.filas[0]?.ConsultaId), nombre);
    } catch (err) {
      setError(err instanceof ErrorApi ? err.message : 'No se pudo publicar la consulta.');
    } finally {
      setOcupado(false);
    }
  };

  return (
    <form className="formulario panel-flotante" onSubmit={enviar} aria-label="Publicar como consulta personalizada">
      <h4>{consultaId ? 'Actualizar consulta personalizada' : 'Publicar como consulta personalizada'}</h4>
      <div className="campos">
        <div className="campo">
          <label htmlFor="pc-nombre">Nombre <span className="obligatorio" aria-hidden="true">*</span></label>
          <input id="pc-nombre" value={nombre} onChange={(e) => setNombre(e.target.value)} required maxLength={150} autoFocus />
        </div>
        <div className="campo">
          <label htmlFor="pc-descripcion">Descripción</label>
          <input id="pc-descripcion" value={descripcion} onChange={(e) => setDescripcion(e.target.value)} maxLength={500} />
        </div>
        <div className="campo">
          <label htmlFor="pc-compartir" id="pc-compartir-etiqueta">Compartir con</label>
          <ListaOrigen id="pc-compartir" etiquetaId="pc-compartir-etiqueta" origen={DESTINATARIOS} multiple="," valor={compartir}
                       onCambio={setCompartir} opcional describedBy="pc-compartir-ayuda"
                       respaldo={<input id="pc-compartir" value={compartir} onChange={(e) => setCompartir(e.target.value)} placeholder="ana, cliente1, rol:Cliente" aria-describedby="pc-compartir-ayuda" />} />
          <small id="pc-compartir-ayuda" className="ayuda">Marque usuarios o roles. Los clientes solo verán los tickets de su organización.</small>
        </div>
      </div>
      {error && <p className="alerta" role="alert">{error}</p>}
      <div className="acciones">
        <button type="submit" className="boton" disabled={ocupado || !nombre.trim()}>{ocupado ? 'Publicando…' : consultaId ? 'Actualizar' : 'Publicar'}</button>
        <button type="button" className="boton secundario-btn" onClick={onCancelar}>Cancelar</button>
      </div>
    </form>
  );
}
