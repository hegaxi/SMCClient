import { useCallback, useEffect, useState } from 'react';
import { escucharSesion, sesion as apiSesion } from './api';
import type { Sesion } from './tipos';
import { CambiarContrasena } from './componentes/CambiarContrasena';
import { PantallaInicioSesion } from './componentes/PantallaInicioSesion';
import { Principal } from './Principal';

type Estado = { tipo: 'cargando' } | { tipo: 'anonimo'; aviso?: string } | { tipo: 'activa'; sesion: Sesion };

interface PropsApp {
  intervaloSyncMs?: number;
}

/**
 * Orden de las pantallas: inicio de sesión -> cambio obligatorio de contraseña -> sincronización -> aplicación.
 * Usuarios, contraseñas y permisos viven en SQL Server; aquí solo se muestran.
 */
export default function App({ intervaloSyncMs }: PropsApp = {}) {
  const [estado, setEstado] = useState<Estado>({ tipo: 'cargando' });

  const cargar = useCallback(async () => {
    try {
      setEstado({ tipo: 'activa', sesion: await apiSesion.obtener() });
    } catch {
      setEstado({ tipo: 'anonimo' });
    }
  }, []);

  useEffect(() => {
    void cargar();
    escucharSesion(
      () => setEstado({ tipo: 'anonimo', aviso: 'Su sesión terminó. Inicie sesión de nuevo.' }),
      () => setEstado((e) => (e.tipo === 'activa' ? { tipo: 'activa', sesion: { ...e.sesion, debeCambiarContrasena: true } } : e)),
    );
  }, [cargar]);

  const salir = async () => {
    await apiSesion.cerrar().catch(() => {});
    window.history.replaceState(null, '', window.location.pathname);
    setEstado({ tipo: 'anonimo' });
  };

  if (estado.tipo === 'cargando') {
    return <main className="pantalla-sync"><div className="tarjeta"><div className="indicador" aria-hidden="true" /><p role="status">Cargando…</p></div></main>;
  }
  if (estado.tipo === 'anonimo') {
    return <PantallaInicioSesion aviso={estado.aviso} onIniciada={(s) => setEstado({ tipo: 'activa', sesion: s })} />;
  }
  if (estado.sesion.debeCambiarContrasena) {
    return <CambiarContrasena obligatorio onListo={() => void cargar()} />;
  }
  return <Principal sesion={estado.sesion} intervaloSyncMs={intervaloSyncMs} onSalir={salir} />;
}
