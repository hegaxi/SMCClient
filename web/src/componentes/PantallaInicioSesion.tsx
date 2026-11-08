import { useState, type FormEvent } from 'react';
import { ErrorApi, sesion } from '../api';
import type { Sesion } from '../tipos';

interface Props {
  aviso?: string | null;
  onIniciada: (s: Sesion) => void;
}

export function PantallaInicioSesion({ aviso, onIniciada }: Props) {
  const [usuario, setUsuario] = useState('');
  const [contrasena, setContrasena] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const enviar = async (e: FormEvent) => {
    e.preventDefault();
    setOcupado(true);
    setError(null);
    try {
      onIniciada(await sesion.iniciar(usuario.trim(), contrasena));
    } catch (err) {
      setError(err instanceof ErrorApi ? err.message : 'No se pudo iniciar sesión.');
      setContrasena('');
    } finally {
      setOcupado(false);
    }
  };

  return (
    <main className="pantalla-sync" aria-labelledby="titulo-inicio">
      <form className="tarjeta inicio-sesion" onSubmit={enviar}>
        <h1 id="titulo-inicio">SMCClient</h1>
        <p className="secundario">Scrum y mesa de ayuda. Inicie sesión para continuar.</p>
        {aviso && <p className="aviso" role="status">{aviso}</p>}
        <div className="campo">
          <label htmlFor="usuario">Usuario</label>
          <input id="usuario" name="username" autoComplete="username" value={usuario} onChange={(e) => setUsuario(e.target.value)} required autoFocus />
        </div>
        <div className="campo">
          <label htmlFor="contrasena">Contraseña</label>
          <input id="contrasena" name="password" type="password" autoComplete="current-password" value={contrasena}
                 onChange={(e) => setContrasena(e.target.value)} required />
        </div>
        {error && <p className="alerta" role="alert">{error}</p>}
        <button type="submit" className="boton" disabled={ocupado || !usuario || !contrasena}>
          {ocupado ? 'Entrando…' : 'Iniciar sesión'}
        </button>
        <p className="secundario pie">¿Olvidó su contraseña? Pida a un administrador que la restablezca.</p>
      </form>
    </main>
  );
}
