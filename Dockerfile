FROM node:12 as frontend-builder

WORKDIR /frontend
COPY package.json /frontend/
RUN npm install

COPY client /frontend/client
COPY webpack.config.js /frontend/
RUN npm run build

FROM python:3.7-slim

EXPOSE 5000

RUN apt-get update  -y
RUN apt-get install -y unzip
RUN apt-get install -y libaio-dev  # depends on Oracle
RUN apt-get clean -y

# Oracle instantclient
ADD oracle/instantclient-basiclite-linux.x64-19.5.0.0.0dbru.zip /tmp/instantclient-basiclite-linux.zip
ADD oracle/instantclient-sdk-linux.x64-19.5.0.0.0dbru.zip /tmp/instantclient-sdk-linux.zip

RUN unzip /tmp/instantclient-basiclite-linux.zip -d /usr/local/
RUN unzip /tmp/instantclient-sdk-linux.zip -d /usr/local/
RUN ln -sf /usr/local/instantclient_19_5 /usr/local/instantclient
RUN ln -sf /usr/local/instantclient/libclntsh.so.19.1 /usr/local/instantclient/libclntsh.so

ENV ORACLE_HOME=/usr/local/instantclient
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/instantclient

# Add REDASH ENV to add Oracle Query Runner
ENV REDASH_ADDITIONAL_QUERY_RUNNERS=redash.query_runner.oracle
# -- End setup Oracle

# Controls whether to install extra dependencies needed for all data sources.
ARG skip_ds_deps

RUN useradd --create-home redash

# Ubuntu packages
RUN apt-get update && \
  apt-get install -y \
  curl \
  gnupg \
  build-essential \
  pwgen \
  libffi-dev \
  sudo \
  git-core \
  wget \
  # Postgres client
  libpq-dev \
  # for SAML
  xmlsec1 \
  # Additional packages required for data sources:
  libssl-dev \
  default-libmysqlclient-dev \
  freetds-dev \
  libsasl2-dev && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

WORKDIR /app

# We first copy only the requirements file, to avoid rebuilding on every file
# change.
COPY requirements.txt requirements_bundles.txt requirements_dev.txt requirements_oracle_ds.txt requirements_all_ds.txt ./
RUN pip install -r requirements.txt -r requirements_dev.txt -r requirements_oracle_ds.txt
RUN if [ "y$skip_ds_deps" = "n" ] ; then pip install -r requirements_all_ds.txt ; else echo "Skipping pip install -r requirements_all_ds.txt" ; fi

COPY . /app
COPY --from=frontend-builder /frontend/client/dist /app/client/dist
RUN chown -R redash /app
USER redash

ENTRYPOINT ["/app/bin/docker-entrypoint"]
CMD ["server"]
