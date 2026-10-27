# Imagem de execucao da API BipTag.
# O .jar e gerado pelo pipeline de CI/CD (mvn verify) antes do build da imagem.
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

RUN addgroup -S biptag && adduser -S biptag -G biptag

COPY target/biptag-api-*.jar app.jar

USER biptag

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=5 \
  CMD wget -qO- http://localhost:${PORT:-8080}/v3/api-docs > /dev/null || exit 1

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
