FROM knovus/drone-openfaas:latest as faas

FROM gcr.io/kaniko-project/executor:debug as drone-plugin

RUN apk --no-cache add ca-certificates git

COPY --from=faas /usr/bin/faas-cli /usr/local/bin/

USER root
COPY drone-plugin.sh /usr/local/bin/
ENTRYPOINT [ "/usr/local/bin/drone-plugin.sh" ]