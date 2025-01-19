FROM ubuntu:latest

RUN apt update

RUN apt install curl ripgrep xz-utils -y && \
  curl -LO https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz

RUN tar -xf zig-linux-x86_64-0.13.0.tar.xz && \
    ln -sfn /zig-linux-x86_64-0.13.0/zig /usr/bin/zig

