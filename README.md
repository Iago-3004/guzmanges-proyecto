# GuzmanGes — App de Gestión de Preventa

**GuzmanGes** es una solución completa de preventa móvil para representantes comerciales, conectada con el ERP **Odoo 18 Community**. Permite consultar clientes y productos, dar de alta nuevos clientes y registrar pedidos durante la visita comercial, con sincronización bidireccional contra Odoo y funcionamiento totalmente offline.

Proyecto Final de Ciclo del título **Desarrollo de Aplicaciones Multiplataforma** (DAM).

---

## Arquitectura

Monorepo con tres componentes:

```
guzmanges-proyecto/
├── api/                 →  Backend: API REST (Spring Boot + MySQL)
├── app/                 →  App móvil (Flutter, Android + iOS)
├── doc/                 →  Documentación (memoria, manuales, diagramas)
├── docker-compose.yml   →  Despliegue API + MySQL
└── .github/workflows/   →  CI: build & release de los artefactos
```

```
┌──────────────┐    REST/JWT    ┌──────────────┐   XML-RPC   ┌──────────┐
│   Flutter    │ ◄────────────► │ Spring Boot  │ ◄─────────► │   Odoo   │
│  (Android/iOS)│               │   + MySQL    │             │   18 CE  │
│  SQLite local│                │  + Actuator  │             │          │
└──────────────┘                └──────────────┘             └──────────┘
```

- **Odoo 18 Community** es el sistema maestro de clientes, productos, pedidos y catálogos (modos y condiciones de pago).
- **Spring Boot 4** actúa como capa intermedia: importa de Odoo a MySQL, expone una API REST con JWT y reenvía a Odoo las altas creadas desde la app.
- **Flutter** consume la API y mantiene una caché local en SQLite. La app es **offline-first**: el comercial puede operar sin red y la sincronización se dispara a demanda.

---

## Tecnologías

| Capa | Tecnología |
|---|---|
| App móvil | Flutter 3.35 (Dart) — Android e iOS |
| Estado | Provider |
| Almacenamiento local | SQLite (`sqflite`) + `flutter_secure_storage` |
| HTTP | Dio |
| Backend | Spring Boot 4.0.5 · Java 21 |
| Persistencia | Spring Data JPA · MySQL 8 |
| Seguridad | Spring Security + JWT (`jjwt` 0.12) |
| Integración ERP | Odoo 18 Community (XML-RPC) |
| Documentación API | springdoc-openapi 2.8 (Swagger UI + OpenAPI 3) |
| Observabilidad | Spring Boot Actuator (health) |
| Build | Maven (api) · Flutter SDK (app) |
| Despliegue | Docker · Docker Compose |
| CI/CD | GitHub Actions (build & release de APK, IPA y imagen Docker) |

---

## Funcionalidades

- Autenticación con JWT y dos roles: **administrador** y **preventa**.
- Configuración inicial de la URL del servidor desde la app, con verificación contra `/actuator/health`.
- Gestión de **clientes**: consulta, alta con validación estructural de CIF/NIF/NIE, resolución de duplicados, propagación de la posición fiscal desde Odoo.
- Catálogo de **productos**: consulta con stock, precio y código de barras (read-only; se gestionan en Odoo).
- **Pedidos**: alta con líneas, cálculo de totales provisionales en la app (recálculo definitivo tras envío a Odoo), histórico filtrado por preventa.
- **Sincronización bidireccional** con Odoo:
  - Descendente: maestros, productos, clientes, pedidos.
  - Ascendente: altas de clientes y pedidos pendientes, con resolución de dependencias (un pedido espera a que su cliente esté sincronizado).
- **Offline-first**: identidad dual (UUID local + id de servidor) y reconciliación por estado de sincronización (`SINCRONIZADO`, `PENDENTE`, `ERRO`).
- **Borrado lógico** de clientes y pedidos para conservar la consistencia frente a borrados/cancelaciones en Odoo.
- Pantalla **"Acerca de"** con borrado total de datos locales (vuelve la app al estado de recién instalada).
- **Gestión de usuarios** (solo administrador, vía API): alta, edición, cambio de contraseña, baja con control de dependencias.
- **Health check** público en `/actuator/health` (incluye estado de MySQL).
- **API documentada** en Swagger UI (`/swagger-ui.html`) con soporte de autenticación Bearer.

---

