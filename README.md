# docker-student-ide — Entorno de Desarrollo para Estudiantes

Un entorno de desarrollo completo, listo con **Node.js**, **Python** (stack de ML/DL), **Jupyter**, **MLflow** y **asistentes de IA** (Pi, OpenCode, Freebuff, gentle-ai, Qoder y Antigravity) — todo con un solo comando.

En **Windows** se instala todo de forma **nativa** (sin Docker). En **macOS / Linux** corre en el navegador con Docker.

---

## Instalación

### Windows (nativa — preferida)

Instala todo de forma nativa (Git, Node.js, Python, VS Code y los agentes de IA)
directamente en tu máquina, **sin Docker**.

```powershell
git clone https://github.com/CarlosAndres12/docker-student-ide.git
cd docker-student-ide
.\setup-windows.ps1
```

El script instala automáticamente:

- **Git, Node.js LTS y Python (última versión)** vía `winget`.
- **Stack Python de ML/DL** en un entorno virtual `.venv` (PyTorch, TensorFlow, Jupyter, MLflow, etc.).
- **Agentes de IA**: Pi, OpenCode, Freebuff, gentle-ai, Qoder y Antigravity CLI (`agy`).
- **Visual Studio Code** con las extensiones del entorno.

Al terminar abre VS Code en `student_workspace/`. Todo es idempotente: volver a
ejecutarlo solo instala lo que falte.

> Detalles técnicos y versión de cada herramienta: `docs/windows-native-setup.md`.

### macOS / Linux (con Docker)

Copia y pega el comando de abajo en tu terminal. El script clona el repositorio,
instala Docker si hace falta e inicia el entorno automáticamente.

```bash
curl -fsSL https://raw.githubusercontent.com/CarlosAndres12/docker-student-ide/main/scripts/install.sh | bash
```

### Windows (con Docker — alternativa)

```powershell
irm https://raw.githubusercontent.com/CarlosAndres12/docker-student-ide/main/scripts/install.ps1 | iex
```

> ⏱️ **La primera vez tarda entre 10 y 20 minutos** (descarga e instala todo el stack).
> Las siguientes veces es mucho más rápido gracias a la caché de Docker.
>
> Una vez que termine, abre **http://localhost:8443** en tu navegador y usa la
> contraseña **`student`**.

### Alternativa: instalación manual

Si prefieres clonar el repositorio manualmente:

```bash
git clone https://github.com/CarlosAndres12/docker-student-ide.git
cd docker-student-ide
./start.sh                    # macOS / Linux
# .\start.ps1                 # Windows (PowerShell, con Docker)
```

O si ya tienes Docker y no quieres usar los scripts:

```bash
git clone https://github.com/CarlosAndres12/docker-student-ide.git
cd docker-student-ide
docker compose up
```

---

## ¿Qué es esto?

Es un "laboratorio portátil" con todo lo necesario para programar. En **Windows** se
instala de forma **nativa** (VS Code); en **macOS / Linux** corre dentro de un
contenedor Docker y se abre en el navegador. Funciona para varias materias:

- **Desarrollo Web** — Node.js, React, Vite, TypeScript
- **Ciencia de Datos / Machine Learning** — Python, PyTorch, TensorFlow, Jupyter, MLflow
- **Programación general** — todo lo anterior disponible a la vez

Todo lo que guardes queda en la carpeta `student_workspace/` de tu computadora, así que **no pierdes tu trabajo** al reiniciar.

---

## Requisitos previos

| Requisito | Notas |
|---|---|
| **NVIDIA Container Toolkit** | **Opcional** — solo si tu curso necesita GPU |
| **Conexión a internet** | La primera compilación descarga ~4–6 GB |
| **~20 GB libres en disco** | Cache de build + imagen final + tu workspace |

> ✅ Docker se instalará automáticamente si no lo tienes. Los scripts se encargan de todo.

---

## Ejecución en segundo plano

Para ejecutar en segundo plano (el terminal queda libre):

```bash
./start.sh -d          # macOS / Linux
.\start.ps1 -d         # Windows (PowerShell)
# o también:
docker compose up -d
```

Para detener el entorno:

```bash
docker compose down
```

---

## Configuración (opcional)

