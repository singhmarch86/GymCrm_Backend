# Serves the compiled Flutter web app behind nginx.
#
# This image copies a **pre-built** build/web rather than running the Flutter
# compiler itself. That is a deliberate trade-off:
#
#   - the official-ish Flutter SDK images are ~1GB and the compile takes
#     minutes inside Docker, versus ~27s on the host where the pub cache and
#     build artefacts are already warm
#   - the local toolchain is the same one used for `flutter analyze`, so what
#     ships is exactly what was checked
#
# The cost is that the build is not self-contained: run
#
#     flutter build web --release
#
# before `docker compose build web`. The COPY below fails loudly if you forget,
# rather than silently serving a stale bundle.
FROM nginx:1.27-alpine

# Replace the default site config with the SPA-aware one.
RUN rm -f /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/app.conf

COPY build/web /usr/share/nginx/html

EXPOSE 80

# nginx:alpine's default CMD already runs in the foreground; stated explicitly
# so the intent survives a base-image change.
CMD ["nginx", "-g", "daemon off;"]
