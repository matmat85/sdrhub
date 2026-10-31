FROM ubuntu:24.04 AS build
ARG BUILD_JOBS=2
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl git zip build-essential cmake ccache tzdata libspdlog-dev libliquid-dev nlohmann-json3-dev libgtest-dev libgmock-dev libusb-1.0-0-dev libfftw3-dev libboost-all-dev libsoapysdr-dev gnuradio gnuradio-dev libsndfile1-dev libssl-dev libpaho-mqtt-dev libpaho-mqttpp-dev libcli11-dev

WORKDIR /root/auto-sdr/
ARG SOAPY_RTLTCP_REF=51fac2b88161367514dc72694c14a9efb8bb58e5
RUN git clone https://github.com/pothosware/SoapyRTLTCP.git /soapy_rtltcp && \
    git -C /soapy_rtltcp checkout "${SOAPY_RTLTCP_REF}" && \
    cmake -S /soapy_rtltcp -B /soapy_rtltcp/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local && \
    cmake --build /soapy_rtltcp/build -j${BUILD_JOBS} && \
    cmake --install /soapy_rtltcp/build
COPY CMakeLists.txt CMakeLists.txt
COPY tests tests
COPY sources sources

FROM build AS build_release
RUN --mount=type=cache,target=/root/.cache/ccache,id=ccache \
    cmake -B /root/auto-sdr/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache /root/auto-sdr && \
    cmake --build /root/auto-sdr/build -j${BUILD_JOBS} && \
    strip /root/auto-sdr/build/auto_sdr && \
    strip /root/auto-sdr/build/auto_sdr_test

FROM build AS build_debug
RUN --mount=type=cache,target=/root/.cache/ccache,id=ccache \
    cmake -B /root/auto-sdr/build -DCMAKE_BUILD_TYPE=Debug -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache /root/auto-sdr && \
    cmake --build /root/auto-sdr/build -j${BUILD_JOBS}

FROM ubuntu:24.04 AS run
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y tzdata ca-certificates libspdlog1.12 libliquid1 nlohmann-json3-dev libusb-1.0-0 libfftw3-bin libssl3t64 libpaho-mqtt1.3 libpaho-mqttpp3-1 && \
    apt-get install -y --no-install-recommends gnuradio libsoapysdr0.8 soapysdr0.8-module-all && \
    apt-get purge -y soapysdr0.8-module-audio soapysdr0.8-module-uhd && \
    apt-get clean all && \
    rm -rf /var/lib/apt/lists/

FROM run AS test
COPY --from=build_release /root/auto-sdr/build/auto_sdr_test /usr/bin/auto_sdr_test
CMD ["/usr/bin/auto_sdr_test"]

FROM run
RUN mkdir -p /app && \
    mkdir -p /config
COPY --from=build /usr/local/lib/SoapySDR/modules0.8/librtltcpSupport.so /usr/local/lib/SoapySDR/modules0.8/
COPY --from=build_release /root/auto-sdr/build/auto_sdr /usr/bin/auto_sdr
COPY --from=build_debug /root/auto-sdr/build/auto_sdr /usr/bin/auto_sdr.debug
RUN ldconfig && \
    chown -R ubuntu:ubuntu /app/ && \
    chown -R ubuntu:ubuntu /config/
ARG VERSION=""
ARG COMMIT=""
ARG CHANGES=""
RUN echo "$(TZ=UTC date +"%Y-%m-%dT%H:%M:%S%z")" | tee /sdr_scanner_build_time && \
    echo "$VERSION" | tee /sdr_scanner_version && \
    echo "$COMMIT" | tee /sdr_scanner_commit && \
    echo "$CHANGES" | tee /sdr_scanner_changes
WORKDIR /app
COPY entrypoint/* /entrypoint/
CMD ["/entrypoint/entrypoint.sh"]
