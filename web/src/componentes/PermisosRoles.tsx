import { Fragment, useCallback, useEffect, useMemo, useState } from 'react';
import { api, ErrorApi } from '../api';
import { SUBGRUPOS_ADMIN, SUBGRUPOS_CONSULTAS, subagrupar } from '../menu';
import type { Fila, ProcedimientoInfo } from '../tipos';

/** Una opción del menú que se concede a los roles (seg.fn_Opciones). */
interface Opcion {
  codigo: string;
  titulo: string;
  descripcion: string | null;
  categoria: string;
  principal: string;
  esAccion: boolean;
  exentoSync: boolean;
  procedimientos: string | null;
}

interface Rol {
  nombre: string;
  esExterno: boolean;
  usuarios: number;
}

interface Seccion {
  titulo: string;
  /** Categoría completa que se puede conceder de una vez (incluye lo que se agregue después). */
  categoria: { codigo: string; titulo: string } | null;
  subgrupos: { titulo: string | null; opciones: Opcion[] }[];
}

const CATEGORIAS: Record<string, string> = {
  usuario: 'Todo lo personal: tableros, filtros y consultas compartidas',
  lectura: 'Todas las consultas y la sincronización',
  admin: 'Toda la administración',
};

/** Representa una opción como procedimiento para ubicarla con las mismas reglas que el menú. */
const comoProc = (o: Opcion): ProcedimientoInfo => ({
  nombre: o.principal, titulo: o.titulo, descripcion: o.descripcion, permiso: o.categoria, exentoSync: o.exentoSync,
  accion: o.esAccion, oculto: false, parametros: [], columnas: null, titulosResultados: null,
});

function agrupar(opciones: Opcion[]): Seccion[] {
  const porPrincipal = new Map(opciones.map((o) => [o.principal, o]));
  const sub = (lista: Opcion[], reglas: Parameters<typeof subagrupar>[1] | null, otros: string) =>
    reglas
      ? subagrupar(lista.map(comoProc), reglas, otros).map((s) => ({ titulo: s.titulo, opciones: s.procs.map((p) => porPrincipal.get(p.nombre)!) }))
      : [{ titulo: null, opciones: [...lista].sort((a, b) => a.titulo.localeCompare(b.titulo, 'es')) }];
  const de = (f: (o: Opcion) => boolean) => opciones.filter(f);
  const secciones: Seccion[] = [
    { titulo: 'Tableros y consultas compartidas', categoria: { codigo: 'usuario', titulo: CATEGORIAS.usuario },
      subgrupos: sub(de((o) => o.categoria === 'usuario'), null, '') },
    { titulo: 'Consultas', categoria: { codigo: 'lectura', titulo: CATEGORIAS.lectura },
      subgrupos: sub(de((o) => o.categoria === 'lectura' && !o.exentoSync), SUBGRUPOS_CONSULTAS, 'Otras consultas') },
    { titulo: 'Sincronización', categoria: null, subgrupos: sub(de((o) => o.categoria === 'lectura' && o.exentoSync), null, '') },
    { titulo: 'Administración', categoria: { codigo: 'admin', titulo: CATEGORIAS.admin },
      subgrupos: sub(de((o) => o.categoria === 'admin'), SUBGRUPOS_ADMIN, 'Otras herramientas') },
  ];
  return secciones.filter((s) => s.subgrupos.some((g) => g.opciones.length > 0));
}

const leerOpcion = (f: Fila): Opcion => ({
  codigo: String(f.Codigo), titulo: String(f.Titulo), descripcion: f.Descripcion == null ? null : String(f.Descripcion),
  categoria: String(f.Categoria), principal: String(f.Principal), esAccion: f.EsAccion === true, exentoSync: f.ExentoSync === true,
  procedimientos: f.Procedimientos == null ? null : String(f.Procedimientos),
});

/**
 * "Permisos por opción": cada opción del menú (también tableros, filtros, consultas compartidas y restablecer contraseña)
 * contra cada rol. Una casilla concede o quita la opción al rol (api.Rol_Opcion_Establecer); la fila de la categoría
 * concede la sección completa, incluidas las opciones que se agreguen después.
 */