El archivo `.env` ya viene listo para usar. Solo edítalo si necesitas cambiar
**cualquiera** de estos valores (todos son opcionales):

```bash
# Contraseña de code-server (cámbiala si compartes la computadora)
PASSWORD=student

# Puertos personalizados (si el puerto por defecto está ocupado)
CODESERVER_PORT=9443     # en vez de 8443
JUPYTER_PORT=8889        # en vez de 8888
MLFLOW_PORT=5556         # en vez de 5555

# IDs de usuario (start.sh los detecta automáticamente; solo edítalos
# si usas docker compose up directamente y no son 1000)
PUID=1000
PGID=1000
```

Después de editar `.env`, reinicia el contenedor:

```bash
docker compose down
docker compose up -d
```

---

## Primer ingreso

1. Abre **http://localhost:8443** en tu navegador e ingresa la contraseña.

2. code-server abre en `/config/workspace` — esta es tu carpeta `student_workspace/`
   de tu computadora. **Todo lo que crees aquí persiste entre reinicios.**

3. Abre una terminal dentro de code-server (**Terminal → New Terminal**) y verifica
   que todo funcione (ver sección "Verificación rápida" más abajo).

> ⚠️ **Si compartes la computadora**, cambia la contraseña por defecto editando
> `PASSWORD` en `.env` (ver "Configuración (opcional)" arriba).

---

## ¿Qué hay dentro?

### Stack de desarrollo web
- **Node.js 22.23.1** (LTS) + npm
- CLI globales: `create-vite`, `typescript`, `npm-check-updates`
- Plantilla `package.json` con React 18, react-router-dom, axios, eslint, prettier, vitest, @testing-library/react (todas las versiones fijadas)

### Stack de Python / ML / DL
- **Python** con venv y pip (3.11 en Docker; última versión en Windows nativo)
- Núcleo: pandas, numpy, scipy, scikit-learn
- Deep learning (CPU por defecto): PyTorch, TensorFlow
- Boosting: xgboost, lightgbm
- NLP/CV: transformers, opencv-python, nltk
- Visualización: matplotlib, seaborn, plotly
- Notebooks: jupyter, jupyterlab, ipywidgets
- Experimentos: optuna, mlflow
- Calidad de código: black, ruff, pytest, python-dotenv

> **Todas las versiones están fijadas** en `requirements.txt` para que el entorno
> sea reproducible. No se instala nada "a mano" en el Dockerfile.

### Asistente de IA (Pi) — capa gratuita
- Pi CLI con `gentle-pi` (flujo SDD) y `gentle-engram` (memoria persistente)
- `pi-free` para desbloquear proveedores gratuitos (Kilo, Cline, OpenRouter, etc.)
- **Bloqueado por defecto a proveedores gratuitos** — no se cobra nada.

---

## Puertos y cómo acceder

> Esta sección aplica al modo **Docker** (macOS / Linux). En **Windows nativo**
> no hay puertos: VS Code se abre localmente y Jupyter/MLflow corren en
> `localhost` desde tu propia terminal.

| Puerto | Servicio | Cómo se accede |
|---|---|---|
| **8443** | code-server (el IDE) | Directo en el navegador: http://localhost:8443 |
| **8888** | Jupyter / JupyterLab | Directo en el navegador: http://localhost:8888 |
| **5555** | MLflow UI | Directo en el navegador: http://localhost:5555 |
| 3000–9999 | Servidores de desarrollo (Vite, etc.) | A través de la pestaña **Ports** de code-server |
| 5000, 8000 | Backends / APIs | A través de la pestaña **Ports** de code-server |

> Los puertos 3000–9999, 5000 y 8000 **no se exponen al host** — se acceden vía
> code-server, que los reenvía automáticamente. Esto evita conflictos con otros
> servicios que tengas corriendo en tu computadora.

Todos los puertos del navegador (8443, 8888, 5555) se pueden cambiar en `.env`:

```bash
CODESERVER_PORT=9443    # si el 8443 está ocupado
JUPYTER_PORT=8889       # si el 8888 está ocupado
MLFLOW_PORT=5556       # si el 5555 está ocupado
```

---

## Notas por tipo de curso

### Curso de Desarrollo Web