## Estructura del repositorio

### Backend (`api/`)

```
api/src/main/java/com/guzmanges/api/
├── config/        →  Spring Security, OpenAPI, datos iniciales
├── controller/    →  Endpoints REST
├── dto/           →  Objetos de transferencia
├── entity/        →  Entidades JPA
├── exception/     →  Manejo global de errores
├── mapper/        →  Conversión entidad ↔ DTO
├── odoo/          →  Cliente XML-RPC, mappers y servicios de sincronización
├── repository/    →  Spring Data JPA
├── security/      →  Filtros y proveedor JWT
├── service/       →  Lógica de negocio
└── util/          →  Utilidades comunes
```

### App (`app/`)

```
app/lib/
├── config/        →  Configuración global
├── core/          →  Red (Dio), BD (sqflite + DAOs + migraciones), almacenamiento, validación
├── dto/           →  DTOs de envío a la API
├── models/        →  Modelos de dominio (Cliente, Producto, Pedido, LineaPedido, …)
├── providers/     →  Estado (Auth, AppConfig, Clientes, Productos, Pedidos, Sync, Catálogos)
├── routes/        →  Rutas nominadas
├── screens/       →  Pantallas (clientes, productos, pedidos, sync, login, acerca_de, …)
├── services/      →  Capa de API + servicios de sincronización
├── theme/         →  Tema Material 3
├── utils/         →  Utilidades de UI/formateo
└── widgets/       →  Componentes reutilizables
```

### Documentación (`doc/`)

