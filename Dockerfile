# Taken from Sir Boops' Dockerfile: https://git.sergal.org/Sir-Boops/docker-mastodon/src/branch/master/Dockerfile
# For the purposes of using jemalloc.

FROM ubuntu:18.04 as build-dep

# Use bash for the shell
SHELL ["bash", "-c"]

# Install Node
ENV NODE_VER="6.14.4"
RUN	echo "Etc/UTC" > /etc/localtime && \
	apt update && \
	apt -y dist-upgrade && \
	apt -y install wget make gcc g++ python && \
	cd ~ && \
	wget https://nodejs.org/download/release/v$NODE_VER/node-v$NODE_VER.tar.gz && \
	tar xf node-v$NODE_VER.tar.gz && \
	cd node-v$NODE_VER && \
	./configure --prefix=/opt/node && \
	make -j$(nproc) > /dev/null && \
	make install

# Install jemalloc
ENV JE_VER="5.1.0"
RUN apt -y install autoconf && \
	cd ~ && \
	wget https://github.com/jemalloc/jemalloc/archive/$JE_VER.tar.gz && \
	tar xf $JE_VER.tar.gz && \
	cd jemalloc-$JE_VER && \
	./autogen.sh && \
	./configure --prefix=/opt/jemalloc && \
	make -j$(nproc) > /dev/null && \
	make install_bin install_include install_lib

# Install ruby
ENV RUBY_VER="2.5.1"
ENV CPPFLAGS="-I/opt/jemalloc/include"
ENV LDFLAGS="-L/opt/jemalloc/lib/"
RUN apt -y install zlib1g-dev libssl-dev \
	  libgdbm-dev libdb-dev libreadline-dev && \
	cd ~ && \
	wget https://cache.ruby-lang.org/pub/ruby/${RUBY_VER%.*}/ruby-$RUBY_VER.tar.gz && \
	tar xf ruby-$RUBY_VER.tar.gz && \
	cd ruby-$RUBY_VER && \
	./configure --prefix=/opt/ruby \
	  --with-jemalloc \
	  --with-shared \
	  --disable-install-doc && \
	ln -s /opt/jemalloc/lib/* /usr/lib/ && \
	make -j$(nproc) > /dev/null && \
	make install

ENV PATH="${PATH}:/opt/ruby/bin:/opt/node/bin"

RUN npm install -g yarn && \
	gem install bundler

ENV MASTO_HASH="b5c8963055b37abfd226865edd2012a16dba587c"
RUN apt -y install git libicu-dev libidn11-dev \
	libpq-dev libprotobuf-dev protobuf-compiler && \
	git clone https://github.com/ashfurrow/mastodon /opt/mastodon && \
	cd /opt/mastodon && \
	git checkout $MASTO_HASH && \
	bundle install -j$(nproc) --deployment --without development test && \
	yarn install --pure-lockfile && \
	rm -rf .git

FROM ubuntu:18.04

COPY --from=build-dep /opt/node /opt/node
COPY --from=build-dep /opt/ruby /opt/ruby
COPY --from=build-dep /opt/jemalloc /opt/jemalloc

ENV PATH="${PATH}:/opt/ruby/bin:/opt/node/bin:/opt/mastodon/bin"
ENV TINI_VERSION="0.18.0"

# Create the mastodon user
RUN apt update && \
	echo "Etc/UTC" > /etc/localtime && \
	ln -s /opt/jemalloc/lib/* /usr/lib/ && \
	apt -y dist-upgrade && \
	apt install -y whois && \
	addgroup --gid 991 mastodon && \
	useradd -m -u 991 -g 991 -d /opt/mastodon mastodon && \
	echo "mastodon:`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 24 | mkpasswd -s -m sha-256`" | chpasswd

COPY --from=build-dep --chown=991:991 /opt/mastodon /opt/mastodon

RUN apt -y --no-install-recommends install \
	  libssl1.1 libpq5 imagemagick ffmpeg \
	  libicu60 libprotobuf10 libidn11 \
	  file ca-certificates tzdata libreadline7 && \
	ln -s /opt/mastodon /mastodon && \
	gem install bundler

# Clean up more dirs
RUN rm -rf /var/cache && \
	rm -rf /var/apt

# Add tini
ENV TINI_SUM="12d20136605531b09a2c2dac02ccee85e1b874eb322ef6baf7561cd93f93c855"
ADD https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini /tini
RUN echo "$TINI_SUM tini" | sha256sum -c -
RUN chmod +x /tini

# Run in prod mode
ENV RAILS_ENV="production"
ENV NODE_ENV="production"

# Tell rails to serve static files
ENV RAILS_SERVE_STATIC_FILES="true"

USER mastodon

# Precompile assets
RUN cd ~ && \
	OTP_SECRET=precompile_placeholder SECRET_KEY_BASE=precompile_placeholder rails assets:precompile && \
	yarn cache clean

WORKDIR /opt/mastodon

ENTRYPOINT ["/tini", "--"]