```bash
# Crear un proyecto nuevo con Vite
npm create vite@latest mi-app -- --template react
cd mi-app
npm install
npm run dev
```

Luego abre la pestaña **Ports** en code-server y reenvía el puerto que Vite te indique
(normalmente 5173).

**Si tu frontend llama a `https://astryx.atmeta.com/`**: configura la variable de
entorno `VITE_API_BASE_URL` en el archivo `.env` de **tu proyecto** (no del contenedor):

```bash
# mi-app/.env
VITE_API_BASE_URL=https://astryx.atmeta.com/
```

Esto es configuración del lado del estudiante — **no viene incluida en la imagen Docker**.
Es posible que también necesites configurar CORS en el lado del API.

### Curso de Machine Learning / Data Science

```bash
# Iniciar JupyterLab
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root
# Luego abre http://localhost:8888 en tu navegador

# Iniciar MLflow
mlflow ui --host 0.0.0.0 --port 5555
# Luego abre http://localhost:5555 en tu navegador
```

Todo el stack de Python (PyTorch, TensorFlow, pandas, scikit-learn, etc.) ya está
instalado en el entorno virtual `/opt/venv`.

### Curso general de programación

Tienes todo lo de arriba disponible a la vez. Usa code-server para editar código,
Jupyter para notebooks, y MLflow para seguimiento de experimentos.

---

## Verificación rápida

Abre una terminal dentro de code-server (**Terminal → New Terminal**) y ejecuta:

> En **Windows nativo**, usa la terminal integrada de VS Code y activa primero el
> entorno Python: `.\.venv\Scripts\Activate.ps1` (en PowerShell).

```bash
# Node.js
node -v            # esperado: v22.x
npm -v

# Python y stack ML/DL
python --version   # esperado: Python 3.11.x (Docker) o la última (nativo)
python -c "import pandas, numpy, scipy, sklearn; print('Stack core OK')"
python -c "import torch; print('PyTorch', torch.__version__)"
python -c "import tensorflow as tf; print('TensorFlow', tf.__version__)"

# Pi (asistente de IA)
pi --version
pi package list    # debería mostrar: gentle-pi, gentle-engram, pi-free

# OpenCode (agente de IA alternativo)
opencode --version

# Freebuff (agente de IA alternativo)
freebuff --version

# gentle-ai (ecosistema potenciador de agentes)
gentle-ai --version

# Qoder (agente de IA alternativo)
qodercli --version

# Antigravity CLI (solo Windows nativo)
agy --version

# GPU (solo si la habilitaste)
nvidia-smi
```

---

## El asistente de IA (Pi)

### ¿Cómo funciona la capa gratuita?

Pi viene configurado para usar **solo proveedores gratuitos** por defecto. Esto se
controla de dos formas:

1. **Variable de entorno** `PI_FREE_ONLY=1` en `.env` (activada por defecto).
2. **Archivo de configuración** en `/home/abc/.pi/config.json`.

Para ver el modo actual o cambiarlo:

```bash
pi-free status    # muestra el modo de enrutamiento actual
pi-free free      # bloquear a solo proveedores gratuitos
pi-free all       # permitir todos (incluidos los de pago) — ¡cuidado!
```

> ⚠️ **Importante**: Mantén `pi-free free` (o `PI_FREE_ONLY=1`) para no usar
> proveedores de pago por accidente.

### Proveedores que necesitan OAuth (kilo, cline)

Algunos proveedores gratuitos usan un flujo de OAuth que abre un navegador. Dentro
del contenedor esto **no funciona directamente** porque no hay navegador gráfico.
Tienes dos opciones:

**Opción A — Clave API (si el proveedor la soporta):**
Descomenta la línea correspondiente en `.env` y pon tu clave:

```bash
KILO_API_KEY=tu_clave_aqui
CLINE_API_KEY=tu_clave_aqui
OPENROUTER_API_KEY=tu_clave_aqui
```

**Opción B — Flujo OAuth una sola vez:**

1. Inicia el contenedor y abre code-server en tu navegador.
2. En una terminal de code-server ejecuta `pi login kilo` (o el proveedor que sea).
3. Copia la URL que aparece y pégala en el navegador de **tu computadora**.
4. Completa el login en tu navegador.
5. El token se guarda en `student_workspace/.pi/` — **sobrevive a reinicios del contenedor**.

