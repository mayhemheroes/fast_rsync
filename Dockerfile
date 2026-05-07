# Build Stage
FROM rustlang/rust:nightly AS builder

## Install build dependencies.
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y cmake clang git build-essential binutils-dev libunwind-dev libblocksruntime-dev liblzma-dev pkg-config zlib1g-dev
RUN cargo install honggfuzz --version 0.5.56
ADD . /fast_rsync
# Remove the rust-toolchain pin so the base image nightly is used
RUN rm -f /fast_rsync/rust-toolchain
WORKDIR /fast_rsync/fuzz
# Fetch dependencies so we can patch the vendored blake2.h before building.
# GCC 14 rejects arrays of ALIGN(64) structs whose size is not a multiple of
# their alignment (blake2s_state=152 bytes, blake2b_state=368 bytes, both
# misaligned against their 64-byte ALIGN attribute).  The fix is to remove
# the ALIGN(64) annotations — they are a performance hint, not correctness.
RUN cargo fetch
RUN find /usr/local/cargo/git/checkouts -name blake2.h | xargs -I{} sed -i \
    -e 's/  ALIGN( 64 ) typedef struct __blake2s_state/  typedef struct __blake2s_state/' \
    -e 's/  ALIGN( 64 ) typedef struct __blake2b_state/  typedef struct __blake2b_state/' \
    {}
RUN HFUZZ_RUN_ARGS="--run_time $run_time --exit_upon_crash" cargo hfuzz build
# Package Stage
FROM ubuntu:20.04
COPY --from=builder /fast_rsync/fuzz/hfuzz_target/x86_64-unknown-linux-gnu/release/* /
