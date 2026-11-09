// Prueba de punta a punta en Chromium contra la API real (que sirve el build de React).
// Uso: BASE_URL=http://127.0.0.1:5080 E2E_USUARIO=admin E2E_CONTRASENA=... node e2e/flujo.mjs
//   E2E_USUARIO / E2E_CONTRASENA: un administrador existente (p. ej. creado con "crear-administrador").
//   E2E_PENDIENTE / E2E_LISTO: comandos de shell opcionales que dejan los datos sin sincronizar / sincronizados,
//   para verificar la pantalla de sincronización. E2E_ATRASAR / E2E_AL_DIA: comandos opcionales que dejan los datos
//   atrasados (sin sincronizar hace horas) y los regresan, para verificar el aviso. E2E_CAPTURAS: carpeta para las capturas.
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

  if (process.env.E2E_ATRASAR) {
    await paso('Datos atrasados: avisa sin bloquear', async () => {
      execSync(process.env.E2E_ATRASAR, { stdio: 'inherit' });
      await pagina.waitForTimeout(6000);   // la API guarda el estado de la sincronización unos segundos
      await pagina.reload();
      await pagina.getByText(/Los datos de Jira tienen .* sin actualizarse/).waitFor();
      await pagina.getByRole('link', { name: 'Buscar historias y tickets' }).waitFor();   // la aplicación sigue disponible
      execSync(process.env.E2E_AL_DIA, { stdio: 'inherit' });
      await pagina.waitForTimeout(6000);
      await pagina.reload();
      await pagina.getByRole('link', { name: 'Buscar historias y tickets' }).waitFor();
      if (await pagina.getByText(/sin actualizarse/).count()) throw new Error('El aviso de atraso sigue visible con datos al día.');
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

  await paso('Horas por sprint (tiempo reportado en Scrum)', async () => {
    await pagina.getByRole('link', { name: 'Horas por sprint' }).click();
    await titulo('Horas por sprint').waitFor();
    await pagina.getByRole('columnheader', { name: 'Horas registradas' }).waitFor();
    await pagina.getByRole('cell', { name: 'Sprint 4' }).waitFor();
    await pagina.getByRole('cell', { name: 'Dev Uno' }).waitFor();
  });

  await paso('Estimado vs real', async () => {
    await pagina.getByRole('link', { name: 'Estimado vs. real' }).click();
    await titulo('Estimado vs. real').waitFor();
    await titulo('Detalle por issue').waitFor();
    await pagina.getByRole('cell', { name: 'Sin estimación' }).first().waitFor();
  });

  await paso('Avance de epicas', async () => {
    await pagina.getByRole('link', { name: 'Avance de épicas' }).click();
    await titulo('Avance de épicas').waitFor();
    await pagina.getByLabel(/^Categor/).waitFor();
    await pagina.getByText('No hay registros con estos filtros.').waitFor();   // los datos de prueba no tienen épicas
  });

  await paso('Validacion de parametros', async () => {
    await pagina.goto(`${BASE}/?p=Issue_Detalle`);   // la sesión sigue tras recargar
    await titulo('Detalle de un issue').waitFor();
    await pagina.getByRole('button', { name: 'Consultar' }).click();
    await pagina.getByText('Es obligatorio.').waitFor();
  });

  await paso('Busqueda avanzada desde cero', async () => {
    await pagina.getByRole('link', { name: 'Búsqueda avanzada' }).click();
    await titulo('Búsqueda avanzada').waitFor();
    await pagina.getByText('1–2 de 2 issues').waitFor();
    // Criterio de lista con los valores existentes y su número de issues.
    await pagina.getByRole('button', { name: /Estado: todos/ }).click();
    await pagina.getByRole('checkbox', { name: /In Progress/ }).check();
    await pagina.getByRole('button', { name: 'Aplicar' }).click();
    await pagina.getByRole('button', { name: 'SCR-7' }).waitFor({ state: 'detached' });
    await pagina.waitForURL(/Criterios=/);
    // Campo personalizado de Jira desde "Más criterios".
    await pagina.getByRole('button', { name: '+ Más criterios' }).click();
    await pagina.getByRole('searchbox', { name: 'Buscar campo' }).fill('Estac');
    await pagina.getByRole('button', { name: 'Estación' }).click();
    await pagina.getByRole('checkbox', { name: /ESTACIÓN SUR/ }).check();
    await pagina.getByRole('button', { name: 'Aplicar' }).click();
    await pagina.getByRole('button', { name: /Estación: ESTACIÓN SUR/ }).waitFor();
    // Fecha relativa.
    await pagina.getByRole('button', { name: '+ Más criterios' }).click();
    await pagina.getByRole('button', { name: 'Creado', exact: true }).click();
    await pagina.getByLabel('Valor: tipo de fecha').selectOption({ label: 'Inicio del año' });
    await pagina.getByRole('button', { name: 'Aplicar' }).click();
    await pagina.getByRole('button', { name: /Creado: desde inicio del año/ }).waitFor();
    // Columnas a elegir.
    await pagina.getByRole('button', { name: 'Columnas' }).click();
    await pagina.getByLabel('Agregar columna').selectOption({ label: 'Etiquetas' });
    await pagina.getByLabel('Agregar columna').selectOption({ label: 'Estación' });
    await pagina.getByRole('button', { name: 'Listo' }).click();
    await pagina.getByRole('columnheader', { name: 'Etiquetas' }).waitFor();
    await pagina.getByRole('cell', { name: /urgente/ }).waitFor();
    await pagina.getByRole('button', { name: 'MDA-1' }).waitFor();
  });

  await paso('La busqueda se recarga desde la direccion y se guarda como filtro', async () => {
    await pagina.reload();
    await pagina.getByRole('button', { name: /Estación: ESTACIÓN SUR/ }).waitFor();
    await pagina.getByRole('columnheader', { name: 'Estación' }).waitFor();
    await pagina.getByRole('button', { name: 'Guardar como filtro' }).click();
    await pagina.getByLabel(/Nombre del filtro/).fill('En curso por estación');
    await pagina.getByRole('button', { name: 'Guardar filtro' }).click();
    await pagina.getByText('Filtro «En curso por estación» guardado').waitFor();
  });

  await paso('Publicar la busqueda como consulta personalizada', async () => {
    await pagina.getByRole('button', { name: 'Publicar como consulta personalizada' }).click();
    await pagina.getByLabel(/^Nombre/).fill('Mesa: en curso por estación');
    await pagina.getByLabel('Descripción', { exact: true }).fill('Tickets en curso de la estación sur');
    await pagina.getByLabel('Compartir con').fill('rol:Consulta');
    await pagina.getByRole('button', { name: 'Publicar', exact: true }).click();
    await titulo('Mesa: en curso por estación').waitFor();
    await pagina.getByText('Compartida con: rol:Consulta').waitFor();
    await pagina.getByRole('button', { name: 'MDA-1' }).waitFor();
  });

  await paso('Configuracion de la sincronizacion', async () => {
    await pagina.getByRole('link', { name: 'Configuración de la sincronización' }).click();
    await pagina.getByRole('cell', { name: 'comentario' }).first().waitFor();
  });

  // ----- Filtros y tableros -----
  await paso('Guardar un filtro con fecha relativa', async () => {
    await pagina.getByRole('link', { name: 'Horas por persona' }).click();
    await pagina.getByLabel(/^Desde/).fill('2026-10-01');
    await pagina.getByRole('button', { name: 'Consultar' }).click();
    await pagina.getByRole('columnheader', { name: 'Horas registradas' }).waitFor();
    await pagina.getByRole('button', { name: 'Guardar como filtro' }).click();
    await pagina.getByLabel(/Nombre del filtro/).fill('Horas desde octubre');
    await pagina.getByLabel('Hasta', { exact: true }).selectOption({ label: 'Hoy' });
    await pagina.getByLabel(/Compartir con quienes/).check();
    await pagina.getByRole('button', { name: 'Guardar filtro' }).click();
    await pagina.getByText('Filtro "Horas desde octubre" guardado').waitFor();
  });

  await paso('Crear un tablero compartido con widgets', async () => {
    await pagina.getByRole('link', { name: '+ Nuevo tablero' }).click();
    await pagina.getByLabel(/^Nombre/).fill('Equipo');
    await pagina.getByLabel('Descripción').fill('Horas del equipo');
    await pagina.getByLabel('Compartir con').fill('rol:Consulta');
    await pagina.getByRole('button', { name: 'Guardar' }).click();
    await titulo('Equipo').waitFor();
    await pagina.getByRole('button', { name: 'Editar' }).click();

    await pagina.getByRole('button', { name: 'Agregar widget' }).click();
    await pagina.getByLabel(/^Título/).fill('Total de horas');
    await pagina.getByLabel(/^Filtro/).selectOption({ label: 'Horas desde octubre · Horas por persona' });
    await pagina.getByLabel('Cálculo').selectOption({ label: 'Suma' });
    await pagina.getByLabel(/^Columna/).selectOption({ label: 'Horas totales' });
    await pagina.getByLabel('Ancho').selectOption({ label: '1/4' });
    await pagina.getByRole('button', { name: 'Guardar widget' }).click();
    await titulo('Total de horas').waitFor();

    await pagina.getByRole('button', { name: 'Agregar widget' }).click();
    await pagina.getByLabel(/^Título/).fill('Horas por persona');
    await pagina.getByLabel(/^Filtro/).selectOption({ label: 'Horas desde octubre · Horas por persona' });
    await pagina.getByLabel('Mostrar como').selectOption('barras');
    await pagina.getByLabel(/^Agrupar por/).selectOption({ label: 'Persona' });
    await pagina.getByLabel(/^Valor/).selectOption({ label: 'Horas totales' });
    await pagina.getByLabel('Ancho').selectOption({ label: '3/4' });
    await pagina.getByRole('button', { name: 'Guardar widget' }).click();
    await pagina.getByRole('list', { name: 'Horas por persona' }).waitFor();

    // Widget con la búsqueda avanzada guardada: tabla con columnas que salen de la búsqueda.
    await pagina.getByRole('button', { name: 'Agregar widget' }).click();
    await pagina.getByLabel(/^Título/).fill('En curso por estación');
    await pagina.getByLabel(/^Filtro/).selectOption({ label: 'En curso por estación · Búsqueda avanzada' });
    await pagina.getByLabel('Mostrar como').selectOption('tabla');
    await pagina.getByRole('checkbox', { name: 'Estación' }).waitFor();
    await pagina.getByRole('button', { name: 'Guardar widget' }).click();
    await titulo('En curso por estación').waitFor();

    // Barras sobre la búsqueda: se calculan en SQL (api.Issues_Resumir) con cualquier campo, no solo las columnas.
    await pagina.getByRole('button', { name: 'Agregar widget' }).click();
    await pagina.getByLabel(/^Título/).fill('Issues por prioridad');
    await pagina.getByLabel(/^Filtro/).selectOption({ label: 'En curso por estación · Búsqueda avanzada' });
    await pagina.getByLabel('Mostrar como').selectOption('barras');
    await pagina.getByLabel(/^Agrupar por/).selectOption({ label: 'Prioridad' });
    await pagina.getByLabel('Cálculo').selectOption({ label: 'Número de registros' });
    await pagina.getByRole('button', { name: 'Guardar widget' }).click();
    await pagina.getByRole('list', { name: 'Issues por prioridad' }).getByText('High').waitFor();
    await pagina.getByRole('button', { name: 'Terminar edición' }).click();
    await pagina.getByText('26', { exact: true }).waitFor();   // 10 h registradas + 16 h automáticas
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
    if (await pagina.getByRole('link', { name: 'Mover widget' }).count()) throw new Error('El menú muestra procedimientos internos de tableros.');
    await pagina.getByRole('link', { name: 'Estado de la sincronización' }).waitFor();
    await pagina.getByRole('link', { name: 'Buscar historias y tickets' }).click();
    await pagina.getByRole('button', { name: 'MDA-1' }).waitFor();
  });

  await paso('El usuario abre la consulta personalizada compartida con su rol', async () => {
    await pagina.getByRole('link', { name: 'Mesa: en curso por estación' }).click();
    await titulo('Mesa: en curso por estación').waitFor();
    await pagina.getByRole('button', { name: 'MDA-1' }).waitFor();
    if (await pagina.getByRole('button', { name: 'Editar en búsqueda avanzada' }).count()) throw new Error('Un usuario de Consulta puede editar la consulta.');
  });

  await paso('El usuario ve el tablero compartido y lo usa de inicio', async () => {
    await pagina.getByRole('link', { name: /^Equipo/ }).click();
    await pagina.getByText('De Administrador', { exact: false }).waitFor();
    await pagina.getByRole('list', { name: 'Horas por persona' }).waitFor();
    if (await pagina.getByRole('button', { name: 'Editar' }).count()) throw new Error('Puede editar un tablero que no es suyo.');
    await pagina.getByRole('button', { name: 'Usar como inicio' }).click();
    await pagina.getByRole('button', { name: 'Quitar de inicio' }).waitFor();
    await pagina.goto(BASE);
    await titulo('Equipo').waitFor();   // al entrar ve su tablero
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
