import { useState, type FormEvent } from 'react';
import { ErrorApi, sesion } from '../api';

/** Contraseña temporal fácil de dictar: 3 palabras de 4 letras y 2 dígitos (≥ 16 caracteres). */
export function generarTemporal(aleatorio = (n: number) => crypto.getRandomValues(new Uint32Array(1))[0] % n): string {
  const letras = 'abcdefghjkmnpqrstuvwxyz';
  const palabra = () => Array.from({ length: 4 }, () => letras[aleatorio(letras.length)]).join('');
  return `${palabra()}-${palabra()}-${palabra()}-${aleatorio(90) + 10}`;
}

/** Administración: asigna una contraseña temporal; el usuario deberá cambiarla al entrar. */
export function RestablecerContrasena() {
  const [usuario, setUsuario] = useState('');
  const [temporal, setTemporal] = useState(() => generarTemporal());
  const [resultado, setResultado] = useState<{ ok: boolean; texto: string } | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const enviar = async (e: FormEvent) => {
    e.preventDefault();
    if (!window.confirm(`¿Restablecer la contraseña de "${usuario.trim()}"? Se cerrarán sus sesiones abiertas.`)) return;
    setOcupado(true);
    setResultado(null);
    try {
      await sesion.restablecerContrasena(usuario.trim(), temporal);
      setResultado({ ok: true, texto: `Listo. Entregue a ${usuario.trim()} la contraseña temporal; deberá cambiarla al entrar.` });
    } catch (err) {
      setResultado({ ok: false, texto: err instanceof ErrorApi ? err.message : 'No se pudo restablecer la contraseña.' });
    } finally {
      setOcupado(false);
    }
  };

  return (
    <article className="vista">
      <header>
        <h1>Restablecer contraseña</h1>
        <p className="secundario">Para un usuario nuevo o que olvidó su contraseña. Primero dé de alta al usuario en <em>Guardar usuario</em>.</p>
      </header>
      <form className="formulario" onSubmit={enviar}>
        <div className="campos">
          <div className="campo">
            <label htmlFor="r-usuario">Usuario <span className="obligatorio" aria-hidden="true">*</span></label>
            <input id="r-usuario" value={usuario} onChange={(e) => setUsuario(e.target.value)} required autoComplete="off" />
          </div>
          <div className="campo">
            <label htmlFor="r-temporal">Contraseña temporal <span className="obligatorio" aria-hidden="true">*</span></label>
            <input id="r-temporal" value={temporal} onChange={(e) => setTemporal(e.target.value)} required autoComplete="off" spellCheck={false} />
            <small className="ayuda">
              <button type="button" className="enlace" onClick={() => setTemporal(generarTemporal())}>Generar otra</button>
            </small>
          </div>
        </div>
        <button type="submit" className="boton" disabled={ocupado || !usuario.trim() || !temporal}>
          {ocupado ? 'Guardando…' : 'Restablecer'}
        </button>
      </form>
      {resultado && <p className={resultado.ok ? 'aviso' : 'alerta'} role={resultado.ok ? 'status' : 'alert'}>{resultado.texto}</p>}
    </article>
  );
}
