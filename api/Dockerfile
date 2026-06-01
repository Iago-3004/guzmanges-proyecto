# syntax=docker/dockerfile:1.7

# ---------------------------------------------------------------------------
# Fase 1: build con Maven Wrapper.
#
# Usamos la imagen JDK porque hace falta el compilador, no solo el runtime.
# Se aprovecha la cache de capas de Docker: primero se copia el `pom.xml` y se
# bajan las dependencias (capa que solo se invalida si cambia el pom), y solo
# después se copia el código fuente. Así, en builds repetidos sin tocar el
# pom, Docker reutiliza el `.m2` cacheado y la compilación es mucho más
# rápida.
# ---------------------------------------------------------------------------
FROM eclipse-temurin:21-jdk-alpine AS build

WORKDIR /workspace

# El Maven Wrapper necesita bash (en alpine usamos sh, mvnw lo soporta).
COPY mvnw .
COPY .mvn .mvn
COPY pom.xml .

# Pre-bajar dependencias para cachear esta capa.
RUN chmod +x mvnw && ./mvnw -B -q dependency:go-offline

# Copiar el código y compilar el jar empaquetado.
COPY src src
RUN ./mvnw -B -q clean package -DskipTests \
    && cp target/*.jar /workspace/app.jar


# ---------------------------------------------------------------------------
# Fase 2: runtime.
#
# Imagen JRE (sin compilador ni herramientas), mucho más pequeña. Ejecutamos
# como usuario no-root por seguridad: si alguien escapara del contenedor, no
# tendría privilegios de root sobre el sistema anfitrión.
# ---------------------------------------------------------------------------
FROM eclipse-temurin:21-jre-alpine

# Usuario y grupo dedicados, sin shell de login.
RUN addgroup -S guzmanges && adduser -S -G guzmanges guzmanges

WORKDIR /app
COPY --from=build --chown=guzmanges:guzmanges /workspace/app.jar /app/app.jar

USER guzmanges

EXPOSE 8080

# Variables JVM por defecto. Se pueden sobrescribir desde docker-compose con
# JAVA_OPTS si hace falta ajustar memoria, GC, etc.
ENV JAVA_OPTS=""

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
