FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart compile exe bin/server.dart -o /app/server

FROM debian:bookworm-slim
WORKDIR /app
COPY --from=build /app/server /app/server
ENV PORT=8000
ENV HOST=0.0.0.0
ENV DATA_DIR=/data
RUN mkdir -p /data
EXPOSE 8000
CMD ["/app/server"]
