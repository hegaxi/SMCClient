import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterEach, vi } from 'vitest';
import { limpiarCacheListas } from '../componentes/ListaOrigen';

afterEach(() => {
  cleanup();
  limpiarCacheListas();
  vi.restoreAllMocks();
  window.history.replaceState(null, '', '/');
});
