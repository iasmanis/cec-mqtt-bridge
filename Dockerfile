FROM jonaseck/rpi-raspbian-libcec-py


COPY ./assets /usr/src/app

WORKDIR /usr/src/app

RUN apt-get update \
    && apt-get install -qqy libxrandr2 liblircclient-dev \
    && rm -rf /var/lib/apt/lists/* \
    && pip install -r requirements.txt

CMD ["python", "bridge.py"]