- `MEMORIA_PROYECTO.pdf` — memoria completa del proyecto.
- `manual_instalacion.md` — guía de despliegue (en gallego).
- `manual_usuario.md` — manual del preventa (en gallego).
- Diagramas PNG: Casos de Uso, Clases, EER (Chen y Crow's Foot), Despliegue, Gantt.

---

## API REST

Todos los endpoints requieren JWT (`Authorization: Bearer <token>`) salvo `/auth/login`, `/actuator/health` y la documentación OpenAPI. Los de `/sync/**` y `/usuarios/**` requieren rol **ADMIN**.

| Método | Ruta | Descripción | Rol |
|---|---|---|---|
| `POST` | `/auth/login` | Autenticación; devuelve el JWT | *(público)* |
| `GET`  | `/actuator/health` | Estado de la API y MySQL | *(público)* |
| `GET`  | `/swagger-ui.html` · `/v3/api-docs` | Documentación interactiva | *(público)* |
| `GET`  | `/clientes` | Lista de clientes activos (filtro `?modificadoDesde=…`) | autenticado |
| `GET`  | `/clientes/{id}` | Detalle de cliente | autenticado |
| `POST` | `/clientes` | Alta de cliente (`?forzarAlta=true` omite control de CIF duplicado) | autenticado |
| `GET`  | `/productos` | Catálogo de productos (filtro `?modificadoDesde=…`) | autenticado |
| `GET`  | `/productos/{id}` | Detalle de producto | autenticado |
| `GET`  | `/pedidos` | Pedidos del usuario (todos si es ADMIN) | autenticado |
| `GET`  | `/pedidos/{id}` | Detalle de pedido | autenticado |
| `POST` | `/pedidos` | Alta de pedido | autenticado |
| `GET`  | `/modos-pago` · `/modos-pago/{id}` | Catálogo de modos de pago | autenticado |
| `GET`  | `/condiciones-pago` · `/condiciones-pago/{id}` | Catálogo de condiciones de pago | autenticado |
| `GET`/`POST`/`PUT`/`PATCH`/`DELETE` | `/usuarios/**` | Gestión de usuarios | **ADMIN** |
| `POST` | `/sync/maestros` | Sincroniza modos y condiciones de pago desde Odoo | **ADMIN** |
| `POST` | `/sync/productos` | Sincroniza productos desde Odoo | **ADMIN** |
| `POST` | `/sync/clientes` | Sincroniza clientes (bidireccional) | **ADMIN** |
| `POST` | `/sync/pedidos` | Sincroniza pedidos (bidireccional) | **ADMIN** |
| `POST` | `/sync/completa` | Ejecuta toda la sincronización en el orden correcto | **ADMIN** |

La especificación completa, con esquemas de DTOs y ejemplos, está disponible en **`/swagger-ui.html`** al arrancar la API.

---

## Puesta en marcha

Hay **tres rutas** para desplegar el sistema:

1. **Desde los artefactos publicados** (releases de GitHub) — la más rápida, no requiere compilar.
2. **Con Docker Compose** — recomendada para servidores; compila la imagen desde código.
3. **Desde código fuente nativo** — para desarrollo.

### Requisitos previos comunes

- Una instancia accesible de **Odoo 18 Community** con los módulos *Ventas*, *Facturación* e *Inventario* activos, y los addons de OCA: `account_payment_mode`, `account_payment_partner`, `base_bank_from_iban`, `l10n_es_partner`.
- Un usuario en Odoo con permisos sobre `res.partner`, `product.product`, `sale.order` y los catálogos de pago. **API key generada** para ese usuario.

### Opción 1 — Desde los artefactos publicados

Cada release del repositorio publica:

- `guzmanges-api-vX.Y.Z.tar.gz` — imagen Docker de la API.
- `guzmanges-app-vX.Y.Z.apk` — app Android (firmada con clave de debug).
- `guzmanges-app-vX.Y.Z.ipa` — app iOS sin firmar (instalable vía Sideloadly, AltStore o Xcode con un Apple ID gratuito).

Importar la imagen y arrancarla:

```bash
docker load < guzmanges-api-vX.Y.Z.tar.gz
docker run -p 8080:8080 --env-file .env guzmanges-api:vX.Y.Z
```

Instalar la app Android con `adb install guzmanges-app-vX.Y.Z.apk` (o transferir el APK al dispositivo y autorizar "orígenes desconocidos"). Para iOS, abrir el `.ipa` en [Sideloadly](https://sideloadly.io/) con un Apple ID; la firma gratuita caduca cada 7 días.

### Opción 2 — Con Docker Compose (recomendada)

Levanta API + MySQL con un solo comando. Pensado para servidores (Portainer, una VPS, etc.).

```bash
git clone https://github.com/Iago-3004/guzmanges-proyecto.git
cd guzmanges-proyecto
cp .env.example .env
# Editar .env con tus credenciales (MySQL, JWT, Odoo)
docker compose up -d --build
```

La API queda en `http://localhost:8080`, MySQL en la red interna de Compose (no expuesta al host). Para exponer MySQL temporalmente, copiar `docker-compose.override.example.yml` a `docker-compose.override.yml` (Compose lo carga automáticamente).

El `healthcheck` del contenedor de la API consulta `/actuator/health` y reinicia el contenedor si MySQL cae.

### Opción 3 — Desde código fuente

```bash
# Backend
cd api
./mvnw spring-boot:run

# App
cd ../app
flutter pub get
flutter run
```

Con MySQL en `localhost:3306` y las variables de entorno descritas más abajo.

---

## Variables de entorno

La API las lee al arrancar (sea contenedor o nativo). MySQL, JWT y CORS tienen valores por defecto válidos para desarrollo; las de Odoo son obligatorias.

### MySQL

| Variable | Descripción | Por defecto |
|---|---|---|
| `MYSQL_HOST` | Host de MySQL | `localhost` |
| `MYSQL_PORT` | Puerto | `3306` |
| `MYSQL_DB` / `MYSQL_DATABASE` | Nombre de la BD | `guzmanges` |
| `MYSQL_USER` | Usuario | `root` |
| `MYSQL_PASSWORD` | Contraseña | `root` |
| `MYSQL_ROOT_PASSWORD` | Solo para Compose | *(obligatoria)* |

### JWT

| Variable | Descripción | Por defecto |
|---|---|---|
| `JWT_SECRET` | Secreto de firma (≥64 caracteres aleatorios) | *(placeholder no apto para producción)* |

Generar uno seguro:

```bash
# Linux/macOS
openssl rand -base64 64
# PowerShell
[Convert]::ToBase64String((1..64 | %{Get-Random -Max 256}))
```

### Odoo (obligatorias)

| Variable | Descripción | Por defecto |
|---|---|---|
| `ODOO_URL` | URL de la instancia | *(obligatoria)* |
| `ODOO_DB` | Nombre de la BD de Odoo | *(obligatoria)* |
| `ODOO_USER` | Usuario/login | *(obligatoria)* |
| `ODOO_APIKEY` | API key (o contraseña) | *(obligatoria)* |
| `ODOO_LANG` | Idioma de campos traducibles | `es_ES` |
| `ODOO_SYNC_ENABLED` | Activa la sincronización periódica | `true` |

### Otros

| Variable | Descripción | Por defecto |
|---|---|---|
| `CORS_ALLOWED_ORIGINS` | Orígenes permitidos (separados por comas, admite comodines) | `http://localhost:*` |
| `POSICION_FISCAL_RECARGO_KEYWORD` | Palabra clave para detectar régimen de recargo de equivalencia | `recargo` |
| `JPA_SHOW_SQL` | Mostrar SQL en logs | `false` |
| `API_HOST_PORT` | Puerto del host (solo Compose) | `8080` |
| `JAVA_OPTS` | Opciones JVM extra | *(vacío)* |

---

## Usuarios por defecto

Al arrancar la API por primera vez se crean dos usuarios de prueba. **Cambiar las contraseñas en cualquier despliegue real**.

| Usuario | Contraseña | Rol |
|---|---|---|
| `admin` | `admin` | ADMIN |
| `preventa` | `preventa` | PREVENTA |

Login de ejemplo:

```bash
curl -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"nombreUsuario":"admin","contrasena":"admin"}'
```

---

## Sincronización con Odoo

La API sincroniza con Odoo en tres situaciones:

1. **Al arrancar** (`ApplicationReadyEvent`): se ejecuta una sincronización inicial completa.
2. **Periódicamente** (`@Scheduled`): cada bloque tiene su propio intervalo configurable (`odoo.sync.<bloque>.interval`).
3. **A demanda** vía `/sync/**` (solo ADMIN), normalmente desde Swagger UI o un script.

El **orden** es importante porque hay dependencias: maestros → productos → clientes → pedidos. Las altas locales (clientes y pedidos) suben **después** de la importación, y los pedidos esperan a que su cliente tenga ya `idOdoo`.

Si Odoo no responde, los errores se registran y la API sigue en marcha. La app móvil refleja el estado de cada registro con chips `SINCRONIZADO` / `PENDENTE` / `ERRO`, y desde la pantalla "Estado de sincronización" se pueden reintentar o eliminar los pendientes.

---

## App móvil

### Compilación

```bash
cd app
flutter pub get

# Android
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk

# iOS (sin firma, para sideloading)
flutter build ios --release --no-codesign
```

Bundle ID: `com.guzmanges.app`. Iconos generados con `flutter_launcher_icons` a partir de `assets/logo_guzmanges.png`.

### Primer arranque

En la primera ejecución la app pide la URL del servidor; valida que responda a `/actuator/health` antes de guardarla. Después se pasa al login.

Para resetear la app (cambio de servidor, dispositivo compartido, etc.): **Acerca de → Borrar todos los datos**.

---

## CI/CD — GitHub Actions

El workflow `.github/workflows/release.yml` genera los tres artefactos de instalación en cada publicación de release.

**Disparadores**:
- Push de un tag `v*.*.*` → la versión se toma del tag.
- `workflow_dispatch` desde la UI de Actions → la versión se introduce manualmente.

**Jobs paralelos**:
1. `docker` — construye y exporta la imagen como `.tar.gz`.
2. `apk` — `flutter build apk --release`.
3. `ipa` — `flutter build ios --no-codesign` y empaqueta como `.ipa` para sideloading.

**Release**: se crea en **borrador** con los tres artefactos adjuntos y las notas de versión auto-generadas. Hay que publicarla manualmente desde la UI de GitHub tras verificar los binarios.

---

## Documentación

- **Memoria del proyecto**: [`doc/MEMORIA_PROYECTO.pdf`](doc/MEMORIA_PROYECTO.pdf).
- **Manual de instalación** (gallego): [`doc/manual_instalacion.md`](doc/manual_instalacion.md).
- **Manual de usuario** (gallego): [`doc/manual_usuario.md`](doc/manual_usuario.md).
- **API**: Swagger UI en `/swagger-ui.html` con la API en marcha.
- **Diagramas**: `doc/Diagrama *.png` (Casos de Uso, Clases, EER, Despliegue, Gantt).

---

## Autor

**Iago Malvido Guzmán** — 2º DAM.
🔗 [github.com/Iago-3004](https://github.com/Iago-3004)

Proyecto desarrollado como Proyecto Final de Ciclo del título de Desarrollo de Aplicaciones Multiplataforma. Defensa: junio 2026.
