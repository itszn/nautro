FROM ubuntu:24.04@sha256:a08e551cb33850e4740772b38217fc1796a66da2506d312abe51acda354ff061 as builder

RUN apt-get update && apt-get install -y \
    build-essential \
    wget \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q https://pkg.machengine.org/zig/zig-x86_64-linux-0.15.0-dev.936+fc2c1883b.tar.xz
COPY sig.txt /sig.txt
RUN sha256sum -c /sig.txt
RUN tar -xf zig-x86_64-linux-0.15.0-dev.936+fc2c1883b.tar.xz

ADD stdlib.patch /.
RUN cd /zig-x86_64-linux-0.15.0-dev.936+fc2c1883b/lib/std && patch -p1 < /stdlib.patch

ENV PATH="/zig-x86_64-linux-0.15.0-dev.936+fc2c1883b/:$PATH"

WORKDIR /app

RUN echo "CARDS"

ADD src/ /app/src/
ADD Makefile /app/.
ADD *.py /app/.

RUN mkdir -p /app/data/cards && make nice

FROM ubuntu:24.04@sha256:a08e551cb33850e4740772b38217fc1796a66da2506d312abe51acda354ff061

WORKDIR /app

ADD entrypoint.sh /app/
COPY --from=builder /app/main /app/.
COPY --from=builder /app/data/cards/ /app/data/cards/
COPY --from=builder /app/libengine_base.so /app/.
COPY frontend/ /app/static/
RUN cp main libengine_base.so /app/static/.
RUN ln -s /app/static/ /static && chmod 777 /srv

USER ubuntu


CMD ["/app/entrypoint.sh"]
