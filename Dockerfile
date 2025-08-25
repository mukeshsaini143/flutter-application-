# Stage 1: Build the Dart app
FROM dart:stable AS build

WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

COPY . .
RUN dart pub get --offline
RUN dart compile exe bin/server.dart -o bin/server

# Stage 2: Run the compiled server (small image)
FROM gcr.io/distroless/base

WORKDIR /app
COPY --from=build /app/bin/server /app/server

EXPOSE 3000
CMD ["/app/server"]
