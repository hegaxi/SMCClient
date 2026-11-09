import { useState, type FormEvent } from 'react';
import { ErrorApi, sesion } from '../api';

interface Props {
  /** Después de que un administrador la restableció: no se puede cancelar. */
  obligatorio: boolean;
  onListo: () => void;
  onCancelar?: () => void;
}

export function CambiarContrasena({ obligatorio, onListo, onCancelar }: Props) {
  const [actual, setActual] = useState('');
  const [nueva, setNueva] = useState('');
  const [confirmar, setConfirmar] = useState('');
  const [errores, setErrores] = useState<Record<string, string>>({});
  const [mensaje, setMensaje] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const enviar = async (e: FormEvent) => {
    e.preventDefault();
    setErrores({});
    setMensaje(null);
    if (nueva !== confirmar) {
      setErrores({ confirmar: 'No coincide con la contraseña nueva.' });
      return;
    }
    setOcupado(true);
    try {
      await sesion.cambiarContrasena(actual, nueva);
      onListo();
    } catch (err) {
      if (err instanceof ErrorApi && err.problema.errors) {
        setErrores(Object.fromEntries(Object.entries(err.problema.errors).map(([k, v]) => [k, v.join(' ')])));
      } else setMensaje(err instanceof Error ? err.message : 'No se pudo cambiar la contraseña.');
    } finally {
      setOcupado(false);
    }
  };

  const campo = (id: 'actual' | 'nueva' | 'confirmar', texto: string, valor: string, cambiar: (v: string) => void, auto: string) => (
    <div className={errores[id] ? 'campo con-error' : 'campo'}>
      <label htmlFor={`c-${id}`}>{texto}</label>
      <input id={`c-${id}`} type="password" autoComplete={auto} value={valor} onChange={(e) => cambiar(e.target.value)} required
             aria-invalid={errores[id] ? true : undefined} aria-describedby={errores[id] ? `c-${id}-error` : undefined} />
      {errores[id] && <small id={`c-${id}-error`} className="error-campo">{errores[id]}</small>}
    </div>
  );

  const contenido = (
    <form className="tarjeta inicio-sesion" onSubmit={enviar}>
      <h1 id="titulo-cambio">{obligatorio ? 'Establezca su contraseña' : 'Cambiar contraseña'}</h1>
      <p className="secundario">
        {obligatorio
          ? 'Un administrador le asignó una contraseña temporal. Elija una nueva para continuar.'
          : 'Al cambiarla se cerrarán sus sesiones abiertas en otros equipos.'}
      </p>
      {campo('actual', obligatorio ? 'Contraseña temporal' : 'Contraseña actual', actual, setActual, 'current-password')}
      {campo('nueva', 'Contraseña nueva', nueva, setNueva, 'new-password')}
      {campo('confirmar', 'Repita la contraseña nueva', confirmar, setConfirmar, 'new-password')}
      {mensaje && <p className="alerta" role="alert">{mensaje}</p>}
      <div className="acciones">
        <button type="submit" className="boton" disabled={ocupado || !actual || !nueva || !confirmar}>
          {ocupado ? 'Guardando…' : 'Guardar contraseña'}
        </button>
        {!obligatorio && onCancelar && <button type="button" className="boton secundario-btn" onClick={onCancelar}>Cancelar</button>}
      </div>
    </form>
  );

  return obligatorio ? <main className="pantalla-sync" aria-labelledby="titulo-cambio">{contenido}</main> : <article className="vista estrecha">{contenido}</article>;
}
