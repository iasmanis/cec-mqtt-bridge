FROM balenalib/armv7hf-debian-python:3.6-bullseye
#

ENV LIBCEC_VERSION=4.0.5 P8_PLATFORM_VERSION=2.1.0.1

WORKDIR /root

COPY ./assets /usr/src/app

ADD https://github.com/Pulse-Eight/libcec/archive/libcec-${LIBCEC_VERSION}.tar.gz https://github.com/Pulse-Eight/platform/archive/p8-platform-${P8_PLATFORM_VERSION}.tar.gz ./

RUN apt-get -y update \
    && apt-get -y install cmake libudev-dev libxrandr-dev swig build-essential libxrandr2 liblircclient-dev \
    && rm -rf /var/cache/apk/* \
    # Userland
    && curl -L https://api.github.com/repos/raspberrypi/userland/tarball | tar xvz \
    && cd raspberrypi-userland* \
    && ./buildme \
    # P8 platform
    && cd /root \
    && tar xvzf p8-platform-${P8_PLATFORM_VERSION}.tar.gz && rm p8-platform-*.tar.gz && mv platform* platform \
    && mkdir platform/build \
    && cd platform/build \
    && cmake -DCMAKE_INSTALL_PREFIX:PATH=/usr \
    .. \
    && make \
    && make install \
    # Libcec
    && cd /root \
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
    && make install \
    # App requirements
    && cd /usr/src/app \
    && pip install -r requirements.txt \
    # Cleanup
    && cd /root \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf platform libcec raspberrypi-userland* \
    && apt-get -y purge cmake libudev-dev libxrandr-dev python3-dev swig build-essential

ENV LD_LIBRARY_PATH=/opt/vc/lib:${LD_LIBRARY_PATH} PYTHONPATH=${PYTHONPATH}/usr/lib/python3.6/dist-packages

WORKDIR /usr/src/app

CMD ["python", "bridge.py"]