export function PermisosRoles() {
  const [roles, setRoles] = useState<Rol[] | null>(null);
  const [opciones, setOpciones] = useState<Opcion[]>([]);
  const [concedidos, setConcedidos] = useState<Set<string>>(new Set());
  const [error, setError] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [guardando, setGuardando] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    try {
      const r = await api.ejecutar('Permisos_Matriz');
      setRoles((r.resultados[0]?.filas ?? []).map((f) => ({ nombre: String(f.Rol), esExterno: f.EsExterno === true, usuarios: Number(f.UsuariosActivos ?? 0) })));
      setOpciones((r.resultados[1]?.filas ?? []).map(leerOpcion));
      setConcedidos(new Set((r.resultados[2]?.filas ?? []).map((f) => `${String(f.Rol)}|${String(f.Permiso)}`)));
    } catch (e) {
      setError(e instanceof ErrorApi ? e.message : 'No se pudieron cargar los permisos.');
      setRoles((x) => x ?? []);
    }
  }, []);
  useEffect(() => { void cargar(); }, [cargar]);

  const secciones = useMemo(() => agrupar(opciones), [opciones]);
  const tiene = (rol: string, permiso: string) => concedidos.has(`${rol}|${permiso}`);

  const cambiar = async (rol: string, permiso: string, titulo: string, concedido: boolean) => {
    const clave = `${rol}|${permiso}`;
    const marcar = (valor: boolean) => setConcedidos((c) => { const n = new Set(c); if (valor) n.add(clave); else n.delete(clave); return n; });
    setGuardando(clave); setError(null); setAviso(null);
    marcar(concedido);   // la casilla responde al instante; si la base lo rechaza, vuelve como estaba
    try {
      await api.ejecutar('Rol_Opcion_Establecer', { Rol: rol, Permiso: permiso, Concedido: concedido });
      setAviso(`${rol}: ${concedido ? 'se concedió' : 'se quitó'} "${titulo}". Aplica en la siguiente acción de sus usuarios.`);
    } catch (e) {
      marcar(!concedido);
      setError(e instanceof ErrorApi ? e.message : 'No se pudo guardar el permiso.');
    } finally {
      setGuardando(null);
    }
  };

  /** Casilla de una opción (o categoría) para un rol. */
  const casilla = (rol: Rol, codigo: string, titulo: string, categoria: string | null) => {
    const incluida = categoria !== null && tiene(rol.nombre, categoria);
    const propia = tiene(rol.nombre, codigo);
    const externoNoPermitido = rol.esExterno && (categoria ?? codigo) !== 'usuario';
    const motivo = incluida ? `Incluida en "${CATEGORIAS[categoria!] ?? categoria}"`
      : externoNoPermitido ? 'Un rol externo (clientes) solo puede tener tableros, filtros y consultas compartidas' : undefined;
    return (
      <td key={rol.nombre} className="celda-permiso" title={motivo}>
        <input type="checkbox" aria-label={`${rol.nombre}: ${titulo}`} checked={propia || incluida}
               disabled={guardando === `${rol.nombre}|${codigo}` || externoNoPermitido || (incluida && !propia)}
               onChange={(e) => void cambiar(rol.nombre, codigo, titulo, e.target.checked)} />
      </td>
    );
  };

  return (
    <article className="vista">
      <header>
        <h1>Permisos por opción</h1>
        <p className="secundario">
          Cada opción del menú se concede por rol: marque la casilla para dar acceso y desmárquela para quitarlo. Los usuarios
          sin ninguna opción solo ven su nombre y el estado de los datos.
        </p>
      </header>
      {error && <p className="alerta" role="alert">{error}</p>}
      {aviso && <p className="aviso" role="status">{aviso}</p>}
      {roles === null ? <div className="cargando" aria-label="Cargando" /> : roles.length === 0 ? (
        <p className="vacio">No hay roles.</p>
      ) : (
        <div className="resultado">
          <div className="contenedor-tabla matriz-permisos" aria-busy={guardando !== null}>
            <table>
              <caption className="solo-lectores">Opciones del menú por rol</caption>
              <thead>
                <tr>
                  <th scope="col">Opción del menú</th>
                  {roles.map((r) => (
                    <th scope="col" key={r.nombre} className="col-rol">
                      {r.nombre}
                      <small>{r.esExterno ? 'Externo · ' : ''}{r.usuarios} usuario{r.usuarios === 1 ? '' : 's'}</small>
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {secciones.map((s) => (
                  <Fragment key={s.titulo}>
                    <tr className="fila-seccion"><th scope="rowgroup" colSpan={roles.length + 1}>{s.titulo}</th></tr>
                    {s.categoria && (
                      <tr className="fila-categoria">
                        <th scope="row">{s.categoria.titulo}<small>Incluye las opciones que se agreguen después</small></th>
                        {roles.map((r) => casilla(r, s.categoria!.codigo, s.categoria!.titulo, null))}
                      </tr>
                    )}
                    {s.subgrupos.map((g) => (
                      <Fragment key={g.titulo ?? '-'}>
                        {g.titulo && s.subgrupos.length > 1 && (
                          <tr className="fila-subgrupo"><th scope="rowgroup" colSpan={roles.length + 1}>{g.titulo}</th></tr>
                        )}
                        {g.opciones.map((o) => (
                          <tr key={o.codigo}>
                            <th scope="row" title={o.procedimientos ? `Procedimientos: ${o.procedimientos}` : undefined}>
                              {o.titulo}{o.esAccion && <small>Acción</small>}
                            </th>
                            {roles.map((r) => casilla(r, o.codigo, o.titulo, o.categoria))}
                          </tr>
                        ))}
                      </Fragment>
                    ))}
                  </Fragment>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </article>
  );
}
