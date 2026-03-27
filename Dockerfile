#
# Multi-stage Dockerfile for Flowset Control Community
# Builds the application from source and produces a deployable image.
#
# Build:  docker build -t flowset-control-community .
# Run:    docker run -p 8081:8081 flowset-control-community
#

# ── Stage 1: Build ────────────────────────────────────────────────
# build.gradle requires Java 17 toolchain; the compiled JAR runs on 21.
FROM gradle:8.12.1-jdk17 AS build

WORKDIR /app

# Copy build config first (maximise layer caching for dependencies)
COPY build.gradle settings.gradle gradle.properties ./

# Pre-download dependencies (cached unless build files change)
RUN gradle dependencies --no-daemon || true

# Copy the rest of the source tree
COPY src/ src/
COPY etc/ etc/

# Build the production fat JAR
# -PbuildType=docker      – marks the build info as a Docker build
# -Pvaadin.productionMode – compiles & bundles the Vaadin frontend for production
RUN gradle clean bootJar \
    -PbuildType=docker \
    -Pvaadin.productionMode=true \
    --no-daemon \
    -x test \
    -x spotbugsMain \
    -x spotbugsTest

# ── Stage 2: Runtime ─────────────────────────────────────────────
FROM amazoncorretto:21-alpine AS runtime

RUN apk add --no-cache curl

WORKDIR /app

# Copy the built JAR from the build stage
COPY --from=build /app/build/libs/*.jar app.jar

# Default port (overridable via SERVER_PORT env var)
EXPOSE 8081

# Health check using the Spring Boot actuator endpoint
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=5 \
    CMD curl --fail --silent http://localhost:${SERVER_PORT:-8081}/actuator/health | grep -q UP || exit 1

# JVM tuning: respect container memory limits
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -Dcom.sun.net.ssl.checkRevocation=false -jar /app/app.jar"]
