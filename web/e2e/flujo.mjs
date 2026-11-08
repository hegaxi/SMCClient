// Prueba de punta a punta en Chromium contra la API real (que sirve el build de React).
// Uso: BASE_URL=http://127.0.0.1:5080 E2E_USUARIO=admin E2E_CONTRASENA=... node e2e/flujo.mjs
//   E2E_USUARIO / E2E_CONTRASENA: un administrador existente (p. ej. creado con "crear-administrador").
//   E2E_PENDIENTE / E2E_LISTO: comandos de shell opcionales que dejan los datos sin sincronizar / sincronizados,
//   para verificar la pantalla de sincronización. E2E_CAPTURAS: carpeta para las capturas.
import { execSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const BASE = process.env.BASE_URL ?? 'http://127.0.0.1:5080';
const USUARIO = process.env.E2E_USUARIO ?? 'admin';
const CONTRASENA = process.env.E2E_CONTRASENA ?? '';
const NUEVO = `maria${Date.now() % 100000}`;
const CAPTURAS = process.env.E2E_CAPTURAS;
if (CAPTURAS) mkdirSync(CAPTURAS, { recursive: true });

const navegador = await chromium.launch();
const pagina = await navegador.newPage({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 2, locale: 'es-MX', timezoneId: 'America/Mexico_City' });
const erroresConsola = [];
// Las respuestas 4xx/503 de la API son esperadas (validación, sincronización); los errores de JavaScript no.
pagina.on('console', (m) => {
  if (m.type() === 'error' && !/Failed to load resource: the server responded with a status of (4\d\d|503)/.test(m.text())) erroresConsola.push(m.text());
});
pagina.on('pageerror', (e) => erroresConsola.push(String(e)));
pagina.on('dialog', (d) => d.accept());   // confirmaciones de las acciones

const paso = async (nombre, fn) => {
  process.stdout.write(`- ${nombre} ... `);
  await fn();
  if (CAPTURAS) await pagina.screenshot({ path: `${CAPTURAS}/${nombre.replace(/[^a-z0-9]+/gi, '_').toLowerCase()}.png`, fullPage: true });
  console.log('ok');
};
const titulo = (t) => pagina.getByRole('heading', { name: t, exact: true });

const iniciarSesion = async (usuario, contrasena) => {
  await pagina.getByRole('heading', { name: 'SMCClient', exact: true }).waitFor();   // pantalla de inicio de sesión visible
  await pagina.getByLabel('Usuario').fill(usuario);
  await pagina.getByLabel('Contraseña').fill(contrasena);
  await pagina.getByRole('button', { name: 'Iniciar sesión' }).click();
};

try {
  await paso('Inicio de sesion', async () => {
    await pagina.goto(BASE);
    await pagina.getByRole('button', { name: 'Iniciar sesión' }).waitFor();
    await iniciarSesion(USUARIO, 'contraseña-equivocada');
    await pagina.getByRole('alert').filter({ hasText: 'Usuario o contraseña incorrectos' }).waitFor();
  });

  if (process.env.E2E_PENDIENTE) {
    execSync(process.env.E2E_PENDIENTE, { stdio: 'inherit' });
    await paso('Pantalla de sincronizacion', async () => {
      await iniciarSesion(USUARIO, CONTRASENA);
      await titulo('Sincronizando los datos de Jira').waitFor();
      await pagina.getByRole('button', { name: 'Sincronizar ahora' }).waitFor();
    });
    execSync(process.env.E2E_LISTO, { stdio: 'inherit' });
    await paso('Se abre sola al terminar la sincronizacion', async () => {
      await titulo('Scrum y mesa de ayuda').waitFor({ timeout: 20_000 });
    });
  } else {
    await paso('Inicio', async () => {
      await iniciarSesion(USUARIO, CONTRASENA);
      await titulo('Scrum y mesa de ayuda').waitFor();
    });
  }

  await paso('Buscar historias y tickets', async () => {
    await pagina.getByRole('link', { name: 'Buscar historias y tickets' }).click();
    await pagina.getByRole('button', { name: 'MDA-1' }).waitFor();
    await pagina.getByLabel('Tipo proyecto').selectOption({ label: 'Mesa de ayuda' });
    await pagina.getByRole('button', { name: 'Consultar' }).click();
    await pagina.waitForURL(/TipoProyecto=service_desk/);
    await pagina.getByRole('button', { name: 'SCR-7' }).waitFor({ state: 'detached' });   // la historia Scrum sale del resultado
    await pagina.getByRole('button', { name: 'MDA-1' }).waitFor();
  });

  await paso('Detalle de un issue', async () => {
    await pagina.getByRole('button', { name: 'MDA-1' }).click();
    await titulo('Detalle de un issue').waitFor();
    await titulo('Tiempo registrado').waitFor();
    await titulo('SLA').waitFor();
    await pagina.getByText('Automation for Jira').first().waitFor();
  });

  await paso('Volver con el boton Atras', async () => {
    await pagina.goBack();
    await titulo('Buscar historias y tickets').waitFor();
  });

  await paso('Horas por persona', async () => {
    await pagina.getByRole('link', { name: 'Horas por persona' }).click();
    await pagina.getByLabel(/Desde/).fill('2026-10-01');
    await pagina.getByLabel(/Hasta/).fill('2026-11-30');
    await pagina.getByRole('button', { name: 'Consultar' }).click();
    await pagina.getByRole('columnheader', { name: 'Horas registradas' }).waitFor();
    await pagina.getByRole('columnheader', { name: 'Horas automáticas' }).waitFor();
    await pagina.getByRole('cell', { name: 'Mesa de ayuda' }).first().waitFor();   // valor codificado traducido
    await pagina.getByRole('cell', { name: '(Sin responsable)' }).waitFor();
  });

  await paso('Validacion de parametros', async () => {
    await pagina.goto(`${BASE}/?p=Issue_Detalle`);   // la sesión sigue tras recargar
    await titulo('Detalle de un issue').waitFor();
    await pagina.getByRole('button', { name: 'Consultar' }).click();
    await pagina.getByText('Es obligatorio.').waitFor();
  });

  // ----- Administración de usuarios desde la aplicación (reglas en SQL Server) -----
  let temporal = '';
  await paso('Administrador da de alta un usuario', async () => {
    await pagina.getByRole('link', { name: 'Guardar usuario' }).click();
    await pagina.getByLabel(/^Login/).fill(NUEVO);
    await pagina.getByLabel(/^Nombre/).fill('María López');
    await pagina.getByLabel(/^Roles/).fill('Consulta');
    await pagina.getByRole('button', { name: 'Ejecutar' }).click();
    await pagina.getByRole('cell', { name: NUEVO }).waitFor();
  });

  await paso('Administrador asigna una contrasena temporal', async () => {
    await pagina.getByRole('link', { name: 'Restablecer contraseña' }).click();
    await pagina.getByLabel(/^Usuario/).fill(NUEVO);
    temporal = await pagina.getByLabel(/^Contraseña temporal/).inputValue();
    await pagina.getByRole('button', { name: 'Restablecer' }).click();
    await pagina.getByRole('status').filter({ hasText: 'deberá cambiarla al entrar' }).waitFor();
  });

  await paso('El usuario entra y debe cambiar su contrasena', async () => {
    await pagina.getByRole('button', { name: 'Salir' }).click();
    await iniciarSesion(NUEVO, temporal);
    await titulo('Establezca su contraseña').waitFor();
    await pagina.getByLabel('Contraseña temporal', { exact: true }).fill(temporal);
    await pagina.getByLabel('Contraseña nueva', { exact: true }).fill('corta');
    await pagina.getByLabel('Repita la contraseña nueva').fill('corta');
    await pagina.getByRole('button', { name: 'Guardar contraseña' }).click();
    await pagina.getByText('al menos 10 caracteres').waitFor();   // regla de SQL Server
    await pagina.getByLabel('Contraseña nueva', { exact: true }).fill('Mi-Clave-Nueva-2026');
    await pagina.getByLabel('Repita la contraseña nueva').fill('Mi-Clave-Nueva-2026');
    await pagina.getByRole('button', { name: 'Guardar contraseña' }).click();
    await titulo('Scrum y mesa de ayuda').waitFor();
  });

  await paso('El usuario consulta y no ve la administracion', async () => {
    await pagina.getByText('María López').waitFor();
    if (await pagina.getByRole('heading', { name: 'Administración' }).count()) throw new Error('Un usuario de Consulta ve Administración.');
    await pagina.getByRole('link', { name: 'Buscar historias y tickets' }).click();
    await pagina.getByRole('button', { name: 'MDA-1' }).waitFor();
  });

  if (erroresConsola.length) throw new Error(`Errores en la consola del navegador:\n${erroresConsola.join('\n')}`);
  console.log('E2E: todo correcto');
} catch (e) {
  if (CAPTURAS) await pagina.screenshot({ path: `${CAPTURAS}/fallo.png`, fullPage: true });
  console.error('\nE2E falló:', e.message);
  process.exitCode = 1;
} finally {
  await navegador.close();
}