> 💡 Después de hacer el login una vez, tu sesión sigue activa aunque hagas
> `docker compose down` y `docker compose up`, porque el token vive en
> `student_workspace/`.

### ⚠️ Riesgo de mantenimiento de pi-free

`pi-free` se instala directamente desde un repositorio de GitHub
(`github.com/apmantza/pi-free`), **no** desde el registro de npm. Esto significa:

- **No tiene la misma garantía de proveniencia** que `gentle-pi` o `gentle-engram`.
- El repositorio **podría cambiar o desaparecer**.
- Está fijado a un commit específico al momento de construir la imagen.

Si la ruta de instalación cambia en el futuro, consulta
[pi.dev/packages/pi-free](https://pi.dev/packages/pi-free) para el comando actual.

---

## Agentes de IA alternativos

Pi es el asistente por defecto; las alternativas son opcionales y se lanzan manualmente desde la terminal.

| Agente | Lanzamiento | Modelos gratuitos |
|---|---|---|
| **OpenCode** | `opencode` | 75+ proveedores vía Models.dev, MCP incluido |
| **Freebuff** | `freebuff` | DeepSeek V4 Flash, Kimi K2.7, MiniMax M2.7 incluidos |
| **gentle-ai** | `gentle-ai` | Mejora cualquier agente con memoria Engram, SDD y skills |
| **Qoder** | `qodercli` | Plataforma agentica con NEXT (autocompletado), Inline Chat, Ask/Agent Chat y Quest Window para delegacion autonoma. Registro gratuito con email/Google/GitHub (sin tarjeta de credito). |
| **Antigravity CLI** | `agy` | Agente de Google que entiende tu código y ejecuta comandos desde la terminal. Solo en Windows nativo. |

> **OpenSpec** (Fission-AI) ya está instalado como el framework SDD del proyecto. No se reinstala como agente.
>
> **Nota sobre gentle-ai**: gentle-ai configura solo OpenCode; Pi ya tiene gentle-pi; Freebuff, Qoder y Antigravity son agentes independientes no configurados por gentle-ai.

Ejecuta `./agents.sh` para ver todos los agentes instalados y sus comandos de lanzamiento.

---

## Modelos gratuitos disponibles

Todos los agentes de IA incluidos funcionan con modelos gratuitos. No necesitas
pagar nada ni configurar claves API para empezar a usarlos.

### Pi — capa gratuita por defecto

Pi está bloqueado a proveedores gratuitos (`PI_FREE_ONLY=1` en `.env`).
Usa `pi-free status` para ver el modo actual y los proveedores disponibles.

Para agregar claves de proveedores adicionales, descomenta las líneas
correspondientes en `.env`:

```bash
# En el archivo .env:
SAMBANOVA_API_KEY=tu_clave
LLM7_API_KEY=tu_clave
OPENMODEL_API_KEY=tu_clave
```

### OpenCode — 75+ proveedores vía Models.dev

OpenCode se conecta a Models.dev y tiene acceso a más de 75 proveedores gratuitos
sin necesidad de configurar claves. También incluye MCP Context7 para búsqueda
de documentación actualizada.

```bash
opencode
```

### Freebuff — modelos gratuitos integrados

Freebuff incluye modelos gratuitos listos para usar: DeepSeek V4 Flash,
Kimi K2.7 y MiniMax M2.7.

```bash
freebuff
```

---

## Solución de problemas

### "port is already allocated" (conflicto de puertos)

**Síntoma**: `docker compose up` falla porque un puerto ya está en uso.

**Detecta qué lo ocupa**:

```bash
ss -tlnp | grep -E ':(8443|8888|5555) '
# o con netstat:
netstat -tulpn | grep -E ':(8443|8888|5555) '
```

**Solución**: cambia el puerto en `.env`:

```bash
CODESERVER_PORT=9443     # en vez de 8443
JUPYTER_PORT=8889        # en vez de 8888
MLFLOW_PORT=5556         # en vez de 5555
```

Luego reinicia:

```bash
docker compose down
docker compose up -d
```

### Archivos propiedad de `root` (problema de permisos)

**Síntoma**: Los archivos en `student_workspace/` aparecen como propiedad de `root`
en tu computadora, o code-server no puede escribir en el workspace.

**Causa**: `PUID`/`PGID` en `.env` no coinciden con tu usuario.

**Solución**:

1. Verifica tus IDs en tu computadora:
   ```bash
   id -u   # ej. 1000
   id -g   # ej. 1000
   ```

2. Actualiza `.env`:
   ```bash
   PUID=1000
   PGID=1000
   ```

3. Recupera los archivos existentes (en tu computadora, **no** dentro del contenedor):
   ```bash
   sudo chown -R $(id -u):$(id -g) student_workspace/
   ```

4. Reinicia:
   ```bash
   docker compose down
   docker compose up -d
   ```

### "command not found: python" o "command not found: node"

El PATH debería incluir `/opt/venv/bin` y `/usr/local/bin`. Si no es así:

```bash
export PATH=/opt/venv/bin:/usr/local/bin:$PATH
```

Agrégalo a `~/.bashrc` (dentro del contenedor) si el problema persiste.

### El contenedor arranca pero code-server no responde

1. Revisa los logs:
   ```bash
   docker compose logs code-server
   ```

2. Verifica que el contenedor está corriendo:
   ```bash
   docker compose ps
   ```

3. Asegúrate de que el puerto en `.env` coincide con la URL que abres.
   Si cambiaste `CODESERVER_PORT=9443`, abre `http://localhost:9443`.

### Pi pierde la autenticación al reiniciar

Los tokens OAuth que no se guardan en `student_workspace/` se pierden al recrear el
contenedor. Revisa la "Opción B" de la sección de Pi para hacer el flujo OAuth una
sola vez y persistir el token en el workspace.

### Arranque en Windows (Windows bootstrap)

**1. "running scripts is disabled" / UnauthorizedAccess**

**Síntoma**: `start.ps1` no se ejecuta por la política de ejecución de PowerShell.

**Causa**: la política (Execution Policy) bloquea scripts sin firmar.

**Solución**: permite scripts locales (no afecta scripts remotos):

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

`install.ps1` ya ejecuta `start.ps1` con `-ExecutionPolicy Bypass` en un proceso
hijo; si aún así ves el error, aplica el comando anterior. Un reinicio de la
terminal (restart terminal) ayuda si el cambio no toma efecto.

**2. "docker: command not found" / docker no se encuentra**

**Síntoma**: el script no encuentra el comando `docker`.

**Causa**: Docker Desktop se instaló en esta sesión y el PATH de la terminal aún
no se actualizó.

**Solución**: reinicia la terminal (restart terminal) o vuelve a ejecutar el
script: ambos scripts refrescan el PATH desde el registro (Machine + User) al
iniciar. Si el problema persiste, reinstala Docker Desktop.

**3. El script se queda en el bucle "Docker aun no responde"**

**Síntoma**: el script espera al daemon y Docker nunca responde.

**Causa**: hay que distinguir entre CLI ausente (instala/reinstala Docker Desktop
y reinicia la terminal) y daemon apagado (Docker Desktop debe estar abierto).

**Solución**: confirma que Docker Desktop esté abierto (icono en la bandeja del
sistema). El script espera hasta 5 minutos (5-min wait, 60 × 5 s) en todos los
casos antes de fallar. Si superó la espera, abre Docker Desktop manualmente y
ejecuta el script de nuevo.

**4. La instalación de WSL pide un usuario Unix**

**Síntoma**: al instalar WSL aparece un aviso interactivo para crear un usuario
Unix predeterminado (WSL user prompt: nombre de usuario + contraseña).

**Causa**: es parte normal de `wsl --install` en instalaciones nuevas.

**Solución**: completa el aviso con un nombre de usuario y una contraseña. El
script te avisa antes de abrirlo; sin ese usuario WSL no funciona.

**5. "git is not installed" / falta Git**

**Síntoma**: `install.ps1` no encuentra `git`.

**Causa**: Git no está instalado o no está en el PATH.

**Solución**: el script intenta `winget install -e --id Git.Git` automáticamente;
si falla, instala Git manualmente desde https://git-scm.com/download/win y vuelve
a ejecutar.

---

## Comandos rápidos

```bash
# Construir la imagen
docker compose build

# Iniciar en segundo plano
docker compose up -d

# Detener
docker compose down

# Ver logs en vivo
docker compose logs -f

# Abrir una shell dentro del contenedor
docker compose exec code-server /bin/bash

# Reconstruir sin caché (solo si una capa se quedó trabada)
docker compose build --no-cache
```

---

## Variables de entorno (`.env`)

| Variable | Valor por defecto | Para qué sirve |
|---|---|---|
| `PUID` | `1000` | Tu ID de usuario (ejecuta `id -u`) |
| `PGID` | `1000` | Tu ID de grupo (ejecuta `id -g`) |
| `TZ` | `Etc/UTC` | Zona horaria del contenedor |
| `PASSWORD` | `student` | Contraseña de code-server (cámbiala si compartes la computadora) |
| `HASHED_PASSWORD` | _(vacío)_ | Alternativa a PASSWORD (hash bcrypt) |
| `CODESERVER_PORT` | `8443` | Puerto del IDE en el host |
| `JUPYTER_PORT` | `8888` | Puerto de Jupyter en el host |
| `MLFLOW_PORT` | `5555` | Puerto de MLflow en el host |
| `DEVICE` | `cpu` | `cpu` o `gpu` (GPU requiere NVIDIA Toolkit) |
| `PI_FREE_ONLY` | `1` | Bloquear Pi a proveedores gratuitos |
| `VITE_API_BASE_URL` | `https://astryx.atmeta.com/` | URL base del API para el frontend |
| `KILO_API_KEY` | _(comentado)_ | Clave API del proveedor Pi (opcional) |
| `CLINE_API_KEY` | _(comentado)_ | Clave API del proveedor Pi (opcional) |
| `OPENROUTER_API_KEY` | _(comentado)_ | Clave API del proveedor Pi (opcional) |

---

## ¿Quieres usar GPU?

Por defecto el entorno usa **solo CPU** para PyTorch y TensorFlow (evita descargas
de varios GB de CUDA). Si tu curso necesita GPU:

1. Instala el [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/)
   en tu computadora.
2. En `.env`, cambia:
   ```bash
   DEVICE=gpu
   ```
3. Descomenta el bloque `deploy.resources` en `docker-compose.yml` (ver los
   comentarios en ese archivo).
4. Descomenta las líneas GPU en `requirements.txt` y comenta las líneas CPU.
5. Reconstruye:
   ```bash
   docker compose build
   docker compose up -d
   ```
6. Verifica dentro del contenedor:
   ```bash
   nvidia-smi    # debería listar tu GPU
   ```

---

## ¿Dónde está todo?

| Archivo / Carpeta | Qué es |
|---|---|
| `Dockerfile` | Receta de construcción de la imagen (multi-etapa, comentada) |
| `docker-compose.yml` | Orquestación del contenedor, puertos, volúmenes |
| `setup-windows.ps1` | **Instalación nativa en Windows (sin Docker)** |
| `requirements.txt` | Paquetes de Python del contenedor (Python 3.11) |
| `requirements-windows.txt` | Paquetes de Python de Windows nativo (Python 3.13) |
| `package.json` | Plantilla de inicio para proyectos frontend |
| `.env.example` | Plantilla de referencia (documenta todas las variables) |
| `.env` | **Configuración lista para usar** — viene con valores por defecto; edítalo solo para personalizar |
| `student_workspace/` | **Tu trabajo** — persiste en tu computadora |
| `docs/deployment-guide.md` | Guía técnica detallada (en inglés) |
| `docs/windows-native-setup.md` | Guía del setup nativo en Windows (versiones y decisiones) |

---

## Ayuda adicional

- **Guía técnica completa** (en inglés): `docs/deployment-guide.md`
- **Documentación de code-server**: [docs.linuxserver.io](https://docs.linuxserver.io/images/docker-code-server/)
- **Paquetes de Pi**: [pi.dev/packages](https://pi.dev/packages)

> Si algo no funciona, revisa primero la sección **Solución de problemas**.
> La mayoría de los problemas son conflictos de puertos o permisos de archivo.