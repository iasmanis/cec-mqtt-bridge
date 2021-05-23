FROM balenalib/armv7hf-debian-python:3.6-bullseye AS builder

ENV LIBCEC_VERSION=6.0.2 P8_PLATFORM_VERSION=2.1.0.1

ADD https://github.com/Pulse-Eight/libcec/archive/libcec-${LIBCEC_VERSION}.tar.gz https://github.com/Pulse-Eight/platform/archive/p8-platform-${P8_PLATFORM_VERSION}.tar.gz /root/

RUN apt-get -y update \
    && apt-get -y install cmake libudev-dev libxrandr-dev swig build-essential libxrandr2 liblircclient-dev \
    && rm -rf /var/cache/apk/*
# Userland
RUN curl -L https://api.github.com/repos/raspberrypi/userland/tarball | tar xvz \
    && cd raspberrypi-userland* \
    && ./buildme
# P8 platform
RUN cd /root \
    && tar xvzf p8-platform-${P8_PLATFORM_VERSION}.tar.gz && rm p8-platform-*.tar.gz && mv platform* platform \
    && mkdir platform/build \
    && cd platform/build \
    && cmake -DCMAKE_INSTALL_PREFIX:PATH=/usr .. \
    && make \
    && make install
# Libcec
RUN cd /root \
    && export PYTHON_LIBDIR=$(python -c 'from distutils import sysconfig; print(sysconfig.get_config_var("LIBDIR"))') \
    && export PYTHON_LDLIBRARY=$(python -c 'from distutils import sysconfig; print(sysconfig.get_config_var("LDLIBRARY"))') \
    && export PYTHON_LIBRARY="${PYTHON_LIBDIR}/${PYTHON_LDLIBRARY}" \
    && export PYTHON_INCLUDE_DIR=$(python -c 'from distutils import sysconfig; print(sysconfig.get_python_inc())') \
    && echo "PYTHON_LIBDIR = $PYTHON_LIBDIR" \
    && echo "PYTHON_LDLIBRARY = $PYTHON_LDLIBRARY" \
    && echo "PYTHON_LIBRARY = $PYTHON_LIBRARY" \
    && echo "PYTHON_INCLUDE_DIR = $PYTHON_INCLUDE_DIR" \
    && tar xvzf libcec-${LIBCEC_VERSION}.tar.gz && rm libcec-*.tar.gz && mv libcec* libcec \
    && mkdir libcec/build \
    && cd libcec/build \
    && cmake -DCMAKE_INSTALL_PREFIX:PATH=/usr \
    -DRPI_INCLUDE_DIR=/opt/vc/include \
    -DRPI_LIB_DIR=/opt/vc/lib \
    -DPYTHON_LIBRARY="${PYTHON_LIBRARY}" \
    -DPYTHON_INCLUDE_DIR="${PYTHON_INCLUDE_DIR}" \
    .. \
    && make -j4 \
    && make install DESTDIR=/opt/libcec

COPY ./assets/requirements.txt /app/

RUN cd /app \
    && pip install --no-cache-dir -r requirements.txt


FROM balenalib/armv7hf-debian-python:3.6-bullseye-run

RUN apt-get -y update \
    && apt-get -y install bash libxrandr2 liblircclient-dev \
    && rm -rf /var/cache/apk/*

COPY --from=builder /usr/local/lib/python3.6/site-packages /usr/local/lib/python3.6/site-packages
COPY --from=builder /opt/vc/lib /usr/lib/arm-linux-gnueabihf/
COPY --from=builder /opt/libcec /

WORKDIR /app

COPY ./assets /app

ENV PYTHONPATH=${PYTHONPATH}/usr/lib/python3.6/dist-packages

CMD ["python3", "-u", "bridge.py" ]
