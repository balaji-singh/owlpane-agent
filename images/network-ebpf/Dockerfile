FROM alpine:3.21
RUN apk add --no-cache curl
COPY emit-flows.sh /usr/local/bin/emit-flows.sh
RUN chmod 0555 /usr/local/bin/emit-flows.sh
USER 0
ENTRYPOINT ["/bin/sh", "/usr/local/bin/emit-flows.sh"]
