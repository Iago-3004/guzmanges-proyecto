# 📱 GuzmanGes — App de Gestión de Preventa

**GuzmanGes** es una aplicación móvil de preventa diseñada para optimizar la gestión comercial y el proceso de toma de pedidos por parte de los representantes de ventas (preventas). Permite consultar clientes, productos y el histórico de pedidos sincronizados desde el ERP **Odoo**, así como registrar nuevos pedidos y dar de alta clientes durante la visita comercial.

---

## 🧱 Arquitectura

El proyecto se organiza como **monorepo** con tres componentes:

```
guzmanges-proyecto/
├── api/    →  Backend: API REST (Spring Boot + MySQL)
├── app/    →  Frontend: aplicación móvil (Flutter)
└── doc/    →  Documentación del proyecto (memoria, diagramas)
```

```
┌──────────────┐    REST/JWT    ┌──────────────┐   XML-RPC   ┌──────────┐
│   Flutter    │ ◄────────────► │ Spring Boot  │ ◄─────────► │   Odoo   │
│  (móvil)     │                │   + MySQL    │             │  (ERP)   │
│  SQLite local│                │              │             │          │
└──────────────┘                └──────────────┘             └──────────┘
```

- **Odoo** es el sistema maestro de clientes, productos y catálogos.
- **Spring Boot** actúa como capa intermedia: sincroniza datos de Odoo a MySQL y expone una API REST.
- **Flutter** consume la API y mantiene una caché local en SQLite para trabajar sin conexión.

---

## 🛠️ Tecnologías

| Componente | Tecnología |
|---|---|
| Frontend | Flutter (Dart) — Android / iOS |
| Backend | Spring Boot 4 · Java 21 |
| Base de datos | MySQL |
| Caché local | SQLite (modo offline) |
| Autenticación | Spring Security + JWT |
| Integración ERP | Odoo (XML-RPC) |
| Build | Maven (backend) · Flutter SDK (frontend) |

---

## ✨ Funcionalidades

- 🔐 Autenticación con JWT y roles (administrador / preventa).
- 👥 Consulta de la cartera de clientes y alta de nuevos clientes.
- 📦 Consulta del catálogo de productos con precios y stock.
- 🧾 Creación, edición y envío de pedidos.
- 📋 Histórico de pedidos por cliente (app + Odoo).
- 🔄 Sincronización bidireccional con Odoo.
- 📴 Funcionamiento offline con cola de envío y sincronización al recuperar la conexión.

---

## 📂 Estructura del backend (`api/`)

```
api/src/main/java/com/guzmanges/api/
├── config/        →  Configuración (Spring Security, datos iniciales)
├── controller/    →  Endpoints REST
├── dto/           →  Objetos de transferencia de datos
├── entity/        →  Entidades JPA (modelo de dominio)
├── exception/     →  Manejo centralizado de errores
├── mapper/        →  Conversión entidad ↔ DTO
├── odoo/          →  Cliente de integración con Odoo
├── repository/    →  Acceso a datos (Spring Data JPA)
├── security/      →  Filtros y proveedores JWT
└── service/       →  Lógica de negocio
```

---

## 🚀 Puesta en marcha

### Requisitos

- Java 21
- MySQL en ejecución (recomendado vía Docker)
- Flutter SDK (para el frontend)

1. Crear la base de datos:
   ```sql
   CREATE DATABASE guzmanges CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   ```

2. Configurar las variables de entorno. La API las lee al arrancar; si alguna no
   está definida, se usa su valor por defecto (válido para desarrollo local).

   | Variable | Descripción | Valor por defecto |
   |---|---|---|
   | `MYSQL_HOST` | Host del servidor MySQL | `localhost` |
   | `MYSQL_PORT` | Puerto de MySQL | `3306` |
   | `MYSQL_DB` | Nombre de la base de datos | `guzmanges` |
   | `MYSQL_USER` | Usuario de MySQL | `root` |
   | `MYSQL_PASSWORD` | Contraseña de MySQL | `root` |
   | `JWT_SECRET` | Clave secreta para firmar los tokens JWT (mínimo 64 caracteres) | *(placeholder de desarrollo)* |
   | `CORS_ALLOWED_ORIGINS` | Orígenes permitidos para CORS, separados por comas | `http://localhost:*` |

   > ⚠️ En producción es **obligatorio** definir un `JWT_SECRET` propio (cadena
   > larga y aleatoria) y ajustar las credenciales de MySQL y los orígenes CORS.
   > El valor por defecto del secreto **no es seguro** para un entorno real.

   Para generar un secreto seguro:
   ```bash
   openssl rand -base64 64
   ```

3. Arrancar la API:
   ```bash
   cd api
   ./mvnw spring-boot:run
   ```
   La API queda disponible en `http://localhost:8080`.

Al arrancar por primera vez se crean dos usuarios de prueba:

| Usuario | Contraseña | Rol |
|---|---|---|
| `admin` | `admin` | ADMIN |
| `preventa` | `preventa` | PREVENTA |

Ejemplo de login:
```bash
curl -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"nombreUsuario":"admin","contrasena":"admin"}'
```

### Frontend

```bash
cd app
flutter pub get
flutter run
```

---

## 📖 Documentación

La documentación completa del proyecto (memoria, diagramas de casos de uso, modelo entidad-relación, modelo relacional, diagrama de clases y planificación) se encuentra en la carpeta [`doc/`](doc/).

---

## 👤 Autor

**Iago Malvido Guzmán** — 2º DAM
🔗 [github.com/Iago-3004](https://github.com/Iago-3004)

Proyecto desarrollado como Proyecto Final de Ciclo del título de Desarrollo de Aplicaciones Multiplataforma (DAM).
